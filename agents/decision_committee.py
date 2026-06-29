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
        regime_agent: Optional[Any] = None,
        open_positions: Optional[Dict[str, Any]] = None,
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
        size_mult = max(0.10, min(1.0, size_mult))

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
