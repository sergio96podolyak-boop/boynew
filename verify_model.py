#!/usr/bin/env python3
"""
בדיקת ההפרדה של מנוע ה-ML — האם הוא מבחין בין יתרון אמיתי לרעש?

זו הבדיקה שחשפה שהמודל-לכל-סימבול לא עובד, והיא זו שצריכה לרוץ אחרי
**כל** שינוי במדד היתרון, בכיול, בפיצ'רים או בתוויות.

הרעיון: בונים שתי סדרות סינתטיות שבהן התשובה ידועה מראש —
  * רעש טהור      — הפיצ'רים אינם מנבאים כלום. יתרון נכון = 0.
  * יתרון מוטמע   — פיצ'ר אחד מקדים את התשואה בנר. יתרון נכון > 0.
ומודדים כמה מכל אחת המודל מזהה. מודל שמדווח יתרון דומה בשניהם הוא מודל
שמדווח רעש כיכולת, וכל סף כניסה שמבוסס עליו חסר משמעות.

    ./venv/bin/python verify_model.py            # מהיר  (40 סימבולים)
    ./venv/bin/python verify_model.py 80         # מדויק יותר, איטי יותר
"""
import importlib.util
import logging
import os
import sys
import time

import numpy as np
import pandas as pd

# נטען ישירות מהקובץ — לא דרך החבילה agents, שגוררת תלויות כבדות
_SPEC = importlib.util.spec_from_file_location(
    "tmodel", os.path.join(os.path.dirname(os.path.abspath(__file__)), "agents", "model.py")
)
_TM = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_TM)

N_FEATURES = 46
N_ROWS = 480          # MIN_ML_TRAINING_CANDLES
HORIZON = 5           # ML_LABEL_HORIZON
THRESHOLD = 0.0005    # ML_LABEL_THRESHOLD
FLOOR = _TM.TradingModel.EDGE_FLOOR
FEATURES = [f"f{i}" for i in range(N_FEATURES)]


def _frame(seed: int, signal: float) -> pd.DataFrame:
    """signal=0 -> רעש טהור. signal>0 -> f0 של נר t מנבא את תשואת t+1."""
    r = np.random.default_rng(seed)
    driver = r.normal(0, 1, N_ROWS)
    ret = r.normal(0, 0.0025, N_ROWS)
    if signal > 0:
        ret[1:] += signal * 0.0025 * driver[:-1]
    df = pd.DataFrame({"close": 100 * np.exp(np.cumsum(ret)), "f0": driver})
    for name in FEATURES[1:]:
        df[name] = r.normal(0, 1, N_ROWS)
    return df


def _per_symbol(frames: dict) -> np.ndarray:
    model = _TM.TradingModel()
    for sym, df in frames.items():
        model.train(sym, df, FEATURES, horizon=HORIZON, threshold=THRESHOLD)
    return np.array(
        [float((model.get_training_stats(s) or {}).get("reliability", 0.0) or 0.0) for s in frames]
    )


def _pooled(frames: dict) -> np.ndarray:
    model = _TM.TradingModel()
    for sym, df in frames.items():
        model.stage(sym, df, FEATURES, horizon=HORIZON, threshold=THRESHOLD)
    model.train_global(FEATURES, n_folds=4, stale_sec=0)
    return np.array(
        [float((model.get_training_stats(s) or {}).get("reliability", 0.0) or 0.0) for s in frames]
    )


def _report(title: str, noise: np.ndarray, edge: np.ndarray, secs: float) -> bool:
    n = len(noise)
    print(f"\n  {title}   ({secs:.0f} שניות)")
    print(f"    רעש טהור    : יתרון {noise.mean():+.4f} | עוברים {(noise > FLOOR).sum():3d}/{n}")
    print(f"    יתרון מוטמע : יתרון {edge.mean():+.4f} | עוברים {(edge > FLOOR).sum():3d}/{n}")
    sep = edge.mean() - noise.mean()
    print(f"    הפרדה       : {sep:+.4f}")

    # הציון הוא probability × _edge_multiplier(edge) × 100. אפילו בהסתברות
    # 1.0 המקסימום הוא המכפיל עצמו × 100 — ולכן יתרון נמוך מדי הופך כל
    # סף כניסה לבלתי-אפשרי, בלי קשר לכמה המודל בטוח.
    ceiling = _TM.TradingModel._edge_multiplier(float(edge.mean())) * 100.0
    print(f"    תקרת ציון   : {ceiling:.1f}  (SCORE_ENTRY טיפוסי: 62-78)")
    ok = sep > 0.05 and float(edge.mean()) > 0.10
    print(f"    {'✓ מפריד' if ok else '✗ לא מפריד — רעש נראה כמו יכולת'}")
    return ok


def main() -> int:
    n_sym = int(sys.argv[1]) if len(sys.argv) > 1 else 40
    logging.disable(logging.CRITICAL)

    noise_frames = {f"N{i}USDT": _frame(1000 + i, 0.0) for i in range(n_sym)}
    edge_frames = {f"E{i}USDT": _frame(2000 + i, 0.45) for i in range(n_sym)}

    print(f"בדיקת הפרדה | {n_sym} סימבולים × {N_ROWS} נרות × {N_FEATURES} פיצ'רים")
    print(f"סף היתרון (EDGE_FLOOR): {FLOOR}")

    t0 = time.time()
    ok_per = _report("מודל לכל סימבול", _per_symbol(noise_frames), _per_symbol(edge_frames),
                     time.time() - t0)
    t0 = time.time()
    ok_pool = _report("מודל מאוחד", _pooled(noise_frames), _pooled(edge_frames),
                      time.time() - t0)

    print()
    if ok_pool:
        print("המסלול הפעיל (ML_POOLED_MODEL=true) מפריד יתרון מרעש. ✓")
    else:
        print("אזהרה: המסלול הפעיל אינו מפריד יתרון מרעש — אל תסחרו עליו.")
    if not ok_per:
        print("מודל לכל סימבול (ML_POOLED_MODEL=false) אינו מפריד — זו הסיבה שהוא הוחלף.")
    return 0 if ok_pool else 1


if __name__ == "__main__":
    sys.exit(main())
