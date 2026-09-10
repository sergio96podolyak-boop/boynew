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
[ "${1:-}" = "--apply" ] && APPLY=1

# ── ההון בחשבון ───────────────────────────────────────────────────
EQUITY="${EQUITY_USDT:-47}"

# שער הרווח-נטו הוא בדולרים מוחלטים, לא באחוזים. עם פוזיציות קטנות
# ערך קבוע של 0.25$ דורש תזוזה של יותר מ-1% — הבוט פשוט לא ייכנס לשום עסקה.
# לכן מחשבים אותו מהנוטיונל, כך שהתזוזה הנדרשת נשארת ~0.30%.
#   notional = הון × 0.10 (מרג'ין) × 5 (מינוף) = הון × 0.5
#   min_net  = notional × (0.0030 - 0.0007 עמלת maker) = notional × 0.0023
MIN_NET_PROFIT="$(awk -v e="$EQUITY" 'BEGIN{v=e*0.5*0.0023; if(v<0.02)v=0.02; printf "%.2f", v}')"

# מפתח | ערך בטוח | הסבר
SETTINGS=(
  "LIVE_MAX_MARGIN_FRACTION|0.10|מרג'ין מקסימלי לפוזיציה מתוך ההון"
  "MAX_MARGIN_FRACTION_PER_POSITION|0.10|אותו cap, מסלול קלאסי"
  "HFT_MAX_OPEN_POSITIONS|2|כמה פוזיציות במקביל"
  "SIZE_BASE_PCT|0.08|גודל בסיס"
  "SIZE_HIGH_PCT|0.12|גודל בציון גבוה"
  "SIZE_EXTREME_PCT|0.20|גודל בציון קיצוני"
  "HIGH_CONVICTION_SIZE_MULTIPLIER|1.00|בלי הגדלה על ביטחון גבוה"
  "CAPITAL_ALLOCATOR_SIZE_MULTIPLIER|1.00|בלי הגדלה מהמקצה הון"
  "LIVE_REQUIRED_MIN_EQUITY_USDT|25|רצפה — מתחת לזה הבוט לא סוחר"
  "LIVE_MAX_LEVERAGE|5|תקרת מינוף"
  "LEVERAGE|5|מינוף בפועל"
  "HFT_MIN_NOTIONAL_USDT|5|מינימום בינאנס — מתחת לזה הזמנות נדחות"
  "DAILY_MAX_DRAWDOWN_PCT|0.05|kill יומי"
  "MAX_DRAWDOWN_PCT|0.10|kill סשן"
  "MIN_EXPECTED_NET_PROFIT_USDT|${MIN_NET_PROFIT}|שער רווח-נטו — מותאם לגודל הפוזיציה"
  "MIN_PROFIT_COST_RATIO|3.0|רווח צפוי לפחות פי 3 מהעמלה"
  "MAKER_ENTRY_ENABLED|true|כניסה כ-maker — 0.10% -> 0.07%"
  "MAKER_ENTRY_FALLBACK_MARKET|false|לא לרדוף אחרי המחיר ב-MARKET"
)

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
MARGIN=$(awk -v e="$EQUITY" 'BEGIN{printf "%.2f", e*0.10}')
NOTIONAL=$(awk -v m="$MARGIN" 'BEGIN{printf "%.2f", m*5}')
TOTAL=$(awk -v n="$NOTIONAL" 'BEGIN{printf "%.2f", n*2}')
FEE_T=$(awk -v n="$NOTIONAL" 'BEGIN{printf "%.3f", n*0.0010}')
FEE_M=$(awk -v n="$NOTIONAL" 'BEGIN{printf "%.3f", n*0.0007}')
KILL=$(awk -v e="$EQUITY" 'BEGIN{printf "%.2f", e*0.05}')

echo "  ── עם ההגדרות הבטוחות, על הון של ${EQUITY}\$ ──"
printf "     מרג'ין לפוזיציה   : %s\$\n" "$MARGIN"
printf "     נוטיונל (מינוף 5) : %s\$\n" "$NOTIONAL"
printf "     חשיפה מקסימלית    : %s\$  (2 פוזיציות)\n" "$TOTAL"
printf "     עמלת סבב — taker  : %s\$\n" "$FEE_T"
printf "     עמלת סבב — maker  : %s\$   ← עם MAKER_ENTRY_ENABLED=true\n" "$FEE_M"
printf "     kill יומי נעצר ב- : -%s\$  (5%%)\n" "$KILL"
MOVE=$(awk -v n="$NOTIONAL" -v g="$MIN_NET_PROFIT" 'BEGIN{printf "%.2f", 100*(g+n*0.0007)/n}')
printf "     שער כניסה — דורש  : תזוזה של %s%% לפחות\n" "$MOVE"
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
  echo "      bash safe_settings.sh --apply"
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
