#!/usr/bin/env python3
"""Run the Binance multi-product opportunity radar as a lightweight service."""

from __future__ import annotations

import logging
import os
import signal
import time

from agents.opportunity_radar import OpportunityRadarAgent
from config import TradingConfig


RUNNING = True


def _handle_stop(signum, frame) -> None:  # noqa: ARG001
    global RUNNING
    RUNNING = False


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    signal.signal(signal.SIGINT, _handle_stop)
    signal.signal(signal.SIGTERM, _handle_stop)

    config = TradingConfig()
    interval = max(15, int(os.getenv("OPPORTUNITY_RADAR_REFRESH_SECONDS", "60")))
    radar = OpportunityRadarAgent(config=config)

    logging.info("Opportunity radar service started; interval=%ss", interval)
    while RUNNING:
        started = time.time()
        try:
            snapshot = radar.refresh()
            summary = snapshot.get("summary", {})
            logging.info(
                "radar updated products=%s watch_ready=%s spot=%s futures=%s options=%s",
                summary.get("products_watched"),
                summary.get("watch_ready"),
                summary.get("spot_symbols"),
                summary.get("futures_symbols"),
                summary.get("options_rows"),
            )
        except Exception:
            logging.exception("radar refresh failed")

        elapsed = time.time() - started
        sleep_for = max(1, interval - elapsed)
        stop_at = time.time() + sleep_for
        while RUNNING and time.time() < stop_at:
            time.sleep(1)

    logging.info("Opportunity radar service stopped")


if __name__ == "__main__":
    main()
