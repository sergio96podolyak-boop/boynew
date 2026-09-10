"""
XGBoost ML model for Binance Futures aggressive trading bot.
Handles per-symbol model training and prediction with fallback to sklearn.
"""

import logging
import warnings
import json
import os
import time
from typing import Optional, Tuple, Dict, List
import numpy as np
import pandas as pd
from sklearn.preprocessing import StandardScaler

# Configure logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

# Try to import XGBoost, fallback to sklearn
try:
    from xgboost import XGBClassifier
    XGBOOST_AVAILABLE = True
except ImportError:
    logger.warning("XGBoost not available, falling back to sklearn GradientBoosting")
    from sklearn.ensemble import GradientBoostingClassifier as XGBClassifier
    XGBOOST_AVAILABLE = False

# Suppress XGBoost warnings
warnings.filterwarnings('ignore', category=UserWarning)

_MODEL_HEALTH_FILE = os.path.join(os.path.dirname(__file__), "..", "data", "model_health.json")


class TradingModel:
    """
    XGBoost-based ML model for trading signal prediction.
    Maintains per-symbol models with automatic retraining logic.
    """

    def __init__(self):
        """Initialize model storage and scalers."""
        self.models: Dict[str, object] = {}  # Per-symbol XGBoost models
        self.scalers: Dict[str, StandardScaler] = {}  # Per-symbol scalers
        self.call_counts: Dict[str, int] = {}  # Track calls for retraining
        self.training_history: Dict[str, dict] = {}  # Track training metadata
        logger.info("TradingModel initialized")

    def _get_xgboost_model(self) -> object:
        """
        Create a *regularized* XGBoost (or sklearn fallback) model.

        The data per symbol is tiny (~150 candles), so a deep, high-tree model
        memorizes the window (train acc ~1.0) and emits fake 97% confidence on
        unseen data. Shallow depth + subsampling + L2 keeps it honest.
        """
        if XGBOOST_AVAILABLE:
            params = {
                'n_estimators': 120,
                'max_depth': 3,
                'learning_rate': 0.05,
                'subsample': 0.8,
                'colsample_bytree': 0.8,
                'min_child_weight': 3,
                'gamma': 0.1,
                'reg_lambda': 1.5,
                'eval_metric': 'mlogloss',
                'random_state': 42,
                'n_jobs': -1,
            }
            try:
                return XGBClassifier(**params)
            except TypeError as e:
                logger.warning(f"Error creating XGBoost model: {e}, using basic params")

        # sklearn GradientBoosting fallback (no xgboost-only kwargs)
        return XGBClassifier(
            n_estimators=120,
            max_depth=3,
            learning_rate=0.05,
            subsample=0.8,
            random_state=42,
        )

    # ------------------------------------------------------------------
    # עזרי הערכה
    # ------------------------------------------------------------------

    @staticmethod
    def _walk_forward_folds(n_rows: int, n_splits: int = 4, min_train: int = 80):
        """
        חלונות walk-forward מתרחבים: מאמנים על העבר, בודקים על העתיד שאחריו.

        לעולם לא מערבבים — בסדרת זמן, ערבוב היה נותן למודל להציץ קדימה
        ולייצר דיוק מדומה. כל fold מאמן על [0:i) ובודק על [i:i+step).

        מחזיר רשימת (train_idx, test_idx). ריקה אם אין מספיק שורות.
        """
        import numpy as np

        if n_rows < min_train + 20:
            return []
        span = n_rows - min_train
        step = max(20, span // n_splits)
        folds = []
        start = min_train
        while start + step <= n_rows and len(folds) < n_splits:
            folds.append((np.arange(0, start), np.arange(start, start + step)))
            start += step
        # שארית משמעותית מצטרפת ל-fold האחרון במקום להיזרק
        if folds and start < n_rows and (n_rows - start) >= 10:
            tr, te = folds[-1]
            folds[-1] = (tr, np.arange(te[0], n_rows))
        return folds

    @staticmethod
    def _class_weights(y):
        """
        משקל הפוך לשכיחות המחלקה.

        היעד לא מאוזן — בחלון מגמתי מחלקה אחת יכולה לתפוס 70% מהשורות,
        והמודל לומד פשוט לנחש אותה תמיד. משקלים מחזירים לכל מחלקה את אותה
        חשיבות בפונקציית ההפסד.
        """
        import numpy as np

        counts = np.bincount(y)
        counts = np.where(counts == 0, 1, counts)
        w = len(y) / (len(counts) * counts)
        return w[y]

    # ביטחון מינימלי שמעליו נחשבת תחזית "כזו שהיינו סוחרים עליה"
    ACT_CONFIDENCE = 0.45
    MIN_ACTIONABLE = 8

    # --- כיול הציון ---
    # הציון היה probability * reliability * 100 מול סף כניסה של 72-78.
    # כדי לעבור אותו נדרשה אמינות >= 0.82 — אבל אמינות היא *יתרון מעל
    # מקריות*, ובשוק נזיל יתרון אמיתי הוא 0.05-0.30. 0.82 פשוט לא קיים.
    # התוצאה: הסף היה בלתי-אפשרי מתמטית, ו"Ranked 0 opportunities" הופיע
    # בכל לולאה. ה-ML לא הזיז אף עסקה מעולם.
    #
    # התיקון ממפה יתרון לטווח 0..1 בעקומה רוויה, כך שסף 72 נשאר בעל
    # משמעות: יתרון 0.20 עם הסתברות 0.85 נותן ציון ~74 (עובר בקושי),
    # ורעש ביתרון 0.02 נותן ~18 (נדחה).
    EDGE_FULL = 0.25     # יתרון שממנו הביטחון מלא
    EDGE_FLOOR = 0.03    # מתחת לזה — רעש, אין אות

    @classmethod
    def _edge_multiplier(cls, edge: float) -> float:
        """ממיר יתרון גולמי למכפיל ציון 0..1 (עקומה רוויה)."""
        if edge <= cls.EDGE_FLOOR:
            return 0.0
        return float(min(1.0, (edge / cls.EDGE_FULL) ** 0.6))

    def _fit_eval_fold(self, X_tr, y_tr, X_te, y_te):
        """
        מאמן על חלון אחד ומחזיר (דיוק, בסיס, יתרון) — או None אם ה-fold לא שמיש.

        `יתרון` הוא המדד שקובע את האמינות, והוא **לא** דיוק כולל.

        למה: הבוט לא סוחר על כל נר. הוא סוחר רק כשהמודל מכריז כיוון
        בביטחון. לכן השאלה הרלוונטית היא "כשהמודל אומר לונג — כמה פעמים
        הוא צודק, לעומת מה שהיה יוצא במקרה?" ולא "כמה נרות הוא סיווג נכון".

        ההבדל מכריע כשמחלקה אחת שולטת. בחלון מגמתי שבו 70% מהנרות הם לונג,
        מודל שתמיד מנחש לונג משיג 70% דיוק בלי שום יכולת — ומודל אמיתי עם
        יתרון קטן ומדויק *נראה גרוע ממנו*. זו בדיוק הסיבה ש-78 מתוך 86
        המודלים קיבלו אמינות 0.

        היתרון נמדד כ-lift מעל שכיחות הבסיס:
            יתרון = (דיוק ההכרזות בכיוון X - שכיחות X בחלון) / (1 - שכיחות X)
        משוקלל לפי כמה הכרזות היו בכל כיוון. חיובי = יש ערך; אפס = מקריות.
        """
        import numpy as np

        classes = np.unique(y_tr)
        if len(classes) < 2:
            return None

        idx = {int(c): i for i, c in enumerate(classes.tolist())}
        keep = np.isin(y_te, classes)
        if keep.sum() < 10:
            return None

        y_tr_m = np.array([idx[int(v)] for v in y_tr], dtype=int)
        y_te_m = np.array([idx[int(v)] for v in y_te[keep]], dtype=int)

        try:
            m = self._get_xgboost_model()
            m.fit(X_tr, y_tr_m, sample_weight=self._class_weights(y_tr_m))
            proba = m.predict_proba(X_te[keep])
        except Exception as exc:
            logger.debug("fold training failed (non-fatal): %s", exc)
            return None

        pred = proba.argmax(axis=1)
        conf = proba.max(axis=1)
        acc = float((pred == y_te_m).mean())

        # בסיס לדיווח: "תמיד המחלקה הנפוצה באימון", נמדד על המבחן
        majority = int(np.bincount(y_tr_m).argmax())
        base = float((y_te_m == majority).mean())

        # --- היתרון על ההכרזות שהיינו באמת סוחרים עליהן ---
        # FLAT (התווית 1) אינה עסקה, ולכן אינה נספרת.
        flat_idx = idx.get(1)
        lift_num = 0.0
        lift_den = 0
        for cls_idx in range(len(classes)):
            if cls_idx == flat_idx:
                continue
            sel = (pred == cls_idx) & (conf >= self.ACT_CONFIDENCE)
            n = int(sel.sum())
            if n == 0:
                continue
            precision = float((y_te_m[sel] == cls_idx).mean())
            base_rate = float((y_te_m == cls_idx).mean())
            if base_rate >= 1.0:
                continue
            lift_num += n * (precision - base_rate) / (1.0 - base_rate)
            lift_den += n

        if lift_den < self.MIN_ACTIONABLE:
            # המודל כמעט לא מכריז כיוון בביטחון — אין ממה להסיק יתרון
            edge = 0.0
        else:
            edge = lift_num / lift_den

        return acc, base, float(edge)

    def train(
        self,
        symbol: str,
        df: pd.DataFrame,
        feature_names: List[str],
        horizon: int = 3,
        threshold: float = 0.003
    ) -> bool:
        """
        Train XGBoost model for a specific symbol.

        Args:
            symbol: Trading pair symbol (e.g., 'BTCUSDT')
            df: DataFrame with OHLCV data and features
            feature_names: List of feature column names to use
            horizon: Candles ahead to predict
            threshold: Return threshold for +1/-1 classification

        Returns:
            bool: True if training successful, False otherwise
        """
        try:
            # Validate input data
            if df is None or len(df) < 100:
                logger.warning(f"{symbol}: Insufficient data for training (< 100 rows)")
                return False

            if not all(col in df.columns for col in feature_names):
                missing = [col for col in feature_names if col not in df.columns]
                logger.warning(f"{symbol}: Missing features: {missing}")
                return False

            # Window the data (last 500 candles)
            max_lookback = 500
            use_rows = min(len(df), max_lookback)
            df_window = df.iloc[-use_rows:].copy().reset_index(drop=True)

            if len(df_window) < 100:
                logger.warning(f"{symbol}: Windowed data too small (< 100 rows)")
                return False

            # Build target: future_return over horizon
            # Labels: 0=SHORT, 1=FLAT, 2=LONG (XGBoost requires non-negative int labels)
            closes = df_window['close'].values
            y = np.ones(len(df_window), dtype=int)  # default: FLAT=1
            for i in range(len(df_window) - horizon):
                future_return = (closes[i + horizon] - closes[i]) / closes[i]
                if future_return > threshold:
                    y[i] = 2  # LONG
                elif future_return < -threshold:
                    y[i] = 0  # SHORT

            # Extract features and target, trim last horizon rows
            X = df_window[feature_names].iloc[:-horizon].copy()
            y_trimmed = y[:-horizon]

            # Drop NaN rows from both X and y together
            valid_mask = ~X.isna().any(axis=1)
            nan_count = (~valid_mask).sum()
            if nan_count > 0:
                logger.warning(f"{symbol}: Found {nan_count} NaN rows, dropping")

            X_clean = X[valid_mask].reset_index(drop=True)
            y_clean = y_trimmed[valid_mask.values]

            if len(X_clean) < 100:
                logger.warning(f"{symbol}: Insufficient data after NaN removal ({len(X_clean)} rows)")
                return False

            # Check for single class
            unique_classes = np.unique(y_clean)
            if len(unique_classes) < 2:
                logger.warning(
                    f"{symbol}: Single class in target ({unique_classes}), "
                    "cannot train classifier"
                )
                return False
            # Scale features
            scaler = StandardScaler()
            X_scaled = scaler.fit_transform(X_clean)

            # ----------------------------------------------------------------
            # הערכה: walk-forward במקום חלוקה בודדת
            # ----------------------------------------------------------------
            # חלוקה של 80/20 על ~186 דגימות משאירה מבחן של ~37 שורות. דיוק
            # שנמדד על 37 דגימות נע בערך ±8% רק מרעש, ולכן ה-reliability של
            # אותו סימבול קפץ בין 0.00 ל-0.48 בין לולאה ללולאה בלי שקרה דבר.
            # כמה חלונות עוקבים, ממוצעים, נותנים אומדן יציב בהרבה.
            folds = self._walk_forward_folds(len(X_scaled), n_splits=4)
            fold_acc, fold_base, fold_edge = [], [], []
            for tr_idx, te_idx in folds:
                res = self._fit_eval_fold(
                    X_scaled[tr_idx], y_clean[tr_idx],
                    X_scaled[te_idx], y_clean[te_idx],
                )
                if res is not None:
                    fold_acc.append(res[0])
                    fold_base.append(res[1])
                    fold_edge.append(res[2])

            if fold_acc:
                test_accuracy = float(np.mean(fold_acc))
                baseline = float(np.mean(fold_base))
                edge = float(np.mean(fold_edge))
                n_folds = len(fold_acc)
            else:
                # אין מספיק נתונים לאפילו חלון אחד — אין אומדן, אין אמון
                test_accuracy, baseline, edge, n_folds = 0.0, 1.0, 0.0, 0

            # ----------------------------------------------------------------
            # אמינות מול "חסר-מיומנות" אמיתי
            # ----------------------------------------------------------------
            # קודם הבסיס חושב כרוב של מחלקות ה-*מבחן* עצמו — ידע שאסטרטגיה
            # אמיתית לא יכולה להחזיק מראש, והוא גם נע עם המגמה של החלון
            # (חלון מגמתי -> בסיס 0.71, חלון דשדוש -> 0.50). זה לא מדד ליכולת
            # אלא מדד לכמה החלון היה חד-צדדי.
            #
            # הבסיס הנכון: "תמיד לנחש את המחלקה שהייתה הנפוצה ביותר באימון",
            # ולמדוד את זה על המבחן. את זה כן אפשר לעשות בזמן אמת, ולכן זה
            # הרף שהמודל חייב לעבור. הוא מחושב בתוך כל fold ב-_fit_eval_fold.
            reliability = float(min(1.0, max(0.0, edge)))

            # ----------------------------------------------------------------
            # המודל לייצור: מאומן על *כל* הנתונים
            # ----------------------------------------------------------------
            # ההערכה כבר נעשתה ביושר על חלונות עתידיים; אין סיבה לזרוק 20%
            # מהנתונים מהמודל שבאמת יסחר.
            class_labels = [int(c) for c in np.unique(y_clean).tolist()]
            class_to_idx = {label: idx for idx, label in enumerate(class_labels)}
            y_final = np.array([class_to_idx[int(v)] for v in y_clean], dtype=int)

            model = self._get_xgboost_model()
            model.fit(X_scaled, y_final, sample_weight=self._class_weights(y_final))
            train_accuracy = float(model.score(X_scaled, y_final))

            # Store model and scaler
            self.models[symbol] = model
            self.scalers[symbol] = scaler
            self.call_counts[symbol] = 0
            self.training_history[symbol] = {
                'train_accuracy': train_accuracy,
                'test_accuracy': test_accuracy,
                'baseline': baseline,
                'reliability': reliability,
                'n_samples': len(X_clean),
                'n_features': len(feature_names),
                'n_folds': n_folds,
                'edge': round(edge, 4),
                'unique_classes': len(unique_classes),
                'class_labels': class_labels,
            }

            logger.info(
                f"{symbol}: Model trained | Train: {train_accuracy:.3f} | "
                f"CV-Test: {test_accuracy:.3f} | Baseline: {baseline:.3f} | "
                f"Edge: {edge:+.3f} | Reliability: {reliability:.2f} | "
                f"Samples: {len(X_clean)} | Folds: {n_folds}"
            )
            self._write_health_snapshot()
            return True

        except Exception as e:
            logger.error(f"{symbol}: Training failed - {type(e).__name__}: {str(e)}")
            return False

    def predict(
        self,
        symbol: str,
        features: Dict[str, float],
        feature_names: List[str]
    ) -> Tuple[str, float, float]:
        """
        Generate trading signal from trained model.

        Args:
            symbol: Trading pair symbol
            features: Dict of feature values
            feature_names: Ordered list of feature names

        Returns:
            Tuple of (direction, score, probability):
                - direction: 'LONG', 'SHORT', or 'FLAT'
                - score: 0-100 confidence score
                - probability: 0-1 raw probability
        """
        try:
            # Check if model is trained
            if symbol not in self.models or symbol not in self.scalers:
                logger.debug(f"{symbol}: Model not trained, returning FLAT")
                return ('FLAT', 0.0, 0.0)

            # Increment call counter
            self.call_counts[symbol] = self.call_counts.get(symbol, 0) + 1

            # Extract features in correct order
            feature_vector = np.array([features.get(fname, 0.0) for fname in feature_names])

            # Check for NaN values
            if np.isnan(feature_vector).any():
                logger.warning(f"{symbol}: NaN in feature vector, returning FLAT")
                return ('FLAT', 0.0, 0.0)

            # Scale features
            scaler = self.scalers[symbol]
            feature_scaled = scaler.transform([feature_vector])

            # Get model prediction
            model = self.models[symbol]
            prediction = model.predict(feature_scaled)[0]
            probabilities = model.predict_proba(feature_scaled)[0]
            class_labels = self.training_history.get(symbol, {}).get(
                'class_labels',
                [0, 1, 2],
            )

            # Map prediction to direction (0=SHORT, 1=FLAT, 2=LONG)
            direction_map = {0: 'SHORT', 1: 'FLAT', 2: 'LONG'}
            pred_idx = int(prediction)
            pred_label = (
                int(class_labels[pred_idx])
                if 0 <= pred_idx < len(class_labels)
                else pred_idx
            )
            direction = direction_map.get(pred_label, 'FLAT')

            # Get probability for predicted class
            class_idx = np.argmax(probabilities)
            probability = float(probabilities[class_idx])

            # Discount the score by the model's real out-of-sample reliability.
            # An overfit model that prints 0.97 but has no edge (reliability ~0)
            # collapses to a near-zero score → it never crosses the entry
            # threshold → no trade. Only genuinely skilled models score high.
            reliability = float(self.training_history.get(symbol, {}).get('reliability', 0.0))
            mult = self._edge_multiplier(reliability)
            score = probability * mult * 100.0

            # אין יתרון מוכח -> לא מציעים כיוון בכלל
            if mult <= 0.0:
                direction = 'FLAT'

            logger.debug(
                f"{symbol}: {direction} | Score: {score:.1f} "
                f"(prob={probability:.2f} × edge={reliability:.3f} -> ×{mult:.2f}) | "
                f"Probs: {probabilities}"
            )
            return (direction, score, probability)

        except Exception as e:
            logger.error(
                f"{symbol}: Prediction failed - {type(e).__name__}: {str(e)}"
            )
            return ('FLAT', 0.0, 0.0)

    def is_trained(self, symbol: str) -> bool:
        """Check if model is trained for symbol."""
        return symbol in self.models and symbol in self.scalers

    def should_retrain(self, symbol: str, interval: int = 100) -> bool:
        """
        Check if model should be retrained based on call count.

        Args:
            symbol: Trading pair symbol
            interval: Number of prediction calls before retraining

        Returns:
            bool: True if retraining is recommended
        """
        if symbol not in self.models:
            return False

        calls = self.call_counts.get(symbol, 0)
        should_retrain = calls >= interval

        if should_retrain:
            logger.info(f"{symbol}: Retraining recommended (calls: {calls})")
            self.call_counts[symbol] = 0

        return should_retrain

    def get_training_stats(self, symbol: str) -> Optional[dict]:
        """Get training statistics for a symbol."""
        return self.training_history.get(symbol)

    def _write_health_snapshot(self) -> None:
        """Publish per-symbol model health for dashboard/research agents."""
        try:
            rows = {}
            reliabilities = []
            healthy = 0
            for symbol, stats in self.training_history.items():
                reliability = float(stats.get("reliability", 0.0) or 0.0)
                reliabilities.append(reliability)
                if reliability >= 0.10:
                    healthy += 1
                rows[symbol] = {
                    "train_accuracy": float(stats.get("train_accuracy", 0.0) or 0.0),
                    "test_accuracy": float(stats.get("test_accuracy", 0.0) or 0.0),
                    "baseline": float(stats.get("baseline", 0.0) or 0.0),
                    "reliability": reliability,
                    "n_samples": int(stats.get("n_samples", 0) or 0),
                    "n_features": int(stats.get("n_features", 0) or 0),
                    "unique_classes": int(stats.get("unique_classes", 0) or 0),
                    "class_labels": [int(x) for x in stats.get("class_labels", [])],
                    "calls_since_train": int(self.call_counts.get(symbol, 0) or 0),
                    "healthy": reliability >= 0.10,
                }

            avg_reliability = float(np.mean(reliabilities)) if reliabilities else 0.0
            payload = {
                "updated_at": time.time(),
                "model_type": "XGBoost" if XGBOOST_AVAILABLE else "GradientBoosting",
                "aggregate": {
                    "trained_symbols": len(rows),
                    "healthy_symbols": healthy,
                    "avg_reliability": avg_reliability,
                },
                "symbols": rows,
            }
            os.makedirs(os.path.dirname(_MODEL_HEALTH_FILE), exist_ok=True)
            with open(_MODEL_HEALTH_FILE, "w", encoding="utf-8") as f:
                json.dump(payload, f, ensure_ascii=False, indent=2)
        except Exception as exc:
            logger.debug("model health snapshot write failed: %s", exc)

    def reset_symbol(self, symbol: str) -> None:
        """Reset all data for a symbol."""
        self.models.pop(symbol, None)
        self.scalers.pop(symbol, None)
        self.call_counts.pop(symbol, None)
        self.training_history.pop(symbol, None)
        self._write_health_snapshot()
        logger.info(f"{symbol}: Model reset")

    def reset_all(self) -> None:
        """Reset all models."""
        self.models.clear()
        self.scalers.clear()
        self.call_counts.clear()
        self.training_history.clear()
        self._write_health_snapshot()
        logger.info("All models reset")
