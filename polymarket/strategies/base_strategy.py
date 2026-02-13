"""
Base Strategy Class for Polymarket Trading

All trading strategies should inherit from this class.
"""

from abc import ABC, abstractmethod
from typing import Dict, Optional, List, Any
from datetime import datetime
from dataclasses import dataclass
import numpy as np


@dataclass
class MarketSignal:
    """Trading signal from strategy"""
    action: str  # 'BUY', 'SELL', 'HOLD'
    token_id: str  # Which outcome token to trade
    size: float  # Position size (0.0 to 1.0)
    confidence: float  # Confidence level (0.0 to 1.0)
    reason: str  # Human-readable reason
    metadata: Dict[str, Any]  # Additional strategy-specific data


@dataclass
class Position:
    """Open position tracking"""
    token_id: str
    outcome: str  # 'Yes' or 'No'
    size: float
    entry_price: float
    entry_time: datetime
    current_price: float
    unrealized_pnl: float
    realized_pnl: float = 0.0


class BaseStrategy(ABC):
    """
    Base class for all Polymarket trading strategies.
    
    Inherit from this class and implement:
    - analyze_market(): Your trading logic
    - get_parameters(): Return strategy parameters
    """
    
    def __init__(self, name: str, initial_balance: float = 1000.0):
        """
        Initialize the strategy.
        
        Args:
            name: Strategy name
            initial_balance: Starting USDC balance
        """
        self.name = name
        self.initial_balance = initial_balance
        self.current_balance = initial_balance
        self.equity = initial_balance
        
        # Position tracking
        self.positions: Dict[str, Position] = {}  # token_id -> Position
        self.closed_positions: List[Position] = []
        
        # Performance metrics
        self.total_trades = 0
        self.winning_trades = 0
        self.losing_trades = 0
        self.total_profit = 0.0
        self.total_loss = 0.0
        self.max_drawdown = 0.0
        self.peak_equity = initial_balance
        
        # Risk management
        self.max_position_size = 0.5  # Max 50% of balance per position
        self.max_total_exposure = 0.8  # Max 80% total exposure
        self.min_confidence = 0.6  # Minimum confidence to trade
        
    @abstractmethod
    def analyze_market(self, market_data: Dict) -> Optional[MarketSignal]:
        """
        Analyze market and generate trading signal.
        
        Args:
            market_data: Dictionary containing:
                - 'event': Event information
                - 'market': Market information
                - 'prices': Current outcome prices
                - 'orderbook': Orderbook data
                - 'history': Historical price data (if available)
        
        Returns:
            MarketSignal or None if no trade
        """
        pass
    
    @abstractmethod
    def get_parameters(self) -> Dict[str, Any]:
        """
        Return strategy parameters.
        
        Returns:
            Dictionary of parameter names and values
        """
        pass
    
    def update_position(self, token_id: str, current_price: float) -> None:
        """
        Update position with current price.
        
        Args:
            token_id: Token ID
            current_price: Current market price
        """
        if token_id in self.positions:
            pos = self.positions[token_id]
            # Validate inputs
            if not (np.isfinite(current_price) and current_price > 0 and current_price < 1):
                return  # Skip update if price is invalid
            if not (np.isfinite(pos.size) and pos.size > 0):
                return  # Skip update if position size is invalid
            if not (np.isfinite(pos.entry_price) and pos.entry_price > 0):
                return  # Skip update if entry price is invalid
            
            pos.current_price = current_price
            unrealized_pnl = (current_price - pos.entry_price) * pos.size
            pos.unrealized_pnl = unrealized_pnl if np.isfinite(unrealized_pnl) else 0.0
    
    def calculate_equity(self) -> float:
        """Calculate current equity (balance + unrealized PnL)"""
        # Validate balance
        if not np.isfinite(self.current_balance):
            self.current_balance = 0.0
        
        unrealized = sum(
            pos.unrealized_pnl if np.isfinite(pos.unrealized_pnl) else 0.0 
            for pos in self.positions.values()
        )
        equity = self.current_balance + unrealized
        return equity if np.isfinite(equity) else self.current_balance
    
    def update_drawdown(self) -> None:
        """Update maximum drawdown"""
        self.equity = self.calculate_equity()
        if self.equity > self.peak_equity:
            self.peak_equity = self.equity
        
        # Safe division - avoid division by zero
        if self.peak_equity > 0:
            drawdown = (self.peak_equity - self.equity) / self.peak_equity
            if drawdown > self.max_drawdown:
                self.max_drawdown = drawdown
        else:
            # If peak_equity is 0, set drawdown to 0
            self.max_drawdown = 0.0
    
    def can_open_position(self, size: float, token_id: str) -> bool:
        """
        Check if strategy can open a new position.
        
        Args:
            size: Position size in USDC
            token_id: Token ID
        
        Returns:
            True if position can be opened
        """
        # Validate inputs
        if not (np.isfinite(size) and size > 0):
            return False
        if not (np.isfinite(self.current_balance) and self.current_balance > 0):
            return False
        
        # Check if already have position in this token
        if token_id in self.positions:
            return False
        
        # Check position size limit
        if size > self.current_balance * self.max_position_size:
            return False
        
        # Check total exposure limit
        total_exposure = sum(
            pos.size if np.isfinite(pos.size) else 0.0 
            for pos in self.positions.values()
        )
        if not np.isfinite(total_exposure):
            total_exposure = 0.0
        
        if total_exposure + size > self.current_balance * self.max_total_exposure:
            return False
        
        # Check balance
        if size > self.current_balance:
            return False
        
        return True
    
    def get_performance_metrics(self) -> Dict[str, Any]:
        """Get current performance metrics"""
        win_rate = (self.winning_trades / self.total_trades * 100) if self.total_trades > 0 else 0.0
        profit_factor = abs(self.total_profit / self.total_loss) if self.total_loss != 0 else 0.0
        
        return {
            'name': self.name,
            'total_trades': self.total_trades,
            'winning_trades': self.winning_trades,
            'losing_trades': self.losing_trades,
            'win_rate': win_rate,
            'total_profit': self.total_profit,
            'total_loss': self.total_loss,
            'net_profit': self.total_profit + self.total_loss,
            'profit_factor': profit_factor,
            'max_drawdown': self.max_drawdown,
            'current_balance': self.current_balance,
            'equity': self.equity,
            'unrealized_pnl': sum(pos.unrealized_pnl for pos in self.positions.values()),
            'open_positions': len(self.positions)
        }
