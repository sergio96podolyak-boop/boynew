---
name: bot-health-check
description: Runs a read-only health check of the boynew Binance Futures bot — compiles the code, validates TradingConfig, summarizes DB status via status.py, and scans recent logs for errors. Use when the user asks if the bot is OK/working/healthy, after code changes, or before restarting the bot. Never places or cancels orders.
---

# Bot health check (read-only)

Everything here is read-only. Do NOT run `main.py`, `protect_positions.py`, or anything with `--live --yes`.
Run from the project root. Use `./venv/bin/python` if it exists, otherwise `python3`.

## Checklist

Copy and tick as you go:

```
- [ ] 1. Code compiles
- [ ] 2. Config validates (paper mode)
- [ ] 3. DB status summary
- [ ] 4. Log scan for errors
- [ ] 5. Report
```

### 1. Code compiles
```bash
./venv/bin/python -m compileall -q . -x '(venv|_old_backup|node_modules|sergio-site|market_bloom)'
```
Any `SyntaxError` → report file:line. This is a blocker.

### 2. Config validates
```bash
./venv/bin/python -c "from config import TradingConfig as C; c=C(); c.paper_trading=True; c.validate(); print('config OK | hft=', c.aggressive_hft, '| leverage=', c.leverage, '| max_dd=', c.max_drawdown_pct)"
```
Forcing paper avoids false failures from live-only gates. If `.env` has `PAPER_TRADING=false`, also run without forcing paper and report whether the live gates pass — never print API keys.

### 3. DB status
```bash
./venv/bin/python status.py
```
Add `--live` only if the user asked about live state — it calls Binance (read-only) and shows balance, positions and protective SL/TP orders. Flag any line saying a position has no exchange protection as **CRITICAL**.

### 4. Log scan
```bash
tail -n 2000 trading_system.log 2>/dev/null | grep -E "CRITICAL|ERROR|Traceback" | tail -n 30
```
Also check `trading_live.log` if it exists. Group repeated errors and count them; quote the most recent one in full.

### 5. Report

Reply in the user's language (usually Hebrew), short:

| בדיקה | מצב |
|---|---|
| קוד מתקמפל | ✅ / ❌ |
| קונפיג | ✅ / ❌ + הסיבה |
| DB / ביצועים | שורה אחת |
| לוגים | ✅ נקי / ⚠️ N שגיאות |

Then: the single most important problem (if any) and one concrete next step.

## Common issues

- **`trading.db` missing** — bot never ran in this folder, or `DB_PATH` points elsewhere. Not an error by itself.
- **`database is locked`** — bot is running and writing; retry, don't delete `-wal`/`-shm` files.
- **Orders rejected for min notional** — raise `HFT_MIN_NOTIONAL_USDT` to 5 in `.env`.
- **`LIVE trading is locked`** in validate — expected unless the user deliberately enabled live.
