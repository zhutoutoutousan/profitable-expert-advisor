"""
Martingale Strategy Simulation
Analyzes the statistical properties and risk of martingale strategies
"""
import numpy as np
import matplotlib
matplotlib.use('Agg')  # Use non-interactive backend
import matplotlib.pyplot as plt
from scipy import stats
import pandas as pd

class MartingaleSimulator:
    def __init__(self, initial_balance=10000, base_lot=0.01, win_prob=0.5, 
                 win_amount=10, loss_amount=10, max_losses=10):
        self.initial_balance = initial_balance
        self.base_lot = base_lot
        self.win_prob = win_prob
        self.win_amount = win_amount
        self.loss_amount = loss_amount
        self.max_losses = max_losses
        
    def calculate_position_size(self, consecutive_losses):
        """Calculate position size after n consecutive losses"""
        return self.base_lot * (2 ** consecutive_losses)
    
    def calculate_required_capital(self, consecutive_losses):
        """Calculate total capital needed after n losses"""
        return self.base_lot * (2 ** (consecutive_losses + 1) - 1)
    
    def simulate_trade_sequence(self, num_trades=1000):
        """Simulate a sequence of trades"""
        balance = self.initial_balance
        consecutive_losses = 0
        trades = []
        ruin = False
        
        for i in range(num_trades):
            if balance <= 0:
                ruin = True
                break
                
            # Calculate position size
            position_size = self.calculate_position_size(consecutive_losses)
            required_capital = self.calculate_required_capital(consecutive_losses)
            
            # Check if we have enough capital
            if required_capital > balance:
                ruin = True
                break
            
            # Simulate trade outcome
            is_win = np.random.random() < self.win_prob
            
            if is_win:
                # Win: recover all previous losses
                profit = position_size * self.win_amount
                balance += profit
                consecutive_losses = 0
                outcome = 'Win'
            else:
                # Loss: add to consecutive losses
                loss = position_size * self.loss_amount
                balance -= loss
                consecutive_losses += 1
                outcome = 'Loss'
            
            trades.append({
                'trade': i + 1,
                'balance': balance,
                'position_size': position_size,
                'consecutive_losses': consecutive_losses,
                'outcome': outcome,
                'profit': profit if is_win else -loss
            })
        
        return pd.DataFrame(trades), ruin
    
    def monte_carlo_analysis(self, num_simulations=1000, num_trades=100):
        """Run Monte Carlo simulation"""
        results = []
        ruin_count = 0
        
        for sim in range(num_simulations):
            trades_df, ruin = self.simulate_trade_sequence(num_trades)
            if ruin:
                ruin_count += 1
                final_balance = 0
            else:
                final_balance = trades_df['balance'].iloc[-1]
            
            results.append({
                'simulation': sim,
                'final_balance': final_balance,
                'ruin': ruin,
                'total_trades': len(trades_df),
                'max_consecutive_losses': trades_df['consecutive_losses'].max() if len(trades_df) > 0 else 0
            })
        
        return pd.DataFrame(results), ruin_count / num_simulations
    
    def plot_simulation_results(self, num_simulations=100):
        """Plot simulation results"""
        fig, axes = plt.subplots(2, 2, figsize=(15, 10))
        
        # Run simulations
        results_df, ruin_prob = self.monte_carlo_analysis(num_simulations)
        
        # Plot 1: Final Balance Distribution
        axes[0, 0].hist(results_df['final_balance'], bins=50, edgecolor='black')
        axes[0, 0].axvline(self.initial_balance, color='red', linestyle='--', 
                          label=f'Initial Balance: ${self.initial_balance:,.0f}')
        axes[0, 0].set_xlabel('Final Balance ($)')
        axes[0, 0].set_ylabel('Frequency')
        axes[0, 0].set_title(f'Final Balance Distribution\nRuin Probability: {ruin_prob:.2%}')
        axes[0, 0].legend()
        axes[0, 0].grid(True, alpha=0.3)
        
        # Plot 2: Ruin Probability vs Consecutive Losses
        max_losses_range = range(1, self.max_losses + 1)
        ruin_probs = []
        for n in max_losses_range:
            required = self.calculate_required_capital(n)
            ruin_probs.append(1.0 if required > self.initial_balance else 0.0)
        
        axes[0, 1].plot(max_losses_range, ruin_probs, 'ro-', linewidth=2, markersize=8)
        axes[0, 1].set_xlabel('Consecutive Losses')
        axes[0, 1].set_ylabel('Ruin Probability')
        axes[0, 1].set_title('Ruin Probability vs Consecutive Losses')
        axes[0, 1].grid(True, alpha=0.3)
        axes[0, 1].set_ylim([-0.1, 1.1])
        
        # Plot 3: Position Size Growth
        losses_range = range(0, self.max_losses + 1)
        position_sizes = [self.calculate_position_size(n) for n in losses_range]
        required_capital = [self.calculate_required_capital(n) for n in losses_range]
        
        ax3_twin = axes[1, 0].twinx()
        line1 = axes[1, 0].plot(losses_range, position_sizes, 'b-o', 
                               label='Position Size', linewidth=2)
        line2 = ax3_twin.plot(losses_range, required_capital, 'r-s', 
                             label='Required Capital', linewidth=2)
        
        axes[1, 0].set_xlabel('Consecutive Losses')
        axes[1, 0].set_ylabel('Position Size (Lots)', color='b')
        ax3_twin.set_ylabel('Required Capital ($)', color='r')
        axes[1, 0].set_title('Position Size and Capital Requirements')
        axes[1, 0].grid(True, alpha=0.3)
        
        # Combine legends
        lines = line1 + line2
        labels = [l.get_label() for l in lines]
        axes[1, 0].legend(lines, labels, loc='upper left')
        
        # Plot 4: Sample Trade Sequence
        sample_trades, _ = self.simulate_trade_sequence(50)
        axes[1, 1].plot(sample_trades['trade'], sample_trades['balance'], 
                       'g-', linewidth=2, label='Balance')
        axes[1, 1].axhline(self.initial_balance, color='red', linestyle='--', 
                          label='Initial Balance')
        axes[1, 1].set_xlabel('Trade Number')
        axes[1, 1].set_ylabel('Balance ($)')
        axes[1, 1].set_title('Sample Trade Sequence (50 trades)')
        axes[1, 1].legend()
        axes[1, 1].grid(True, alpha=0.3)
        
        plt.tight_layout()
        return fig

if __name__ == "__main__":
    # Create simulator
    simulator = MartingaleSimulator(
        initial_balance=10000,
        base_lot=0.01,
        win_prob=0.5,
        win_amount=10,
        loss_amount=10,
        max_losses=10
    )
    
    # Run analysis
    print("Running Martingale Simulation...")
    results_df, ruin_prob = simulator.monte_carlo_analysis(num_simulations=1000, num_trades=100)
    
    print(f"\n=== Martingale Strategy Analysis ===")
    print(f"Initial Balance: ${simulator.initial_balance:,.2f}")
    print(f"Win Probability: {simulator.win_prob:.1%}")
    print(f"\nMonte Carlo Results (1000 simulations):")
    print(f"Ruin Probability: {ruin_prob:.2%}")
    print(f"Mean Final Balance: ${results_df['final_balance'].mean():,.2f}")
    print(f"Median Final Balance: ${results_df['final_balance'].median():,.2f}")
    print(f"Std Dev Final Balance: ${results_df['final_balance'].std():,.2f}")
    print(f"Max Final Balance: ${results_df['final_balance'].max():,.2f}")
    print(f"Min Final Balance: ${results_df['final_balance'].min():,.2f}")
    
    # Calculate statistics
    profitable_sims = (results_df['final_balance'] > simulator.initial_balance).sum()
    print(f"\nProfitable Simulations: {profitable_sims}/{len(results_df)} ({profitable_sims/len(results_df):.1%})")
    print(f"Average Max Consecutive Losses: {results_df['max_consecutive_losses'].mean():.2f}")
    
    # Generate plots
    import os
    # Get the script directory and construct path to figures
    script_dir = os.path.dirname(os.path.abspath(__file__))
    figures_dir = os.path.join(script_dir, '..', 'figures')
    figures_path = os.path.abspath(figures_dir)
    os.makedirs(figures_path, exist_ok=True)
    
    fig = simulator.plot_simulation_results(num_simulations=100)
    output_path = os.path.join(figures_path, 'martingale_analysis.png')
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    print(f"\nFigure saved to {output_path}")
    plt.close()
