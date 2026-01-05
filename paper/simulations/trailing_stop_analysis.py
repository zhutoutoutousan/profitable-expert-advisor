"""
Trailing Stop Loss Analysis
Compares fixed stop loss vs trailing stop loss performance
"""
import numpy as np
import matplotlib
matplotlib.use('Agg')  # Use non-interactive backend
import matplotlib.pyplot as plt
import pandas as pd
from scipy.stats import norm

class TrailingStopAnalyzer:
    def __init__(self, initial_price=100, drift=0.0001, volatility=0.02, 
                 trailing_distance=0.02, fixed_stop_distance=0.02):
        self.initial_price = initial_price
        self.drift = drift
        self.volatility = volatility
        self.trailing_distance = trailing_distance
        self.fixed_stop_distance = fixed_stop_distance
        
    def simulate_price_path(self, num_steps=1000, dt=1/252):
        """Simulate price using geometric Brownian motion"""
        prices = [self.initial_price]
        
        for _ in range(num_steps):
            dW = np.random.normal(0, np.sqrt(dt))
            dS = self.drift * prices[-1] * dt + self.volatility * prices[-1] * dW
            prices.append(prices[-1] + dS)
        
        return np.array(prices)
    
    def apply_fixed_stop(self, prices, stop_distance):
        """Apply fixed stop loss"""
        stop_price = self.initial_price - stop_distance * self.initial_price
        exit_idx = None
        
        for i, price in enumerate(prices):
            if price <= stop_price:
                exit_idx = i
                break
        
        if exit_idx is None:
            exit_price = prices[-1]
            exit_idx = len(prices) - 1
        else:
            exit_price = stop_price
        
        return exit_idx, exit_price
    
    def apply_trailing_stop(self, prices, trailing_distance):
        """Apply trailing stop loss"""
        stop_price = self.initial_price - trailing_distance * self.initial_price
        exit_idx = None
        
        for i, price in enumerate(prices):
            # Update trailing stop (only moves up for long positions)
            new_stop = price - trailing_distance * price
            if new_stop > stop_price:
                stop_price = new_stop
            
            # Check if stop is hit
            if price <= stop_price:
                exit_idx = i
                break
        
        if exit_idx is None:
            exit_price = prices[-1]
            exit_idx = len(prices) - 1
        else:
            exit_price = stop_price
        
        return exit_idx, exit_price, stop_price
    
    def compare_strategies(self, num_simulations=1000, num_steps=1000):
        """Compare fixed vs trailing stop"""
        results = []
        
        for sim in range(num_simulations):
            prices = self.simulate_price_path(num_steps)
            
            # Fixed stop
            fixed_exit_idx, fixed_exit_price = self.apply_fixed_stop(
                prices, self.fixed_stop_distance)
            fixed_return = (fixed_exit_price - self.initial_price) / self.initial_price
            
            # Trailing stop
            trailing_exit_idx, trailing_exit_price, final_stop = self.apply_trailing_stop(
                prices, self.trailing_distance)
            trailing_return = (trailing_exit_price - self.initial_price) / self.initial_price
            
            results.append({
                'simulation': sim,
                'final_price': prices[-1],
                'fixed_return': fixed_return,
                'trailing_return': trailing_return,
                'fixed_exit_time': fixed_exit_idx,
                'trailing_exit_time': trailing_exit_idx,
                'improvement': trailing_return - fixed_return
            })
        
        return pd.DataFrame(results)
    
    def plot_comparison(self, num_simulations=1000):
        """Plot comparison results"""
        results_df = self.compare_strategies(num_simulations)
        
        fig, axes = plt.subplots(2, 2, figsize=(15, 10))
        
        # Plot 1: Return Distribution Comparison
        axes[0, 0].hist(results_df['fixed_return'], bins=50, alpha=0.5, 
                       label='Fixed Stop', color='red', edgecolor='black')
        axes[0, 0].hist(results_df['trailing_return'], bins=50, alpha=0.5, 
                       label='Trailing Stop', color='green', edgecolor='black')
        axes[0, 0].axvline(0, color='black', linestyle='--', linewidth=1)
        axes[0, 0].set_xlabel('Return')
        axes[0, 0].set_ylabel('Frequency')
        axes[0, 0].set_title('Return Distribution Comparison')
        axes[0, 0].legend()
        axes[0, 0].grid(True, alpha=0.3)
        
        # Plot 2: Improvement Distribution
        axes[0, 1].hist(results_df['improvement'], bins=50, color='blue', 
                       edgecolor='black', alpha=0.7)
        axes[0, 1].axvline(0, color='red', linestyle='--', linewidth=2, 
                          label='No Improvement')
        axes[0, 1].axvline(results_df['improvement'].mean(), color='green', 
                          linestyle='--', linewidth=2, 
                          label=f'Mean: {results_df["improvement"].mean():.4f}')
        axes[0, 1].set_xlabel('Improvement (Trailing - Fixed)')
        axes[0, 1].set_ylabel('Frequency')
        axes[0, 1].set_title('Trailing Stop Improvement Distribution')
        axes[0, 1].legend()
        axes[0, 1].grid(True, alpha=0.3)
        
        # Plot 3: Sample Price Path with Stops
        sample_prices = self.simulate_price_path(500)
        _, fixed_exit = self.apply_fixed_stop(sample_prices, self.fixed_stop_distance)
        trailing_stops = []
        current_stop = self.initial_price - self.trailing_distance * self.initial_price
        
        for price in sample_prices:
            new_stop = price - self.trailing_distance * price
            if new_stop > current_stop:
                current_stop = new_stop
            trailing_stops.append(current_stop)
        
        axes[1, 0].plot(sample_prices, 'b-', label='Price', linewidth=2)
        axes[1, 0].axhline(self.initial_price - self.fixed_stop_distance * self.initial_price, 
                          color='red', linestyle='--', label='Fixed Stop', linewidth=2)
        axes[1, 0].plot(trailing_stops, 'g--', label='Trailing Stop', linewidth=2)
        axes[1, 0].set_xlabel('Time Step')
        axes[1, 0].set_ylabel('Price')
        axes[1, 0].set_title('Sample Price Path with Stop Losses')
        axes[1, 0].legend()
        axes[1, 0].grid(True, alpha=0.3)
        
        # Plot 4: Performance Metrics Comparison
        metrics = ['Mean Return', 'Std Dev', 'Sharpe Ratio', 'Win Rate', 'Max Return']
        fixed_vals = [
            results_df['fixed_return'].mean(),
            results_df['fixed_return'].std(),
            results_df['fixed_return'].mean() / results_df['fixed_return'].std() if results_df['fixed_return'].std() > 0 else 0,
            (results_df['fixed_return'] > 0).mean(),
            results_df['fixed_return'].max()
        ]
        trailing_vals = [
            results_df['trailing_return'].mean(),
            results_df['trailing_return'].std(),
            results_df['trailing_return'].mean() / results_df['trailing_return'].std() if results_df['trailing_return'].std() > 0 else 0,
            (results_df['trailing_return'] > 0).mean(),
            results_df['trailing_return'].max()
        ]
        
        x = np.arange(len(metrics))
        width = 0.35
        axes[1, 1].bar(x - width/2, fixed_vals, width, label='Fixed Stop', color='red', alpha=0.7)
        axes[1, 1].bar(x + width/2, trailing_vals, width, label='Trailing Stop', color='green', alpha=0.7)
        axes[1, 1].set_xlabel('Metric')
        axes[1, 1].set_ylabel('Value')
        axes[1, 1].set_title('Performance Metrics Comparison')
        axes[1, 1].set_xticks(x)
        axes[1, 1].set_xticklabels(metrics, rotation=45, ha='right')
        axes[1, 1].legend()
        axes[1, 1].grid(True, alpha=0.3, axis='y')
        
        plt.tight_layout()
        return fig, results_df

if __name__ == "__main__":
    # Create analyzer
    analyzer = TrailingStopAnalyzer(
        initial_price=100,
        drift=0.0001,
        volatility=0.02,
        trailing_distance=0.02,
        fixed_stop_distance=0.02
    )
    
    print("Running Trailing Stop Analysis...")
    fig, results_df = analyzer.plot_comparison(num_simulations=1000)
    
    print("\n=== Trailing Stop vs Fixed Stop Analysis ===")
    print(f"\nFixed Stop Results:")
    print(f"  Mean Return: {results_df['fixed_return'].mean():.4f}")
    print(f"  Std Dev: {results_df['fixed_return'].std():.4f}")
    print(f"  Sharpe Ratio: {results_df['fixed_return'].mean() / results_df['fixed_return'].std():.4f}")
    print(f"  Win Rate: {(results_df['fixed_return'] > 0).mean():.2%}")
    
    print(f"\nTrailing Stop Results:")
    print(f"  Mean Return: {results_df['trailing_return'].mean():.4f}")
    print(f"  Std Dev: {results_df['trailing_return'].std():.4f}")
    print(f"  Sharpe Ratio: {results_df['trailing_return'].mean() / results_df['trailing_return'].std():.4f}")
    print(f"  Win Rate: {(results_df['trailing_return'] > 0).mean():.2%}")
    
    print(f"\nImprovement:")
    improvement = results_df['trailing_return'].mean() - results_df['fixed_return'].mean()
    print(f"  Mean Improvement: {improvement:.4f} ({improvement/results_df['fixed_return'].mean()*100:.1f}%)")
    print(f"  Improvement Frequency: {(results_df['improvement'] > 0).mean():.2%}")
    
    import os
    # Get the script directory and construct path to figures
    script_dir = os.path.dirname(os.path.abspath(__file__))
    figures_dir = os.path.join(script_dir, '..', 'figures')
    figures_path = os.path.abspath(figures_dir)
    os.makedirs(figures_path, exist_ok=True)
    
    output_path = os.path.join(figures_path, 'trailing_stop_analysis.png')
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    print(f"\nFigure saved to {output_path}")
    plt.close()
