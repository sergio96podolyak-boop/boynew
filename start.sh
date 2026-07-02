#!/usr/bin/env bash
#
# start.sh — הפעלה בפקודה אחת.
# מסדר הכול לבד: סביבה וירטואלית, תלויות, קובץ .env, ואז מריץ את הבוט + הדשבורד.
#
# שימוש (בטרמינל של VS Code, בתוך תיקיית boynew):
#     bash start.sh            # paper (ברירת מחדל, בלי כסף אמיתי)
#     bash start.sh --live     # לייב — דורש מפתחות אמיתיים ב-.env
#
# אחרי שזה עולה, פתח בדפדפן:  http://localhost:8501
#
set -e
cd "$(dirname "$0")"

PY=python3
command -v "$PY" >/dev/null 2>&1 || { echo "❌ python3 לא מותקן. התקן Python 3 קודם."; exit 1; }

# 1) סביבה וירטואלית
if [ ! -d venv ]; then
  echo "📦 יוצר סביבה וירטואלית (פעם אחת)..."
  "$PY" -m venv venv
fi

# 2) תלויות — מתקין רק אם streamlit עוד לא קיים (כדי שהרצות הבאות יהיו מהירות)
if ! ./venv/bin/python -c "import streamlit" >/dev/null 2>&1; then
  echo "⬇️  מתקין תלויות (פעם ראשונה — יכול לקחת כמה דקות)..."
  ./venv/bin/python -m pip install --upgrade pip -q
  ./venv/bin/pip install -r requirements.txt
else
  echo "✅ התלויות כבר מותקנות."
fi

# 3) קובץ .env — נוצר מהתבנית אם חסר (ברירת מחדל = paper, בלי כסף אמיתי)
if [ ! -f .env ]; then
  cp .env.example .env
  echo "📝 נוצר .env במצב paper. ללייב — ערוך אותו והכנס מפתחות + PAPER_TRADING=false."
fi

# 4) הפעלה — main.py מריץ את המנוע וגם מעלה את הדשבורד
echo ""
if [[ " $* " == *" --live "* ]]; then
  echo "🔴 מפעיל LIVE רק אם .env כולל LIVE_TRADING_ENABLED=true + אישור סיכון."
  echo "   אם זה נעצר — זו נעילת בטיחות, לא קריסה."
  RUN_ENV=()
else
  echo "🟡 מפעיל PAPER גם אם .env מכוון ללייב — בלי כסף אמיתי."
  RUN_ENV=(PAPER_TRADING=true)
fi
echo "🚀 מפעיל את הבוט + הדשבורד..."
echo "🌐 פתח בדפדפן:  http://localhost:8501"
echo "   (לעצירה: Ctrl+C)"
echo ""
# מונע מהמק להירדם בזמן שהבוט רץ — שינה = לולאה קפואה ופוזיציות בלי ניהול
if command -v caffeinate >/dev/null 2>&1; then
  exec env "${RUN_ENV[@]}" caffeinate -is ./venv/bin/python main.py "$@"
else
  exec env "${RUN_ENV[@]}" ./venv/bin/python main.py "$@"
fi
