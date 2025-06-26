#!/usr/bin/env python3
import pandas as pd
import glob, os

# Map your file‐specific names to Qlib’s schema
COLUMN_MAP = {
    "Time":    "datetime",
    "Open":    "open",
    "High":    "high",
    "Low":     "low",
    "Close":   "close",
    "Volume":  "volume"
}

RAW_DIR  = "data/raw"
CLEAN_DIR = "data/raw_clean"

os.makedirs(CLEAN_DIR, exist_ok=True)

for path in glob.glob(f"{RAW_DIR}/*.csv"):
    df = pd.read_csv(path)
    # 1) rename columns
    df = df.rename(columns=COLUMN_MAP)
    # 2) add the symbol column (basename before first underscore)
    symbol = os.path.basename(path).split("_")[0]
    df["symbol"] = symbol
    # 3) keep only the expected columns in the right order
    df = df[["symbol","datetime","open","high","low","close","volume"]]
    # 4) write out to a clean directory
    out_path = os.path.join(CLEAN_DIR, os.path.basename(path))
    df.to_csv(out_path, index=False)
    print(f"  → Wrote cleaned file: {out_path}")
