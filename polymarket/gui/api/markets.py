"""
Markets API Routes
"""

from flask import Blueprint, jsonify
from polymarket.api import GammaClient, ClobClient
import os

markets_bp = Blueprint('markets', __name__)

# Initialize API clients
try:
    gamma_client = GammaClient()
    clob_client = ClobClient()
    USE_REAL_API = True
except Exception as e:
    print(f"[WARNING] Could not initialize API clients: {e}")
    USE_REAL_API = False
    gamma_client = None
    clob_client = None


@markets_bp.route('/markets')
def get_markets():
    """Get markets from real Polymarket API"""
    if not USE_REAL_API:
        return jsonify({
            'markets': [
                {
                    'id': '1',
                    'question': 'Will Bitcoin reach $100k by 2025?',
                    'event': 'Crypto Markets',
                    'yes_price': 0.65,
                    'no_price': 0.35,
                    'bid': 0.64,
                    'ask': 0.66,
                    'spread': 0.02,
                    'token_id': 'token123'
                }
            ]
        })
    
    try:
        events_data = gamma_client.get_events(active=True, closed=False, limit=50)
        
        if isinstance(events_data, dict):
            events = events_data.get('data', events_data.get('events', []))
        else:
            events = events_data if isinstance(events_data, list) else []
        
        print(f"[DEBUG] Fetched {len(events)} events from API")
        
        markets = []
        for event in events:
            event_markets = event.get('markets', [])
            if not event_markets:
                continue
            
            for market in event_markets:
                try:
                    clob_token_ids = market.get('clobTokenIds', [])
                    if len(clob_token_ids) < 2:
                        continue
                    
                    yes_token = clob_token_ids[0]
                    no_token = clob_token_ids[1]
                    
                    import json
                    outcomes = json.loads(market.get('outcomes', '["Yes", "No"]'))
                    outcome_prices = json.loads(market.get('outcomePrices', '[0.5, 0.5]'))
                    
                    yes_price = float(outcome_prices[0]) if len(outcome_prices) > 0 else 0.5
                    no_price = float(outcome_prices[1]) if len(outcome_prices) > 1 else 0.5
                    
                    # Try to get better prices from orderbook
                    try:
                        yes_book = clob_client.get_orderbook(yes_token)
                        yes_bids = yes_book.get('bids', [])
                        yes_asks = yes_book.get('asks', [])
                        
                        if yes_bids and yes_asks:
                            yes_bid = float(yes_bids[0].get('price', yes_price))
                            yes_ask = float(yes_asks[0].get('price', yes_price))
                            yes_price = (yes_bid + yes_ask) / 2
                    except Exception as e:
                        pass
                    
                    spread = abs(yes_price - no_price)
                    try:
                        yes_book = clob_client.get_orderbook(yes_token)
                        yes_bids = yes_book.get('bids', [])
                        yes_asks = yes_book.get('asks', [])
                        if yes_bids and yes_asks:
                            best_bid = float(yes_bids[0].get('price', yes_price))
                            best_ask = float(yes_asks[0].get('price', yes_price))
                            spread = best_ask - best_bid
                    except:
                        pass
                    
                    markets.append({
                        'id': market.get('id', ''),
                        'question': market.get('question', event.get('title', 'Unknown Market')),
                        'event': event.get('title', 'Unknown Event'),
                        'yes_price': yes_price,
                        'no_price': no_price,
                        'bid': yes_price - (spread / 2) if yes_price > (spread / 2) else 0.0,
                        'ask': yes_price + (spread / 2) if yes_price < (1 - spread / 2) else 1.0,
                        'spread': spread,
                        'token_id': yes_token,
                        'volume': market.get('volume', 0)
                    })
                except Exception as e:
                    print(f"Error processing market: {e}")
                    continue
        
        print(f"[DEBUG] Returning {len(markets)} markets to frontend")
        return jsonify({'markets': markets})
    except Exception as e:
        import traceback
        print(f"Error fetching markets: {e}")
        print(traceback.format_exc())
        return jsonify({'markets': [], 'error': str(e)})


@markets_bp.route('/market/<market_id>')
def get_market_details(market_id):
    """Get market details from real API"""
    if not USE_REAL_API:
        return jsonify({
            'orderbook': {'bids': [], 'asks': []},
            'best_bid_ask': {'bid': 0.5, 'ask': 0.5, 'spread': 0.0},
            'depth': {'bid_depth': 0, 'ask_depth': 0}
        })
    
    try:
        book = clob_client.get_orderbook(market_id)
        
        bids = book.get('bids', [])
        asks = book.get('asks', [])
        
        best_bid = float(bids[0].get('price', 0.5)) if bids else 0.5
        best_ask = float(asks[0].get('price', 0.5)) if asks else 0.5
        
        bid_depth = sum(float(bid.get('size', 0)) for bid in bids)
        ask_depth = sum(float(ask.get('size', 0)) for ask in asks)
        
        return jsonify({
            'orderbook': {
                'bids': bids[:10],
                'asks': asks[:10]
            },
            'best_bid_ask': {
                'bid': best_bid,
                'ask': best_ask,
                'spread': best_ask - best_bid,
                'mid': (best_bid + best_ask) / 2
            },
            'depth': {
                'bid_depth': bid_depth,
                'ask_depth': ask_depth,
                'total_depth': bid_depth + ask_depth
            }
        })
    except Exception as e:
        print(f"Error fetching market details: {e}")
        return jsonify({
            'orderbook': {'bids': [], 'asks': []},
            'best_bid_ask': {'bid': 0.5, 'ask': 0.5, 'spread': 0.0},
            'depth': {'bid_depth': 0, 'ask_depth': 0},
            'error': str(e)
        })
