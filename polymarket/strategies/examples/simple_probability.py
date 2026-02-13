"""
Simple Probability Strategy Example

Trades when market probability deviates significantly from fair value.
"""

from typing import Dict, Optional
from ..base_strategy import BaseStrategy, MarketSignal


class SimpleProbabilityStrategy(BaseStrategy):
    """
    Simple strategy that buys when probability is too low,
    sells when probability is too high.
    """
    
    def __init__(self, 
                 name: str = "SimpleProbability",
                 initial_balance: float = 1000.0,
                 threshold: float = 0.15,
                 min_confidence: float = 0.7):
        """
        Initialize strategy.
        
        Args:
            name: Strategy name
            initial_balance: Starting balance
            threshold: Probability deviation threshold (0.15 = 15%)
            min_confidence: Minimum confidence to trade
        """
        super().__init__(name, initial_balance)
        self.threshold = threshold
        self.min_confidence = min_confidence
    
    def analyze_market(self, market_data: Dict) -> Optional[MarketSignal]:
        """
        Analyze market and generate signal.
        
        Strategy logic:
        - If Yes probability < 0.5 - threshold: Buy (undervalued)
        - If Yes probability > 0.5 + threshold: Sell (overvalued)
        """
        market = market_data.get('market', {})
        prices = market_data.get('prices', {})
        
        if not prices:
            return None
        
        yes_price = prices.get('Yes', 0.5)
        no_price = prices.get('No', 0.5)
        
        # Calculate deviation from fair value (0.5)
        deviation = abs(yes_price - 0.5)
        
        if deviation < self.threshold:
            return None  # Not enough deviation
        
        # Get token_id from market
        market_obj = market_data.get('market', {})
        token_ids = market_obj.get('clobTokenIds', [])
        if not token_ids:
            return None
        
        token_id = token_ids[0]
        
        # Determine action
        if yes_price < (0.5 - self.threshold):
            # Yes is undervalued, buy
            confidence = min(1.0, deviation / self.threshold)
            if confidence >= self.min_confidence:
                return MarketSignal(
                    action='BUY',
                    token_id=token_id,
                    size=0.2,  # 20% of balance
                    confidence=confidence,
                    reason=f"Yes probability {yes_price:.2%} is undervalued (deviation: {deviation:.2%})",
                    metadata={'yes_price': yes_price, 'deviation': deviation}
                )
        
        elif yes_price > (0.5 + self.threshold):
            # Yes is overvalued, sell (close position if we have one)
            confidence = min(1.0, deviation / self.threshold)
            if confidence >= self.min_confidence:
                # Check if we have a position to close
                if token_id in self.positions:
                    return MarketSignal(
                        action='SELL',
                        token_id=token_id,
                        size=1.0,  # Close entire position
                        confidence=confidence,
                        reason=f"Yes probability {yes_price:.2%} is overvalued (deviation: {deviation:.2%})",
                        metadata={'yes_price': yes_price, 'deviation': deviation}
                    )
        
        return None
    
    def get_parameters(self) -> Dict:
        """Return strategy parameters"""
        return {
            'threshold': self.threshold,
            'min_confidence': self.min_confidence,
            'max_position_size': self.max_position_size,
            'max_total_exposure': self.max_total_exposure
        }
