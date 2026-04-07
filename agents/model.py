"""
XGBoost ML model for Binance Futures aggressive trading bot.
Handles per-symbol model training and prediction with fallback to sklearn.
"""

import logging
import warnings
from typing import Optional, Tuple, Dict, List
import numpy as np
import pandas as pd
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split

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
        """Create XGBoost or sklearn fallback model."""
        params = {
            'n_estimators': 200,
            'max_depth': 6,
            'learning_rate': 0.05,
            'eval_metric': 'mlogloss' if XGBOOST_AVAILABLE else 'log_loss',
            'use_label_encoder': False if XGBOOST_AVAILABLE else None,
            'random_state': 42,
            'n_jobs': -1,
            'verbose': 0
        }

        # Remove use_label_encoder for non-XGBoost models
        if not XGBOOST_AVAILABLE:
            params.pop('use_label_encoder')

        try:
            return XGBClassifier(**params)
        except TypeError as e:
            logger.warning(f"Error creating XGBoost model: {e}, using basic params")
            basic_params = {
                'n_estimators': 200,
                'max_depth': 6,
                'learning_rate': 0.05,
                'random_state': 42,
                'n_jobs': -1,
                'verbose': 0
            }
            return XGBClassifier(**basic_params)

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

            # Train-test split
            X_train, X_test, y_train, y_test = train_test_split(
                X_scaled, y_clean, test_size=0.2, shuffle=False
            )

            # Create and train model
            model = self._get_xgboost_model()
            model.fit(X_train, y_train)

            # Calculate accuracy
            train_accuracy = model.score(X_train, y_train)
            test_accuracy = model.score(X_test, y_test)

            # Store model and scaler
            self.models[symbol] = model
            self.scalers[symbol] = scaler
            self.call_counts[symbol] = 0
            self.training_history[symbol] = {
                'train_accuracy': train_accuracy,
                'test_accuracy': test_accuracy,
                'n_samples': len(X_clean),
                'n_features': len(feature_names),
                'unique_classes': len(unique_classes)
            }

            logger.info(
                f"{symbol}: Model trained successfully | "
                f"Train Acc: {train_accuracy:.3f} | Test Acc: {test_accuracy:.3f} | "
                f"Samples: {len(X_clean)} | Classes: {unique_classes.tolist()}"
            )
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

            # Map prediction to direction (0=SHORT, 1=FLAT, 2=LONG)
            direction_map = {0: 'SHORT', 1: 'FLAT', 2: 'LONG'}
            direction = direction_map.get(int(prediction), 'FLAT')

            # Get probability for predicted class
            class_idx = np.argmax(probabilities)
            probability = float(probabilities[class_idx])
            score = probability * 100

            logger.debug(
                f"{symbol}: Prediction - {direction} | Score: {score:.1f} | "
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

    def reset_symbol(self, symbol: str) -> None:
        """Reset all data for a symbol."""
        self.models.pop(symbol, None)
        self.scalers.pop(symbol, None)
        self.call_counts.pop(symbol, None)
        self.training_history.pop(symbol, None)
        logger.info(f"{symbol}: Model reset")

    def reset_all(self) -> None:
        """Reset all models."""
        self.models.clear()
        self.scalers.clear()
        self.call_counts.clear()
        self.training_history.clear()
        logger.info("All models reset")
