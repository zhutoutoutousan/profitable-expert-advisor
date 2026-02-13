"""
Polymarket Data API Client

Provides positions, trade history, and portfolio data.
API Documentation: https://docs.polymarket.com/developers/misc-endpoints/data-api-get-positions
"""

import requests
from typing import Dict, Optional, List
from datetime import datetime


class DataClient:
    """Client for Polymarket Data API - Positions and history"""
    
    BASE_URL = "https://data-api.polymarket.com"
    
    def __init__(self, api_key: Optional[str] = None, timeout: int = 30):
        """
        Initialize Data API client.
        
        Args:
            api_key: Optional API key for authenticated requests
            timeout: Request timeout in seconds
        """
        self.timeout = timeout
        self.api_key = api_key
        self.session = requests.Session()
        self.session.headers.update({
            'Accept': 'application/json',
            'User-Agent': 'Polymarket-Trading-Framework/1.0'
        })
        
        if api_key:
            self.session.headers['Authorization'] = f'Bearer {api_key}'
    
    def _get(self, endpoint: str, params: Optional[Dict] = None) -> Dict:
        """Make GET request with error handling"""
        url = f"{self.BASE_URL}{endpoint}"
        try:
            response = self.session.get(url, params=params, timeout=self.timeout)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            raise Exception(f"Data API error: {e}")
    
    def get_positions(self, user_address: str) -> List[Dict]:
        """
        Get user positions.
        
        Args:
            user_address: User wallet address
        
        Returns:
            List of position dictionaries
        """
        params = {'user': user_address}
        return self._get('/positions', params=params)
    
    def get_trades(self, user_address: str, limit: int = 100) -> List[Dict]:
        """
        Get user trade history.
        
        Args:
            user_address: User wallet address
            limit: Maximum number of trades to return
        
        Returns:
            List of trade dictionaries
        """
        params = {
            'user': user_address,
            'limit': limit
        }
        return self._get('/trades', params=params)
    
    def get_portfolio(self, user_address: str) -> Dict:
        """
        Get user portfolio summary.
        
        Args:
            user_address: User wallet address
        
        Returns:
            Portfolio dictionary with balances, positions, etc.
        """
        params = {'user': user_address}
        return self._get('/portfolio', params=params)
