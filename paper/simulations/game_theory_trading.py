"""
Game Theory Analysis: Retail Traders vs Big Players
Models the strategic interaction between retail traders (driven by FOMO/group psychology)
and institutional players in financial markets.

Key Features:
- Retail traders exhibit FOMO behavior (herding, momentum following)
- Big players act strategically to exploit retail behavior
- Finite repeated game (not infinite, as big players are human)
- Nash equilibrium analysis
- Order book model: realistic price impact based on order book depth
- Big players have more capital and their trades move markets through order book consumption
"""
import numpy as np
import matplotlib
matplotlib.use('Agg')  # Use non-interactive backend
import matplotlib.pyplot as plt
import pandas as pd
from scipy.optimize import minimize, differential_evolution
from scipy.stats import norm
import itertools
from collections import defaultdict

class RetailTrader:
    """Models retail trader behavior with FOMO and group psychology"""
    
    def __init__(self, base_risk_aversion=0.5, fomo_sensitivity=0.3, 
                 herd_tendency=0.4, memory_decay=0.9):
        self.base_risk_aversion = base_risk_aversion
        self.fomo_sensitivity = fomo_sensitivity
        self.herd_tendency = herd_tendency
        self.memory_decay = memory_decay
        self.price_memory = []
        self.sentiment = 0.0  # -1 (bearish) to +1 (bullish)
        
    def update_sentiment(self, price_change, market_momentum, retail_activity):
        """Update sentiment based on FOMO and herding"""
        # FOMO component: stronger reaction to positive moves
        fomo_component = self.fomo_sensitivity * np.tanh(price_change * 10)
        
        # Herding component: follow the crowd
        herd_component = self.herd_tendency * np.tanh(retail_activity * 5)
        
        # Momentum component
        momentum_component = 0.2 * np.tanh(market_momentum * 3)
        
        # Update sentiment with memory decay
        new_sentiment = fomo_component + herd_component + momentum_component
        self.sentiment = self.memory_decay * self.sentiment + (1 - self.memory_decay) * new_sentiment
        self.sentiment = np.clip(self.sentiment, -1, 1)
        
        return self.sentiment
    
    def decide_action(self, current_price, expected_return, volatility):
        """Decide trading action based on sentiment and risk"""
        # Risk-adjusted expected utility
        risk_adjusted_return = expected_return - self.base_risk_aversion * volatility**2
        
        # Sentiment bias
        sentiment_bias = self.sentiment * (1 - self.base_risk_aversion)
        
        # Decision threshold
        decision_score = risk_adjusted_return + sentiment_bias
        
        if decision_score > 0.02:
            return 'buy', min(abs(decision_score) * 10, 1.0)  # position size
        elif decision_score < -0.02:
            return 'sell', min(abs(decision_score) * 10, 1.0)
        else:
            return 'hold', 0.0


class OrderBook:
    """Models order book depth and price impact"""
    
    def __init__(self, base_liquidity=1000, depth_levels=10, 
                 liquidity_decay=0.95, liquidity_replenish=0.02):
        """
        base_liquidity: Base liquidity at each price level
        depth_levels: Number of price levels in order book
        liquidity_decay: How much liquidity is consumed (0-1)
        liquidity_replenish: Rate at which liquidity replenishes per round
        """
        self.base_liquidity = base_liquidity
        self.depth_levels = depth_levels
        self.liquidity_decay = liquidity_decay
        self.liquidity_replenish = liquidity_replenish
        self.bid_depth = np.ones(depth_levels) * base_liquidity  # Liquidity at each level below price
        self.ask_depth = np.ones(depth_levels) * base_liquidity  # Liquidity at each level above price
        
    def calculate_price_impact(self, volume, direction, current_price):
        """
        Calculate price impact based on order book consumption
        direction: +1 for buy, -1 for sell
        Returns: price impact as fraction (e.g., 0.01 = 1% move)
        """
        if volume == 0:
            return 0.0
        
        remaining_volume = abs(volume)
        total_impact = 0.0
        price_level = current_price
        
        # Determine which side of book to consume
        if direction > 0:  # Buying - consume ask side (above current price)
            depth_array = self.ask_depth.copy()
        else:  # Selling - consume bid side (below current price)
            depth_array = self.bid_depth.copy()
        
        # Consume order book levels
        level_spread = 0.002  # 0.2% price increment per level (increased impact)
        for level in range(self.depth_levels):
            if remaining_volume <= 0:
                break
            
            available_liquidity = depth_array[level]
            consumed = min(remaining_volume, available_liquidity)
            
            # Price impact increases as we go deeper into the book
            # Impact = (level + 1) * spread * (consumed / available_liquidity)
            # More impact when consuming larger portion of available liquidity
            consumption_ratio = consumed / max(available_liquidity, 1)
            level_impact = (level + 1) * level_spread * consumption_ratio
            total_impact += level_impact
            
            # Consume liquidity
            depth_array[level] -= consumed
            remaining_volume -= consumed
        
        # If volume exceeds all available depth, add extra impact
        if remaining_volume > 0:
            # Large impact for exceeding available liquidity
            excess_impact = 0.005 * (remaining_volume / self.base_liquidity)
            total_impact += excess_impact
        
        # Update order book
        if direction > 0:
            self.ask_depth = depth_array
        else:
            self.bid_depth = depth_array
        
        return total_impact * np.sign(direction)
    
    def replenish_liquidity(self):
        """Replenish order book liquidity over time"""
        # Replenish both sides
        self.bid_depth = np.minimum(
            self.bid_depth + self.base_liquidity * self.liquidity_replenish,
            self.base_liquidity
        )
        self.ask_depth = np.minimum(
            self.ask_depth + self.base_liquidity * self.liquidity_replenish,
            self.base_liquidity
        )
    
    def get_total_liquidity(self):
        """Get total available liquidity"""
        return np.sum(self.bid_depth) + np.sum(self.ask_depth)


class BigPlayer:
    """Models institutional/big player strategic behavior"""
    
    def __init__(self, capital=1000000, market_impact_coef=0.001, 
                 patience=0.7, exploit_retail=True,
                 sentiment_threshold=0.6, volume_threshold=20, trade_size_pct=0.20):
        self.capital = capital
        self.market_impact_coef = market_impact_coef
        self.patience = patience  # How long to wait before acting
        self.exploit_retail = exploit_retail
        self.position = 0.0
        self.retail_sentiment_history = []
        # Configurable thresholds
        self.sentiment_threshold = sentiment_threshold
        self.volume_threshold = volume_threshold
        self.trade_size_pct = trade_size_pct
        
    def observe_retail_behavior(self, retail_sentiment, retail_volume):
        """Observe and learn from retail behavior"""
        self.retail_sentiment_history.append(retail_sentiment)
        if len(self.retail_sentiment_history) > 20:
            self.retail_sentiment_history.pop(0)
    
    def strategic_action(self, current_price, retail_sentiment, retail_volume, 
                        fundamental_value, game_round, order_book=None):
        """
        Strategic action based on retail behavior and fundamentals
        Returns: (action, size) where size is in actual units (not normalized)
        """
        if not self.exploit_retail:
            # Simple fundamental trading
            if current_price < fundamental_value * 0.98:
                # Buy: use 5% of capital
                size = min(100, self.capital * 0.05 / current_price)
                return 'buy', size
            elif current_price > fundamental_value * 1.02:
                # Sell: close position
                size = min(100, abs(self.position))
                return 'sell', size
            else:
                return 'hold', 0.0
        
        # Exploit retail FOMO
        avg_retail_sentiment = np.mean(self.retail_sentiment_history) if self.retail_sentiment_history else 0
        
        # Strategy: fade extreme retail sentiment
        # Use configurable thresholds
        if avg_retail_sentiment > self.sentiment_threshold and retail_volume > self.volume_threshold:
            # Retail is bullish - sell to them (large size)
            size = min(300, self.capital * self.trade_size_pct / current_price)
            return 'sell', size
        elif avg_retail_sentiment < -self.sentiment_threshold and retail_volume > self.volume_threshold:
            # Retail is bearish - buy from them (large size)
            size = min(300, self.capital * self.trade_size_pct / current_price)
            return 'buy', size
        
        # Trade on fundamentals more frequently (less patience)
        if game_round % max(1, int(3 / (1 - self.patience))) == 0:  # Trade every 3-10 rounds
            if current_price < fundamental_value * 0.98:  # More sensitive
                # Medium size fundamental trade
                size = min(100, self.capital * 0.05 / current_price)
                return 'buy', size
            elif current_price > fundamental_value * 1.02:  # More sensitive
                # Medium size fundamental trade
                size = min(100, abs(self.position))
                return 'sell', size
        
        return 'hold', 0.0


class TradingGame:
    """Simulates the repeated game between retail traders and big players"""
    
    def __init__(self, num_retail_traders=100, num_big_players=5, 
                 initial_price=100, fundamental_value=100, volatility=0.02,
                 order_book_liquidity=50, fundamental_reversion=0.01,
                 big_sentiment_threshold=0.6, big_volume_threshold=20, 
                 big_trade_size_pct=0.20):
        self.num_retail_traders = num_retail_traders
        self.num_big_players = num_big_players
        self.initial_price = initial_price
        self.fundamental_value = fundamental_value
        self.volatility = volatility
        self.fundamental_reversion = fundamental_reversion
        
        # Initialize order book with realistic liquidity
        # Lower liquidity = more price impact from trades
        # 50 units per level means 500 total units (10 levels)
        # Retail can trade 0-200 units total, so this creates meaningful impact
        self.order_book = OrderBook(
            base_liquidity=order_book_liquidity,
            depth_levels=10,
            liquidity_decay=0.95,
            liquidity_replenish=0.05  # Faster replenishment
        )
        
        # Create independent random state for this game
        # Use a unique seed based on time, object id, and random component
        import time
        import os
        base_seed = (int(time.time() * 1000000) % (2**31) + 
                    id(self) % 1000000 + 
                    os.getpid() * 1000) % (2**31)
        # Add some randomness from global RNG to ensure uniqueness
        try:
            base_seed = (base_seed + np.random.randint(0, 1000000)) % (2**31)
        except:
            pass
        self.rng = np.random.RandomState(base_seed)
        
        # Initialize players with game-specific random state
        self.retail_traders = [RetailTrader(
            base_risk_aversion=self.rng.uniform(0.3, 0.7),
            fomo_sensitivity=self.rng.uniform(0.2, 0.5),
            herd_tendency=self.rng.uniform(0.3, 0.6)
        ) for _ in range(num_retail_traders)]
        
        self.big_players = [BigPlayer(
            capital=self.rng.uniform(500000, 2000000),
            exploit_retail=True,
            sentiment_threshold=big_sentiment_threshold,
            volume_threshold=big_volume_threshold,
            trade_size_pct=big_trade_size_pct
        ) for _ in range(num_big_players)]
        
        self.price_history = [initial_price]
        self.retail_sentiment_history = []
        self.retail_volume_history = []
        self.big_player_volume_history = []
        self.retail_pnl_history = []
        self.big_player_pnl_history = []
        
        # Track cumulative positions for proper PnL calculation
        self.retail_position = 0.0  # Cumulative position (positive = long, negative = short)
        self.big_player_position = 0.0
        
    def update_price(self, retail_net_volume, big_player_net_volume, 
                    fundamental_shock=0):
        """
        Update price based on trading through order book and fundamentals
        Volumes are in actual units (not normalized)
        """
        current_price = self.price_history[-1]
        
        # Calculate price impact through order book
        # Retail traders aggregate volume can be significant (100 traders * 0-2 units = 0-200 units)
        retail_impact = 0.0
        if retail_net_volume != 0:
            retail_direction = np.sign(retail_net_volume)
            retail_impact = self.order_book.calculate_price_impact(
                abs(retail_net_volume), retail_direction, current_price
            )
            # Order book naturally gives less impact per unit for smaller trades
            # But when retail herds together (FOMO), aggregate volume creates impact
        
        # Big players have much larger trades - more impact
        big_impact = 0.0
        if big_player_net_volume != 0:
            big_direction = np.sign(big_player_net_volume)
            # Big players' trades consume more order book depth
            big_impact = self.order_book.calculate_price_impact(
                abs(big_player_net_volume), big_direction, current_price
            )
            # Big players' trades have full impact (they move markets)
            big_impact *= 1.0
        
        # Replenish order book liquidity
        self.order_book.replenish_liquidity()
        
        # Fundamental mean reversion (much stronger to prevent price explosion)
        # Pull price back toward fundamental value
        price_deviation = (current_price - self.fundamental_value) / self.fundamental_value
        fundamental_drift = -self.fundamental_reversion * price_deviation
        
        # Random shock using game's independent random state
        random_shock = self.rng.normal(0, self.volatility)
        
        # Price update (multiplicative but bounded)
        total_change = retail_impact + big_impact + fundamental_drift + random_shock + fundamental_shock
        total_change = np.clip(total_change, -0.1, 0.1)  # Cap at 10% per round
        new_price = current_price * (1 + total_change)
        
        return max(new_price, 0.01)  # Prevent negative prices
    
    def play_round(self, game_round, fundamental_shock=0):
        """Play one round of the game"""
        current_price = self.price_history[-1]
        
        # Calculate market momentum
        if len(self.price_history) > 1:
            momentum = (self.price_history[-1] - self.price_history[-2]) / self.price_history[-2]
        else:
            momentum = 0
        
        # Retail traders decide
        retail_actions = []
        retail_sentiments = []
        retail_net_volume = 0
        
        for trader in self.retail_traders:
            expected_return = momentum  # Simple expectation
            sentiment = trader.update_sentiment(momentum, momentum, 
                                               len([a for a in retail_actions if a[0] != 'hold']) / max(len(retail_actions), 1))
            action, normalized_size = trader.decide_action(current_price, expected_return, self.volatility)
            
            # Convert normalized size to actual units (retail traders trade small)
            # Normalized size is 0-1, convert to 0.1-2 units per trader
            actual_size = normalized_size * 2.0  # Retail traders trade 0-2 units each
            retail_actions.append((action, actual_size))
            retail_sentiments.append(sentiment)
            
            if action == 'buy':
                retail_net_volume += actual_size
            elif action == 'sell':
                retail_net_volume -= actual_size
        
        avg_retail_sentiment = np.mean(retail_sentiments)
        retail_volume = sum([size for _, size in retail_actions])
        
        # Big players observe and act
        big_player_net_volume = 0
        for big_player in self.big_players:
            big_player.observe_retail_behavior(avg_retail_sentiment, retail_volume)
            action, size = big_player.strategic_action(
                current_price, avg_retail_sentiment, retail_volume,
                self.fundamental_value, game_round, order_book=self.order_book
            )
            
            # Big players trade in actual units (already calculated based on capital)
            if action == 'buy':
                big_player_net_volume += size
            elif action == 'sell':
                big_player_net_volume -= size
        
        # Update price
        new_price = self.update_price(retail_net_volume, big_player_net_volume, 
                                     fundamental_shock)
        
        # Calculate PnL properly
        # PnL on existing position: position_at_start * price_change
        # PnL on new trades: new_trades * price_change (they entered at current_price, price moved to new_price)
        # Total PnL = (position_at_start + new_trades) * price_change = position_at_end * price_change
        
        price_change_amount = new_price - current_price
        
        # Calculate PnL on average position during the round
        # This accounts for both existing positions and new trades
        position_at_start = self.retail_position
        position_at_end = self.retail_position + retail_net_volume
        average_position = (position_at_start + position_at_end) / 2
        
        # Retail PnL: average position * price change
        retail_pnl = average_position * price_change_amount
        
        # Update retail position for next round
        self.retail_position = position_at_end
        
        # Big player PnL: same calculation
        position_at_start_big = self.big_player_position
        position_at_end_big = self.big_player_position + big_player_net_volume
        average_position_big = (position_at_start_big + position_at_end_big) / 2
        
        big_player_pnl = average_position_big * price_change_amount
        
        # Update big player position for next round
        self.big_player_position = position_at_end_big
        
        # Update history
        self.price_history.append(new_price)
        self.retail_sentiment_history.append(avg_retail_sentiment)
        self.retail_volume_history.append(retail_volume)
        self.big_player_volume_history.append(abs(big_player_net_volume))
        self.retail_pnl_history.append(retail_pnl)
        self.big_player_pnl_history.append(big_player_pnl)
        
        # Calculate exploitation metric: big players trading opposite to retail sentiment
        # Positive sentiment (bullish retail) -> big players should sell (negative volume)
        # Negative sentiment (bearish retail) -> big players should buy (positive volume)
        exploitation_signal = -np.sign(avg_retail_sentiment) * np.sign(big_player_net_volume) if big_player_net_volume != 0 else 0
        
        return {
            'price': new_price,
            'retail_sentiment': avg_retail_sentiment,
            'retail_volume': retail_volume,
            'big_player_volume': abs(big_player_net_volume),
            'big_player_direction': np.sign(big_player_net_volume),
            'retail_pnl': retail_pnl,
            'big_player_pnl': big_player_pnl,
            'exploitation_signal': exploitation_signal
        }
    
    def simulate_game(self, num_rounds=100, fundamental_shocks=None):
        """Simulate the full game"""
        if fundamental_shocks is None:
            fundamental_shocks = [0] * num_rounds
        
        results = []
        for round_num in range(num_rounds):
            shock = fundamental_shocks[round_num] if round_num < len(fundamental_shocks) else 0
            result = self.play_round(round_num, shock)
            result['round'] = round_num
            results.append(result)
        
        return pd.DataFrame(results)
    
    def calculate_nash_equilibrium(self):
        """Calculate approximate Nash equilibrium"""
        # Simplified Nash equilibrium calculation
        # In equilibrium, big players should not be able to improve by changing strategy
        # given retail behavior, and vice versa
        
        # Average retail sentiment in equilibrium
        if len(self.retail_sentiment_history) > 10:
            eq_retail_sentiment = np.mean(self.retail_sentiment_history[-10:])
        else:
            eq_retail_sentiment = 0
        
        # Equilibrium price should be close to fundamental when both sides are balanced
        if len(self.price_history) > 10:
            eq_price = np.mean(self.price_history[-10:])
        else:
            eq_price = self.initial_price
        
        return {
            'equilibrium_price': eq_price,
            'equilibrium_retail_sentiment': eq_retail_sentiment,
            'price_deviation': abs(eq_price - self.fundamental_value) / self.fundamental_value
        }


def analyze_game_theory(num_simulations=50, num_rounds=100):
    """Run multiple game simulations and analyze results"""
    all_results = []
    nash_equilibria = []
    
    for sim in range(num_simulations):
        # Each game gets completely independent random state
        # Use simulation number + time + random component for unique seed
        import time
        base_seed = int(time.time() * 1000000) % (2**31)
        game_seed = (base_seed + sim * 7919 + np.random.randint(0, 1000000)) % (2**31)
        game_rng = np.random.RandomState(game_seed)
        
        # Vary initial conditions for more diversity
        initial_price = 100 + game_rng.normal(0, 2)  # Small variation in starting price
        fundamental_value = 100 + game_rng.normal(0, 1)  # Small variation in fundamental
        
        game = TradingGame(
            num_retail_traders=100,
            num_big_players=5,
            initial_price=initial_price,
            fundamental_value=fundamental_value,
            volatility=0.02
        )
        
        # Override game's RNG with our independent one for shocks
        game.rng = game_rng
        
        # Add random fundamental shocks - unique per game
        fundamental_shocks = game_rng.normal(0, 0.01, num_rounds)
        # Add random large shocks at random times (not fixed rounds)
        num_large_shocks = game_rng.randint(1, 4)  # 1-3 large shocks per game
        shock_times = game_rng.choice(num_rounds, num_large_shocks, replace=False)
        shock_sizes = game_rng.normal(0, 0.03, num_large_shocks)  # Random shock sizes
        for time, size in zip(shock_times, shock_sizes):
            fundamental_shocks[time] = size
        
        results = game.simulate_game(num_rounds, fundamental_shocks)
        results['simulation'] = sim
        
        # Calculate Nash equilibrium
        nash = game.calculate_nash_equilibrium()
        nash['simulation'] = sim
        nash_equilibria.append(nash)
        
        all_results.append(results)
    
    combined_results = pd.concat(all_results, ignore_index=True)
    nash_df = pd.DataFrame(nash_equilibria)
    
    return combined_results, nash_df


def calculate_meta_analysis(results_df, nash_df):
    """Calculate comprehensive meta-analysis across all games"""
    meta_stats = {}
    
    # Aggregate PnL statistics
    final_retail_pnl = results_df.groupby('simulation')['retail_pnl'].sum()
    final_big_pnl = results_df.groupby('simulation')['big_player_pnl'].sum()
    
    meta_stats['retail_pnl'] = {
        'mean': final_retail_pnl.mean(),
        'median': final_retail_pnl.median(),
        'std': final_retail_pnl.std(),
        'min': final_retail_pnl.min(),
        'max': final_retail_pnl.max(),
        'win_rate': (final_retail_pnl > 0).mean(),
        'sharpe': final_retail_pnl.mean() / final_retail_pnl.std() if final_retail_pnl.std() > 0 else 0
    }
    
    meta_stats['big_player_pnl'] = {
        'mean': final_big_pnl.mean(),
        'median': final_big_pnl.median(),
        'std': final_big_pnl.std(),
        'min': final_big_pnl.min(),
        'max': final_big_pnl.max(),
        'win_rate': (final_big_pnl > 0).mean(),
        'sharpe': final_big_pnl.mean() / final_big_pnl.std() if final_big_pnl.std() > 0 else 0
    }
    
    # Price efficiency
    price_efficiency = []
    for sim in results_df['simulation'].unique():
        sim_data = results_df[results_df['simulation'] == sim]
        price_deviations = np.abs(sim_data['price'].values - 100) / 100
        efficiency = 1 - price_deviations.mean()
        price_efficiency.append(max(0, efficiency))
    
    meta_stats['market_efficiency'] = {
        'mean': np.mean(price_efficiency),
        'median': np.median(price_efficiency),
        'std': np.std(price_efficiency),
        'min': np.min(price_efficiency),
        'max': np.max(price_efficiency)
    }
    
    # Nash equilibrium statistics
    meta_stats['nash_equilibrium'] = {
        'mean_price': nash_df['equilibrium_price'].mean(),
        'std_price': nash_df['equilibrium_price'].std(),
        'mean_deviation': nash_df['price_deviation'].mean(),
        'mean_sentiment': nash_df['equilibrium_retail_sentiment'].mean()
    }
    
    # FOMO and herding metrics
    sentiment_volatility = results_df.groupby('simulation')['retail_sentiment'].std()
    volume_volatility = results_df.groupby('simulation')['retail_volume'].std()
    sentiment_volume_corr = results_df.groupby('simulation').apply(
        lambda x: x['retail_sentiment'].corr(x['retail_volume'])
    )
    
    meta_stats['fomo_herding'] = {
        'avg_sentiment_volatility': sentiment_volatility.mean(),
        'avg_volume_volatility': volume_volatility.mean(),
        'sentiment_volume_correlation': sentiment_volume_corr.mean(),
        'sentiment_volume_correlation_std': sentiment_volume_corr.std()
    }
    
    # Exploitation metrics
    exploitation_scores = []
    for sim in results_df['simulation'].unique():
        sim_data = results_df[results_df['simulation'] == sim]
        if len(sim_data) < 10:
            continue
        retail_sentiment = sim_data['retail_sentiment'].values
        big_volume = sim_data['big_player_volume'].values
        abs_sentiment = np.abs(retail_sentiment)
        if len(abs_sentiment) > 5 and big_volume.std() > 0 and abs_sentiment.std() > 0:
            try:
                corr = np.corrcoef(abs_sentiment, big_volume)[0, 1]
                if not np.isnan(corr) and not np.isinf(corr):
                    exploitation_scores.append(corr)
            except:
                pass
    
    if len(exploitation_scores) > 0:
        meta_stats['exploitation'] = {
            'mean': np.mean(exploitation_scores),
            'median': np.median(exploitation_scores),
            'std': np.std(exploitation_scores)
        }
    else:
        meta_stats['exploitation'] = {
            'mean': 0,
            'median': 0,
            'std': 0
        }
    
    return meta_stats


def plot_game_analysis(num_simulations=100, show_random_games=10):
    """Plot comprehensive game theory analysis with meta-analysis"""
    results_df, nash_df = analyze_game_theory(num_simulations, num_rounds=100)
    
    # Calculate meta-analysis
    meta_stats = calculate_meta_analysis(results_df, nash_df)
    
    fig = plt.figure(figsize=(20, 16))
    gs = fig.add_gridspec(4, 3, hspace=0.4, wspace=0.3)
    
    # Plot 1: Random 10 Games Evolution (Price)
    ax1 = fig.add_subplot(gs[0, 0])
    random_sims = np.random.choice(results_df['simulation'].unique(), 
                                   min(show_random_games, len(results_df['simulation'].unique())), 
                                   replace=False)
    colors = plt.cm.tab10(np.linspace(0, 1, len(random_sims)))
    for idx, sim in enumerate(random_sims):
        sim_data = results_df[results_df['simulation'] == sim]
        ax1.plot(sim_data['round'], sim_data['price'], 
                color=colors[idx], alpha=0.6, linewidth=1.5, label=f'Game {sim}')
    ax1.axhline(100, color='r', linestyle='--', linewidth=2, label='Fundamental Value')
    ax1.set_xlabel('Game Round')
    ax1.set_ylabel('Price')
    ax1.set_title(f'Random {len(random_sims)} Games: Price Evolution')
    ax1.legend(loc='best', fontsize=7, ncol=2)
    ax1.grid(True, alpha=0.3)
    
    # Plot 2: Random 10 Games Evolution (Sentiment)
    ax2 = fig.add_subplot(gs[0, 1])
    for idx, sim in enumerate(random_sims):
        sim_data = results_df[results_df['simulation'] == sim]
        ax2.plot(sim_data['round'], sim_data['retail_sentiment'], 
                color=colors[idx], alpha=0.6, linewidth=1.5)
    ax2.axhline(0, color='black', linestyle=':', linewidth=1, alpha=0.5)
    ax2.set_xlabel('Game Round')
    ax2.set_ylabel('Retail Sentiment')
    ax2.set_title(f'Random {len(random_sims)} Games: Sentiment Evolution')
    ax2.grid(True, alpha=0.3)
    
    # Plot 3: Retail vs Big Player PnL Distribution
    ax3 = fig.add_subplot(gs[0, 2])
    final_retail_pnl = results_df.groupby('simulation')['retail_pnl'].sum()
    final_big_pnl = results_df.groupby('simulation')['big_player_pnl'].sum()
    ax3.hist(final_retail_pnl, bins=30, alpha=0.5, label='Retail Traders', 
            color='red', edgecolor='black')
    ax3.hist(final_big_pnl, bins=30, alpha=0.5, label='Big Players', 
            color='blue', edgecolor='black')
    ax3.axvline(0, color='black', linestyle='--', linewidth=2)
    ax3.axvline(final_retail_pnl.mean(), color='red', linestyle=':', linewidth=2, alpha=0.7)
    ax3.axvline(final_big_pnl.mean(), color='blue', linestyle=':', linewidth=2, alpha=0.7)
    ax3.set_xlabel('Total PnL')
    ax3.set_ylabel('Frequency')
    ax3.set_title('PnL Distribution: Retail vs Big Players')
    ax3.legend()
    ax3.grid(True, alpha=0.3)
    
    # Plot 4: Nash Equilibrium Analysis
    ax4 = fig.add_subplot(gs[1, 0])
    ax4.scatter(nash_df['equilibrium_price'], nash_df['price_deviation'], 
               c=nash_df['equilibrium_retail_sentiment'], cmap='RdYlGn', 
               s=100, alpha=0.6, edgecolors='black')
    ax4.axvline(100, color='r', linestyle='--', label='Fundamental Value')
    ax4.set_xlabel('Equilibrium Price')
    ax4.set_ylabel('Price Deviation from Fundamental')
    ax4.set_title('Nash Equilibrium Analysis')
    ax4.legend()
    ax4.grid(True, alpha=0.3)
    cbar = plt.colorbar(ax4.collections[0], ax=ax4)
    cbar.set_label('Retail Sentiment')
    
    # Plot 5: Sentiment vs Volume Relationship
    ax5 = fig.add_subplot(gs[1, 1])
    scatter = ax5.scatter(results_df['retail_sentiment'], results_df['retail_volume'], 
               alpha=0.3, s=10, c=results_df['round'], cmap='viridis')
    ax5.set_xlabel('Retail Sentiment')
    ax5.set_ylabel('Retail Trading Volume')
    ax5.set_title('FOMO Effect: Sentiment vs Volume')
    ax5.grid(True, alpha=0.3)
    cbar = plt.colorbar(scatter, ax=ax5)
    cbar.set_label('Game Round')
    
    # Plot 6: Cumulative PnL Over Time (All 100 Games)
    ax6 = fig.add_subplot(gs[1, 2])
    
    # Calculate cumulative PnL for each game
    retail_cum_pnl_by_game = []
    big_cum_pnl_by_game = []
    rounds = sorted(results_df['round'].unique())
    
    for sim in results_df['simulation'].unique():
        sim_data = results_df[results_df['simulation'] == sim].sort_values('round')
        retail_cum = sim_data['retail_pnl'].cumsum().values
        big_cum = sim_data['big_player_pnl'].cumsum().values
        retail_cum_pnl_by_game.append(retail_cum)
        big_cum_pnl_by_game.append(big_cum)
    
    # Convert to numpy array (pad with NaN if games have different lengths)
    max_rounds = max(len(cum) for cum in retail_cum_pnl_by_game)
    retail_matrix = np.full((len(retail_cum_pnl_by_game), max_rounds), np.nan)
    big_matrix = np.full((len(big_cum_pnl_by_game), max_rounds), np.nan)
    
    for i, (retail_cum, big_cum) in enumerate(zip(retail_cum_pnl_by_game, big_cum_pnl_by_game)):
        retail_matrix[i, :len(retail_cum)] = retail_cum
        big_matrix[i, :len(big_cum)] = big_cum
    
    # Calculate mean and std across all games
    retail_mean = np.nanmean(retail_matrix, axis=0)
    retail_std = np.nanstd(retail_matrix, axis=0)
    retail_upper = retail_mean + 1.96 * retail_std  # 95% confidence interval
    retail_lower = retail_mean - 1.96 * retail_std
    
    big_mean = np.nanmean(big_matrix, axis=0)
    big_std = np.nanstd(big_matrix, axis=0)
    big_upper = big_mean + 1.96 * big_std
    big_lower = big_mean - 1.96 * big_std
    
    # Plot confidence bands
    ax6.fill_between(range(len(retail_mean)), retail_lower, retail_upper, 
                     alpha=0.2, color='red', label='Retail 95% CI')
    ax6.fill_between(range(len(big_mean)), big_lower, big_upper, 
                     alpha=0.2, color='blue', label='Big Players 95% CI')
    
    # Plot mean lines
    ax6.plot(range(len(retail_mean)), retail_mean, 
            'r-', linewidth=2, label=f'Retail Traders (Mean, n={num_simulations})')
    ax6.plot(range(len(big_mean)), big_mean, 
            'b-', linewidth=2, label=f'Big Players (Mean, n={num_simulations})')
    
    # Show a few individual game trajectories (random sample)
    sample_games = np.random.choice(results_df['simulation'].unique(), 
                                    min(5, len(results_df['simulation'].unique())), 
                                    replace=False)
    for sim in sample_games:
        sim_data = results_df[results_df['simulation'] == sim].sort_values('round')
        ax6.plot(sim_data['round'], sim_data['retail_pnl'].cumsum(), 
                'r-', alpha=0.15, linewidth=0.5)
        ax6.plot(sim_data['round'], sim_data['big_player_pnl'].cumsum(), 
                'b-', alpha=0.15, linewidth=0.5)
    
    ax6.axhline(0, color='black', linestyle='--', linewidth=1)
    ax6.set_xlabel('Game Round')
    ax6.set_ylabel('Cumulative PnL')
    ax6.set_title(f'Cumulative PnL Evolution (All {num_simulations} Games)')
    ax6.legend(fontsize=8)
    ax6.grid(True, alpha=0.3)
    
    # Plot 7: Market Efficiency (Price vs Fundamental)
    ax7 = fig.add_subplot(gs[2, 0])
    price_efficiency = []
    for sim in results_df['simulation'].unique():
        sim_data = results_df[results_df['simulation'] == sim]
        price_deviations = np.abs(sim_data['price'].values - 100) / 100
        efficiency = 1 - price_deviations.mean()  # Efficiency: 1 = perfect, 0 = 100% deviation
        price_efficiency.append(max(0, efficiency))  # Ensure non-negative
    price_efficiency = np.array(price_efficiency)
    if len(price_efficiency) > 0:
        ax7.hist(price_efficiency, bins=30, color='purple', alpha=0.7, edgecolor='black')
        ax7.axvline(np.mean(price_efficiency), color='red', linestyle='--', 
                   linewidth=2, label=f'Mean: {np.mean(price_efficiency):.3f}')
    ax7.set_xlabel('Market Efficiency (1 - |Price - Fundamental|/Fundamental)')
    ax7.set_ylabel('Frequency')
    ax7.set_title('Market Efficiency Distribution')
    ax7.legend()
    ax7.grid(True, alpha=0.3)
    
    # Plot 8: Herding Behavior Analysis
    ax8 = fig.add_subplot(gs[2, 1])
    sentiment_volatility = results_df.groupby('simulation')['retail_sentiment'].std()
    volume_volatility = results_df.groupby('simulation')['retail_volume'].std()
    ax8.scatter(sentiment_volatility, volume_volatility, alpha=0.6, s=100, 
               edgecolors='black')
    ax8.set_xlabel('Sentiment Volatility')
    ax8.set_ylabel('Volume Volatility')
    ax8.set_title('Herding Behavior: Sentiment vs Volume Volatility')
    ax8.grid(True, alpha=0.3)
    
    # Plot 9: Meta-Analysis Summary
    ax9 = fig.add_subplot(gs[2, 2])
    # Simulate games of different lengths
    game_lengths = [50, 100, 150, 200]
    final_pnl_by_length = []
    for length in game_lengths:
        game = TradingGame()
        results = game.simulate_game(num_rounds=length)
        final_pnl_by_length.append({
            'length': length,
            'retail_pnl': results['retail_pnl'].sum(),
            'big_pnl': results['big_player_pnl'].sum()
        })
    length_df = pd.DataFrame(final_pnl_by_length)
    x = np.arange(len(game_lengths))
    width = 0.35
    ax8.bar(x - width/2, length_df['retail_pnl'], width, label='Retail', 
           color='red', alpha=0.7)
    ax8.bar(x + width/2, length_df['big_pnl'], width, label='Big Players', 
           color='blue', alpha=0.7)
    ax8.set_xlabel('Game Length (Rounds)')
    ax8.set_ylabel('Final PnL')
    ax8.set_title('Finite Game Effects: PnL vs Game Length')
    ax8.set_xticks(x)
    ax8.set_xticklabels(game_lengths)
    ax8.legend()
    ax8.grid(True, alpha=0.3, axis='y')
    ax8.axhline(0, color='black', linestyle='--', linewidth=1)
    
    # Plot 9: Meta-Analysis Summary
    # Create summary table visualization
    ax9.axis('off')
    summary_text = f"""
    META-ANALYSIS SUMMARY (n={num_simulations} games)
    
    Retail Traders:
      Mean PnL: ${meta_stats['retail_pnl']['mean']:.2f}
      Win Rate: {meta_stats['retail_pnl']['win_rate']:.1%}
      Sharpe: {meta_stats['retail_pnl']['sharpe']:.3f}
    
    Big Players:
      Mean PnL: ${meta_stats['big_player_pnl']['mean']:.2f}
      Win Rate: {meta_stats['big_player_pnl']['win_rate']:.1%}
      Sharpe: {meta_stats['big_player_pnl']['sharpe']:.3f}
    
    Market Efficiency: {meta_stats['market_efficiency']['mean']:.3f}
    FOMO Correlation: {meta_stats['fomo_herding']['sentiment_volume_correlation']:.3f}
    Exploitation Score: {meta_stats['exploitation']['mean']:.3f}
    
    Nash Equilibrium:
      Price: ${meta_stats['nash_equilibrium']['mean_price']:.2f}
      Deviation: {meta_stats['nash_equilibrium']['mean_deviation']:.4f}
    """
    ax9.text(0.1, 0.5, summary_text, transform=ax9.transAxes, 
            fontsize=10, verticalalignment='center', family='monospace',
            bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))
    
    # Plot 10: Strategic Exploitation (moved to new row)
    ax10 = fig.add_subplot(gs[3, 0])
    # Calculate exploitation metric
    exploitation_scores = []
    for sim in results_df['simulation'].unique():
        sim_data = results_df[results_df['simulation'] == sim].copy()
        if len(sim_data) < 10:
            continue
        retail_sentiment = sim_data['retail_sentiment'].values
        big_volume = sim_data['big_player_volume'].values
        abs_sentiment = np.abs(retail_sentiment)
        if len(abs_sentiment) > 5 and big_volume.std() > 0 and abs_sentiment.std() > 0:
            try:
                corr = np.corrcoef(abs_sentiment, big_volume)[0, 1]
                if not np.isnan(corr) and not np.isinf(corr):
                    exploitation_scores.append(corr)
            except:
                pass
    
    if len(exploitation_scores) > 0:
        exploitation_scores = np.array(exploitation_scores)
        if len(exploitation_scores) > 5:
            q1, q3 = np.percentile(exploitation_scores, [10, 90])
            exploitation_scores = exploitation_scores[(exploitation_scores >= q1) & 
                                                      (exploitation_scores <= q3)]
        if len(exploitation_scores) > 0:
            bins = min(20, max(5, len(exploitation_scores) // 2))
            counts, bins_edges, patches = ax10.hist(exploitation_scores, bins=bins, 
                                                   color='orange', alpha=0.7, edgecolor='black')
            mean_score = np.mean(exploitation_scores)
            ax10.axvline(mean_score, color='red', linestyle='--', 
                       linewidth=2, label=f'Mean: {mean_score:.3f}')
            ax10.axvline(0, color='black', linestyle=':', linewidth=1, alpha=0.5)
            ax10.legend(fontsize=8)
            if len(counts) > 0:
                ax10.set_ylim([0, max(counts) * 1.15])
    else:
        ax10.text(0.5, 0.5, 'Insufficient data', ha='center', va='center', 
                transform=ax10.transAxes, fontsize=10)
    ax10.set_xlabel('Exploitation Score')
    ax10.set_ylabel('Frequency')
    ax10.set_title('Big Player Exploitation of Retail FOMO')
    ax10.grid(True, alpha=0.3)
    
    plt.suptitle(f'Game Theory Analysis: Retail Traders vs Big Players\n'
                f'Meta-Analysis of {num_simulations} Games - FOMO, Herding, and Strategic Exploitation', 
                fontsize=16, fontweight='bold', y=0.995)
    
    return fig, results_df, nash_df, meta_stats


def evaluate_configuration(params, num_simulations=10, num_rounds=100):
    """
    Evaluate a configuration of parameters
    Returns: (big_player_pnl, retail_pnl, profit_difference)
    params: dict with keys:
        - order_book_liquidity
        - big_sentiment_threshold
        - big_volume_threshold
        - big_trade_size_pct
        - fundamental_reversion
        - num_big_players
    """
    # Extract parameters
    order_book_liquidity = params.get('order_book_liquidity', 50)
    big_sentiment_threshold = params.get('big_sentiment_threshold', 0.6)
    big_volume_threshold = params.get('big_volume_threshold', 20)
    big_trade_size_pct = params.get('big_trade_size_pct', 0.20)
    fundamental_reversion = params.get('fundamental_reversion', 0.01)
    num_big_players = int(params.get('num_big_players', 5))
    
    # Store original BigPlayer strategic_action for modification
    # We'll need to modify the TradingGame to accept these parameters
    all_big_pnl = []
    all_retail_pnl = []
    
    for sim in range(num_simulations):
        # Each simulation gets completely independent random state
        import time
        base_seed = int(time.time() * 1000000) % (2**31)
        game_seed = (base_seed + sim * 7919 + np.random.randint(0, 1000000)) % (2**31)
        game_rng = np.random.RandomState(game_seed)
        
        # Vary initial conditions for diversity
        initial_price = 100 + game_rng.normal(0, 1)
        fundamental_value = 100 + game_rng.normal(0, 0.5)
        
        # Create game with custom parameters
        game = TradingGame(
            num_retail_traders=100,
            num_big_players=num_big_players,
            initial_price=initial_price,
            fundamental_value=fundamental_value,
            volatility=0.02,
            order_book_liquidity=order_book_liquidity,
            fundamental_reversion=fundamental_reversion,
            big_sentiment_threshold=big_sentiment_threshold,
            big_volume_threshold=big_volume_threshold,
            big_trade_size_pct=big_trade_size_pct
        )
        
        # Override game's RNG with our independent one
        game.rng = game_rng
        
        # Run simulation with random fundamental shocks (unique per game)
        fundamental_shocks = game_rng.normal(0, 0.01, num_rounds)
        # Add random large shocks at random times
        num_shocks = game_rng.randint(0, 3)
        if num_shocks > 0:
            shock_times = game_rng.choice(num_rounds, num_shocks, replace=False)
            shock_sizes = game_rng.normal(0, 0.02, num_shocks)
            for time, size in zip(shock_times, shock_sizes):
                fundamental_shocks[time] = size
        results = game.simulate_game(num_rounds, fundamental_shocks)
        
        # Calculate total PnL
        total_big_pnl = results['big_player_pnl'].sum()
        total_retail_pnl = results['retail_pnl'].sum()
        
        all_big_pnl.append(total_big_pnl)
        all_retail_pnl.append(total_retail_pnl)
    
    mean_big_pnl = np.mean(all_big_pnl)
    mean_retail_pnl = np.mean(all_retail_pnl)
    profit_difference = mean_big_pnl - mean_retail_pnl  # Big player advantage
    
    # Calculate win rates from individual simulations
    big_win_rate = np.mean(np.array(all_big_pnl) > 0)
    retail_win_rate = np.mean(np.array(all_retail_pnl) > 0)
    
    return mean_big_pnl, mean_retail_pnl, profit_difference, big_win_rate, retail_win_rate, all_big_pnl, all_retail_pnl


def genetic_optimization(num_generations=20, population_size=30, num_simulations=5):
    """
    Genetic algorithm to find optimal configuration for big players
    Objective: Maximize (big_player_pnl - retail_pnl)
    """
    print("\n" + "="*60)
    print("GENETIC ALGORITHM OPTIMIZATION")
    print("="*60)
    print(f"Generations: {num_generations}, Population: {population_size}")
    print(f"Simulations per evaluation: {num_simulations}")
    print("="*60)
    
    # Parameter bounds
    bounds = [
        (20, 200),      # order_book_liquidity
        (0.3, 0.9),     # big_sentiment_threshold
        (10, 100),      # big_volume_threshold
        (0.05, 0.30),   # big_trade_size_pct
        (0.001, 0.05),  # fundamental_reversion
        (3, 10),        # num_big_players
    ]
    
    param_names = [
        'order_book_liquidity',
        'big_sentiment_threshold',
        'big_volume_threshold',
        'big_trade_size_pct',
        'fundamental_reversion',
        'num_big_players'
    ]
    
    # Objective function (minimize negative profit difference)
    def objective(x):
        params = dict(zip(param_names, x))
        try:
            _, _, profit_diff, _, _, _, _ = evaluate_configuration(params, num_simulations=num_simulations, num_rounds=50)
            return -profit_diff  # Negative because we're minimizing
        except Exception as e:
            print(f"Error in evaluation: {e}")
            return 1e10  # Large penalty for invalid configurations
    
    # Run differential evolution (genetic algorithm)
    print("\nStarting optimization...")
    result = differential_evolution(
        objective,
        bounds,
        maxiter=num_generations,
        popsize=population_size,
        seed=42,
        polish=True,
        workers=1
    )
    
    optimal_params = dict(zip(param_names, result.x))
    optimal_params['num_big_players'] = int(optimal_params['num_big_players'])
    
    # Evaluate optimal configuration with more simulations
    print("\nEvaluating optimal configuration with more simulations...")
    big_pnl, retail_pnl, profit_diff, big_wr, retail_wr, _, _ = evaluate_configuration(
        optimal_params, num_simulations=20, num_rounds=100
    )
    
    print(f"\n{'='*60}")
    print("OPTIMAL CONFIGURATION FOUND:")
    print(f"{'='*60}")
    for key, value in optimal_params.items():
        print(f"  {key}: {value:.4f}" if isinstance(value, float) else f"  {key}: {value}")
    print(f"\nResults (20 simulations):")
    print(f"  Big Player Mean PnL: ${big_pnl:,.2f}")
    print(f"  Retail Mean PnL: ${retail_pnl:,.2f}")
    print(f"  Profit Difference: ${profit_diff:,.2f}")
    print(f"  Big Player Win Rate: {big_wr:.1%}")
    print(f"  Retail Win Rate: {retail_wr:.1%}")
    print(f"{'='*60}\n")
    
    return optimal_params, result


def grid_search_optimization(num_simulations=5):
    """
    Grid search over parameter space (faster but less thorough)
    Returns top configurations
    """
    print("\n" + "="*60)
    print("GRID SEARCH OPTIMIZATION")
    print("="*60)
    
    # Define parameter grids
    param_grids = {
        'order_book_liquidity': [30, 50, 100, 150],
        'big_sentiment_threshold': [0.4, 0.5, 0.6, 0.7],
        'big_volume_threshold': [15, 25, 40, 60],
        'big_trade_size_pct': [0.10, 0.15, 0.20, 0.25],
        'fundamental_reversion': [0.005, 0.01, 0.02, 0.03],
        'num_big_players': [3, 5, 7, 10]
    }
    
    # Generate all combinations (sample to avoid too many)
    keys = list(param_grids.keys())
    values = list(param_grids.values())
    
    # Limit combinations for speed
    all_combinations = list(itertools.product(*values))
    np.random.shuffle(all_combinations)
    max_combinations = min(50, len(all_combinations))  # Limit to 50 configurations
    sampled_combinations = all_combinations[:max_combinations]
    
    print(f"Testing {len(sampled_combinations)} configurations...")
    
    results = []
    for i, combo in enumerate(sampled_combinations):
        params = dict(zip(keys, combo))
        try:
            big_pnl, retail_pnl, profit_diff, big_wr, retail_wr, _, _ = evaluate_configuration(
                params, num_simulations=num_simulations, num_rounds=50
            )
            results.append({
                **params,
                'big_pnl': big_pnl,
                'retail_pnl': retail_pnl,
                'profit_diff': profit_diff,
                'big_win_rate': big_wr,
                'retail_win_rate': retail_wr
            })
            if (i + 1) % 10 == 0:
                print(f"  Completed {i+1}/{len(sampled_combinations)} configurations...")
        except Exception as e:
            print(f"  Error with configuration {i+1}: {e}")
            continue
    
    results_df = pd.DataFrame(results)
    results_df = results_df.sort_values('profit_diff', ascending=False)
    
    optimal = results_df.iloc[0].to_dict()
    
    print(f"\n{'='*60}")
    print("TOP CONFIGURATION FOUND:")
    print(f"{'='*60}")
    for key in keys:
        print(f"  {key}: {optimal[key]}")
    print(f"\nResults:")
    print(f"  Big Player Mean PnL: ${optimal['big_pnl']:,.2f}")
    print(f"  Retail Mean PnL: ${optimal['retail_pnl']:,.2f}")
    print(f"  Profit Difference: ${optimal['profit_diff']:,.2f}")
    print(f"{'='*60}\n")
    
    return results_df, optimal


def plot_optimization_results(optimal_params, grid_results_df=None, num_simulations=20):
    """
    Create comprehensive visualization of optimization results
    Highlights optimal configuration vs others
    """
    print("\nGenerating optimization visualization...")
    
    # Evaluate optimal configuration in detail
    optimal_big_pnl, optimal_retail_pnl, optimal_profit_diff, optimal_big_wr, optimal_retail_wr, _, _ = evaluate_configuration(
        optimal_params, num_simulations=num_simulations, num_rounds=100
    )
    
    # Run optimal configuration for detailed analysis
    optimal_game = TradingGame(
        num_retail_traders=100,
        num_big_players=int(optimal_params['num_big_players']),
        initial_price=100,
        fundamental_value=100,
        volatility=0.02,
        order_book_liquidity=optimal_params['order_book_liquidity'],
        fundamental_reversion=optimal_params['fundamental_reversion'],
        big_sentiment_threshold=optimal_params['big_sentiment_threshold'],
        big_volume_threshold=optimal_params['big_volume_threshold'],
        big_trade_size_pct=optimal_params['big_trade_size_pct']
    )
    
    optimal_results = optimal_game.simulate_game(100)
    
    # Create figure with subplots
    fig = plt.figure(figsize=(20, 14))
    gs = fig.add_gridspec(3, 3, hspace=0.4, wspace=0.3)
    
    # Plot 1: Optimal Configuration - Price Evolution
    ax1 = fig.add_subplot(gs[0, 0])
    ax1.plot(optimal_results['round'], optimal_results['price'], 
            'b-', linewidth=2.5, label='Optimal Config', zorder=3)
    ax1.axhline(100, color='r', linestyle='--', linewidth=2, label='Fundamental Value', alpha=0.7)
    ax1.set_xlabel('Game Round')
    ax1.set_ylabel('Price')
    ax1.set_title('Optimal Configuration: Price Evolution', fontweight='bold')
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    
    # Plot 2: Optimal Configuration - PnL Evolution
    ax2 = fig.add_subplot(gs[0, 1])
    retail_cum_pnl = optimal_results['retail_pnl'].cumsum()
    big_cum_pnl = optimal_results['big_player_pnl'].cumsum()
    ax2.plot(optimal_results['round'], retail_cum_pnl, 
            'r-', linewidth=2, label='Retail Traders', alpha=0.7)
    ax2.plot(optimal_results['round'], big_cum_pnl, 
            'b-', linewidth=2.5, label='Big Players (Optimal)', zorder=3)
    ax2.axhline(0, color='black', linestyle=':', linewidth=1, alpha=0.5)
    ax2.set_xlabel('Game Round')
    ax2.set_ylabel('Cumulative PnL')
    ax2.set_title('Optimal Configuration: Cumulative PnL', fontweight='bold')
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    
    # Plot 3: Optimal Configuration - Sentiment vs Big Player Volume
    ax3 = fig.add_subplot(gs[0, 2])
    scatter = ax3.scatter(optimal_results['retail_sentiment'], 
                         optimal_results['big_player_volume'],
                         c=optimal_results['round'], cmap='viridis',
                         alpha=0.6, s=50, edgecolors='black', linewidth=0.5)
    ax3.axvline(optimal_params['big_sentiment_threshold'], 
               color='red', linestyle='--', linewidth=2, 
               label=f"Threshold: {optimal_params['big_sentiment_threshold']:.2f}")
    ax3.axvline(-optimal_params['big_sentiment_threshold'], 
               color='red', linestyle='--', linewidth=2)
    ax3.set_xlabel('Retail Sentiment')
    ax3.set_ylabel('Big Player Volume')
    ax3.set_title('Optimal: Exploitation Strategy', fontweight='bold')
    ax3.legend()
    ax3.grid(True, alpha=0.3)
    cbar = plt.colorbar(scatter, ax=ax3)
    cbar.set_label('Game Round')
    
    # Plot 4: Parameter Comparison (if grid results available)
    if grid_results_df is not None and len(grid_results_df) > 0:
        ax4 = fig.add_subplot(gs[1, 0])
        top_10 = grid_results_df.head(10)
        y_pos = np.arange(len(top_10))
        colors = ['gold' if i == 0 else 'steelblue' for i in range(len(top_10))]
        ax4.barh(y_pos, top_10['profit_diff'], color=colors, edgecolor='black')
        ax4.set_yticks(y_pos)
        ax4.set_yticklabels([f"Config {i+1}" for i in range(len(top_10))])
        ax4.set_xlabel('Profit Difference (Big - Retail)')
        ax4.set_title('Top 10 Configurations (Optimal Highlighted)', fontweight='bold')
        ax4.axvline(0, color='black', linestyle='--', linewidth=1, alpha=0.5)
        ax4.grid(True, alpha=0.3, axis='x')
    else:
        ax4 = fig.add_subplot(gs[1, 0])
        ax4.text(0.5, 0.5, 'Grid search results not available', 
                ha='center', va='center', transform=ax4.transAxes, fontsize=12)
        ax4.axis('off')
    
    # Plot 5: Parameter Space - Order Book Liquidity vs Profit Difference
    if grid_results_df is not None and len(grid_results_df) > 0:
        ax5 = fig.add_subplot(gs[1, 1])
        scatter = ax5.scatter(grid_results_df['order_book_liquidity'], 
                             grid_results_df['profit_diff'],
                             c=grid_results_df['num_big_players'], 
                             cmap='coolwarm', s=100, alpha=0.6,
                             edgecolors='black', linewidth=0.5)
        # Highlight optimal
        ax5.scatter([optimal_params['order_book_liquidity']], 
                   [optimal_profit_diff], 
                   s=300, marker='*', color='gold', 
                   edgecolors='black', linewidth=2, zorder=5,
                   label='Optimal')
        ax5.set_xlabel('Order Book Liquidity')
        ax5.set_ylabel('Profit Difference (Big - Retail)')
        ax5.set_title('Parameter Space: Liquidity vs Profit', fontweight='bold')
        ax5.legend()
        ax5.grid(True, alpha=0.3)
        cbar = plt.colorbar(scatter, ax=ax5)
        cbar.set_label('Number of Big Players')
    else:
        ax5 = fig.add_subplot(gs[1, 1])
        ax5.scatter([optimal_params['order_book_liquidity']], 
                   [optimal_profit_diff], 
                   s=300, marker='*', color='gold', 
                   edgecolors='black', linewidth=2, zorder=5)
        ax5.set_xlabel('Order Book Liquidity')
        ax5.set_ylabel('Profit Difference')
        ax5.set_title('Optimal Configuration', fontweight='bold')
        ax5.grid(True, alpha=0.3)
    
    # Plot 6: Parameter Space - Sentiment Threshold vs Trade Size
    if grid_results_df is not None and len(grid_results_df) > 0:
        ax6 = fig.add_subplot(gs[1, 2])
        scatter = ax6.scatter(grid_results_df['big_sentiment_threshold'], 
                             grid_results_df['big_trade_size_pct'],
                             c=grid_results_df['profit_diff'], 
                             cmap='RdYlGn', s=100, alpha=0.6,
                             edgecolors='black', linewidth=0.5)
        # Highlight optimal
        ax6.scatter([optimal_params['big_sentiment_threshold']], 
                   [optimal_params['big_trade_size_pct']], 
                   s=300, marker='*', color='gold', 
                   edgecolors='black', linewidth=2, zorder=5,
                   label='Optimal')
        ax6.set_xlabel('Sentiment Threshold')
        ax6.set_ylabel('Trade Size (% of Capital)')
        ax6.set_title('Parameter Space: Strategy Parameters', fontweight='bold')
        ax6.legend()
        ax6.grid(True, alpha=0.3)
        cbar = plt.colorbar(scatter, ax=ax6)
        cbar.set_label('Profit Difference')
    else:
        ax6 = fig.add_subplot(gs[1, 2])
        ax6.scatter([optimal_params['big_sentiment_threshold']], 
                   [optimal_params['big_trade_size_pct']], 
                   s=300, marker='*', color='gold', 
                   edgecolors='black', linewidth=2, zorder=5)
        ax6.set_xlabel('Sentiment Threshold')
        ax6.set_ylabel('Trade Size (% of Capital)')
        ax6.set_title('Optimal Configuration', fontweight='bold')
        ax6.grid(True, alpha=0.3)
    
    # Plot 7: Optimal Configuration Summary Table
    ax7 = fig.add_subplot(gs[2, :])
    ax7.axis('off')
    
    summary_text = f"""
    OPTIMAL CONFIGURATION FOR BIG PLAYERS
    {'='*80}
    
    Parameters:
      Order Book Liquidity:        {optimal_params['order_book_liquidity']:.1f} units/level
      Sentiment Threshold:          {optimal_params['big_sentiment_threshold']:.3f}
      Volume Threshold:             {optimal_params['big_volume_threshold']:.1f} units
      Trade Size (% of Capital):    {optimal_params['big_trade_size_pct']:.1%}
      Fundamental Reversion:        {optimal_params['fundamental_reversion']:.4f}
      Number of Big Players:        {int(optimal_params['num_big_players'])}
    
    Performance Results ({num_simulations} simulations):
      Big Player Mean PnL:          ${optimal_big_pnl:,.2f}
      Retail Mean PnL:               ${optimal_retail_pnl:,.2f}
      Profit Difference:             ${optimal_profit_diff:,.2f}
      Big Player Win Rate:           {optimal_big_wr:.1%}
      Retail Win Rate:                {optimal_retail_wr:.1%}
    
    Strategy Insight:
      Big players exploit retail FOMO by trading {optimal_params['big_trade_size_pct']:.1%} of capital
      when retail sentiment exceeds {optimal_params['big_sentiment_threshold']:.2f} and volume > {optimal_params['big_volume_threshold']:.0f}.
      Lower order book liquidity ({optimal_params['order_book_liquidity']:.0f}) creates more price impact,
      allowing big players to move markets more effectively.
    """
    
    ax7.text(0.05, 0.5, summary_text, transform=ax7.transAxes, 
            fontsize=11, verticalalignment='center', family='monospace',
            bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.8))
    
    plt.suptitle('Genetic Algorithm Optimization: Optimal Configuration for Big Players\n'
                f'Maximizing Profit Difference (Big Player PnL - Retail PnL)', 
                fontsize=16, fontweight='bold', y=0.995)
    
    return fig, optimal_params, optimal_results


def create_comparison_figure(optimal_params, num_simulations=20):
    """
    Create a comparison figure showing Optimal vs Default configuration
    """
    print("  Creating comparison between optimal and default configurations...")
    
    # Default configuration
    default_params = {
        'order_book_liquidity': 50,
        'big_sentiment_threshold': 0.6,
        'big_volume_threshold': 20,
        'big_trade_size_pct': 0.20,
        'fundamental_reversion': 0.01,
        'num_big_players': 5
    }
    
    # Evaluate both configurations
    opt_big_pnl, opt_retail_pnl, opt_profit_diff, opt_big_wr, opt_retail_wr, opt_big_pnls, opt_retail_pnls = evaluate_configuration(
        optimal_params, num_simulations=num_simulations, num_rounds=100
    )
    
    def_big_pnl, def_retail_pnl, def_profit_diff, def_big_wr, def_retail_wr, def_big_pnls, def_retail_pnls = evaluate_configuration(
        default_params, num_simulations=num_simulations, num_rounds=100
    )
    
    # Run one detailed simulation of each for trajectory plots
    opt_game = TradingGame(
        num_retail_traders=100,
        num_big_players=int(optimal_params['num_big_players']),
        initial_price=100,
        fundamental_value=100,
        volatility=0.02,
        order_book_liquidity=optimal_params['order_book_liquidity'],
        fundamental_reversion=optimal_params['fundamental_reversion'],
        big_sentiment_threshold=optimal_params['big_sentiment_threshold'],
        big_volume_threshold=optimal_params['big_volume_threshold'],
        big_trade_size_pct=optimal_params['big_trade_size_pct']
    )
    opt_results = opt_game.simulate_game(100)
    
    def_game = TradingGame(
        num_retail_traders=100,
        num_big_players=int(default_params['num_big_players']),
        initial_price=100,
        fundamental_value=100,
        volatility=0.02,
        order_book_liquidity=default_params['order_book_liquidity'],
        fundamental_reversion=default_params['fundamental_reversion'],
        big_sentiment_threshold=default_params['big_sentiment_threshold'],
        big_volume_threshold=default_params['big_volume_threshold'],
        big_trade_size_pct=default_params['big_trade_size_pct']
    )
    def_results = def_game.simulate_game(100)
    
    # Create figure
    fig = plt.figure(figsize=(18, 12))
    gs = fig.add_gridspec(2, 3, hspace=0.35, wspace=0.3)
    
    # Plot 1: Price Evolution Comparison
    ax1 = fig.add_subplot(gs[0, 0])
    ax1.plot(opt_results['round'], opt_results['price'], 
            'b-', linewidth=2.5, label='Optimal Config', zorder=3)
    ax1.plot(def_results['round'], def_results['price'], 
            'r--', linewidth=2, label='Default Config', alpha=0.7)
    ax1.axhline(100, color='gray', linestyle=':', linewidth=1.5, label='Fundamental Value', alpha=0.5)
    ax1.set_xlabel('Game Round')
    ax1.set_ylabel('Price')
    ax1.set_title('Price Evolution: Optimal vs Default', fontweight='bold')
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    
    # Plot 2: Cumulative PnL Comparison
    ax2 = fig.add_subplot(gs[0, 1])
    opt_retail_cum = opt_results['retail_pnl'].cumsum()
    opt_big_cum = opt_results['big_player_pnl'].cumsum()
    def_retail_cum = def_results['retail_pnl'].cumsum()
    def_big_cum = def_results['big_player_pnl'].cumsum()
    
    ax2.plot(opt_results['round'], opt_retail_cum, 
            'r-', linewidth=2, label='Optimal: Retail', alpha=0.6)
    ax2.plot(opt_results['round'], opt_big_cum, 
            'b-', linewidth=2.5, label='Optimal: Big Players', zorder=3)
    ax2.plot(def_results['round'], def_retail_cum, 
            'r--', linewidth=1.5, label='Default: Retail', alpha=0.5)
    ax2.plot(def_results['round'], def_big_cum, 
            'b--', linewidth=1.5, label='Default: Big Players', alpha=0.5)
    ax2.axhline(0, color='black', linestyle=':', linewidth=1, alpha=0.5)
    ax2.set_xlabel('Game Round')
    ax2.set_ylabel('Cumulative PnL')
    ax2.set_title('Cumulative PnL: Optimal vs Default', fontweight='bold')
    ax2.legend(fontsize=8)
    ax2.grid(True, alpha=0.3)
    
    # Plot 3: PnL Distribution Comparison
    ax3 = fig.add_subplot(gs[0, 2])
    ax3.hist(opt_big_pnls, bins=20, alpha=0.6, label='Optimal: Big Players', 
            color='blue', edgecolor='black', density=True)
    ax3.hist(def_big_pnls, bins=20, alpha=0.4, label='Default: Big Players', 
            color='lightblue', edgecolor='black', linestyle='--', density=True, histtype='step', linewidth=2)
    ax3.axvline(0, color='black', linestyle='--', linewidth=1, alpha=0.5)
    ax3.axvline(opt_big_pnl, color='blue', linestyle=':', linewidth=2, alpha=0.7, label=f'Optimal Mean: ${opt_big_pnl:,.0f}')
    ax3.axvline(def_big_pnl, color='lightblue', linestyle=':', linewidth=2, alpha=0.7, label=f'Default Mean: ${def_big_pnl:,.0f}')
    ax3.set_xlabel('Total PnL')
    ax3.set_ylabel('Density')
    ax3.set_title('Big Player PnL Distribution', fontweight='bold')
    ax3.legend(fontsize=8)
    ax3.grid(True, alpha=0.3)
    
    # Plot 4: Performance Metrics Comparison
    ax4 = fig.add_subplot(gs[1, 0])
    metrics = ['Mean PnL', 'Win Rate', 'Profit Diff']
    optimal_values = [opt_big_pnl / 1000, opt_big_wr * 100, opt_profit_diff / 1000]  # Scale for visibility
    default_values = [def_big_pnl / 1000, def_big_wr * 100, def_profit_diff / 1000]
    
    x = np.arange(len(metrics))
    width = 0.35
    bars1 = ax4.bar(x - width/2, optimal_values, width, label='Optimal', color='blue', alpha=0.7)
    bars2 = ax4.bar(x + width/2, default_values, width, label='Default', color='red', alpha=0.7)
    
    ax4.set_ylabel('Value (Scaled)')
    ax4.set_title('Big Player Performance: Optimal vs Default', fontweight='bold')
    ax4.set_xticks(x)
    ax4.set_xticklabels(metrics)
    ax4.legend()
    ax4.grid(True, alpha=0.3, axis='y')
    ax4.axhline(0, color='black', linestyle='--', linewidth=1)
    
    # Add value labels on bars
    for bars in [bars1, bars2]:
        for bar in bars:
            height = bar.get_height()
            ax4.text(bar.get_x() + bar.get_width()/2., height,
                    f'{height:.1f}', ha='center', va='bottom', fontsize=8)
    
    # Plot 5: Parameter Comparison
    ax5 = fig.add_subplot(gs[1, 1])
    param_names = ['Liquidity', 'Sentiment\nThreshold', 'Volume\nThreshold', 
                   'Trade Size\n(%)', 'Reversion', 'Num Players']
    optimal_params_list = [
        optimal_params['order_book_liquidity'],
        optimal_params['big_sentiment_threshold'],
        optimal_params['big_volume_threshold'],
        optimal_params['big_trade_size_pct'] * 100,
        optimal_params['fundamental_reversion'] * 1000,
        optimal_params['num_big_players']
    ]
    default_params_list = [
        default_params['order_book_liquidity'],
        default_params['big_sentiment_threshold'],
        default_params['big_volume_threshold'],
        default_params['big_trade_size_pct'] * 100,
        default_params['fundamental_reversion'] * 1000,
        default_params['num_big_players']
    ]
    
    x = np.arange(len(param_names))
    bars1 = ax5.bar(x - width/2, optimal_params_list, width, label='Optimal', color='blue', alpha=0.7)
    bars2 = ax5.bar(x + width/2, default_params_list, width, label='Default', color='red', alpha=0.7)
    
    ax5.set_ylabel('Parameter Value')
    ax5.set_title('Configuration Parameters', fontweight='bold')
    ax5.set_xticks(x)
    ax5.set_xticklabels(param_names, fontsize=8)
    ax5.legend()
    ax5.grid(True, alpha=0.3, axis='y')
    
    # Plot 6: Summary Statistics
    ax6 = fig.add_subplot(gs[1, 2])
    ax6.axis('off')
    
    summary_text = f"""
    PERFORMANCE COMPARISON ({num_simulations} simulations)
    {'='*50}
    
    OPTIMAL CONFIGURATION:
      Big Player Mean PnL:    ${opt_big_pnl:,.2f}
      Retail Mean PnL:         ${opt_retail_pnl:,.2f}
      Profit Difference:       ${opt_profit_diff:,.2f}
      Big Player Win Rate:     {opt_big_wr:.1%}
      Retail Win Rate:         {opt_retail_wr:.1%}
    
    DEFAULT CONFIGURATION:
      Big Player Mean PnL:    ${def_big_pnl:,.2f}
      Retail Mean PnL:         ${def_retail_pnl:,.2f}
      Profit Difference:       ${def_profit_diff:,.2f}
      Big Player Win Rate:     {def_big_wr:.1%}
      Retail Win Rate:         {def_retail_wr:.1%}
    
    IMPROVEMENT:
      PnL Improvement:         ${opt_profit_diff - def_profit_diff:,.2f}
      Win Rate Improvement:    {opt_big_wr - def_big_wr:+.1%}
      Relative Improvement:    {(opt_profit_diff / def_profit_diff - 1) * 100:+.1f}%
    """
    
    ax6.text(0.05, 0.5, summary_text, transform=ax6.transAxes, 
            fontsize=10, verticalalignment='center', family='monospace',
            bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.8))
    
    plt.suptitle('Optimal vs Default Configuration Comparison\n'
                f'Genetic Algorithm Optimization Results', 
                fontsize=16, fontweight='bold', y=0.995)
    
    return fig


def export_results_to_csv(results_df, nash_df, meta_stats, output_dir):
    """Export comprehensive results to CSV files for LaTeX paper writing"""
    import os
    
    # 1. Full game results
    results_df.to_csv(os.path.join(output_dir, 'game_theory_full_results.csv'), index=False)
    
    # 2. Per-game summary
    game_summary = []
    for sim in results_df['simulation'].unique():
        sim_data = results_df[results_df['simulation'] == sim]
        price_efficiency = 1 - np.abs(sim_data['price'].values - 100).mean() / 100
        
        game_summary.append({
            'simulation': sim,
            'final_price': sim_data['price'].iloc[-1],
            'total_retail_pnl': sim_data['retail_pnl'].sum(),
            'total_big_player_pnl': sim_data['big_player_pnl'].sum(),
            'avg_retail_sentiment': sim_data['retail_sentiment'].mean(),
            'retail_sentiment_volatility': sim_data['retail_sentiment'].std(),
            'retail_volume_volatility': sim_data['retail_volume'].std(),
            'sentiment_volume_correlation': sim_data['retail_sentiment'].corr(sim_data['retail_volume']),
            'market_efficiency': max(0, price_efficiency),
            'equilibrium_price': nash_df[nash_df['simulation'] == sim]['equilibrium_price'].values[0] if len(nash_df[nash_df['simulation'] == sim]) > 0 else np.nan,
            'equilibrium_sentiment': nash_df[nash_df['simulation'] == sim]['equilibrium_retail_sentiment'].values[0] if len(nash_df[nash_df['simulation'] == sim]) > 0 else np.nan
        })
    
    game_summary_df = pd.DataFrame(game_summary)
    game_summary_df.to_csv(os.path.join(output_dir, 'game_theory_per_game_summary.csv'), index=False)
    
    # 3. Meta-analysis summary
    meta_summary = []
    for category, stats in meta_stats.items():
        for metric, value in stats.items():
            meta_summary.append({
                'category': category,
                'metric': metric,
                'value': value
            })
    
    meta_summary_df = pd.DataFrame(meta_summary)
    meta_summary_df.to_csv(os.path.join(output_dir, 'game_theory_meta_analysis.csv'), index=False)
    
    # 4. Nash equilibrium summary
    nash_df.to_csv(os.path.join(output_dir, 'game_theory_nash_equilibria.csv'), index=False)
    
    print(f"\nCSV files exported to {output_dir}:")
    print("  - game_theory_full_results.csv (all round-by-round data)")
    print("  - game_theory_per_game_summary.csv (per-game aggregated metrics)")
    print("  - game_theory_meta_analysis.csv (meta-analysis across all games)")
    print("  - game_theory_nash_equilibria.csv (Nash equilibrium for each game)")


if __name__ == "__main__":
    import os
    import sys
    
    # Check if optimization mode
    if len(sys.argv) > 1 and sys.argv[1] == '--optimize':
        print("=" * 60)
        print("GENETIC ALGORITHM OPTIMIZATION MODE")
        print("=" * 60)
        
        # Run grid search (faster for initial exploration)
        print("\n[Step 1] Running grid search optimization...")
        grid_results_df, optimal_from_grid = grid_search_optimization(num_simulations=5)
        
        # Use grid search result as starting point for genetic algorithm
        print("\n[Step 2] Running genetic algorithm optimization...")
        optimal_params, ga_result = genetic_optimization(
            num_generations=15, 
            population_size=25, 
            num_simulations=5
        )
        
        # Generate visualization
        print("\n[Step 3] Generating optimization visualization...")
        fig, optimal_params_final, optimal_results = plot_optimization_results(
            optimal_params, 
            grid_results_df=grid_results_df,
            num_simulations=20
        )
        
        # Save figure
        script_dir = os.path.dirname(os.path.abspath(__file__))
        figures_dir = os.path.join(script_dir, '..', 'figures')
        figures_path = os.path.abspath(figures_dir)
        os.makedirs(figures_path, exist_ok=True)
        
        output_path = os.path.join(figures_path, 'game_theory_optimization.png')
        plt.savefig(output_path, dpi=300, bbox_inches='tight')
        print(f"\n✓ Optimization figure saved to {output_path}")
        
        # Also create a comparison figure: Optimal vs Default configuration
        print("\n[Step 4] Generating comparison figure (Optimal vs Default)...")
        fig_comparison = create_comparison_figure(optimal_params_final, num_simulations=20)
        comparison_path = os.path.join(figures_path, 'game_theory_optimal_vs_default.png')
        plt.savefig(comparison_path, dpi=300, bbox_inches='tight')
        print(f"✓ Comparison figure saved to {comparison_path}")
        plt.close('all')
        
        # Save optimal configuration
        import json
        config_path = os.path.join(script_dir, '..', 'optimal_config.json')
        with open(config_path, 'w') as f:
            json.dump(optimal_params_final, f, indent=2)
        print(f"✓ Optimal configuration saved to {config_path}")
        
        print("\n" + "=" * 60)
        print("OPTIMIZATION COMPLETE!")
        print("=" * 60)
        print(f"Figures saved:")
        print(f"  - {output_path}")
        print(f"  - {comparison_path}")
        print(f"Configuration saved: {config_path}")
        print("=" * 60)
        
    else:
        # Standard analysis mode
        print("Running Game Theory Trading Simulation...")
        print("=" * 60)
        print("Modeling strategic interaction between:")
        print("  - Retail traders (FOMO-driven, herding behavior)")
        print("  - Big players (strategic, exploit retail behavior)")
        print("  - Finite repeated games (not infinite)")
        print("=" * 60)
        print("\nNote: Run with --optimize flag to find optimal configuration")
        print("=" * 60)
        
        num_games = 100
        fig, results_df, nash_df, meta_stats = plot_game_analysis(num_simulations=num_games, show_random_games=10)
        
        # Save figure
        script_dir = os.path.dirname(os.path.abspath(__file__))
        figures_dir = os.path.join(script_dir, '..', 'figures')
        figures_path = os.path.abspath(figures_dir)
        os.makedirs(figures_path, exist_ok=True)
        
        output_path = os.path.join(figures_path, 'game_theory_trading.png')
        plt.savefig(output_path, dpi=300, bbox_inches='tight')
        print(f"\nFigure saved to {output_path}")
        plt.close()
        
        # Export CSV files
        csv_output_dir = os.path.join(script_dir, '..')
        csv_output_path = os.path.abspath(csv_output_dir)
        export_results_to_csv(results_df, nash_df, meta_stats, csv_output_path)
        
        # Print meta-analysis summary
        print("\n=== Meta-Analysis Results (100 Games) ===")
        print(f"\nRetail Traders Performance:")
        print(f"  Mean Final PnL: ${meta_stats['retail_pnl']['mean']:,.2f}")
        print(f"  Median Final PnL: ${meta_stats['retail_pnl']['median']:,.2f}")
        print(f"  Std Dev: ${meta_stats['retail_pnl']['std']:,.2f}")
        print(f"  Win Rate: {meta_stats['retail_pnl']['win_rate']:.2%}")
        print(f"  Sharpe Ratio: {meta_stats['retail_pnl']['sharpe']:.4f}")
        
        print(f"\nBig Players Performance:")
        print(f"  Mean Final PnL: ${meta_stats['big_player_pnl']['mean']:,.2f}")
        print(f"  Median Final PnL: ${meta_stats['big_player_pnl']['median']:,.2f}")
        print(f"  Std Dev: ${meta_stats['big_player_pnl']['std']:,.2f}")
        print(f"  Win Rate: {meta_stats['big_player_pnl']['win_rate']:.2%}")
        print(f"  Sharpe Ratio: {meta_stats['big_player_pnl']['sharpe']:.4f}")
        
        print(f"\nNash Equilibrium Analysis:")
        print(f"  Mean Equilibrium Price: ${meta_stats['nash_equilibrium']['mean_price']:.2f}")
        print(f"  Std Dev Price: ${meta_stats['nash_equilibrium']['std_price']:.2f}")
        print(f"  Mean Price Deviation: {meta_stats['nash_equilibrium']['mean_deviation']:.4f}")
        print(f"  Mean Retail Sentiment: {meta_stats['nash_equilibrium']['mean_sentiment']:.4f}")
        
        print(f"\nMarket Efficiency:")
        print(f"  Mean: {meta_stats['market_efficiency']['mean']:.4f}")
        print(f"  Median: {meta_stats['market_efficiency']['median']:.4f}")
        print(f"  Std Dev: {meta_stats['market_efficiency']['std']:.4f}")
        print(f"  Range: [{meta_stats['market_efficiency']['min']:.4f}, {meta_stats['market_efficiency']['max']:.4f}]")
        
        print(f"\nFOMO and Herding Effects:")
        print(f"  Average Sentiment Volatility: {meta_stats['fomo_herding']['avg_sentiment_volatility']:.4f}")
        print(f"  Average Volume Volatility: {meta_stats['fomo_herding']['avg_volume_volatility']:.4f}")
        print(f"  Sentiment-Volume Correlation: {meta_stats['fomo_herding']['sentiment_volume_correlation']:.4f} ± {meta_stats['fomo_herding']['sentiment_volume_correlation_std']:.4f}")
        
        print(f"\nExploitation Analysis:")
        print(f"  Mean Exploitation Score: {meta_stats['exploitation']['mean']:.4f}")
        print(f"  Median: {meta_stats['exploitation']['median']:.4f}")
        print(f"  Std Dev: {meta_stats['exploitation']['std']:.4f}")
        
        print("\n" + "=" * 60)
        print("Key Insights:")
        print("1. Retail traders exhibit FOMO-driven behavior (sentiment-volume correlation)")
        print("2. Big players strategically exploit retail sentiment extremes")
        print("3. Games are finite, leading to different equilibria than infinite games")
        print("4. Market efficiency depends on the balance of power between players")
        print("5. Meta-analysis across 100 games provides robust statistical evidence")
        print("=" * 60)
