import sys, pathlib, os
# Ensure fx-pipeline root (parent) is in path for module resolution
root_dir = pathlib.Path(__file__).resolve().parents[1]
if str(root_dir) not in sys.path:
    sys.path.insert(0, str(root_dir))

import pandas as pd
from factors.mql5_baseline import MQL5BaselineAlpha
import numpy as np

def test_signal_runs():
    # Create a minimal OHLC dataframe (20 rows) with synthetic ramp prices
    idx = pd.date_range("2020-01-01", periods=30, freq="15T")
    price = pd.Series(1.10 + (0.0001 * np.arange(30)), index=idx)
    df = pd.DataFrame({
        "open": price.shift(1).fillna(price.iloc[0]),
        "high": price + 0.0002,
        "low": price - 0.0002,
        "close": price,
    })

    factor = MQL5BaselineAlpha()
    result = factor(df.copy())

    assert "signal" in result.columns
    # signals should be in the set {-1,0,1}
    assert set(result["signal"].unique()) <= { -1, 0, 1 }