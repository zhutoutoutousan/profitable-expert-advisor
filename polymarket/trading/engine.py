"""
Live Trading Engine for Polymarket

Handles real-time order placement and position management.
"""

from typing import Dict, Optional, List
from datetime import datetime
import time
from ..strategies.base_strategy import BaseStrategy, MarketSignal
from ..api.gamma_client import GammaClient
from ..api.clob_client import ClobClient
from ..api.data_client import DataClient
from ..utils.config import Config


class LiveTradingEngine:
    """
    Live trading engine for Polymarket.
    
    Monitors markets, executes strategy signals, and manages positions.
    """
    
    def __init__(self, 
                 strategy: BaseStrategy,
                 poll_interval: int = 60):
        """
        Initialize live trading engine.
        
        Args:
            strategy: Strategy instance to trade
            poll_interval: Seconds between market checks
        """
        self.strategy = strategy
        self.poll_interval = poll_interval
        self.is_running = False
        
        # Initialize API clients
        self.gamma_client = GammaClient()
        self.clob_client = ClobClient()
        self.data_client = DataClient(api_key=Config.DATA_API_KEY)
        
        # Trading state
        self.monitored_markets: List[Dict] = []
        self.last_check_time: Optional[datetime] = None
    
    def setup_clob_client(self):
        """
        Setup authenticated CLOB client for order placement.
        
        Note: This requires py-clob-client package and proper authentication.
        For full implementation, install: pip install py-clob-client
        """
        try:
            from py_clob_client.client import ClobClient as PyClobClient
            from py_clob_client.utilities import create_or_derive_api_creds
            
            if not Config.PRIVATE_KEY:
                raise ValueError("POLYMARKET_PRIVATE_KEY not set in config")
            
            # Initialize client
            host = "https://clob.polymarket.com"
            chain_id = Config.CHAIN_ID
            
            self.trading_client = PyClobClient(
                host=host,
                key=Config.PRIVATE_KEY,
                chain_id=chain_id
            )
            
            # Derive API credentials
            creds = self.trading_client.create_or_derive_api_creds()
            
            # Reinitialize with credentials
            self.trading_client = PyClobClient(
                host=host,
                api_key=creds['apiKey'],
                api_secret=creds['secret'],
                api_passphrase=creds['passphrase'],
                signature_type=Config.SIGNATURE_TYPE,
                funder=Config.FUNDER_ADDRESS,
                chain_id=chain_id
            )
            
            print("CLOB client authenticated successfully")
            return True
            
        except ImportError:
            print("Warning: py-clob-client not installed. Install with: pip install py-clob-client")
            print("Live trading will be simulated only.")
            self.trading_client = None
            return False
        except Exception as e:
            print(f"Error setting up CLOB client: {e}")
            self.trading_client = None
            return False
    
    def add_market(self, event_slug: Optional[str] = None, market_slug: Optional[str] = None):
        """
        Add a market to monitor.
        
        Args:
            event_slug: Event slug (e.g., 'will-bitcoin-reach-100k-by-2025')
            market_slug: Market slug
        """
        if event_slug:
            event = self.gamma_client.get_event_by_slug(event_slug)
            if event:
                self.monitored_markets.append({
                    'event': event,
                    'markets': event.get('markets', [])
                })
        elif market_slug:
            market = self.gamma_client.get_market_by_slug(market_slug)
            if market:
                self.monitored_markets.append({
                    'event': None,
                    'markets': [market]
                })
    
    def monitor_tag(self, tag_id: int, limit: int = 20):
        """
        Monitor all active markets in a tag/category.
        
        Args:
            tag_id: Tag ID to monitor
            limit: Maximum number of markets
        """
        events = self.gamma_client.get_events(
            active=True,
            closed=False,
            tag_id=tag_id,
            limit=limit
        )
        
        for event in events:
            self.monitored_markets.append({
                'event': event,
                'markets': event.get('markets', [])
            })
    
    def execute_order(self, signal: MarketSignal, market_data: Dict) -> Optional[Dict]:
        """
        Execute a trading order.
        
        Args:
            signal: Trading signal
            market_data: Market data
        
        Returns:
            Order result dictionary
        """
        if not self.trading_client:
            print("Warning: Trading client not available. Simulating order.")
            return self._simulate_order(signal, market_data)
        
        market = market_data['market']
        token_ids = market.get('clobTokenIds', [])
        
        if not token_ids:
            return None
        
        token_id = token_ids[0] if signal.action == 'BUY' else token_ids[0]
        
        # Calculate order size
        position_size_usdc = signal.size * self.strategy.current_balance
        
        try:
            if signal.action == 'BUY':
                # Place buy order
                # Note: Actual implementation would use trading_client.create_order()
                # This is a placeholder
                print(f"Placing BUY order: {position_size_usdc:.2f} USDC at token {token_id}")
                # order = self.trading_client.create_order(...)
                return {'status': 'placed', 'action': 'BUY', 'size': position_size_usdc}
            
            elif signal.action == 'SELL':
                # Close position
                if token_id in self.strategy.positions:
                    print(f"Closing position: {token_id}")
                    # order = self.trading_client.create_order(...)
                    return {'status': 'closed', 'action': 'SELL', 'token_id': token_id}
            
        except Exception as e:
            print(f"Error executing order: {e}")
            return None
    
    def _simulate_order(self, signal: MarketSignal, market_data: Dict) -> Dict:
        """Simulate order execution for testing"""
        return {
            'status': 'simulated',
            'action': signal.action,
            'timestamp': datetime.now(),
            'signal': signal
        }
    
    def update_positions(self):
        """Update all open positions with current prices"""
        for token_id, position in list(self.strategy.positions.items()):
            try:
                current_price = self.clob_client.get_price(token_id, side='buy')
                self.strategy.update_position(token_id, current_price)
            except Exception as e:
                print(f"Error updating position {token_id}: {e}")
    
    def check_markets(self):
        """Check all monitored markets for trading signals"""
        for market_data in self.monitored_markets:
            for market in market_data['markets']:
                # Get current prices
                try:
                    token_ids = market.get('clobTokenIds', [])
                    if not token_ids:
                        continue
                    
                    # Get orderbook data
                    orderbook = self.clob_client.get_orderbook(token_ids[0])
                    best_bid_ask = self.clob_client.get_best_bid_ask(token_ids[0])
                    
                    # Parse outcomes and prices
                    import json
                    outcomes = json.loads(market.get('outcomes', '["Yes", "No"]'))
                    prices = json.loads(market.get('outcomePrices', '[0.5, 0.5]'))
                    
                    market_info = {
                        'event': market_data['event'],
                        'market': market,
                        'prices': {
                            outcome: float(price) 
                            for outcome, price in zip(outcomes, prices)
                        },
                        'orderbook': orderbook,
                        'best_bid_ask': best_bid_ask,
                        'timestamp': datetime.now()
                    }
                    
                    # Get strategy signal
                    signal = self.strategy.analyze_market(market_info)
                    
                    if signal and signal.confidence >= self.strategy.min_confidence:
                        print(f"\nSignal generated: {signal.action} - {signal.reason}")
                        result = self.execute_order(signal, market_info)
                        if result:
                            print(f"Order result: {result}")
                
                except Exception as e:
                    print(f"Error checking market: {e}")
                    continue
    
    def start(self):
        """Start the live trading engine"""
        print("Starting live trading engine...")
        
        # Setup trading client
        if not self.setup_clob_client():
            print("Warning: Running in simulation mode")
        
        if not self.monitored_markets:
            print("No markets to monitor. Add markets with add_market() or monitor_tag()")
            return
        
        self.is_running = True
        print(f"Monitoring {len(self.monitored_markets)} markets")
        print(f"Poll interval: {self.poll_interval} seconds")
        print("Press Ctrl+C to stop\n")
        
        try:
            while self.is_running:
                self.last_check_time = datetime.now()
                
                # Update positions
                self.update_positions()
                
                # Check markets
                self.check_markets()
                
                # Print status
                equity = self.strategy.calculate_equity()
                print(f"\n[{self.last_check_time.strftime('%Y-%m-%d %H:%M:%S')}] "
                      f"Equity: ${equity:.2f} | "
                      f"Open Positions: {len(self.strategy.positions)} | "
                      f"Total Trades: {self.strategy.total_trades}")
                
                # Wait for next poll
                time.sleep(self.poll_interval)
        
        except KeyboardInterrupt:
            print("\nStopping trading engine...")
            self.stop()
    
    def stop(self):
        """Stop the trading engine"""
        self.is_running = False
        print("Trading engine stopped")
        
        # Print final performance
        metrics = self.strategy.get_performance_metrics()
        print("\nFinal Performance:")
        print(f"  Total Trades: {metrics['total_trades']}")
        print(f"  Win Rate: {metrics['win_rate']:.2f}%")
        print(f"  Net Profit: ${metrics['net_profit']:.2f}")
        print(f"  Final Equity: ${metrics['equity']:.2f}")
