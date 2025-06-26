Below is a **practical, end-to-end build plan** that stitches Qlib, Microsoft's new **R\&D-Agent(Q)**, and your MetaTrader-5 Expert Advisor into a single, self-improving pipeline that is laser-focused on **clearing FundingPips' two-step challenge (8 % → 5 % profit, ≤ 5 % daily loss, ≤ 10 % total DD)**.

---

## 0 · Pre-flight

| Host                            | Use                                                             | Key packages                                                                                                                            |
| ------------------------------- | --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| **Linux box / GPU workstation** | research loop (Qlib + R\&D-Agent), signal API, Prometheus stack | `conda create -n rdagent python=3.10` → `pip install pyqlib rdagent lightgbm fastapi uvicorn redis prometheus-client` ([github.com][1]) |
| **Win 10/11 VM + MT5**          | runs your EA, talks to signal API                               | MetaTrader 5, MT5-Python bridge (`pip install MetaTrader5`)                                                                             |

> **Why two machines?**  Qlib/RD-Agent depend on Docker & Conda and run best on Linux, while MT5 requires Windows.

### 0.1 Environment Validation

1. **Verify system requirements**: Check available RAM (≥16GB recommended), CPU cores, and GPU compatibility for RD-Agent.
2. **Test network connectivity** between Linux and Windows machines.
3. **Validate package versions** and resolve any dependency conflicts.
4. **Set up SSH/RDP access** for remote management and monitoring.

### 0.2 Directory Structure Setup

```bash
mkdir -p ~/fx-pipeline/{data/{raw,processed,qlib},models/{baseline,evolved,production},configs,logs,scripts}
```

*Create `~/fx-pipeline/.gitignore` with the following entries:*

```
data/raw/
data/processed/
logs/
models/
.env
__pycache__/
*.pyc
```

### 0.3 Configuration Management

1. **Create environment files**: copy `.env.example` to `.env` and fill in API keys, paths, and connection strings.
2. **Set up logging configuration** with appropriate log levels and rotation.
3. **Configure resource limits** (memory, CPU) for containerized components.

```bash
# Example .env template
cat > .env.example <<'EOF'
QLIB_DATA_PATH=~/.qlib/forex_m1
REDIS_URL=redis://localhost:6379/0
MT5_TERMINAL_PATH="C:\\Program Files\\MetaTrader 5\\terminal64.exe"
API_KEY=your_api_key_here
EOF
cp .env.example .env
```

---

## 1 · Raw Market Data → Qlib Format

1. **Use your existing M15 data** (EURUSD_M15_in.csv, EURUSD_M15_out.csv) and any additional M15 bars for other pairs.
2. **Normalize & save**

   ```bash
   python -m qlib.data.convert_csv_to_bin \
          --csv_dir ./csv_raw \
          --qlib_dir ~/.qlib/forex_m1 \
          --symbol_field_name symbol \
          --date_field_name datetime
   ```

   Qlib's binary format gives millisecond lookup and is required for its back-tester / RD-Agent loops. ([github.com][2])

### 1.1 Data Validation

1. **Inspect EURUSD_M15_in.csv** for data quality issues (missing timestamps, price anomalies, gaps).
2. **Validate data schema** ensuring columns match expected format (OHLCV + timestamp).
3. **Check for sufficient data coverage** (minimum 2+ years for reliable backtesting).
4. **Detect and handle outliers** using statistical methods or domain knowledge.

### 1.2 Data Preprocessing Pipeline

```python
# scripts/prepare_m15_data.py
"""
Validate and preprocess raw Forex M15 CSV files and convert them into Qlib's binary format.
"""
def validate_forex_data(df):
    # Check for missing values, price inversions, weekend data
    # Implement gap detection and filling strategies
    # Apply timezone normalization (UTC)
    return df

if __name__ == "__main__":
    import argparse, os, pandas as pd, qlib
    from qlib.data import D
    parser = argparse.ArgumentParser(description="Preprocess and convert Forex M15 CSV to Qlib binary format")
    parser.add_argument("--csv_dir", required=True, help="Directory containing raw CSV files")
    parser.add_argument("--qlib_dir", required=True, help="Target Qlib binary data directory")
    parser.add_argument("--symbol_field_name", default="symbol", help="CSV column for symbol")
    parser.add_argument("--date_field_name", default="datetime", help="CSV column for datetime")
    args = parser.parse_args()
    # TODO: load CSV files into DataFrame, call validate_forex_data, then save to binary using qlib
```
```bash
# Example preprocessing and conversion command
python scripts/prepare_m15_data.py --csv_dir ./data/raw --qlib_dir ~/.qlib/forex_m1 --symbol_field_name symbol --date_field_name datetime
python -m qlib.data.convert_csv_to_bin --csv_dir ./data/raw --qlib_dir ~/.qlib/forex_m1 --symbol_field_name symbol --date_field_name datetime
```

### 1.3 Data Versioning and Backup

1. **Create versioned data snapshots** using DVC or similar.
2. **Set up automated backups** of raw and processed data.
3. **Implement data lineage tracking** to trace processed data back to sources.

```bash
# Initialize DVC and track raw data snapshot
cd ~/fx-pipeline
dvc init
dvc remote add origin <remote-storage-url>
dvc add data/raw
git add .dvc/config data/raw.dvc
git commit -m "Track raw data with DVC"
```

### 1.4 Validation Dataset Preparation

1. **Reserve EURUSD_M15_out.csv** as hold-out validation set.
2. **Implement time-series cross-validation** splits respecting temporal order.
3. **Create performance benchmarks** using simple buy-and-hold strategies.

---

## 2 · Load Your **Baseline EA** into Qlib

*Re-implement only the **decision logic** in Python; you're not trading yet.*

```python
# factors/baseline.py
class BaselineFXAlpha:
    def __init__(self, win=21):
        self.win = win            # e.g. rolling ATR window
    def __call__(self, df):
        df["atr"] = ta.atr(df.high, df.low, df.close, self.win)
        df["signal"] = (df.close > df.close.shift()) & (df.atr < df.atr.rolling(20).mean())
        return df
```

1. Register this as a **custom factor** inside Qlib's `ExpressionOps`.
2. Create a `baseline.yaml` experiment file that plugs the factor into a LightGBM model and back-tests using Qlib's built-in broker simulator.

Run once with:

```bash
qlib_run baseline.yaml
```

Confirm current metrics (CAGR, max-DD, Sharpe) so you have a ground-truth before letting the agents loose.

### 2.1 MQL5 Code Analysis

1. **Extract trading logic** from `main.mq5` and document all indicators, signals, and rules.
2. **Identify all parameters** used in the EA (ATR periods, SL/TP multipliers, risk percentages).
3. **Map MQL5 functions** to equivalent Python/TA-Lib implementations.
4. **Document position sizing** and risk management rules.

### 2.2 Python Factor Implementation

```python
# factors/mql5_baseline.py
class MQL5BaselineAlpha:
    def __init__(self, params_from_mq5):
        # Import all parameters from main.mq5 analysis
        pass
    
    def __call__(self, df):
        # Replicate exact MQL5 logic in Python
        # Add extensive logging for validation
        pass
```

### 2.3 Logic Validation

1. **Unit test each indicator** calculation against known values.
2. **Compare Python vs MQL5 signals** on identical historical data.
3. **Validate position sizing** calculations match the EA logic.
4. **Test edge cases** (market gaps, low liquidity periods).

### 2.4 Performance Benchmarking

1. **Run baseline backtest** on EURUSD_M15_in.csv with Qlib simulator.
2. **Generate performance reports** (returns, Sharpe, max DD, win rate).
3. **Compare against simple benchmarks** (moving average crossover, buy-and-hold).
4. **Validate against FundingPips criteria** (8% target, 5% daily/10% total DD limits).

---

## 3 · Spin-up **R\&D-Agent(Q)**

```bash
# still inside the Conda env
pip install rdagent           # if not installed
rdagent health_check          # sanity test
```

Common one-liners:

| What it does                                                                    | Command                   |
| ------------------------------------------------------------------------------- | ------------------------- |
| **Iterative factor evolution** (adds/removes technicals, price-action patterns) | `rdagent fin_factor`      |
| **Model evolution** (hyper-params, architectures)                               | `rdagent fin_model`       |
| **Web UI & logs**                                                               | `rdagent ui --port 19899` |

Commands above are straight from the official quick-start docs. ([github.com][1])

### 3.1 Configuration Setup

1. **Create `rdagent.yaml`** with project-specific settings:
   ```yaml
   data_path: ~/.qlib/forex_m1
   model_type: lightgbm
   objective: fundingpips_reward
   max_iterations: 100
   timeframe: M15
   target_reward: 8
   patience: 25
   reward_script: rewards/fundingpips_reward.py
   reward_class: FundingPipsReward
   ```

*Save the above `rdagent.yaml` in the project root.*

2. **Configure compute resources** (CPU cores, memory limits, GPU allocation).
3. **Set up experiment tracking** with MLflow or Weights & Biases integration.

### 3.2 Database and Storage Initialization

1. **Initialize Redis** for caching intermediate results and agent communication.
2. **Set up experiment database** to track all model iterations and results.
3. **Configure artifact storage** for models, logs, and generated code.
4. **Test data pipeline** connectivity between RD-Agent and Qlib.

### 3.3 Resource Monitoring Setup

1. **Configure system monitoring** (CPU, RAM, GPU utilization).
2. **Set up experiment progress tracking** with estimated completion times.
3. **Implement resource limits** to prevent system overload during intensive searches.

---

## 4 · Tell RD-Agent What "Success" Looks Like

Create `fundingpips_reward.py` and register it in `rdagent.yaml` so every loop is scored by:

```python
score = (equity_curve[-1] - 1.0) * 100          # % return
penalty = max(0, daily_dd - 5) * 10 + max(0, total_dd - 10) * 20
reward  = score - penalty
```

Set a *stop condition* in the YAML:

```yaml
target_reward: 8        # ≥ 8 implied % return with no penalties
patience: 25            # abort if 25 iterations without improvement
```

### 4.1 Reward Function Development

*Save the following into `rewards/fundingpips_reward.py`:*
```python
class FundingPipsReward:
    def __init__(self):
        self.target_return = 8.0    # Phase 1: 8%, Phase 2: 5%
        self.max_daily_dd = 5.0
        self.max_total_dd = 10.0

    def calculate_reward(self, backtest_results):
        """
        Compute net reward: %return minus penalties for excess drawdown.
        backtest_results -> dict containing equity_curve, daily_dd, total_dd
        """
        equity = backtest_results.get("equity_curve", [])
        score = (equity[-1] - 1.0) * 100
        daily_dd = backtest_results.get("daily_dd", 0)
        total_dd = backtest_results.get("total_dd", 0)
        penalty = max(0, daily_dd - self.max_daily_dd) * 10 + max(0, total_dd - self.max_total_dd) * 20
        return score - penalty
```

### 4.2 Risk Metric Definitions

1. **Implement FundingPips-specific metrics**:
   - Daily drawdown calculation methodology
   - Total drawdown measurement
   - Profit calculation rules (unrealized vs realized)
2. **Add risk-adjusted metrics** (Sortino ratio, Calmar ratio).
3. **Define trading frequency penalties** (avoid over-trading).

### 4.3 Baseline Performance Establishment

1. **Run baseline EA** on validation data (EURUSD_M15_out.csv).
2. **Document baseline performance** as improvement benchmark.
3. **Set realistic improvement targets** based on baseline results.
4. **Validate reward function** produces expected scores for known strategies.

---

## 5 · Run the Self-Loop

```bash
rdagent fin_factor --config rdagent.yaml  # launches Research → Dev → Feedback loop
```

*What happens under the hood* ([github.com][3], [github.com][1])

1. **Research-stage agent** proposes new hypotheses: "add a stochastic RSI factor with 14-period look-back."
2. **Development-stage agent** calls its code-gen sub-agent (Co-STEER) to patch the factor class & YAML.
3. **Back-test** is executed through Qlib; metrics flow back to a **multi-armed bandit scheduler** that decides which idea to pursue next.
4. Loop continues until `target_reward` is met.

### 5.1 Monitoring and Logging Setup

1. **Configure comprehensive logging** for all agent decisions and actions.
2. **Set up real-time progress monitoring** with dashboards.
3. **Implement experiment checkpointing** for recovery from failures.
4. **Create alert system** for significant performance improvements or issues.

### 5.2 Progress Tracking

```python
# monitoring/progress_tracker.py
class ExperimentTracker:
    def log_iteration(self, iteration, factors, performance, execution_time):
        # Track factor evolution over time
        # Monitor resource utilization
        # Log performance improvements
        pass
```

### 5.3 Early Stopping and Optimization

1. **Implement adaptive patience** based on progress rate.
2. **Add convergence detection** to avoid unnecessary iterations.
3. **Configure resource-based stopping** (time limits, cost thresholds).
4. **Set up emergency stops** for system resource protection.

### 5.4 Parallel Experiment Management

1. **Configure multi-GPU training** if available.
2. **Set up distributed computing** for factor search parallelization.
3. **Implement experiment queuing** for resource optimization.

---

## 6 · Freeze the Winning Model & Export Live Signal Code

```bash
rdagent export best --out models/best_model.pkl
python scripts/gen_live_inference.py \
       --model models/best_model.pkl \
       --out   live_signal_service.py
```

The helper script builds a minimal FastAPI endpoint:

```python
@app.post("/signal")
def get_signal(bar: Bar):
    prob = model.predict(bar.to_feature_vec())
    return {"side": "BUY" if prob > 0.5 else "SELL",
            "conf": float(prob)}
```

### 6.1 Model Validation and Selection

1. **Run final validation** on EURUSD_M15_out.csv hold-out data.
2. **Perform walk-forward analysis** to test temporal stability.
3. **Compare top N models** using multiple performance metrics.
4. **Validate model generalization** across different market conditions.

### 6.2 Model Serialization and Versioning

```python
# scripts/model_manager.py
class ModelManager:
    def save_model_with_metadata(self, model, version, performance_metrics):
        # Save model + preprocessing pipeline + feature definitions
        # Include version history and performance benchmarks
        # Generate model documentation and usage instructions
        pass
```

### 6.3 A/B Testing Framework

1. **Implement gradual rollout** system for new models.
2. **Create performance comparison** infrastructure.
3. **Set up automatic rollback** if performance degrades.
4. **Design champion/challenger** testing methodology.

### 6.4 Live Inference Code Generation

```python
# scripts/gen_live_inference.py
def generate_production_service(model_path, output_path):
    # Generate optimized inference code
    # Include input validation and error handling
    # Add performance monitoring and logging
    # Implement caching for repeated calculations
    pass
```

---

## 7 · Deploy **Signal API**

```bash
nohup uvicorn live_signal_service:app \
      --host 0.0.0.0 --port 9000 &
```

Add Prometheus middleware so you can scrape PnL, drawdown, and API latency.

### 7.1 Production Deployment Setup

1. **Containerize the application** with Docker for consistent deployment.
2. **Set up reverse proxy** (nginx) for load balancing and SSL termination.
3. **Configure environment-specific** settings (dev/staging/prod).
4. **Implement graceful shutdown** handling for maintenance windows.

### 7.2 Security and Authentication

1. **Add API authentication** (API keys, JWT tokens).
2. **Implement rate limiting** to prevent abuse.
3. **Set up SSL/TLS certificates** for encrypted communication.
4. **Configure firewall rules** and network security.

### 7.3 Performance Optimization

```python
# optimizations/caching.py
@lru_cache(maxsize=1000)
def calculate_features(ohlc_data):
    # Cache frequently requested feature calculations
    # Implement intelligent cache invalidation
    pass
```

### 7.4 Health Checks and Monitoring

1. **Implement comprehensive health checks** (model loading, data access, memory usage).
2. **Set up uptime monitoring** with external services.
3. **Configure log aggregation** for centralized troubleshooting.
4. **Add performance metrics collection** (response times, throughput).

---

## 8 · Connect Your MT5 EA

Inside your MQL5 code (simplified):

```cpp
string json = "{}";
int    res  = WebRequest("POST",
                         "http://<linux-ip>:9000/signal", "", 1000, NULL, 0, json, NULL);
if(res == 200)
{
   string side = json_value_by_key(json, "side");
   if(side == "BUY"  && !PositionSelect(_Symbol)) OpenBuy();
   if(side == "SELL" && !PositionSelect(_Symbol)) OpenSell();
}
```

*Plus* your existing ATR-based SL/TP & 1 % risk sizing logic.

### 8.1 Connection Testing and Validation

1. **Test API connectivity** from MT5 environment to Linux signal server.
1.5 **Enable WebRequest** for the REST URL in MT5: Tools → Options → Expert Advisors → allow WebRequest for the signal API URL.
2. **Validate JSON parsing** in MQL5 code with various response formats.
3. **Test error handling** for network timeouts and API failures.
4. **Verify signal latency** is acceptable for trading strategy.

### 8.2 Enhanced Error Handling & JSON Parsing

```cpp
// In main.mq5 - Enhanced WebRequest handling with JSON parsing
int MAX_RETRIES = 3;
int TIMEOUT_MS = 2000;

bool GetSignalWithRetry(string &signal, double &confidence) {
    for(int i = 0; i < MAX_RETRIES; i++) {
        int result = CallSignalAPI(signal, confidence);
        if(result == 200) return true;
        Sleep(1000 * (i + 1)); // Exponential backoff
    }
    return false; // Use fallback logic
}
```

### 8.3 Fallback Mechanisms

1. **Implement local backup signals** when API is unavailable.
2. **Add circuit breaker** logic for repeated API failures.
3. **Create manual override** capabilities for emergency situations.
4. **Set up offline mode** using last known successful model.

### 8.4 Performance Optimization

1. **Optimize WebRequest frequency** to minimize latency impact.
2. **Implement request batching** for multiple symbol signals.
3. **Add local caching** of recent signals to reduce API calls.
4. **Profile and optimize** MQL5 code execution time.

---

## 9 · Manual Mirroring to FundingPips

Until API trading is allowed on the evaluation account, simply mirror the trades the EA executes on your MT5 demo into the FundingPips web dashboard.

### 9.1 Trade Synchronization System

```python
# scripts/trade_sync.py
class TradeSyncManager:
    def monitor_mt5_trades(self):
        # Monitor MT5 terminal for new positions
        # Extract position details (symbol, size, entry price, SL/TP)
        # Queue trades for manual execution
        pass
    
    def generate_trade_instructions(self):
        # Create human-readable trade instructions
        # Include risk calculations and position sizing
        # Generate alerts/notifications for urgent trades
        pass
```

### 9.2 Position Size Calculation

1. **Calculate FundingPips position sizes** based on account balance and risk rules.
2. **Convert MT5 lot sizes** to FundingPips platform units.
3. **Validate position sizes** against platform limits and margin requirements.
4. **Account for spread differences** between platforms.

### 9.3 Manual Execution Validation

1. **Create execution checklists** to ensure accuracy.
2. **Implement trade verification** against original MT5 positions.
3. **Track execution delays** and their impact on performance.
4. **Monitor position drift** between platforms over time.

### 9.4 Automation Preparation

1. **Document all manual steps** for future API integration.
2. **Design API integration architecture** for automatic execution.
3. **Test with FundingPips demo API** when available.
4. **Prepare compliance documentation** for live trading approval.

---

## 10 · Monitoring & Safety Nets

* **Prometheus + Grafana** dashboard: equity curve, daily DD, open risk.
* **Alertmanager rule**

  ```yaml
  alert: FundingPipsDailyLoss
  expr: daily_drawdown_pct > 4
  for: 1m
  labels: {severity: "critical"}
  annotations:
    summary: "Daily loss > 4 %, EA will self-disable in 60 s"
  ```
* **EA emergency flag** that checks the Prometheus alert file and calls `ExpertRemove()` if breached.

### 10.1 Comprehensive Dashboard Setup

```yaml
# grafana/dashboards/fx-trading.json
{
  "dashboard": {
    "title": "FX Trading Pipeline",
    "panels": [
      {"title": "Real-time PnL", "type": "stat"},
      {"title": "Daily Drawdown", "type": "gauge"},
      {"title": "Position Exposure", "type": "piechart"},
      {"title": "Signal API Latency", "type": "timeseries"},
      {"title": "Model Performance Drift", "type": "timeseries"}
    ]
  }
}
```

### 10.2 Alert Configuration

1. **Set up multi-channel alerting** (email, SMS, Slack, Discord).
2. **Configure alert escalation** for critical issues.
3. **Implement alert fatigue prevention** with intelligent grouping.
4. **Add alert acknowledgment** and resolution tracking.

### 10.3 Log Aggregation and Analysis

1. **Set up centralized logging** with ELK stack or similar.
2. **Implement log correlation** across MT5, signal API, and monitoring systems.
3. **Create automated log analysis** for pattern detection.
4. **Set up log-based alerting** for anomaly detection.

### 10.4 Performance Drift Detection

```python
# monitoring/drift_detector.py
class ModelDriftDetector:
    def __init__(self, baseline_metrics):
        self.baseline = baseline_metrics
    
    def detect_performance_drift(self, current_metrics):
        # Statistical tests for performance degradation
        # Alert on significant metric changes
        # Recommend model retraining when needed
        pass
```

---

## 11 · CI/CD

GitHub Actions:

```yaml
on: push
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Qlib back-test
        run: qlib_run baseline.yaml
  build:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - run: docker build -t fx-rdagent:${{ github.sha }} .
      - run: docker push ...
```

### 11.1 Testing Pipeline

```yaml
# .github/workflows/testing.yml
name: Comprehensive Testing
on: [push, pull_request]
jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - name: Run factor unit tests
        run: pytest tests/factors/
      - name: Run backtesting validation
        run: python tests/validate_backtest.py
  
  integration-tests:
    runs-on: ubuntu-latest
    steps:
      - name: Test signal API
        run: python tests/test_signal_api.py
      - name: Test MT5 connection simulation
        run: python tests/test_mt5_connection.py
```

### 11.2 Environment Promotion

1. **Create staging environment** that mirrors production.
2. **Implement blue-green deployment** for zero-downtime updates.
3. **Set up database migration** scripts for schema changes.
4. **Configure environment-specific** configuration management.

### 11.3 Deployment Validation

```python
# scripts/deployment_validation.py
def validate_deployment():
    # Test all API endpoints
    # Verify model loading and prediction
    # Check database connectivity
    # Validate monitoring setup
    # Run smoke tests on critical paths
    pass
```

### 11.4 Rollback and Recovery

1. **Implement automated rollback** triggers based on performance metrics.
2. **Create database backup** and restore procedures.
3. **Set up infrastructure as code** for rapid environment recreation.
4. **Document emergency procedures** for manual intervention.

### 11.5 Release Management

1. **Create semantic versioning** strategy for models and code.
2. **Implement feature flagging** for controlled rollouts.
3. **Set up release notes** generation and change tracking.
4. **Configure automated deployment** approvals and gates.

---

## 12 · Step-by-Step Execution Guide

Follow these commands in the exact order to set up, run research loops, and deploy:

```bash
# 1. Setup Linux research environment
conda create -n rdagent python=3.10
conda activate rdagent
pip install pyqlib rdagent lightgbm fastapi uvicorn redis prometheus-client MetaTrader5 dvc

# 2. Initialize project structure and .gitignore
mkdir -p ~/fx-pipeline/{data/{raw,processed,qlib},models/{baseline,evolved,production},configs,logs,scripts}
# Create project .gitignore as defined in section 0.2

# 3. Configure environment variables
cd ~/fx-pipeline
cat > .env.example <<'EOF'
QLIB_DATA_PATH=~/.qlib/forex_m1
REDIS_URL=redis://localhost:6379/0
MT5_TERMINAL_PATH="C:\\Program Files\\MetaTrader 5\\terminal64.exe"
API_KEY=your_api_key_here
EOF
cp .env.example .env

# 4. Initialize DVC and track raw data
dvc init
dvc remote add origin <remote-storage-url>
dvc add data/raw
git add .dvc/config data/raw.dvc
git commit -m "Track raw data with DVC"

# 5. Preprocess and convert raw CSV data to Qlib format
python scripts/prepare_m15_data.py --csv_dir data/raw --qlib_dir ~/.qlib/forex_m1 --symbol_field_name symbol --date_field_name datetime
python -m qlib.data.convert_csv_to_bin --csv_dir data/raw --qlib_dir ~/.qlib/forex_m1 --symbol_field_name symbol --date_field_name datetime

# 6. (Optional) Validate data quality via manual inspection or tests

# 7. Implement baseline EA logic in Python
mkdir -p factors
# Edit factors/baseline.py with your MQL5 decision logic

# 8. Create baseline experiment config
mkdir -p configs
# Define configs/baseline.yaml according to section 2

# 9. Run baseline backtest
qlib_run configs/baseline.yaml

# 10. Configure RD-Agent and health-check
# Save rdagent.yaml per section 3.1
rdagent health_check

# 11. Develop and register the reward function
mkdir -p rewards
# Edit rewards/fundingpips_reward.py per section 4.1

# 12. Launch RD-Agent self-improvement loop
rdagent fin_factor --config rdagent.yaml
# Monitor progress: rdagent ui --port 19899

# 13. Export best model and generate live inference service
rdagent export best --out models/best_model.pkl
python scripts/gen_live_inference.py --model models/best_model.pkl --out live_signal_service.py

# 14. Build and deploy the signal API container
docker build -t fx-signal-api .
docker run -d --name signal-api -p 9000:9000 fx-signal-api

# 15. Start monitoring stack (Prometheus, Grafana, Alertmanager)
docker-compose up -d prometheus grafana alertmanager

# 16. Update MT5 EA to call the REST API
# Ensure WebRequest is enabled in MT5 (Tools → Options → Expert Advisors)
# Edit main.mq5 with WebRequest/JSON parsing as in section 8

# 17. (Optional) Run trade synchronization for manual mirroring
python scripts/trade_sync.py --config configs/trade_sync.yaml

# 18. (Ongoing) Monitor performance, alerts, and iterate on factor/model design
```

### Critical Success Checkpoints

- [ ] **Checkpoint 1**: Baseline EA replicated in Python with identical signals
- [ ] **Checkpoint 2**: RD-Agent successfully improves upon baseline performance  
- [ ] **Checkpoint 3**: Signal API responds correctly to MT5 WebRequests
- [ ] **Checkpoint 4**: Trade sync accurately captures and formats MT5 trades
- [ ] **Checkpoint 5**: Manual execution achieves target performance on FundingPips demo
- [ ] **Checkpoint 6**: Full pipeline runs end-to-end without intervention

### Troubleshooting Common Issues

1. **RD-Agent not improving**: Check reward function, increase patience, verify data quality
2. **MT5 WebRequest fails**: Verify firewall, check URL format, test JSON parsing
3. **Signal API errors**: Check model loading, validate feature calculation, review logs
4. **Manual execution drift**: Verify position sizing calculations, check execution timing
5. **Performance degradation**: Monitor for data drift, check model staleness

---

### What You Achieve

* **Automated R\&D** – RD-Agent generates fresh alpha factors & model tweaks autonomously, guided by FundingPips risk-adjusted reward.
* **Separation of concerns** – research (Linux) and execution (Windows + MT5) run independently, linked only by a lightweight REST signal.
* **"One-click" redeploy** – when the agent finds a better model, the pipeline can rebuild the Docker image, roll out the new signal API, and your EA uses it on the next bar.

Follow this blueprint and you'll have a **continuous-improvement loop** that keeps hammering away at the FundingPips targets until the metrics line up—and once they do, you're only one drag-and-drop away from putting the upgraded EA on a live chart.

[1]: https://github.com/microsoft/RD-Agent "GitHub - microsoft/RD-Agent: Research and development (R&D) is crucial for the enhancement of industrial productivity, especially in the AI era, where the core aspects of R&D are mainly focused on data and models. We are committed to automating these high-value generic R&D processes through R&D-Agent, which lets AI drive data-driven AI. https://aka.ms/RD-Agent-Tech-Report"
[2]: https://github.com/microsoft/qlib "GitHub - microsoft/qlib: Qlib is an AI-oriented Quant investment platform that aims to use AI tech to empower Quant Research, from exploring ideas to implementing productions. Qlib supports diverse ML modeling paradigms, including supervised learning, market dynamics modeling, and RL, and is now equipped with https://github.com/microsoft/RD-Agent to automate R&D process."
[3]: https://github.com/microsoft/RD-Agent?utm_source=chatgpt.com "microsoft/RD-Agent: Research and development (R&D) is ... - GitHub"
