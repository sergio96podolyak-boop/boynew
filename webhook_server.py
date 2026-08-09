"""
webhook_server.py — מקבל התראות מ-TradingView ומבצע אותן על Binance Futures.

TradingView Alert → POST JSON → השרת מבצע: פתיחה/סגירה של פוזיציה במרקט,
כולל ביטול הוראות ה-Stop-Loss בסגירה. כל בקשה חייבת לכלול "secret" תקין.

הרצה מקומית:
    ./venv/bin/pip install flask gunicorn
    WEBHOOK_SECRET=מחרוזת-סודית ./venv/bin/python webhook_server.py
בענן (Cloud Run) רץ דרך gunicorn על $PORT (ראה Dockerfile).

פעולות נתמכות (שדה "action"):
    OPEN_LONG / OPEN_SHORT      — פותח פוזיציה במרקט + SL/TP אוטומטי
    CLOSE_LONG / CLOSE_SHORT    — סוגר את הפוזיציה במרקט ומבטל SL פתוח
    CLOSE_ALL                   — סוגר כל פוזיציה פתוחה על הסימבול
"""

import logging
import os

import requests
from flask import Flask, jsonify, request

from config import config
from database.repository import TradeRepository
from agents.risk_manager import RiskManagerAgent
from agents.execution import ExecutionAgent

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("webhook")

WEBHOOK_SECRET = os.getenv("WEBHOOK_SECRET", "")
BINANCE_BASE = "https://fapi.binance.com"

app = Flask(__name__)

# --- shared agents (live) ---
_repo = TradeRepository(db_path=config.db_path)


def _live_balance() -> float:
    try:
        from agents.binance_compat import create_binance_client, live_full_account_info
        c = create_binance_client(config.api_key, config.api_secret)
        acc = live_full_account_info(c)
        return float(acc["margin_balance"]) if acc else config.paper_initial_balance
    except Exception:
        return config.paper_initial_balance


_risk = RiskManagerAgent(config=config, initial_balance=_live_balance())
_exec = ExecutionAgent(config=config, risk_manager=_risk, repository=_repo)


def _price(symbol: str) -> float:
    r = requests.get(f"{BINANCE_BASE}/fapi/v1/ticker/price", params={"symbol": symbol}, timeout=10)
    r.raise_for_status()
    return float(r.json()["price"])


def _atr(symbol: str) -> float:
    try:
        r = requests.get(
            f"{BINANCE_BASE}/fapi/v1/klines",
            params={"symbol": symbol, "interval": config.hft_timeframe, "limit": 15}, timeout=10,
        )
        kl = r.json()
        trs = [float(k[2]) - float(k[3]) for k in kl]
        return sum(trs[-14:]) / max(1, min(len(trs), 14))
    except Exception:
        return _price(symbol) * 0.005


@app.get("/health")
def health():
    return jsonify({"status": "ok", "mode": "PAPER" if config.paper_trading else "LIVE"}), 200


@app.post("/webhook")
def webhook():
    data = request.get_json(force=True, silent=True) or {}

    # --- auth: a shared secret is mandatory, or anyone could trade your account ---
    if not WEBHOOK_SECRET or data.get("secret") != WEBHOOK_SECRET:
        logger.warning("Rejected webhook (bad/missing secret) from %s", request.remote_addr)
        return jsonify({"error": "unauthorized"}), 401

    action = (data.get("action") or "").upper()
    symbol = (data.get("symbol") or "").upper()
    if not symbol:
        return jsonify({"error": "missing symbol"}), 400

    try:
        # ---------------- CLOSE ----------------
        if action in ("CLOSE_SHORT", "CLOSE_LONG", "CLOSE_ALL"):
            pos = _exec.get_position(symbol)
            if pos is None:
                return jsonify({"status": "no_position", "symbol": symbol}), 200
            amt = float(pos.get("positionAmt", 0))
            is_short = amt < 0
            # only act on the requested side
            if action == "CLOSE_SHORT" and not is_short:
                return jsonify({"status": "skip", "reason": "position is not short"}), 200
            if action == "CLOSE_LONG" and is_short:
                return jsonify({"status": "skip", "reason": "position is not long"}), 200
            # hft_close → market close (Market Buy for a short) + cancels open SL/TP orders
            result = _exec.hft_close(symbol, _price(symbol), reason=f"tv_{action.lower()}")
            return jsonify({"status": "closed", "symbol": symbol, "result": bool(result)}), 200

        # ---------------- OPEN ----------------
        if action in ("OPEN_LONG", "OPEN_SHORT"):
            direction = "LONG" if action == "OPEN_LONG" else "SHORT"
            if symbol in _risk.open_positions or _exec.get_position(symbol) is not None:
                return jsonify({"status": "skip", "reason": "already in position"}), 200

            price = _price(symbol)
            atr = _atr(symbol)
            _risk.update_balance(_live_balance())
            decision = _risk.evaluate(
                symbol=symbol, score=100.0, direction=direction, entry_price=price, atr=atr,
                current_balance=_risk._current_balance, open_positions=_risk.open_positions,
            )
            if not decision.approved:
                return jsonify({"status": "rejected", "reason": decision.rejection_reason}), 200

            trade_id = _exec.hft_open(
                symbol=symbol, direction=direction, quantity=decision.quantity,
                entry_price=price, sl=decision.sl_price, tp=decision.tp_price, confidence=100.0,
            )
            return jsonify({"status": "opened", "symbol": symbol, "side": direction,
                            "trade_id": trade_id}), 200

        return jsonify({"error": f"unknown action: {action}"}), 400

    except Exception as exc:
        logger.exception("Webhook action failed: %s", exc)
        return jsonify({"error": str(exc)}), 500


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    logger.info("Webhook server starting on :%d | mode=%s", port,
                "PAPER" if config.paper_trading else "LIVE")
    app.run(host="0.0.0.0", port=port)
