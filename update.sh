#!/usr/bin/env bash
#
# update.sh — מושך את הגרסה האחרונה ומאמת שהיא באמת הגיעה.
#
# למה זה קיים: `bash start.sh` רק מריץ את הקוד שכבר על הדיסק. בלי משיכה
# לפניו הוא מפעיל את הגרסה הישנה, והכל "לא משתנה" בלי שום הודעת שגיאה.
# הסקריפט הזה עושה את שני השלבים ומדפיס בסוף מה באמת רץ.
#
# שימוש:
#     bash update.sh              # משיכה + אימות
#     bash update.sh --run        # משיכה + אימות + הפעלה
#
set -e
cd "$(dirname "$0")"
BRANCH="claude/serene-knuth-ax2o6m"

echo "📥 מושך את $BRANCH ..."

# 1) שינויים מקומיים לצד — כולל קבצים לא-מנוהלים. אף פעם לא מוחקים.
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "   יש שינויים מקומיים — שומר אותם ב-stash (לשחזור: git stash pop)"
  git stash push -u -m "auto-stash לפני update $(date +%H:%M)" >/dev/null
fi

# 2) משיכה. merge --ff-only נכשל ברעש במקום ליצור מיזוג מבלבל.
git fetch origin "$BRANCH" --quiet
git checkout "$BRANCH" --quiet 2>/dev/null || git checkout -b "$BRANCH" "origin/$BRANCH" --quiet
git merge --ff-only "origin/$BRANCH" --quiet

# 3) אימות — מה באמת יושב על הדיסק עכשיו
echo ""
echo "✅ מה רץ עכשיו:"
echo "   קומיט:        $(git log --oneline -1)"
echo "   dashboard.py: $(wc -l < dashboard.py | tr -d ' ') שורות"
for f in dashboard_floor.py dashboard_market.py dashboard_ledger.py; do
  [ -f "$f" ] && echo "   $f ✓" || echo "   $f ❌ חסר!"
done

# 4) בדיקה שהמקטעים הישנים באמת נעלמו
if grep -q "מצב מסחר עכשיו" dashboard.py 2>/dev/null; then
  echo ""
  echo "❌ הקוד הישן עדיין כאן — משהו השתבש. אל תריץ, תשלח את הפלט הזה."
  exit 1
fi
echo "   כפילות:       נוקתה ✓"

if [[ " $* " == *" --run "* ]]; then
  echo ""
  exec bash start.sh
fi
echo ""
echo "עכשיו:  bash start.sh"
