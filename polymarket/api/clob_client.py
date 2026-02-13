"""
Polymarket CLOB API Client

Provides orderbook data, price quotes, and order placement.
API Documentation: https://docs.polymarket.com/developers/CLOB/introduction
"""

import requests
from typing import Dict, Optional, List
import time


class ClobClient:
    """Client for Polymarket CLOB API - Trading and orderbook data"""
    
    BASE_URL = "https://clob.polymarket.com"
    
    def __init__(self, timeout: int = 30):
        """
        Initialize CLOB API client.
        
        Args:
            timeout: Request timeout in seconds
        """
        self.timeout = timeout
        self.session = requests.Session()
        self.session.headers.update({
            'Accept': 'application/json',
            'User-Agent': 'Polymarket-Trading-Framework/1.0'
        })
    
    def _get(self, endpoint: str, params: Optional[Dict] = None) -> Dict:
        """Make GET request with error handling"""
        url = f"{self.BASE_URL}{endpoint}"
        try:
            response = self.session.get(url, params=params, timeout=self.timeout)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            raise Exception(f"CLOB API error: {e}")
    
    def get_price(self, token_id: str, side: str = 'buy') -> float:
        """
        Get current price for a token.
        
        Args:
            token_id: CLOB token ID
            side: 'buy' or 'sell'
        
        Returns:
            Current price as float
        """
        params = {
            'token_id': token_id,
            'side': side
        }
        response = self._get('/price', params=params)
        return float(response.get('price', 0.0))
    
    def get_orderbook(self, token_id: str) -> Dict:
        """
        Get orderbook depth for a token.
        
        Per docs: https://docs.polymarket.com/quickstart/fetching-data
        Endpoint: /book?token_id=YOUR_TOKEN_ID
        
        Args:
            token_id: CLOB token ID
        
        Returns:
            Dictionary with 'bids' and 'asks' arrays
        """
        params = {'token_id': token_id}
        return self._get('/book', params=params)
    
    def get_best_bid_ask(self, token_id: str) -> Dict[str, float]:
        """
        Get best bid and ask prices.
        
        Args:
            token_id: CLOB token ID
        
        Returns:
            Dictionary with 'bid' and 'ask' prices
        """
        book = self.get_orderbook(token_id)
        
        best_bid = float(book['bids'][0]['price']) if book.get('bids') else 0.0
        best_ask = float(book['asks'][0]['price']) if book.get('asks') else 1.0
        
        return {
            'bid': best_bid,
            'ask': best_ask,
            'spread': best_ask - best_bid,
            'mid': (best_bid + best_ask) / 2
        }
    
    def get_market_depth(self, token_id: str, levels: int = 10) -> Dict:
        """
        Get market depth up to specified levels.
        
        Args:
            token_id: CLOB token ID
            levels: Number of levels to retrieve
        
        Returns:
            Dictionary with bid/ask depth
        """
        book = self.get_orderbook(token_id)
        
        bids = book.get('bids', [])[:levels]
        asks = book.get('asks', [])[:levels]
        
        # Calculate cumulative depth
        bid_depth = sum(float(bid['size']) for bid in bids)
        ask_depth = sum(float(ask['size']) for ask in asks)
        
        return {
            'bids': bids,
            'asks': asks,
            'bid_depth': bid_depth,
            'ask_depth': ask_depth,
            'total_depth': bid_depth + ask_depth
        }
    
    def calculate_impact(self, token_id: str, size: float, side: str) -> Dict:
        """
        Calculate estimated price impact for a trade size.
        
        Args:
            token_id: CLOB token ID
            size: Trade size
            side: 'buy' or 'sell'
        
        Returns:
            Dictionary with impact metrics
        """
        book = self.get_orderbook(token_id)
        
        if side == 'buy':
            levels = book.get('asks', [])
        else:
            levels = book.get('bids', [])
        
        remaining = size
        total_cost = 0.0
        levels_consumed = []
        
        for level in levels:
            level_price = float(level['price'])
            level_size = float(level['size'])
            
            if remaining <= 0:
                break
            
            consumed = min(remaining, level_size)
            total_cost += consumed * level_price
            remaining -= consumed
            
            levels_consumed.append({
                'price': level_price,
                'size': consumed
            })
        
        avg_price = total_cost / size if size > 0 else 0.0
        best_price = float(levels[0]['price']) if levels else 0.0
        impact = abs(avg_price - best_price) / best_price if best_price > 0 else 0.0
        
        return {
            'average_price': avg_price,
            'best_price': best_price,
            'price_impact': impact,
            'levels_consumed': len(levels_consumed),
            'slippage': avg_price - best_price if side == 'buy' else best_price - avg_price
        }
