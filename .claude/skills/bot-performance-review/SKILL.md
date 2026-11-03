---
name: bot-performance-review
description: Analyzes the boynew bot's trading performance from the SQLite DB (trades, decision_audit, portfolio_snapshots) — win rate, PnL, expectancy, best/worst symbols, exit reasons, and drawdown over a chosen period. Use when the user asks how the bot is doing, whether it makes money, which coins work, or why it loses.
---

# Bot performance review

Read-only analysis of `trading.db` (or `$DB_PATH`). Never modify the DB.

## Workflow

```
- [ ] 1. Pick period (default: last 7 days; also show all-time totals)
- [ ] 2. Run the queries
- [ ] 3. Sanity-check the data
- [ ] 4. Report findings + one recommendation
```

### 1. Period
If the user didn't say, use the last 7 days. `opened_at`/`closed_at` are ISO text, so compare with `datetime('now','-7 days')`.

### 2. Queries
Run with `sqlite3 -header -column trading.db "<SQL>"`.

**Summary**
```sql
SELECT COUNT(*) trades,
       SUM(pnl>0) wins, ROUND(100.0*SUM(pnl>0)/COUNT(*),1) win_rate_pct,
       ROUND(SUM(pnl),2) total_pnl,
       ROUND(AVG(CASE WHEN pnl>0 THEN pnl END),3) avg_win,
       ROUND(AVG(CASE WHEN pnl<=0 THEN pnl END),3) avg_loss,
       ROUND(AVG(pnl),3) expectancy
FROM trades WHERE status='closed' AND closed_at >= datetime('now','-7 days');
```

**By symbol** (top and bottom)
```sql
SELECT symbol, COUNT(*) n, ROUND(SUM(pnl),2) pnl, ROUND(100.0*SUM(pnl>0)/COUNT(*),0) win_pct
FROM trades WHERE status='closed' AND closed_at >= datetime('now','-7 days')
GROUP BY symbol HAVING n>=2 ORDER BY pnl DESC;
```

**By exit reason**
```sql
SELECT close_reason, COUNT(*) n, ROUND(SUM(pnl),2) pnl
FROM trades WHERE status='closed' AND closed_at >= datetime('now','-7 days')
GROUP BY close_reason ORDER BY n DESC;
```

**By side**
```sql
SELECT side, COUNT(*) n, ROUND(SUM(pnl),2) pnl, ROUND(100.0*SUM(pnl>0)/COUNT(*),0) win_pct
FROM trades WHERE status='closed' AND closed_at >= datetime('now','-7 days') GROUP BY side;
```

**Risk gate (decision_audit)**
```sql
SELECT approved, COUNT(*) n, ROUND(AVG(adjusted_score),3) avg_score, ROUND(AVG(consensus),2) avg_consensus
FROM decision_audit WHERE created_at >= datetime('now','-7 days') GROUP BY approved;
```

**Equity curve / max drawdown**
```sql
SELECT timestamp, equity FROM portfolio_snapshots
WHERE timestamp >= datetime('now','-7 days') ORDER BY timestamp;
```
Compute max drawdown = max over time of (running peak − equity) / running peak.

### 3. Sanity checks
- Fewer than 30 closed trades → say the sample is too small to conclude anything.
- `pnl` NULL on closed rows or absurd `entry_price` → data issue (see `fix_entry_prices.py`); report it, don't fix silently.
- Open trades older than a day → mention possible stuck/stale positions.

### 4. Report
Reply in the user's language (usually Hebrew). Lead with one line: making or losing money, how much, over how many trades. Then a small table (win rate, PnL, expectancy, max drawdown), best/worst 3 symbols, the dominant exit reason, and **one** concrete recommendation tied to a config knob in `.env` (e.g. raise score threshold, blacklist a symbol, adjust SL/TP). State plainly there is no guaranteed profit; past results don't predict future ones.
