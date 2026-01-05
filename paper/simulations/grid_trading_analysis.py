"""
Grid Trading Strategy Analysis
Analyzes grid trading performance in different market conditions
"""
import numpy as np
import matplotlib
matplotlib.use('Agg')  # Use non-interactive backend
import matplotlib.pyplot as plt
import pandas as pd
from scipy.stats import norm

class GridTradingAnalyzer:
    def __init__(self, initial_price=100, grid_spacing=1.0, num_levels=10):
        self.initial_price = initial_price
        self.grid_spacing = grid_spacing
        self.num_levels = num_levels
    
    def create_grid(self):
        """Create grid price levels"""
        grid_levels = []
        for i in range(-self.num_levels, self.num_levels + 1):
            price = self.initial_price + i * self.grid_spacing
            grid_levels.append(price)
        return np.array(grid_levels)
    
    def simulate_mean_reverting_price(self, num_steps=1000, mean_reversion_speed=0.1, 
                                     volatility=0.5, mean_price=100):
        """Simulate mean-reverting price (Ornstein-Uhlenbeck process)"""
        prices = [self.initial_price]
        dt = 1.0 / num_steps
        
        for _ in range(num_steps):
            dW = np.random.normal(0, np.sqrt(dt))
            dS = mean_reversion_speed * (mean_price - prices[-1]) * dt + volatility * dW
            prices.append(prices[-1] + dS)
        
        return np.array(prices)
    
    def simulate_trending_price(self, num_steps=1000, drift=0.01, volatility=0.5):
        """Simulate trending price (geometric Brownian motion)"""
        prices = [self.initial_price]
        dt = 1.0 / num_steps
        
        for _ in range(num_steps):
            dW = np.random.normal(0, np.sqrt(dt))
            dS = drift * prices[-1] * dt + volatility * prices[-1] * dW
            prices.append(prices[-1] + dS)
        
        return np.array(prices)
    
    def calculate_grid_profits(self, prices, grid_levels, position_size=0.01):
        """Calculate profits from grid trading"""
        positions = {}  # Track open positions at each grid level
        total_profit = 0
        trades = []
        
        for price in prices:
            # Check for grid hits
            for i, grid_price in enumerate(grid_levels):
                # Buy signal: price hits grid from above
                if price <= grid_price + 0.1 and price >= grid_price - 0.1:
                    if i not in positions or positions[i] == 'sell':
                        # Open buy position
                        positions[i] = 'buy'
                        trades.append({
                            'type': 'buy',
                            'price': grid_price,
                            'time': len(trades)
                        })
                
                # Sell signal: price hits grid from below
                if price >= grid_price - 0.1 and price <= grid_price + 0.1:
                    if i in positions and positions[i] == 'buy':
                        # Close buy position (profit)
                        profit = (price - grid_price) * position_size
                        total_profit += profit
                        del positions[i]
                        trades.append({
                            'type': 'sell',
                            'price': price,
                            'profit': profit,
                            'time': len(trades)
                        })
        
        # Close remaining positions at final price
        final_price = prices[-1]
        for level, pos_type in positions.items():
            if pos_type == 'buy':
                profit = (final_price - grid_levels[level]) * position_size
                total_profit += profit
        
        return total_profit, trades
    
    def analyze_grid_trading(self, num_simulations=100, market_type='mean_reverting'):
        """Analyze grid trading performance"""
        results = []
        
        for sim in range(num_simulations):
            if market_type == 'mean_reverting':
                prices = self.simulate_mean_reverting_price()
            else:
                prices = self.simulate_trending_price()
            
            grid_levels = self.create_grid()
            profit, trades = self.calculate_grid_profits(prices, grid_levels)
            
            results.append({
                'simulation': sim,
                'profit': profit,
                'num_trades': len([t for t in trades if t['type'] == 'sell']),
                'final_price': prices[-1],
                'price_range': prices.max() - prices.min(),
                'max_drawdown': self.calculate_max_drawdown(prices)
            })
        
        return pd.DataFrame(results)
    
    def calculate_max_drawdown(self, prices):
        """Calculate maximum drawdown"""
        peak = prices[0]
        max_dd = 0
        
        for price in prices:
            if price > peak:
                peak = price
            dd = (peak - price) / peak
            if dd > max_dd:
                max_dd = dd
        
        return max_dd
    
    def optimize_grid_spacing(self, num_simulations=50, spacing_range=np.arange(0.5, 5.0, 0.5)):
        """Find optimal grid spacing"""
        results = []
        
        for spacing in spacing_range:
            self.grid_spacing = spacing
            df = self.analyze_grid_trading(num_simulations=num_simulations, 
                                         market_type='mean_reverting')
            
            results.append({
                'spacing': spacing,
                'mean_profit': df['profit'].mean(),
                'std_profit': df['profit'].std(),
                'sharpe_ratio': df['profit'].mean() / df['profit'].std() if df['profit'].std() > 0 else 0,
                'mean_trades': df['num_trades'].mean()
            })
        
        return pd.DataFrame(results)
    
    def plot_analysis(self, num_simulations=100):
        """Plot analysis results"""
        # Analyze in different market conditions
        mean_reverting_results = self.analyze_grid_trading(num_simulations, 'mean_reverting')
        trending_results = self.analyze_grid_trading(num_simulations, 'trending')
        optimization_df = self.optimize_grid_spacing()
        
        fig, axes = plt.subplots(2, 2, figsize=(15, 10))
        
        # Plot 1: Profit Distribution Comparison
        axes[0, 0].hist(mean_reverting_results['profit'], bins=30, alpha=0.5, 
                       label='Mean Reverting Market', color='green', edgecolor='black')
        axes[0, 0].hist(trending_results['profit'], bins=30, alpha=0.5, 
                       label='Trending Market', color='red', edgecolor='black')
        axes[0, 0].axvline(0, color='black', linestyle='--', linewidth=2)
        axes[0, 0].set_xlabel('Total Profit')
        axes[0, 0].set_ylabel('Frequency')
        axes[0, 0].set_title('Grid Trading Profit Distribution by Market Type')
        axes[0, 0].legend()
        axes[0, 0].grid(True, alpha=0.3)
        
        # Plot 2: Sample Price Path with Grid
        sample_prices = self.simulate_mean_reverting_price()
        grid_levels = self.create_grid()
        
        axes[0, 1].plot(sample_prices, 'b-', linewidth=2, label='Price')
        for level in grid_levels:
            axes[0, 1].axhline(level, color='gray', linestyle='--', alpha=0.3)
        axes[0, 1].axhline(self.initial_price, color='red', linestyle='-', 
                          linewidth=2, label='Initial Price')
        axes[0, 1].set_xlabel('Time Step')
        axes[0, 1].set_ylabel('Price')
        axes[0, 1].set_title('Sample Price Path with Grid Levels')
        axes[0, 1].legend()
        axes[0, 1].grid(True, alpha=0.3)
        
        # Plot 3: Optimal Grid Spacing
        axes[1, 0].plot(optimization_df['spacing'], optimization_df['sharpe_ratio'], 
                       'b-o', linewidth=2, markersize=8, label='Sharpe Ratio')
        optimal_idx = optimization_df['sharpe_ratio'].idxmax()
        optimal_spacing = optimization_df.loc[optimal_idx, 'spacing']
        axes[1, 0].axvline(optimal_spacing, color='red', linestyle='--', 
                          label=f'Optimal: {optimal_spacing:.2f}')
        axes[1, 0].set_xlabel('Grid Spacing')
        axes[1, 0].set_ylabel('Sharpe Ratio')
        axes[1, 0].set_title('Optimal Grid Spacing Analysis')
        axes[1, 0].legend()
        axes[1, 0].grid(True, alpha=0.3)
        
        # Plot 4: Profit vs Number of Trades
        axes[1, 1].scatter(mean_reverting_results['num_trades'], 
                          mean_reverting_results['profit'], 
                          alpha=0.5, label='Mean Reverting', color='green')
        axes[1, 1].scatter(trending_results['num_trades'], 
                          trending_results['profit'], 
                          alpha=0.5, label='Trending', color='red')
        axes[1, 1].axhline(0, color='black', linestyle='--', linewidth=1)
        axes[1, 1].set_xlabel('Number of Trades')
        axes[1, 1].set_ylabel('Total Profit')
        axes[1, 1].set_title('Profit vs Trade Frequency')
        axes[1, 1].legend()
        axes[1, 1].grid(True, alpha=0.3)
        
        plt.tight_layout()
        return fig, mean_reverting_results, trending_results, optimization_df

if __name__ == "__main__":
    analyzer = GridTradingAnalyzer(initial_price=100, grid_spacing=1.0, num_levels=10)
    
    print("Running Grid Trading Analysis...")
    fig, mr_results, tr_results, opt_df = analyzer.plot_analysis(num_simulations=100)
    
    print("\n=== Grid Trading Strategy Analysis ===")
    print(f"\nMean Reverting Market:")
    print(f"  Mean Profit: ${mr_results['profit'].mean():.2f}")
    print(f"  Std Dev: ${mr_results['profit'].std():.2f}")
    print(f"  Win Rate: {(mr_results['profit'] > 0).mean():.2%}")
    print(f"  Mean Trades: {mr_results['num_trades'].mean():.1f}")
    
    print(f"\nTrending Market:")
    print(f"  Mean Profit: ${tr_results['profit'].mean():.2f}")
    print(f"  Std Dev: ${tr_results['profit'].std():.2f}")
    print(f"  Win Rate: {(tr_results['profit'] > 0).mean():.2%}")
    print(f"  Mean Trades: {tr_results['num_trades'].mean():.1f}")
    
    optimal_idx = opt_df['sharpe_ratio'].idxmax()
    print(f"\nOptimal Grid Spacing: {opt_df.loc[optimal_idx, 'spacing']:.2f}")
    print(f"  Optimal Sharpe Ratio: {opt_df.loc[optimal_idx, 'sharpe_ratio']:.4f}")
    
    import os
    # Get the script directory and construct path to figures
    script_dir = os.path.dirname(os.path.abspath(__file__))
    figures_dir = os.path.join(script_dir, '..', 'figures')
    figures_path = os.path.abspath(figures_dir)
    os.makedirs(figures_path, exist_ok=True)
    
    output_path = os.path.join(figures_path, 'grid_trading_analysis.png')
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    print(f"\nFigure saved to {output_path}")
    plt.close()
