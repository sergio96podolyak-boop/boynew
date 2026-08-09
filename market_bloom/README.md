# PoMarket

משחק ניהול מיני־מרקט ל־Android ול־iPhone, בנוי ב־Flutter.

## מה כבר עובד

- דמות נשלטת באמצעות ג׳ויסטיק.
- מחסן שממנו אוספים מוצרים ומדף שאותו ממלאים.
- לקוחות נכנסים, מחכים למלאי, קונים ומשלמים בקופה.
- מטבעות, יהלומים, רמות, משימות וארבעה מסלולי שדרוג.
- שמירה אוטומטית ורווחים בזמן שהמשחק סגור.
- בונוס של פרסומת מתוגמלת.
- חנות מוכנה לשלושה מוצרים: ללא פרסומות, חבילת מטבעות וחבילת התחלה.
- אייקון מקורי של PoMarket בכל הגדלים הנדרשים לחנויות.
- תמיכה ב־Android, iOS וגרסת Web לצורכי בדיקה.

## הפעלה מקומית

```bash
cd market_bloom
flutter pub get
flutter run -d chrome
```

בדיקות:

```bash
flutter analyze
flutter test
flutter build web --release
```

## מונטיזציה

ב־Android וב־iOS המשחק משתמש ב־Google Mobile Ads ובחבילת הרכישות הרשמית
של Flutter. מזהי בדיקה של Google מוגדרים כברירת מחדל כדי שלא ייווצרו
חשיפות או קליקים לא חוקיים בזמן הפיתוח.

לפני פרסום:

1. ליצור אפליקציות ב־AdMob ולהחליף את מזהי האפליקציה בקבצים
   `android/app/src/main/AndroidManifest.xml` ו־`ios/Runner/Info.plist`.
2. להעביר את מזהי יחידות הפרסום בבנייה:

   ```bash
   flutter build appbundle \
     --dart-define=ADMOB_REWARDED_ANDROID=ca-app-pub-.../...

   flutter build ipa \
     --dart-define=ADMOB_REWARDED_IOS=ca-app-pub-.../...
   ```

3. ליצור ב־Google Play Console וב־App Store Connect את המוצרים:

   - `pomarket_no_ads`
   - `pomarket_coin_pack`
   - `pomarket_starter_pack`

4. לחבר אימות קבלות בצד שרת לפני השקה מסחרית. הקוד הנוכחי מוכן לזרם
   הרכישה, אבל משתמש בבדיקת קבלה בסיסית בלבד.
5. להוסיף מסך הסכמה לפרטיות של Google UMP, מדיניות פרטיות ו־`app-ads.txt`.

## הכנה לחנויות

מזהה החבילה בשתי הפלטפורמות הוא:

```text
com.sergiopodolyak.pomarket
```

כדי להפיק קבצי חנות במחשב הזה עדיין צריך להתקין:

- Android Studio ו־Android SDK עבור קובץ AAB.
- Xcode מלא וכלי השורה שלו עבור קובץ IPA.
- חשבונות מפתח פעילים של Google Play ושל Apple.

## השלבים הבאים

- פתיחת המאפייה ברמה 3 ואזורי עסק חדשים.
- עובדים אוטומטיים, קופות נוספות ותור לקוחות.
- סאונד, אנימציות, אפקטים וערכת איורים מקורית.
- איזון כלכלת המשחק ומחירי המוצרים.
- אירועים יומיים, הישגים וענן לשמירה בין מכשירים.
- אימות רכישות בשרת, אנליטיקה, Crashlytics והסכמת פרטיות.
