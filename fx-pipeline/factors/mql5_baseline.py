"""MQL5BaselineAlpha

Python re-implementation of the MT5 Intraday Swing EA indicator-signal block.
Only computes a BUY (+1), SELL (-1) or FLAT (0) signal that will later be
fed into a trivial LightGBM model for benchmarking.

This first version is deliberately simplified.  It captures the *spirit* of the
EA logic while keeping the implementation feasible for a pandas row-wise
feature pipeline:

* ATR(14) filter – skip if ATR pips < min_atr_pips
* Trend filter   – uses EMA50/EMA200 on the same timeframe as data
* Entry trigger  – RSI crosses ±50 with supportive EMAs & price action

Later iterations can refine the logic (H1/H4 trend, engulfing patterns, etc.).
"""
# flake8: noqa E501
from __future__ import annotations

import numpy as np
import pandas as pd

# ta-lib (pure python) indicators
from ta.volatility import AverageTrueRange
from ta.momentum import RSIIndicator
from ta.trend import EMAIndicator

# Qlib operator registration
try:
    from qlib.data.ops import ExpressionOps  # type: ignore
except ModuleNotFoundError:  # allow unit-test without Qlib installed
    ExpressionOps = None  # type: ignore

# Qlib processor base class gives us default `fit`, `readonly`,
# and `is_for_infer` implementations expected by the data-handler.
try:
    from qlib.data.dataset.processor import Processor  # type: ignore
except ModuleNotFoundError:
    # Allow import when qlib is absent (unit tests) – fall back to plain object
    class Processor:  # type: ignore
        def fit(self, df=None):
            pass

        def readonly(self) -> bool:
            return False

        def is_for_infer(self) -> bool:
            return True

__all__ = ["MQL5BaselineAlpha"]


class MQL5BaselineAlpha(Processor):
    """Custom factor that adds `atr`, `rsi`, `ema_fast`, `ema_slow`, and `signal` columns.

    Parameters mirror the inputs from the original MQL5 EA so they can be
    tuned later via RD-Agent.
    """

    def __init__(
        self,
        rsi_period: int = 14,
        ema_fast: int = 50,
        ema_slow: int = 200,
        atr_period: int = 14,
        sl_atr_mult: float = 1.5,  # unused for now – kept for parity
        tp_atr_mult: float = 3.5,  # unused for now – kept for parity
        min_atr_pips: float = 7.5,
        pip_scale: float | None = None,  # if None we estimate from price precision
        use_engulfing: bool = True,  # placeholder flag
    ) -> None:
        self.rsi_period = rsi_period
        self.ema_fast = ema_fast
        self.ema_slow = ema_slow
        self.atr_period = atr_period
        self.min_atr_pips = min_atr_pips
        self.pip_scale = pip_scale
        self.use_engulfing = use_engulfing

    # ------------------------------------------------------------------
    # Processor API
    # ------------------------------------------------------------------

    def fit(self, df: pd.DataFrame | None = None):  # noqa: D401
        """No parameters to learn – placeholder for Processor compliance."""
        # Nothing to fit; method exists only so DataHandler does not error.
        return None

    # ---------------------------------------------------------------------
    # Core call – expects a DataFrame with columns: open, high, low, close
    # ---------------------------------------------------------------------
    def __call__(self, df: pd.DataFrame) -> pd.DataFrame:  # noqa: D401
        """Append indicator & signal columns to *df* and return it.

        The function is intentionally in-place but returns the same object so
        that it can be chained inside Qlib's feature pipeline.
        """
        # Ensure price columns exist
        required_cols = {"open", "high", "low", "close"}
        if isinstance(df.columns, pd.MultiIndex):
            col_names = df.columns.get_level_values(-1).str.lower()
        else:
            col_names = df.columns.str.lower()
        missing = required_cols - set(col_names)
        if missing:
            raise KeyError(f"DataFrame missing required price columns: {missing}")

        # ------------------------------------------------------------------
        # Indicators
        # ------------------------------------------------------------------
        df = df.copy()

        def _col(name: str) -> pd.Series:
            if isinstance(df.columns, pd.MultiIndex):
                return df[("feature", name)]
            return df[name]

        high = _col("high")
        low = _col("low")
        close = _col("close")

        # ATR
        atr_series = AverageTrueRange(
            high,
            low,
            close,
            window=self.atr_period,
        ).average_true_range()
        # helper to add columns keeping existing MultiIndex structure
        def _add(col_name: str, series: pd.Series):
            if isinstance(df.columns, pd.MultiIndex):
                df[("feature", col_name)] = series
            else:
                df[col_name] = series

        _add("atr", atr_series)

        # RSI
        rsi_series = RSIIndicator(close, window=self.rsi_period).rsi()
        _add("rsi", rsi_series)

        # EMAs
        ema_fast_ser = EMAIndicator(close, window=self.ema_fast).ema_indicator()
        ema_slow_ser = EMAIndicator(close, window=self.ema_slow).ema_indicator()
        _add("ema_fast", ema_fast_ser)
        _add("ema_slow", ema_slow_ser)

        # Estimate pip size if not given (works for most FX pairs, inc. majors)
        if self.pip_scale is None:
            # Heuristic:  if price has 5 decimals (EURUSD ~1.08451) then pip=0.0001
            decimal_places = close.apply(
                lambda x: len(str(x).split(".")[1]) if "." in str(x) else 0
            ).median()
            self.pip_scale = 10 ** -(int(decimal_places) - 1)

        # ATR filter (volatility)
        atr_pips = atr_series / self.pip_scale
        vol_ok = atr_pips >= self.min_atr_pips

        # Trend filter: bullish if price>EMA50>EMA200 etc.
        bullish = (close > ema_fast_ser) & (close > ema_slow_ser)
        bearish = (close < ema_fast_ser) & (close < ema_slow_ser)

        # RSI momentum – simplified cross logic
        rsi_buy = (rsi_series.shift(1) < 50) & (rsi_series >= 53)
        rsi_sell = (rsi_series.shift(1) > 50) & (rsi_series <= 47)

        buy_signal = vol_ok & bullish & rsi_buy
        sell_signal = vol_ok & bearish & rsi_sell

        # Encode as +1 / ‑1 / 0
        signal = np.select([buy_signal, sell_signal], [1, -1], default=0)

        if isinstance(df.columns, pd.MultiIndex):
            df[("label", "LABEL0")] = signal
        else:
            df["LABEL0"] = signal

        # For convenience keep a flat 'signal' copy as well
        df["signal"] = signal

        return df