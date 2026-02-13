"""
Polymarket Gamma API Client

Provides market discovery, metadata, and event data.
API Documentation: https://docs.polymarket.com/developers/gamma-markets-api/overview
"""

import requests
from typing import List, Dict, Optional, Any
from datetime import datetime
import time


class GammaClient:
    """Client for Polymarket Gamma API - Market discovery and metadata"""
    
    BASE_URL = "https://gamma-api.polymarket.com"
    
    def __init__(self, timeout: int = 30):
        """
        Initialize Gamma API client.
        
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
            data = response.json()
            # According to docs, /events returns an array directly
            # But handle both array and dict responses
            return data
        except requests.exceptions.RequestException as e:
            raise Exception(f"Gamma API error: {e}")
    
    def get_events(self, 
                   active: bool = True, 
                   closed: bool = False,
                   limit: int = 100,
                   tag_id: Optional[int] = None,
                   series_id: Optional[int] = None,
                   order: Optional[str] = None,
                   ascending: bool = True) -> List[Dict]:
        """
        Fetch active events/markets.
        
        Args:
            active: Filter for active events
            closed: Filter for closed events
            limit: Maximum number of results
            tag_id: Filter by tag/category ID
            series_id: Filter by series ID (for sports)
            order: Sort order (e.g., 'startTime')
            ascending: Sort ascending or descending
        
        Returns:
            List of event dictionaries
        """
        params = {
            'active': str(active).lower(),
            'closed': str(closed).lower(),
            'limit': limit
        }
        
        if tag_id:
            params['tag_id'] = tag_id
        if series_id:
            params['series_id'] = series_id
        if order:
            params['order'] = order
            params['ascending'] = str(ascending).lower()
        
        return self._get('/events', params=params)
    
    def get_event_by_slug(self, slug: str) -> Optional[Dict]:
        """
        Get event details by slug.
        
        Args:
            slug: Event slug (e.g., 'will-bitcoin-reach-100k-by-2025')
        
        Returns:
            Event dictionary or None if not found
        """
        events = self.get_events(limit=1)
        for event in events:
            if event.get('slug') == slug:
                return event
        return None
    
    def get_market_by_slug(self, slug: str) -> Optional[Dict]:
        """
        Get market details by slug.
        
        Args:
            slug: Market slug
        
        Returns:
            Market dictionary with clobTokenIds, outcomes, prices
        """
        params = {'slug': slug}
        markets = self._get('/markets', params=params)
        return markets[0] if markets else None
    
    def get_tags(self, limit: int = 100) -> List[Dict]:
        """
        Get all available tags/categories.
        
        Args:
            limit: Maximum number of tags to return
        
        Returns:
            List of tag dictionaries
        """
        params = {'limit': limit}
        return self._get('/tags', params=params)
    
    def get_sports(self) -> List[Dict]:
        """
        Get all supported sports leagues.
        
        Returns:
            List of sports league dictionaries
        """
        return self._get('/sports')
    
    def get_market_prices(self, market: Dict) -> Dict[str, float]:
        """
        Extract current prices from market data.
        
        Args:
            market: Market dictionary with outcomes and outcomePrices
        
        Returns:
            Dictionary mapping outcome to price (probability)
        """
        import json
        
        outcomes = json.loads(market.get('outcomes', '[]'))
        prices = json.loads(market.get('outcomePrices', '[]'))
        
        return {outcome: float(price) for outcome, price in zip(outcomes, prices)}
    
    def search_events(self, query: str, limit: int = 20) -> List[Dict]:
        """
        Search events by title/keywords.
        
        Args:
            query: Search query
            limit: Maximum results
        
        Returns:
            List of matching events
        """
        # Note: This is a simplified search - actual API may have different endpoint
        all_events = self.get_events(limit=1000)
        query_lower = query.lower()
        
        matches = []
        for event in all_events:
            title = event.get('title', '').lower()
            if query_lower in title:
                matches.append(event)
                if len(matches) >= limit:
                    break
        
        return matches
