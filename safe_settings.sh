#!/usr/bin/env bash
# safe_settings.sh — מכייל את .env לחשבון קטן (עשרות דולרים).
# לא נוגע במפתחות API, לא נוגע בשום דבר אחר. מגבה לפני כל שינוי.
#
#   bash safe_settings.sh          # מציג מה ישתנה, לא משנה כלום
#   bash safe_settings.sh --apply  # מבצע

set -u

cd "$(dirname "$0")" || exit 1
ENV_FILE=".env"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ אין קובץ .env בתיקייה $(pwd)"
  echo "   העתק קודם:  cp .env.example .env"
  exit 1
fi

APPLY=0
LEVEL="conservative"
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --level) shift; LEVEL="${1:-conservative}" ;;
    --level=*) LEVEL="${1#--level=}" ;;
    conservative|balanced|aggressive|max|swing|active|turbo|unleashed) LEVEL="$1" ;;
    *) echo "לא מכיר את הדגל: $1"; echo "שימוש: bash safe_settings.sh [--level conservative|balanced|aggressive|max|swing|active|turbo|unleashed] [--apply]"; exit 1 ;;
  esac
  shift
done

case "$LEVEL" in
  conservative) LEV=5;  FRAC=0.10; POS=2; DKILL=0.05; SKILL=0.10; SIZE_B=0.08; SIZE_H=0.12; SIZE_X=0.20 ;;
  balanced)     LEV=10; FRAC=0.15; POS=2; DKILL=0.10; SKILL=0.20; SIZE_B=0.12; SIZE_H=0.18; SIZE_X=0.25 ;;
  aggressive)   LEV=15; FRAC=0.25; POS=2; DKILL=0.15; SKILL=0.30; SIZE_B=0.18; SIZE_H=0.25; SIZE_X=0.35 ;;
  max)          LEV=20; FRAC=0.35; POS=2; DKILL=0.25; SKILL=0.50; SIZE_B=0.25; SIZE_H=0.35; SIZE_X=0.45 ;;
  swing)        LEV=10; FRAC=0.30; POS=2; DKILL=0.20; SKILL=0.40; SIZE_B=0.30; SIZE_H=0.40; SIZE_X=0.50 ;;
  active)       LEV=10; FRAC=0.22; POS=4; DKILL=0.20; SKILL=0.40; SIZE_B=0.22; SIZE_H=0.30; SIZE_X=0.38 ;;
  turbo)        LEV=20; FRAC=0.25; POS=4; DKILL=0.40; SKILL=0.70; SIZE_B=0.85; SIZE_H=0.95; SIZE_X=1.00 ;;
  unleashed)    LEV=20; FRAC=0.18; POS=6; DKILL=0.60; SKILL=0.90; SIZE_B=0.85; SIZE_H=0.95; SIZE_X=1.00 ;;
  *) echo "רמה לא מוכרת: $LEVEL  (conservative | balanced | aggressive | max)"; exit 1 ;;
esac

# ── ההון בחשבון ───────────────────────────────────────────────────
EQUITY="${EQUITY_USDT:-47}"

# שער הרווח-נטו הוא בדולרים מוחלטים, לא באחוזים. עם פוזיציות קטנות
# ערך קבוע של 0.25$ דורש תזוזה של יותר מ-1% — הבוט פשוט לא ייכנס לשום עסקה.
# לכן מחשבים אותו מהנוטיונל, כך שהתזוזה הנדרשת נשארת ~0.30%.
#   notional = הון × 0.10 (מרג'ין) × 5 (מינוף) = הון × 0.5
#   min_net  = notional × (0.0030 - 0.0007 עמלת maker) = notional × 0.0023
_notional() {  # equity pos size_pct frac lev  -> the notional risk_manager will actually send
  awk -v e="$1" -v p="$2" -v sp="$3" -v f="$4" -v l="$5" 'BEGIN{
    slice = e/p; n = slice*sp*l;
    normal_cap = slice*l; margin_cap = e*f*l;
    cap = (margin_cap < normal_cap) ? margin_cap : normal_cap;
    if (n > cap) n = cap;
    printf "%.2f", n;
  }'
}
REAL_NOTIONAL="$(_notional "$EQUITY" "$POS" "$SIZE_B" "$FRAC" "$LEV")"
MIN_NET_PROFIT="$(awk -v n="$REAL_NOTIONAL" 'BEGIN{v=n*0.0023; if(v<0.02)v=0.02; printf "%.2f", v}')"

# מפתח | ערך בטוח | הסבר
SETTINGS=(
  "LIVE_MAX_MARGIN_FRACTION|${FRAC}|מרג'ין מקסימלי לפוזיציה מתוך ההון"
  "MAX_MARGIN_FRACTION_PER_POSITION|${FRAC}|אותו cap, מסלול קלאסי"
  "HFT_MAX_OPEN_POSITIONS|${POS}|כמה פוזיציות במקביל"
  "SIZE_BASE_PCT|${SIZE_B}|גודל בסיס"
  "SIZE_HIGH_PCT|${SIZE_H}|גודל בציון גבוה"
  "SIZE_EXTREME_PCT|${SIZE_X}|גודל בציון קיצוני"
  "HIGH_CONVICTION_SIZE_MULTIPLIER|1.00|בלי הגדלה על ביטחון גבוה"
  "CAPITAL_ALLOCATOR_SIZE_MULTIPLIER|1.00|בלי הגדלה מהמקצה הון"
  "LIVE_REQUIRED_MIN_EQUITY_USDT|25|רצפה — מתחת לזה הבוט לא סוחר"
  "LIVE_MAX_LEVERAGE|${LEV}|תקרת מינוף"
  "LEVERAGE|${LEV}|מינוף בפועל"
  "HFT_MIN_NOTIONAL_USDT|5|מינימום בינאנס — מתחת לזה הזמנות נדחות"
  "DAILY_MAX_DRAWDOWN_PCT|${DKILL}|kill יומי"
  "MAX_DRAWDOWN_PCT|${SKILL}|kill סשן"
  "MIN_EXPECTED_NET_PROFIT_USDT|${MIN_NET_PROFIT}|שער רווח-נטו — מותאם לגודל הפוזיציה"
  "MIN_PROFIT_COST_RATIO|3.0|רווח צפוי לפחות פי 3 מהעמלה"
  "MAKER_ENTRY_ENABLED|true|כניסה כ-maker — 0.10% -> 0.07%"
  "MAKER_ENTRY_FALLBACK_MARKET|false|לא לרדוף אחרי המחיר ב-MARKET"
)

# ── swing: מסחר מגמה במקום סקאלפ ──────────────────────────────────
# עמלת סבב היא אחוז קבוע מהנוטיונל. יעד של 0.3% משאיר לה 23% מהרווח;
# יעד של 4% משאיר לה 1.8%. זה כל ההבדל בין הסקאלפ ל-swing בחשבון קטן.
# ── active: יותר פוזיציות במקביל, טווח בינוני ─────────────────────
# הפעילות מגיעה מריבוי פוזיציות ולא מכיווץ היעדים — יעד של 1.5%-5%
# משאיר לעמלה 1.4%-4.7% מהרווח, לעומת 23% בסקאלפ של 0.3%.
# ── unleashed: כל שער שניתן לפתוח — פתוח ──────────────────────────
# זו הרמה האחרונה. אחריה לא נשאר שום פרמטר שמגביל כניסות.
if [ "$LEVEL" = "unleashed" ]; then
  SETTINGS+=(
    "HFT_TIMEFRAME|3m|נר של 3 דקות"
    "ML_LABEL_HORIZON|5|אופק התווית — 15 דקות"
    "ML_LABEL_THRESHOLD|0.0025|0.25% ל-15 דקות"
    "TECHNICAL_FALLBACK_SIGNALS|true|*** מקור האותות השני — היה כבוי ***"
    "TECHNICAL_FALLBACK_MIN_SCORE|62|סף ה-fallback (היה 78)"
    "TECHNICAL_FALLBACK_STRONG_MODE|false|בלי דרישת נפח מוגברת"
    "BLOCK_WHEN_MODEL_UNHEALTHY|false|לא לחסום גם כשהמודל מוכרז לא בריא"
    "CATALYST_NEGATIVE_BLOCK|false|לא לחסום על חדשות שליליות"
    "BLOCK_ON_STALE_NEWS|false|לא לחסום על חדשות ישנות"
    "REGIME_BLOCK_LONGS_DROP_PCT|0.50|חסימת משטר שוק — מנוטרלת"
    "REGIME_BLOCK_SHORTS_RALLY_PCT|0.50|חסימת משטר שוק — מנוטרלת"
    "MIN_ATR_PCT|0|בלי רצפת תנודתיות"
    "MIN_SYMBOL_PRICE_USDT|0.005|גם מטבעות זולים מאוד"
    "SL_MIN_PCT|0.005|סטופ מינימלי"
    "SL_MAX_PCT|0.018|סטופ מרבי"
    "TP_MIN_PCT|0.010|יעד מינימלי"
    "TP_MAX_PCT|0.045|יעד מרבי"
    "TP_SL_RATIO|2.2|יעד = פי 2.2 מהסטופ"
    "MIN_TP_SL_RATIO|1.5|רצפת R:R — הדבר היחיד שנשאר"
    "MIN_NET_REWARD_RISK|1.1|שער R:R נטו — כמעט פתוח"
    "MIN_PROFIT_COST_RATIO|1.2|רווח פי 1.2 מהעמלה (היה 3.0)"
    "MAX_RISK_PCT|0.12|12% מההון בסיכון לעסקה"
    "MAX_SAME_DIRECTION_POSITIONS|5|5 מתוך 6 באותו כיוון"
    "STALE_EXIT_SECONDS|1800|30 דקות"
    "PROFIT_TAKE_PCT|0.015|לקיחת רווח ב-1.5%"
    "PROFIT_TAKE_MIN_AGE_SECONDS|180|3 דקות מינימום"
    "PROFIT_LOCK_TRIGGER_PCT|0.012|נדרכת ב-1.2% — נמדד על 60 עסקאות"
    "PROFIT_LOCK_RETRACE_PCT|0.005|נסיגה של 0.5% לפני יציאה"
    "PROFIT_LOCK_MIN_NET_PCT|0.004|0.4% נטו מינימום"
    "OPPOSITE_PRESSURE_PCT|0.006|לחץ נגדי — 0.6% (פחות יציאות מוקדמות)"
    "SCORE_ENTRY|62|הסף הנמוך ביותר שהמערכת מאפשרת"
    "DECISION_MIN_CONSENSUS|0.50|הסכמת ועדה — חצי מספיק"
    "DECISION_LIVE_MIN_CONSENSUS|0.50|בלייב היה 0.80 — השער האחרון"
    "DECISION_MIN_SCORE_AFTER_GUARDS|55|ציון אחרי קנסות הוועדה (היה 70)"
    "COMMITTEE_MIN_SIZE_MULTIPLIER|0.60|*** רצפת גודל — הוועדה כיווצה ל-0.18 ***"
    "MAX_ENTRIES_PER_HOUR|0|*** מכסת עסקאות לשעה — 0 = ללא הגבלה (היה 6) ***"
    "SYMBOL_REENTRY_COOLDOWN_SECONDS|0|בלי צינון בין עסקאות באותו סימבול (היה 600)"
    "MAX_SPREAD_PCT|0.010|מרווח מקסימלי 1% (היה 0.1% — פסל אלטים)"
    "CROWDED_FUNDING_RATE|0.0030|סף funding עמוס (היה 0.0005)"
    "MAX_ABS_FUNDING_RATE|0.0050|תקרת funding מוחלטת"
    "FUNDING_AVOID_MINUTES|0|בלי הימנעות סביב שעת ה-funding"
    "BROAD_MARKET_MIN_QUOTE_VOLUME_USDT|300000|רצפת נפח נמוכה יותר"
    "MOMENTUM_MIN_QUOTE_VOLUME_USDT|1000000|רצפת נפח למומנטום"
    "NEW_LISTING_MIN_QUOTE_VOLUME_USDT|1000000|רצפת נפח לרישומים חדשים"
    "SCAN_TOP_N|200|יקום מקסימלי"
    "TREND_RUNNER_ENABLED|true|לתת למגמה לרוץ"
    "HIGH_CONVICTION_SIZE_MULTIPLIER|1.25|הגדלה על ביטחון"
    "CAPITAL_ALLOCATOR_SIZE_MULTIPLIER|1.25|הגדלה מהמקצה הון"
    "LIVE_REQUIRED_MIN_EQUITY_USDT|12|רצפה מינימלית"
  )
fi

# ── turbo: מקסימום מינוף, מקסימום פעילות, מקסימום סיכון ───────────
if [ "$LEVEL" = "turbo" ]; then
  SETTINGS+=(
    "HFT_TIMEFRAME|3m|נר של 3 דקות — קצב גבוה"
    "ML_LABEL_HORIZON|5|אופק התווית — 5 נרות = 15 דקות"
    "ML_LABEL_THRESHOLD|0.0025|0.25% ל-15 דקות"
    "SL_MIN_PCT|0.005|סטופ מינימלי"
    "SL_MAX_PCT|0.018|סטופ מרבי"
    "TP_MIN_PCT|0.012|יעד מינימלי"
    "TP_MAX_PCT|0.045|יעד מרבי"
    "TP_SL_RATIO|2.4|יעד = פי 2.4 מהסטופ"
    "MIN_TP_SL_RATIO|2.0|רצפה — R:R לא מתחת ל-1:2"
    "MIN_NET_REWARD_RISK|1.4|שער כניסה מקל"
    "MIN_PROFIT_COST_RATIO|2.0|רווח לפחות פי 2 מהעמלה (במקום 3)"
    "MAX_RISK_PCT|0.10|10% מההון בסיכון לעסקה"
    "MAX_SAME_DIRECTION_POSITIONS|3|מקס 3 מתוך 4 באותו כיוון"
    "STALE_EXIT_SECONDS|1800|30 דקות"
    "PROFIT_TAKE_PCT|0.018|לקיחת רווח ב-1.8%"
    "PROFIT_TAKE_MIN_AGE_SECONDS|300|5 דקות מינימום"
    "PROFIT_LOCK_TRIGGER_PCT|0.008|נעילת רווח נדרכת ב-0.8%"
    "PROFIT_LOCK_RETRACE_PCT|0.003|יוצאת אחרי נסיגה של 0.3%"
    "PROFIT_LOCK_MIN_NET_PCT|0.002|רק אם נשאר 0.2% נטו"
    "OPPOSITE_PRESSURE_PCT|0.004|לחץ נגדי — 0.4%"
    "SCORE_ENTRY|70|סף נמוך — מקסימום כניסות"
    "SCAN_TOP_N|140|יקום רחב מאוד"
    "TREND_RUNNER_ENABLED|true|לתת למגמה לרוץ"
    "HIGH_CONVICTION_SIZE_MULTIPLIER|1.20|הגדלה על ביטחון גבוה"
    "CAPITAL_ALLOCATOR_SIZE_MULTIPLIER|1.20|הגדלה מהמקצה הון"
    "LIVE_REQUIRED_MIN_EQUITY_USDT|15|רצפה נמוכה יותר"
  )
fi

if [ "$LEVEL" = "active" ]; then
  SETTINGS+=(
    "HFT_TIMEFRAME|5m|נר של 5 דקות"
    "ML_LABEL_HORIZON|4|אופק התווית — 4 נרות = 20 דקות"
    "ML_LABEL_THRESHOLD|0.003|0.3% ל-20 דקות"
    "SL_MIN_PCT|0.006|סטופ מינימלי"
    "SL_MAX_PCT|0.020|סטופ מרבי"
    "TP_MIN_PCT|0.015|יעד מינימלי"
    "TP_MAX_PCT|0.050|יעד מרבי"
    "TP_SL_RATIO|2.5|יעד = פי 2.5 מהסטופ"
    "MIN_TP_SL_RATIO|2.0|רצפה — R:R לעולם לא מתחת ל-1:2"
    "MIN_NET_REWARD_RISK|1.6|שער כניסה מקל יותר מ-swing"
    "MAX_RISK_PCT|0.04|4% לעסקה x4 פוזיציות = 16% חשיפה"
    "MAX_SAME_DIRECTION_POSITIONS|3|מקס 3 מתוך 4 באותו כיוון"
    "STALE_EXIT_SECONDS|2700|45 דקות במקום 15"
    "PROFIT_TAKE_PCT|0.020|לקיחת רווח ב-2%"
    "PROFIT_TAKE_MIN_AGE_SECONDS|600|10 דקות מינימום בעסקה"
    "PROFIT_LOCK_TRIGGER_PCT|0.010|נעילת רווח נדרכת ב-1%"
    "PROFIT_LOCK_RETRACE_PCT|0.004|יוצאת אחרי נסיגה של 0.4%"
    "PROFIT_LOCK_MIN_NET_PCT|0.003|רק אם נשאר 0.3% נטו"
    "OPPOSITE_PRESSURE_PCT|0.005|לחץ נגדי — 0.5%"
    "SCORE_ENTRY|74|סף נמוך יותר — יותר כניסות"
    "SCAN_TOP_N|100|יקום רחב — יותר הזדמנויות"
    "TREND_RUNNER_ENABLED|true|לתת למגמה לרוץ"
  )
fi

if [ "$LEVEL" = "swing" ]; then
  SETTINGS+=(
    "MAX_SAME_DIRECTION_POSITIONS|2|שתיהן יכולות להיות באותו כיוון"
    "HFT_TIMEFRAME|15m|נר של 15 דקות במקום דקה"
    "ML_LABEL_HORIZON|4|אופק התווית — 4 נרות = שעה"
    "ML_LABEL_THRESHOLD|0.006|0.6% לשעה; 0.05% ב-15m הוא רעש"
    "SL_MIN_PCT|0.010|סטופ מינימלי — מרווח לנשימה"
    "SL_MAX_PCT|0.035|סטופ מרבי"
    "TP_MIN_PCT|0.025|יעד מינימלי"
    "TP_MAX_PCT|0.090|יעד מרבי"
    "TP_SL_RATIO|2.5|יעד = פי 2.5 מהסטופ"
    "MIN_TP_SL_RATIO|2.0|רצפה — R:R לעולם לא מתחת ל-1:2"
    "MIN_NET_REWARD_RISK|2.0|שער כניסה: רווח נטו לפחות פי 2 מהסיכון"
    "MAX_RISK_PCT|0.06|6% מההון בסיכון לעסקה"
    "STALE_EXIT_SECONDS|0|כיבוי יציאת אין-תנועה"
    "PROFIT_TAKE_PCT|0.040|לקיחת רווח ב-4% תזוזת מחיר"
    "PROFIT_TAKE_MIN_AGE_SECONDS|1800|לא לגעת בעסקה בחצי השעה הראשונה"
    "PROFIT_LOCK_TRIGGER_PCT|0.020|נעילת רווח נדרכת ב-2%"
    "PROFIT_LOCK_RETRACE_PCT|0.008|יוצאת אחרי נסיגה של 0.8%"
    "PROFIT_LOCK_MIN_NET_PCT|0.005|רק אם נשאר 0.5% נטו"
    "OPPOSITE_PRESSURE_PCT|0.010|לחץ נגדי — 1% במקום 0.2%"
    "SCORE_ENTRY|82|סף כניסה גבוה יותר — פחות עסקאות"
    "TREND_RUNNER_ENABLED|true|לתת למגמה לרוץ"
    "SCAN_TOP_N|60|יקום ממוקד יותר"
  )
fi

get_val() {
  grep -E "^[[:space:]]*${1}[[:space:]]*=" "$ENV_FILE" 2>/dev/null \
    | tail -n 1 | sed -E "s/^[^=]*=[[:space:]]*//; s/[[:space:]]*(#.*)?$//"
}

set_val() {
  local key="$1" val="$2" tmp
  tmp="$(mktemp)"
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$ENV_FILE"; then
    awk -v k="$key" -v v="$val" '
      $0 ~ "^[[:space:]]*" k "[[:space:]]*=" { print k "=" v; next }
      { print }
    ' "$ENV_FILE" > "$tmp"
  else
    cp "$ENV_FILE" "$tmp"
    printf '%s=%s\n' "$key" "$val" >> "$tmp"
  fi
  mv "$tmp" "$ENV_FILE"
}

echo ""
echo "══════════════════════════════════════════════════════════════"
if [ "$APPLY" -eq 1 ]; then
  echo "  כיול .env לחשבון קטן — מבצע"
else
  echo "  כיול .env לחשבון קטן — תצוגה מקדימה (לא משנה כלום)"
fi
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "  הגדרה                                       עכשיו  ->  בטוח"
printf "  %s\n" "──────────────────────────────────────────────────────────"

CHANGES=0
for row in "${SETTINGS[@]}"; do
  key="${row%%|*}"
  rest="${row#*|}"
  safe="${rest%%|*}"
  cur="$(get_val "$key")"
  [ -z "$cur" ] && cur="-"
  if [ "$cur" = "$safe" ]; then
    printf "  %-38s %8s      ✓\n" "$key" "$cur"
  else
    printf "  %-38s %8s  ->  %-8s  <--\n" "$key" "$cur" "$safe"
    CHANGES=$((CHANGES + 1))
  fi
done

echo ""

# ── מה זה אומר בכסף ────────────────────────────────────────────────
NOTIONAL="$REAL_NOTIONAL"
NOTIONAL_X="$(_notional "$EQUITY" "$POS" "$SIZE_X" "$FRAC" "$LEV")"
MARGIN=$(awk -v n="$NOTIONAL" -v l="$LEV" 'BEGIN{printf "%.2f", n/l}')
TOTAL=$(awk -v n="$NOTIONAL" -v p="$POS" 'BEGIN{printf "%.2f", n*p}')
FEE_M=$(awk -v n="$NOTIONAL" 'BEGIN{printf "%.3f", n*0.0007}')
KILL=$(awk  -v e="$EQUITY" -v d="$DKILL" 'BEGIN{printf "%.2f", e*d}')
SKILLD=$(awk -v e="$EQUITY" -v d="$SKILL" 'BEGIN{printf "%.2f", e*d}')
PER1=$(awk -v n="$NOTIONAL" 'BEGIN{printf "%.2f", n*0.01}')
# הפסד בסטופ טיפוסי של 1.5% מהנוטיונל
case "$LEVEL" in swing|active|turbo|unleashed) _RP=1 ;; *) _RP=0 ;; esac
if [ "$_RP" = "1" ]; then
  # risk parity: notional is capped at (equity x MAX_RISK_PCT)/sl_pct, so the
  # dollar risk per trade is the budget itself, whatever the stop width.
  RISKPCT=0.06
  [ "$LEVEL" = "active" ] && RISKPCT=0.04
  [ "$LEVEL" = "turbo" ]  && RISKPCT=0.10
  [ "$LEVEL" = "unleashed" ] && RISKPCT=0.12
  STOP=$(awk -v e="$EQUITY" -v r="$RISKPCT" 'BEGIN{printf "%.2f", e*r}')
  STOP_LABEL="תקציב סיכון לעסקה   "
else
  STOP=$(awk -v n="$NOTIONAL" 'BEGIN{printf "%.2f", n*0.015}')
  STOP_LABEL="הפסד בסטופ (1.5%)   "
fi
NSTOP=$(awk -v e="$EQUITY" -v s="$STOP" 'BEGIN{printf "%d", (s>0? e/s : 0)}')
NKILL=$(awk -v k="$KILL" -v s="$STOP" 'BEGIN{printf "%.1f", (s>0? k/s : 0)}')
MOVE=$(awk -v n="$NOTIONAL" -v g="$MIN_NET_PROFIT" 'BEGIN{printf "%.2f", 100*(g+n*0.0007)/n}')

echo "  ── רמה: ${LEVEL}   |   הון: ${EQUITY}\$ ──"
printf "     מרג'ין לפוזיציה     : %s\$\n" "$MARGIN"
printf "     נוטיונל (מינוף %sx)  : %s\$ .. %s\$  (בסיס..קיצוני)\n" "$LEV" "$NOTIONAL" "$NOTIONAL_X"
printf "     חשיפה מקסימלית      : %s\$   (%s פוזיציות)\n" "$TOTAL" "$POS"
printf "     תזוזה של 1%% שווה    : %s\$\n" "$PER1"
printf "     עמלת סבב (maker)    : %s\$\n" "$FEE_M"
printf "     שער כניסה דורש      : תזוזה של %s%%\n" "$MOVE"
echo ""
printf "     %s : -%s\$\n" "$STOP_LABEL" "$STOP"
printf "     kill יומי נעצר ב-   : -%s\$   = %s סטופים\n" "$KILL" "$NKILL"
printf "     kill סשן נעצר ב-    : -%s\$\n" "$SKILLD"
printf "     סטופים עד אפס הון   : %s\n" "$NSTOP"
echo ""

# ── השוואת כל הרמות ────────────────────────────────────────────────
echo "  ── כל הרמות, על ${EQUITY}\$ ──"
echo "     רמה            מינוף פוז'  נוטיונל    1% שווה  סיכון    עד אפס"
echo "     ─────────────────────────────────────────────────────────────"
_row() {
  awk -v name="$1" -v lev="$2" -v frac="$3" -v pos="$4" -v risk="$5" -v sb="$6" -v e="$EQUITY" -v cur="$LEVEL" 'BEGIN{
    slice = e/pos; n = slice*sb*lev;
    nc = slice*lev; mc = e*frac*lev; cap = (mc<nc)?mc:nc; if (n>cap) n=cap;
    # swing/active size from a risk budget, so the dollar risk is the budget;
    # the fixed-tier levels approximate it with a 1.5% stop on the notional.
    st = (risk > 0) ? e*risk : n*0.015;
    mark = (name == cur) ? " <--" : "";
    printf "     %-14s %3dx %2d  %8.2f$  %7.2f$  %6.2f$   %6d%s\n", name, lev, pos, n, n*0.01, st, (st>0? e/st : 0), mark;
  }'
}
_row conservative 5  0.10 2 0    0.08
_row balanced     10 0.15 2 0    0.12
_row aggressive   15 0.25 2 0    0.18
_row max          20 0.35 2 0    0.25
_row swing        10 0.30 2 0.06 0.30
_row active       10 0.22 4 0.04 0.22
_row turbo        20 0.25 4 0.10 0.85
_row unleashed    20 0.18 6 0.12 0.85
echo ""
echo "     \"סטופים עד 0\" = כמה עסקאות מפסידות ברצף מוחקות את החשבון."
echo "     גודל לא משנה אם המערכת רווחית — רק כמה מהר תדע."
echo ""

if [ "$CHANGES" -eq 0 ]; then
  echo "  ✅ הכול כבר מכויל. אין מה לשנות."
  echo ""
  exit 0
fi

if [ "$APPLY" -eq 0 ]; then
  echo "  $CHANGES הגדרות ישתנו. כלום לא נגעתי בו עדיין."
  echo ""
  echo "  להרצה בפועל:"
  echo "      bash safe_settings.sh --level $LEVEL --apply"
  echo ""
  exit 0
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP=".env.backup.${STAMP}"
cp "$ENV_FILE" "$BACKUP"

for row in "${SETTINGS[@]}"; do
  key="${row%%|*}"
  rest="${row#*|}"
  safe="${rest%%|*}"
  set_val "$key" "$safe"
done

echo "  ✅ $CHANGES הגדרות עודכנו."
echo "     גיבוי: $BACKUP"
echo ""
echo "  ⚠️  עמלות: ודא ש-ESTIMATED_TAKER_FEE_PCT תואם לחשבון האמיתי שלך."
echo "     VIP0 בבינאנס = 0.0005. עם הנחת BNB — פחות."
echo "     ערך שגוי כאן מטה את כל הסטטיסטיקה."
echo ""
echo "  הצעד הבא:"
echo "      ./venv/bin/python status.py --live"
echo ""
