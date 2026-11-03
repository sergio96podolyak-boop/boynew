---
name: bot-live-readiness
description: Go/no-go checklist before switching the boynew bot from paper to LIVE Binance Futures trading, or before restarting it live. Verifies paper results, risk limits, live gates in .env, exchange protection, and min-notional settings. Use when the user mentions going live, real money, --live, or LIVE_TRADING_ENABLED. Never enables live trading or places orders itself.
---

# Live readiness (go / no-go)

This skill only **checks and reports**. Never edit `.env` live flags, never run `main.py --live`, and never run `protect_positions.py --live --yes` without the user explicitly asking in this conversation. Real money is at risk; there is no guaranteed profit.

## Checklist

```
- [ ] 1. Paper track record
- [ ] 2. Risk limits in .env
- [ ] 3. Live gates
- [ ] 4. Exchange state & protection
- [ ] 5. Verdict
```

### 1. Paper track record
Use the `bot-performance-review` queries on all paper history.
- **No-go** if fewer than 30 closed trades (matches `STRATEGY_LAB_MIN_LIVE_TRADES`), or expectancy ≤ 0, or max drawdown worse than `MAX_DRAWDOWN_PCT`.

### 2. Risk limits
Read `.env` (never print `BINANCE_API_KEY` / `BINANCE_API_SECRET` values — only whether they are set). Compare with these safe defaults from `.env.example`:

| Key | Safe value | No-go if |
|---|---|---|
| `LEVERAGE` | ≤ 5 | > `LIVE_MAX_LEVERAGE` |
| `LIVE_MAX_MARGIN_FRACTION` | 0.10 | > 0.25 |
| `DAILY_MAX_DRAWDOWN_PCT` | 0.05 | missing or > 0.10 |
| `MAX_DRAWDOWN_PCT` | 0.10 | > 0.20 |
| `HFT_MAX_OPEN_POSITIONS` | 2 | > 5 on a small account |
| `HFT_MIN_NOTIONAL_USDT` | 5 | < 5 (Binance rejects orders) |
| `LIVE_REQUIRED_MIN_EQUITY_USDT` | 25 | account equity below it |

### 3. Live gates
Live needs all of: `PAPER_TRADING=false`, `LIVE_TRADING_ENABLED=true`, `LIVE_TRADING_CONFIRMATION=I_ACCEPT_REAL_BINANCE_FUTURES_RISK`, and real API keys. Check which are set and validate:
```bash
./venv/bin/python -c "from config import TradingConfig as C; c=C(); c.validate(); print('paper' if c.paper_trading else 'LIVE', 'config OK')"
```
Report which gates are still closed — that is normal before going live. Don't open them for the user.

### 4. Exchange state
Only if API keys are set:
```bash
./venv/bin/python status.py --live
```
- Any existing position **without** SL/TP protection → **no-go**. Tell the user `protect_positions.py --live --yes` exists and what it does; run it only if they explicitly ask.
- API key should be futures-only, **withdrawals disabled**, ideally IP-restricted — ask the user to confirm; you can't see this.

### 5. Verdict
Reply in the user's language (usually Hebrew):

**🟢 GO / 🟡 GO with changes / 🔴 NO-GO**

Then a table of every check with ✅/⚠️/❌, the blockers first, and the exact `.env` lines the user would change themselves. Recommend starting live with the minimum size and watching the first trades on the dashboard (`http://localhost:8501`).
