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
    conservative|balanced|aggressive|max) LEVEL="$1" ;;
    *) echo "לא מכיר את הדגל: $1"; echo "שימוש: bash safe_settings.sh [--level conservative|balanced|aggressive|max] [--apply]"; exit 1 ;;
  esac
  shift
done

case "$LEVEL" in
  conservative) LEV=5;  FRAC=0.10; POS=2; DKILL=0.05; SKILL=0.10; SIZE_B=0.08; SIZE_H=0.12; SIZE_X=0.20 ;;
  balanced)     LEV=10; FRAC=0.15; POS=2; DKILL=0.10; SKILL=0.20; SIZE_B=0.12; SIZE_H=0.18; SIZE_X=0.25 ;;
  aggressive)   LEV=15; FRAC=0.25; POS=2; DKILL=0.15; SKILL=0.30; SIZE_B=0.18; SIZE_H=0.25; SIZE_X=0.35 ;;
  max)          LEV=20; FRAC=0.35; POS=2; DKILL=0.25; SKILL=0.50; SIZE_B=0.25; SIZE_H=0.35; SIZE_X=0.45 ;;
  *) echo "רמה לא מוכרת: $LEVEL  (conservative | balanced | aggressive | max)"; exit 1 ;;
esac

# ── ההון בחשבון ───────────────────────────────────────────────────
EQUITY="${EQUITY_USDT:-47}"

# שער הרווח-נטו הוא בדולרים מוחלטים, לא באחוזים. עם פוזיציות קטנות
# ערך קבוע של 0.25$ דורש תזוזה של יותר מ-1% — הבוט פשוט לא ייכנס לשום עסקה.
# לכן מחשבים אותו מהנוטיונל, כך שהתזוזה הנדרשת נשארת ~0.30%.
#   notional = הון × 0.10 (מרג'ין) × 5 (מינוף) = הון × 0.5
#   min_net  = notional × (0.0030 - 0.0007 עמלת maker) = notional × 0.0023
MIN_NET_PROFIT="$(awk -v e="$EQUITY" -v f="$FRAC" -v l="$LEV" 'BEGIN{v=e*f*l*0.0023; if(v<0.02)v=0.02; printf "%.2f", v}')"

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
MARGIN=$(awk -v e="$EQUITY" -v f="$FRAC" 'BEGIN{printf "%.2f", e*f}')
NOTIONAL=$(awk -v m="$MARGIN" -v l="$LEV" 'BEGIN{printf "%.2f", m*l}')
TOTAL=$(awk -v n="$NOTIONAL" -v p="$POS" 'BEGIN{printf "%.2f", n*p}')
FEE_M=$(awk -v n="$NOTIONAL" 'BEGIN{printf "%.3f", n*0.0007}')
KILL=$(awk  -v e="$EQUITY" -v d="$DKILL" 'BEGIN{printf "%.2f", e*d}')
SKILLD=$(awk -v e="$EQUITY" -v d="$SKILL" 'BEGIN{printf "%.2f", e*d}')
PER1=$(awk -v n="$NOTIONAL" 'BEGIN{printf "%.2f", n*0.01}')
# הפסד בסטופ טיפוסי של 1.5% מהנוטיונל
STOP=$(awk -v n="$NOTIONAL" 'BEGIN{printf "%.2f", n*0.015}')
NSTOP=$(awk -v e="$EQUITY" -v s="$STOP" 'BEGIN{printf "%d", (s>0? e/s : 0)}')
NKILL=$(awk -v k="$KILL" -v s="$STOP" 'BEGIN{printf "%.1f", (s>0? k/s : 0)}')
MOVE=$(awk -v n="$NOTIONAL" -v g="$MIN_NET_PROFIT" 'BEGIN{printf "%.2f", 100*(g+n*0.0007)/n}')

echo "  ── רמה: ${LEVEL}   |   הון: ${EQUITY}\$ ──"
printf "     מרג'ין לפוזיציה     : %s\$\n" "$MARGIN"
printf "     נוטיונל (מינוף %sx)  : %s\$\n" "$LEV" "$NOTIONAL"
printf "     חשיפה מקסימלית      : %s\$   (%s פוזיציות)\n" "$TOTAL" "$POS"
printf "     תזוזה של 1%% שווה    : %s\$\n" "$PER1"
printf "     עמלת סבב (maker)    : %s\$\n" "$FEE_M"
printf "     שער כניסה דורש      : תזוזה של %s%%\n" "$MOVE"
echo ""
printf "     הפסד בסטופ (1.5%%)   : -%s\$\n" "$STOP"
printf "     kill יומי נעצר ב-   : -%s\$   = %s סטופים\n" "$KILL" "$NKILL"
printf "     kill סשן נעצר ב-    : -%s\$\n" "$SKILLD"
printf "     סטופים עד אפס הון   : %s\n" "$NSTOP"
echo ""

# ── השוואת כל הרמות ────────────────────────────────────────────────
echo "  ── כל הרמות, על ${EQUITY}\$ ──"
echo "     רמה            מינוף   נוטיונל    1% שווה   סטופ    סטופים עד 0"
echo "     ─────────────────────────────────────────────────────────────"
_row() {
  awk -v name="$1" -v lev="$2" -v frac="$3" -v pos="$4" -v e="$EQUITY" -v cur="$LEVEL" 'BEGIN{
    n = e*frac*lev; st = n*0.015;
    mark = (name == cur) ? " <--" : "";
    printf "     %-14s %3dx  %8.2f$  %7.2f$  %6.2f$   %8d%s\n", name, lev, n, n*0.01, st, (st>0? e/st : 0), mark;
  }'
}
_row conservative 5  0.10 2
_row balanced     10 0.15 2
_row aggressive   15 0.25 2
_row max          20 0.35 2
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
