# Trading Strategy Simulations

This directory contains Python scripts for simulating and analyzing advanced trading techniques.

## Scripts

### 1. martingale_simulation.py
Analyzes the statistical properties and risk of martingale strategies.

**Key Analyses:**
- Ruin probability calculations
- Position size growth
- Required capital analysis
- Monte Carlo simulations

**Usage:**
```bash
python martingale_simulation.py
```

**Output:**
- `martingale_analysis.png`: Comprehensive analysis plots
- Console output with statistics

### 2. trailing_stop_analysis.py
Compares fixed stop loss vs trailing stop loss performance.

**Key Analyses:**
- Return distribution comparison
- Sharpe ratio improvement
- Exit timing analysis
- Sample price path visualization

**Usage:**
```bash
python trailing_stop_analysis.py
```

**Output:**
- `trailing_stop_analysis.png`: Comparison plots
- Console output with performance metrics

### 3. partial_exit_analysis.py
Analyzes the statistical benefits of partial exits.

**Key Analyses:**
- Variance reduction calculation
- Sharpe ratio optimization
- Optimal exit percentage
- Return distribution comparison

**Usage:**
```bash
python partial_exit_analysis.py
```

**Output:**
- `partial_exit_analysis.png`: Analysis plots
- Console output with optimization results

### 4. grid_trading_analysis.py
Analyzes grid trading performance in different market conditions.

**Key Analyses:**
- Mean-reverting vs trending market performance
- Optimal grid spacing
- Trade frequency analysis
- Profit distribution

**Usage:**
```bash
python grid_trading_analysis.py
```

**Output:**
- `grid_trading_analysis.png`: Market condition comparison
- Console output with performance metrics

## Installation

```bash
pip install -r requirements.txt
```

## Running All Simulations

```bash
# Run all simulations
python martingale_simulation.py
python trailing_stop_analysis.py
python partial_exit_analysis.py
python grid_trading_analysis.py
```

## Output Location

All figures are saved to `../figures/` directory:
- `martingale_analysis.png`
- `trailing_stop_analysis.png`
- `partial_exit_analysis.png`
- `grid_trading_analysis.png`

## Mathematical Foundations

These simulations implement:
- Geometric Brownian Motion for price simulation
- Ornstein-Uhlenbeck process for mean-reverting prices
- Monte Carlo methods for statistical analysis
- Kelly Criterion for position sizing
- Sharpe ratio and other risk-adjusted metrics

## Notes

- Simulations use random number generation - results may vary slightly between runs
- For reproducible results, set random seeds in scripts
- Adjust parameters in each script to match your trading conditions
- Results are illustrative - actual trading results will vary
