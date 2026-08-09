"""
AgentMonitor — a lightweight activity bus for the live "agent control center".

Every agent step (scan, score, risk-check, entry, exit, learn) reports a short
line here; the dashboard reads it from the DB and renders moving agent cards +
a live activity feed. Design rules:

  * Never break the trading loop — all writes are wrapped in try/except.
  * Never flood SQLite — repeated (agent, action, symbol) reports are throttled
    to `min_interval` seconds. Pass force=True for one-off events (entries,
    exits, kill-switch) that must always show.

Usage:
    from agents.agent_monitor import init_monitor, get_monitor
    init_monitor(repo)                       # once, at startup
    get_monitor().report("Scanner", "scan", "scanned 50, found 3")
"""

from __future__ import annotations

import logging
import time
from typing import Any, Dict, Optional, Tuple

logger = logging.getLogger(__name__)


class AgentMonitor:
    """Throttled, crash-safe writer of agent activity rows."""

    def __init__(self, repo: Optional[Any] = None, min_interval: float = 1.5):
        self.repo = repo
        self.min_interval = min_interval
        self.loop_count = 0
        self._last_emit: Dict[Tuple[str, str, Optional[str]], float] = {}
        self._write_count = 0

    def set_loop(self, n: int) -> None:
        self.loop_count = n

    def report(
        self,
        agent: str,
        action: str,
        detail: Optional[str] = None,
        symbol: Optional[str] = None,
        status: str = "active",
        severity: str = "INFO",
        force: bool = False,
    ) -> None:
        """Record one activity line. Throttled per (agent, action, symbol) unless force."""
        if self.repo is None:
            return

        key = (agent, action, symbol)
        now = time.time()
        if not force:
            if now - self._last_emit.get(key, 0.0) < self.min_interval:
                return
        self._last_emit[key] = now

        try:
            self.repo.log_agent_activity(
                agent=agent,
                action=action,
                detail=detail,
                symbol=symbol,
                status=status,
                severity=severity,
                loop_count=self.loop_count,
            )
            self._write_count += 1
            if self._write_count % 500 == 0:
                self.repo.prune_agent_activity()
        except Exception as exc:  # pragma: no cover — must never break trading
            logger.debug("AgentMonitor.report failed (non-fatal): %s", exc)


# Module-level singleton — defaults to a no-op (repo=None) until initialized.
_monitor = AgentMonitor(repo=None)


def init_monitor(repo: Any, min_interval: float = 1.5) -> AgentMonitor:
    """Initialize the global monitor with a repository. Call once at startup."""
    global _monitor
    _monitor = AgentMonitor(repo=repo, min_interval=min_interval)
    return _monitor


def get_monitor() -> AgentMonitor:
    """Return the global monitor (no-op safe if never initialized)."""
    return _monitor
