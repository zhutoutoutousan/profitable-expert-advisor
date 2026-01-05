"""
Partial Exit Strategy Analysis
Analyzes the statistical benefits of partial exits
"""
import numpy as np
import matplotlib
matplotlib.use('Agg')  # Use non-interactive backend
import matplotlib.pyplot as plt
import pandas as pd
from scipy.stats import norm

class PartialExitAnalyzer:
    def __init__(self, initial_price=100, drift=0.0001, volatility=0.02):
        self.initial_price = initial_price
        self.drift = drift
        self.volatility = volatility
    
    def simulate_price_path(self, num_steps=1000, dt=1/252):
        """Simulate price using geometric Brownian motion"""
        prices = [self.initial_price]
        
        for _ in range(num_steps):
            dW = np.random.normal(0, np.sqrt(dt))
            dS = self.drift * prices[-1] * dt + self.volatility * prices[-1] * dW
            prices.append(prices[-1] + dS)
        
        return np.array(prices)
    
    def calculate_full_exit_return(self, prices, exit_time):
        """Calculate return for full exit at exit_time"""
        exit_price = prices[exit_time]
        return (exit_price - self.initial_price) / self.initial_price
    
    def calculate_partial_exit_return(self, prices, partial_exit_time, 
                                     partial_exit_pct, final_exit_time):
        """Calculate return for partial exit strategy"""
        partial_exit_price = prices[partial_exit_time]
        final_exit_price = prices[final_exit_time]
        
        # Partial exit profit
        partial_profit = partial_exit_pct * (partial_exit_price - self.initial_price) / self.initial_price
        
        # Remaining position profit
        remaining_profit = (1 - partial_exit_pct) * (final_exit_price - self.initial_price) / self.initial_price
        
        total_return = partial_profit + remaining_profit
        return total_return, partial_profit, remaining_profit
    
    def analyze_partial_exit(self, num_simulations=1000, num_steps=1000, 
                            partial_exit_pct=0.5, partial_exit_time=500):
        """Analyze partial exit strategy"""
        results = []
        
        for sim in range(num_simulations):
            prices = self.simulate_price_path(num_steps)
            
            # Full exit at end
            full_return = self.calculate_full_exit_return(prices, len(prices) - 1)
            
            # Partial exit strategy
            partial_return, partial_profit, remaining_profit = self.calculate_partial_exit_return(
                prices, partial_exit_time, partial_exit_pct, len(prices) - 1)
            
            results.append({
                'simulation': sim,
                'final_price': prices[-1],
                'partial_exit_price': prices[partial_exit_time],
                'full_return': full_return,
                'partial_return': partial_return,
                'partial_profit': partial_profit,
                'remaining_profit': remaining_profit,
                'variance_reduction': np.var([partial_profit, remaining_profit]) - np.var([full_return])
            })
        
        return pd.DataFrame(results)
    
    def optimize_exit_percentage(self, num_simulations=500, exit_percentages=np.arange(0.1, 0.9, 0.1)):
        """Find optimal partial exit percentage"""
        results = []
        
        for exit_pct in exit_percentages:
            df = self.analyze_partial_exit(num_simulations=num_simulations, 
                                          partial_exit_pct=exit_pct)
            
            mean_return = df['partial_return'].mean()
            std_return = df['partial_return'].std()
            sharpe = mean_return / std_return if std_return > 0 else 0
            
            results.append({
                'exit_percentage': exit_pct,
                'mean_return': mean_return,
                'std_return': std_return,
                'sharpe_ratio': sharpe,
                'variance_reduction': df['variance_reduction'].mean()
            })
        
        return pd.DataFrame(results)
    
    def plot_analysis(self, num_simulations=1000):
        """Plot analysis results"""
        results_df = self.analyze_partial_exit(num_simulations)
        optimization_df = self.optimize_exit_percentage()
        
        fig, axes = plt.subplots(2, 2, figsize=(15, 10))
        
        # Plot 1: Return Distribution Comparison
        axes[0, 0].hist(results_df['full_return'], bins=50, alpha=0.5, 
                       label='Full Exit', color='red', edgecolor='black')
        axes[0, 0].hist(results_df['partial_return'], bins=50, alpha=0.5, 
                       label='Partial Exit (50%)', color='green', edgecolor='black')
        axes[0, 0].axvline(0, color='black', linestyle='--', linewidth=1)
        axes[0, 0].set_xlabel('Return')
        axes[0, 0].set_ylabel('Frequency')
        axes[0, 0].set_title('Return Distribution: Full vs Partial Exit')
        axes[0, 0].legend()
        axes[0, 0].grid(True, alpha=0.3)
        
        # Plot 2: Variance Reduction
        axes[0, 1].hist(results_df['variance_reduction'], bins=50, color='blue', 
                       edgecolor='black', alpha=0.7)
        axes[0, 1].axvline(0, color='red', linestyle='--', linewidth=2)
        axes[0, 1].axvline(results_df['variance_reduction'].mean(), color='green', 
                          linestyle='--', linewidth=2,
                          label=f'Mean: {results_df["variance_reduction"].mean():.6f}')
        axes[0, 1].set_xlabel('Variance Reduction')
        axes[0, 1].set_ylabel('Frequency')
        axes[0, 1].set_title('Variance Reduction from Partial Exit')
        axes[0, 1].legend()
        axes[0, 1].grid(True, alpha=0.3)
        
        # Plot 3: Optimal Exit Percentage
        axes[1, 0].plot(optimization_df['exit_percentage'], 
                       optimization_df['sharpe_ratio'], 
                       'b-o', linewidth=2, markersize=8)
        optimal_idx = optimization_df['sharpe_ratio'].idxmax()
        optimal_pct = optimization_df.loc[optimal_idx, 'exit_percentage']
        optimal_sharpe = optimization_df.loc[optimal_idx, 'sharpe_ratio']
        axes[1, 0].axvline(optimal_pct, color='red', linestyle='--', 
                          label=f'Optimal: {optimal_pct:.1%}')
        axes[1, 0].set_xlabel('Partial Exit Percentage')
        axes[1, 0].set_ylabel('Sharpe Ratio')
        axes[1, 0].set_title('Sharpe Ratio vs Exit Percentage')
        axes[1, 0].legend()
        axes[1, 0].grid(True, alpha=0.3)
        
        # Plot 4: Variance Reduction vs Exit Percentage
        axes[1, 1].plot(optimization_df['exit_percentage'], 
                        optimization_df['variance_reduction'], 
                        'g-s', linewidth=2, markersize=8)
        axes[1, 1].axhline(0, color='red', linestyle='--', linewidth=1)
        axes[1, 1].set_xlabel('Partial Exit Percentage')
        axes[1, 1].set_ylabel('Variance Reduction')
        axes[1, 1].set_title('Variance Reduction vs Exit Percentage')
        axes[1, 1].grid(True, alpha=0.3)
        
        plt.tight_layout()
        return fig, results_df, optimization_df

if __name__ == "__main__":
    analyzer = PartialExitAnalyzer()
    
    print("Running Partial Exit Analysis...")
    fig, results_df, optimization_df = analyzer.plot_analysis(num_simulations=1000)
    
    print("\n=== Partial Exit Strategy Analysis ===")
    print(f"\nFull Exit Results:")
    print(f"  Mean Return: {results_df['full_return'].mean():.4f}")
    print(f"  Std Dev: {results_df['full_return'].std():.4f}")
    print(f"  Sharpe Ratio: {results_df['full_return'].mean() / results_df['full_return'].std():.4f}")
    
    print(f"\nPartial Exit Results (50% exit):")
    print(f"  Mean Return: {results_df['partial_return'].mean():.4f}")
    print(f"  Std Dev: {results_df['partial_return'].std():.4f}")
    print(f"  Sharpe Ratio: {results_df['partial_return'].mean() / results_df['partial_return'].std():.4f}")
    print(f"  Mean Variance Reduction: {results_df['variance_reduction'].mean():.6f}")
    
    optimal_idx = optimization_df['sharpe_ratio'].idxmax()
    print(f"\nOptimal Exit Percentage: {optimization_df.loc[optimal_idx, 'exit_percentage']:.1%}")
    print(f"  Optimal Sharpe Ratio: {optimization_df.loc[optimal_idx, 'sharpe_ratio']:.4f}")
    
    import os
    # Get the script directory and construct path to figures
    script_dir = os.path.dirname(os.path.abspath(__file__))
    figures_dir = os.path.join(script_dir, '..', 'figures')
    figures_path = os.path.abspath(figures_dir)
    os.makedirs(figures_path, exist_ok=True)
    
    output_path = os.path.join(figures_path, 'partial_exit_analysis.png')
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    print(f"\nFigure saved to {output_path}")
    plt.close()
