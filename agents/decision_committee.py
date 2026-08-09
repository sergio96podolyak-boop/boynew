"""
DecisionCommitteeAgent — multi-agent gate before a trade reaches execution.

Scanner/model can be noisy, especially on 1m data. This layer requires
agreement from several independent checks and produces an auditable decision.
"""

from __future__ import annotations

import json
import logging
import os
import time
from dataclasses import asdict, dataclass, field
from typing import Any, Dict, List, Optional

from config import TradingConfig

logger = logging.getLogger(__name__)

_DECISION_FILE = os.path.join(os.path.dirname(__file__), "..", "data", "decision_state.json")


@dataclass
class CommitteeDecision:
    approved: bool
    symbol: str
    direction: str
    original_score: float
    adjusted_score: float
    score_adjustment: float
    size_multiplier: float
    consensus: float
    votes_for: int
    votes_total: int
    high_conviction: bool = False
    reasons: List[str] = field(default_factory=list)
    hard_blocks: List[str] = field(default_factory=list)
    decided_at: float = field(default_factory=time.time)


class DecisionCommitteeAgent:
    """Combines Scanner, News, Regime and portfolio-context votes."""

    def __init__(self, config: TradingConfig, monitor: Optional[Any] = None, repo: Optional[Any] = None):
        self.config = config
        self.monitor = monitor
        self.repo = repo
        self.last_decision: Optional[CommitteeDecision] = None

    def evaluate(
        self,
        opportunity: Dict[str, Any],
        *,
        news_agent: Optional[Any] = None,
        catalyst_agent: Optional[Any] = None,
        regime_agent: Optional[Any] = None,
        flow_agent: Optional[Any] = None,
        capital_agent: Optional[Any] = None,
        indirect_agent: Optional[Any] = None,
        open_positions: Optional[Dict[str, Any]] = None,
        drawdown_pct: float = 0.0,
    ) -> CommitteeDecision:
        symbol = opportunity.get("symbol", "")
        direction = opportunity.get("direction", "LONG")
        base_score = float(opportunity.get("score", 0.0) or 0.0)

        score = base_score
        size_mult = 1.0
        votes_for = 0
        votes_total = 0
        reasons: List[str] = []
        hard_blocks: List[str] = []

        def vote(name: str, passed: bool, reason: str, *, hard_block: bool = False) -> None:
            nonlocal votes_for, votes_total
            votes_total += 1
            if passed:
                votes_for += 1
            reasons.append(f"{name}: {reason}")
            if hard_block:
                hard_blocks.append(f"{name}: {reason}")

        scanner_pass = direction in ("LONG", "SHORT") and base_score >= self.config.score_entry
        vote("Scanner", scanner_pass, f"score {base_score:.1f}")

        # News/sentiment vote
        if news_agent is not None:
            try:
                news = news_agent.assess_trade(symbol=symbol, direction=direction)
                score += float(news.get("score_adjustment", 0.0))
                size_mult *= float(news.get("size_multiplier", 1.0))
                hard = bool(news.get("hard_block", False))
                vote("News", bool(news.get("vote", news.get("approved", True))), news.get("reason", "neutral"), hard_block=hard)
            except Exception as exc:
                logger.debug("News committee check failed: %s", exc)
                vote("News", False, "unavailable")
                score -= 1.0

        # Symbol-specific catalysts: listings/delistings/security incidents.
        if catalyst_agent is not None:
            try:
                catalyst = catalyst_agent.assess_trade(symbol=symbol, direction=direction)
                score += float(catalyst.get("score_adjustment", 0.0))
                size_mult *= float(catalyst.get("size_multiplier", 1.0))
                hard = bool(catalyst.get("hard_block", False))
                vote(
                    "Catalyst",
                    bool(catalyst.get("vote", catalyst.get("approved", True))),
                    catalyst.get("reason", "neutral"),
                    hard_block=hard,
                )
            except Exception as exc:
                logger.debug("Catalyst committee check failed: %s", exc)
                vote("Catalyst", True, "unavailable")

        # Broad market regime vote
        if regime_agent is not None:
            try:
                regime = regime_agent.assess_trade(opportunity)
                score += float(regime.score_adjustment)
                size_mult *= float(regime.size_multiplier)
                vote("Regime", bool(regime.vote), regime.reason, hard_block=not regime.approved)
            except Exception as exc:
                logger.debug("Regime committee check failed: %s", exc)
                vote("Regime", False, "unavailable")
                score -= 1.0

        # Order-flow / positioning vote
        if flow_agent is not None:
            try:
                flow = flow_agent.assess_trade(symbol=symbol, direction=direction)
                score += float(getattr(flow, "score_adjustment", 0.0))
                size_mult *= float(getattr(flow, "size_multiplier", 1.0))
                vote(
                    "Flow",
                    bool(getattr(flow, "vote", getattr(flow, "approved", True))),
                    getattr(flow, "reason", "neutral"),
                    hard_block=bool(getattr(flow, "hard_block", False)),
                )
            except Exception as exc:
                logger.debug("Flow committee check failed: %s", exc)
                vote("Flow", True, "unavailable")

        # Capital allocation vote: can reduce or boost size, but never hard-blocks
        # unless a future allocator explicitly marks a hard block.
        if capital_agent is not None:
            try:
                capital = capital_agent.assess_trade(
                    opportunity,
                    open_positions=open_positions,
                    drawdown_pct=drawdown_pct,
                )
                score += float(getattr(capital, "score_adjustment", 0.0))
                size_mult *= float(getattr(capital, "size_multiplier", 1.0))
                vote("Capital", bool(getattr(capital, "vote", True)), getattr(capital, "reason", "normal"))
            except Exception as exc:
                logger.debug("Capital allocator check failed: %s", exc)
                vote("Capital", True, "unavailable")

        # Indirect Grid/DCA/Arbitrage advisory vote. It cannot place orders;
        # it only adjusts score/size before RiskManager and exchange SL/TP.
        if indirect_agent is not None:
            try:
                indirect = indirect_agent.assess_trade(
                    opportunity,
                    open_positions=open_positions,
                    drawdown_pct=drawdown_pct,
                )
                score += float(getattr(indirect, "score_adjustment", 0.0))
                size_mult *= float(getattr(indirect, "size_multiplier", 1.0))
                vote(
                    "Indirect",
                    bool(getattr(indirect, "vote", True)),
                    getattr(indirect, "reason", "neutral"),
                )
            except Exception as exc:
                logger.debug("Indirect strategy check failed: %s", exc)
                vote("Indirect", True, "unavailable")

        funding_reason = opportunity.get("funding_risk") or ""
        funding_penalty = float(opportunity.get("funding_penalty", 0.0) or 0.0)
        funding_size = float(opportunity.get("funding_size_multiplier", 1.0) or 1.0)
        if funding_reason or funding_penalty > 0:
            size_mult *= max(0.10, min(1.0, funding_size))
            vote(
                "Funding",
                funding_penalty < 5.0,
                funding_reason or f"penalty {funding_penalty:.1f}",
            )
        else:
            vote("Funding", True, "normal")

        # Portfolio-context vote: do not stack too aggressively in one direction.
        open_positions = open_positions or {}
        if open_positions:
            same_side = sum(1 for p in open_positions.values() if getattr(p, "side", "") == direction)
            if same_side >= max(1, self.config.hft_max_open_positions - 1):
                score -= 2.0
                size_mult *= 0.85
                vote("Portfolio", False, f"{same_side} open {direction} positions")
            else:
                vote("Portfolio", True, "exposure balanced")
        else:
            vote("Portfolio", True, "no open exposure")

        # Score vote after all guards.
        min_score = max(self.config.score_entry, self.config.decision_min_score_after_guards)
        score_pass = score >= min_score
        vote("ScoreGate", score_pass, f"adjusted {score:.1f} >= {min_score:.1f}")

        consensus = votes_for / votes_total if votes_total else 0.0
        min_consensus = (
            self.config.decision_live_min_consensus
            if not self.config.paper_trading
            else self.config.decision_min_consensus
        )
        approved = not hard_blocks and consensus >= min_consensus and score_pass

        high_conviction = False
        max_size_mult = 1.0
        funding_ok = funding_penalty <= self.config.high_conviction_max_funding_penalty
        if approved and self.config.high_conviction_enabled:
            high_conviction = (
                score >= self.config.high_conviction_min_score
                and consensus >= self.config.high_conviction_min_consensus
                and funding_ok
            )
            if high_conviction:
                max_size_mult = max(1.0, self.config.high_conviction_size_multiplier)
                size_mult *= max_size_mult
                reasons.append(
                    "HighConviction: "
                    f"score {score:.1f}, consensus {consensus:.0%}, size boost {max_size_mult:.2f}x"
                )
        if (
            approved
            and getattr(self.config, "capital_allocator_enabled", False)
            and score >= float(getattr(self.config, "capital_allocator_min_score", 999.0) or 999.0)
            and consensus >= self.config.high_conviction_min_consensus
            and funding_ok
        ):
            capital_max = max(
                1.0,
                float(getattr(self.config, "capital_allocator_size_multiplier", 1.0) or 1.0),
            )
            max_size_mult = max(max_size_mult, capital_max)
            reasons.append(
                "CapitalAllocator: "
                f"score {score:.1f}, consensus {consensus:.0%}, max size {capital_max:.2f}x"
            )

        size_mult = max(0.10, min(max_size_mult, size_mult))

        decision = CommitteeDecision(
            approved=approved,
            symbol=symbol,
            direction=direction,
            original_score=base_score,
            adjusted_score=score,
            score_adjustment=score - base_score,
            size_multiplier=size_mult,
            consensus=consensus,
            votes_for=votes_for,
            votes_total=votes_total,
            high_conviction=high_conviction,
            reasons=reasons,
            hard_blocks=hard_blocks,
        )
        self.last_decision = decision
        self._publish(decision)
        self._log_to_repo(decision)

        if self.monitor:
            detail = (
                f"{symbol} {direction} consensus={consensus:.0%} "
                f"score={score:.1f} size={size_mult:.2f}"
                + (" HC" if high_conviction else "")
            )
            self.monitor.report(
                "Decision",
                "approve" if approved else "reject",
                detail if approved else f"{detail} | {hard_blocks[0] if hard_blocks else reasons[-1]}",
                symbol=symbol,
                status="active",
                severity="INFO" if approved else "WARNING",
                force=True,
            )
        return decision

    def _publish(self, decision: CommitteeDecision) -> None:
        try:
            os.makedirs(os.path.dirname(_DECISION_FILE), exist_ok=True)
            with open(_DECISION_FILE, "w", encoding="utf-8") as f:
                json.dump(asdict(decision), f, ensure_ascii=False, indent=2)
        except Exception as exc:
            logger.debug("decision state write failed: %s", exc)

    def _log_to_repo(self, decision: CommitteeDecision) -> None:
        if self.repo is None:
            return
        try:
            self.repo.log_decision(asdict(decision))
        except Exception as exc:
            logger.debug("decision audit write failed: %s", exc)
