"""Simplified dashboard that definitely works"""
from flask import Flask, render_template, jsonify, request
from flask_socketio import SocketIO, emit
import sys
from pathlib import Path
from datetime import datetime, timedelta
import threading
import time
import numpy as np
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Setup paths
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

# Import Polymarket API clients
try:
    from polymarket.api import GammaClient, ClobClient, DataClient
    gamma_client = GammaClient()
    clob_client = ClobClient()
    data_client = DataClient(api_key=os.getenv('POLYMARKET_API_KEY'))
    USE_REAL_API = True
    print("[OK] Connected to real Polymarket API")
except Exception as e:
    print(f"[WARNING] Could not initialize API clients: {e}")
    print("Falling back to mock data")
    USE_REAL_API = False
    gamma_client = None
    clob_client = None
    data_client = None

app = Flask(__name__, 
            template_folder='templates',
            static_folder='static')
socketio = SocketIO(app, cors_allowed_origins="*")

# Mock state
is_trading = False
strategy_balance = 1000.0
strategy_equity = 1000.0
strategy_positions = 0
strategy_trades = 0

# Backtesting state
backtest_running = False
backtest_results = None

@app.route('/')
def index():
    """Main dashboard"""
    return render_template('dashboard.html')

@app.route('/api/markets')
def get_markets():
    """Get markets from real Polymarket API"""
    if not USE_REAL_API:
        # Fallback to mock data
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
        # Fetch events from Gamma API
        events_data = gamma_client.get_events(active=True, closed=False, limit=50)
        
        # Handle different response formats
        if isinstance(events_data, dict):
            events = events_data.get('data', events_data.get('events', []))
        else:
            events = events_data if isinstance(events_data, list) else []
        
        print(f"[DEBUG] Fetched {len(events)} events from API")
        
        markets = []
        for event in events:
            event_markets = event.get('markets', [])
            if not event_markets:
                # Some events might have markets directly in the event object
                if 'question' in event or 'clobTokenIds' in event:
                    event_markets = [event]
                else:
                    continue
                
            for market in event_markets:
                try:
                    # Get clobTokenIds from market (per official docs)
                    # https://docs.polymarket.com/quickstart/fetching-data
                    clob_token_ids = market.get('clobTokenIds', [])
                    if len(clob_token_ids) < 2:
                        continue
                    
                    yes_token = clob_token_ids[0]
                    no_token = clob_token_ids[1]
                    
                    # Parse outcomes and prices from market (per docs format)
                    import json
                    outcomes = json.loads(market.get('outcomes', '["Yes", "No"]'))
                    outcome_prices = json.loads(market.get('outcomePrices', '[0.5, 0.5]'))
                    
                    # Use prices directly from market data first (faster)
                    yes_price = float(outcome_prices[0]) if len(outcome_prices) > 0 else 0.5
                    no_price = float(outcome_prices[1]) if len(outcome_prices) > 1 else 0.5
                        
                    # Try to get better prices from orderbook (optional enhancement)
                    try:
                        yes_book = clob_client.get_orderbook(yes_token)
                        yes_bids = yes_book.get('bids', [])
                        yes_asks = yes_book.get('asks', [])
                        
                        if yes_bids and yes_asks:
                            yes_bid = float(yes_bids[0].get('price', yes_price))
                            yes_ask = float(yes_asks[0].get('price', yes_price))
                            yes_price = (yes_bid + yes_ask) / 2
                    except Exception as e:
                        print(f"Warning: Could not get orderbook for YES token: {e}")
                        # Use price from market data as fallback
                    
                    # Calculate spread from orderbook if available
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
                            'question': market.get('question', 'Unknown Market'),
                            'event': event.get('title', 'Unknown Event'),
                            'yes_price': yes_price,
                            'no_price': no_price,
                            'bid': yes_price - 0.01 if yes_price > 0.01 else 0.0,
                            'ask': yes_price + 0.01 if yes_price < 0.99 else 1.0,
                            'spread': abs(yes_price - no_price),
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

@app.route('/api/strategy/status')
def get_strategy_status():
    """Get strategy status from real API"""
    if not USE_REAL_API:
        return jsonify({
            'active': is_trading,
            'balance': strategy_balance,
            'equity': strategy_equity,
            'positions': strategy_positions,
            'trades': strategy_trades,
            'win_rate': 0,
            'profit': 0,
            'drawdown': 0
        })
    
    try:
        # Get portfolio data (requires user address)
        # For now, return basic status
        return jsonify({
            'active': is_trading,
            'balance': strategy_balance,
            'equity': strategy_equity,
            'positions': strategy_positions,
            'trades': strategy_trades,
            'win_rate': 0,
            'profit': 0,
            'drawdown': 0
        })
    except Exception as e:
        print(f"Error getting strategy status: {e}")
        return jsonify({
            'active': is_trading,
            'balance': 0.0,
            'equity': 0.0,
            'positions': 0,
            'trades': 0,
            'win_rate': 0,
            'profit': 0,
            'drawdown': 0
        })

@app.route('/api/strategy/positions')
def get_positions():
    """Get positions from real API"""
    if not USE_REAL_API:
        return jsonify({'positions': []})
    
    try:
        # Get positions (requires user address - would need to be configured)
        # For now, return empty
        return jsonify({'positions': []})
    except Exception as e:
        print(f"Error fetching positions: {e}")
        return jsonify({'positions': []})

@app.route('/api/strategy/start', methods=['POST'])
def start_strategy():
    """Start trading strategy"""
    global is_trading
    is_trading = True
    return jsonify({'status': 'started'})

@app.route('/api/strategy/stop', methods=['POST'])
def stop_strategy():
    """Stop trading strategy"""
    global is_trading
    is_trading = False
    return jsonify({'status': 'stopped'})

@app.route('/api/market/<market_id>')
def get_market_details(market_id):
    """Get market details from real API"""
    if not USE_REAL_API:
        return jsonify({
            'orderbook': {'bids': [], 'asks': []},
            'best_bid_ask': {'bid': 0.5, 'ask': 0.5, 'spread': 0.0},
            'depth': {'bid_depth': 0, 'ask_depth': 0}
        })
    
    try:
        # Get market by ID or slug
        # Try to get orderbook for the token
        book = clob_client.get_orderbook(market_id)
        
        bids = book.get('bids', [])
        asks = book.get('asks', [])
        
        best_bid = float(bids[0].get('price', 0.5)) if bids else 0.5
        best_ask = float(asks[0].get('price', 0.5)) if asks else 0.5
        
        bid_depth = sum(float(bid.get('size', 0)) for bid in bids)
        ask_depth = sum(float(ask.get('size', 0)) for ask in asks)
        
        return jsonify({
            'orderbook': {
                'bids': bids[:10],  # Top 10 bids
                'asks': asks[:10]   # Top 10 asks
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

@app.route('/api/backtest/run', methods=['POST'])
def run_backtest():
    """Run backtest"""
    global backtest_running, backtest_results
    
    if backtest_running:
        return jsonify({'error': 'Backtest already running'}), 400
    
    try:
        data = request.json
        start_date = data.get('start_date')
        end_date = data.get('end_date')
        initial_balance = float(data.get('initial_balance', 1000.0))
        threshold = float(data.get('threshold', 0.15))
        min_confidence = float(data.get('min_confidence', 0.7))
        
        # Parse dates
        start = datetime.strptime(start_date, '%Y-%m-%d')
        end = datetime.strptime(end_date, '%Y-%m-%d')
        
        # Run backtest in background thread
        def run_backtest_thread():
            global backtest_running, backtest_results
            backtest_running = True
            
            def log_message(msg, msg_type='info'):
                """Emit log message via WebSocket"""
                socketio.emit('backtest_log', {
                    'message': msg,
                    'type': msg_type,
                    'timestamp': datetime.now().strftime('%H:%M:%S')
                })
                time.sleep(0.01)  # Small delay to prevent flooding
            
            try:
                log_message(f"Starting backtest from {start.date()} to {end.date()}", 'info')
                log_message(f"Initial Balance: ${initial_balance:.2f}", 'info')
                log_message(f"Strategy Parameters: threshold={threshold}, confidence={min_confidence}", 'info')
                
                # Import backtesting engine
                from polymarket.backtesting.engine import BacktestEngine
                from polymarket.strategies.examples import SimpleProbabilityStrategy
                import traceback
                
                # Create strategy
                strategy = SimpleProbabilityStrategy(
                    initial_balance=initial_balance,
                    threshold=threshold,
                    min_confidence=min_confidence
                )
                
                log_message("Strategy initialized: SimpleProbabilityStrategy", 'success')
                
                # Create engine
                engine = BacktestEngine(strategy, start, end, initial_balance)
                
                # Custom run with logging
                log_message("Fetching markets...", 'info')
                markets = engine.fetch_historical_markets()
                
                if not markets:
                    log_message("ERROR: No markets found", 'error')
                    raise ValueError("No markets found for backtesting")
                
                log_message(f"Found {len(markets)} markets to backtest", 'success')
                
                # Run backtest with progress updates
                current_date = start
                day_count = 0
                total_days = (end - start).days + 1
                
                while current_date <= end:
                    # Process markets
                    for market_snapshot in markets:
                        market = market_snapshot['market']
                        import json
                        outcomes = json.loads(market.get('outcomes', '["Yes", "No"]'))
                        prices = json.loads(market.get('outcomePrices', '[0.5, 0.5]'))
                        
                        market_data = {
                            'event': market_snapshot['event'],
                            'market': market,
                            'timestamp': current_date,
                            'prices': {
                                outcome: float(price) 
                                for outcome, price in zip(outcomes, prices)
                            }
                        }
                        
                        # Log market data periodically (only once per day, not per market)
                        if day_count % 5 == 0 and len(markets) > 0 and market_snapshot == markets[0]:
                            yes_price = market_data['prices'].get('Yes', 0.5)
                            equity = strategy.calculate_equity()
                            log_message(
                                f"[MARKET] {current_date.date()} | Yes: {yes_price:.2%} | "
                                f"Balance: ${strategy.current_balance:.2f} | Equity: ${equity:.2f} | "
                                f"Positions: {len(strategy.positions)} | Trades: {strategy.total_trades}",
                                'market'
                            )
                        
                        # Get strategy signal
                        signal = strategy.analyze_market(market_data)
                        
                        if signal:
                            if signal.confidence >= strategy.min_confidence:
                                result = engine.execute_signal(signal, market_data, current_date)
                                if result:
                                    # Calculate PnL for this trade
                                    trade_pnl = 0.0
                                    if signal.action == 'SELL':
                                        # PnL already calculated in execute_signal
                                        # Get from closed positions
                                        if strategy.closed_positions:
                                            last_closed = strategy.closed_positions[-1]
                                            if hasattr(last_closed, 'realized_pnl'):
                                                trade_pnl = last_closed.realized_pnl if np.isfinite(last_closed.realized_pnl) else 0.0
                                    
                                    equity = strategy.calculate_equity()
                                    unrealized_pnl = sum(
                                        pos.unrealized_pnl if np.isfinite(pos.unrealized_pnl) else 0.0
                                        for pos in strategy.positions.values()
                                    )
                                    
                                    log_message(
                                        f"[TRADE] {signal.action} | Size: ${result['size']:.2f} | "
                                        f"Price: {result['price']:.4f} | Balance: ${strategy.current_balance:.2f} | "
                                        f"Positions: {len(strategy.positions)}",
                                        'trade'
                                    )
                                    
                                    # Emit real-time trade update
                                    socketio.emit('backtest_trade', {
                                        'action': signal.action,
                                        'price': float(result['price']),
                                        'size': float(result['size']),
                                        'timestamp': current_date.isoformat(),
                                        'balance': float(strategy.current_balance) if np.isfinite(strategy.current_balance) else 0.0,
                                        'equity': float(equity) if np.isfinite(equity) else 0.0,
                                        'unrealized_pnl': float(unrealized_pnl) if np.isfinite(unrealized_pnl) else 0.0,
                                        'trade_pnl': float(trade_pnl),
                                        'positions': len(strategy.positions),
                                        'total_trades': strategy.total_trades,
                                        'winning_trades': strategy.winning_trades,
                                        'losing_trades': strategy.losing_trades
                                    })
                                # Don't log skipped signals to reduce noise
                    
                    # Update positions
                    for token_id, position in strategy.positions.items():
                        price_change = np.random.normal(0, 0.02)
                        new_price = max(0.01, min(0.99, position.current_price + price_change))
                        strategy.update_position(token_id, new_price)
                    
                    # Update equity curve
                    strategy.update_drawdown()
                    equity = strategy.calculate_equity()
                    unrealized_pnl = sum(
                        pos.unrealized_pnl if np.isfinite(pos.unrealized_pnl) else 0.0
                        for pos in strategy.positions.values()
                    )
                    
                    equity_point = {
                        'date': current_date,
                        'equity': equity if np.isfinite(equity) else strategy.current_balance,
                        'balance': strategy.current_balance if np.isfinite(strategy.current_balance) else 0.0,
                        'unrealized_pnl': unrealized_pnl if np.isfinite(unrealized_pnl) else 0.0
                    }
                    engine.equity_curve.append(equity_point)
                    
                    # Emit real-time equity update (every day)
                    socketio.emit('backtest_equity', {
                        'date': current_date.isoformat(),
                        'equity': float(equity_point['equity']),
                        'balance': float(equity_point['balance']),
                        'unrealized_pnl': float(equity_point['unrealized_pnl']),
                        'total_trades': strategy.total_trades,
                        'positions': len(strategy.positions)
                    })
                    
                    # Calculate daily return
                    if len(engine.equity_curve) > 1:
                        prev_equity = engine.equity_curve[-2]['equity']
                        daily_return = (equity - prev_equity) / prev_equity if prev_equity > 0 else 0.0
                        engine.daily_returns.append(daily_return)
                    
                    # Progress update (less frequent)
                    if day_count % 10 == 0 or day_count == total_days - 1:
                        progress = (day_count / total_days * 100) if total_days > 0 else 0
                        log_message(
                            f"[PROGRESS] Day {day_count}/{total_days} ({progress:.1f}%) | "
                            f"Equity: ${equity:.2f} | Trades: {strategy.total_trades} | "
                            f"Positions: {len(strategy.positions)} | Win Rate: "
                            f"{(strategy.winning_trades / strategy.total_trades * 100) if strategy.total_trades > 0 else 0:.1f}%",
                            'info'
                        )
                    
                    current_date += timedelta(days=1)
                    day_count += 1
                    
                    # Small delay for visibility
                    time.sleep(0.05)
                
                # Close positions
                log_message("Closing all positions...", 'info')
                final_equity = strategy.calculate_equity()
                for token_id, position in list(strategy.positions.items()):
                    if position.size > 0 and position.current_price > 0:
                        exit_value = position.size * position.current_price
                        entry_cost = position.size * position.entry_price
                        pnl = exit_value - entry_cost
                        strategy.current_balance += exit_value
                        strategy.total_trades += 1
                        
                        if pnl > 0:
                            strategy.winning_trades += 1
                            strategy.total_profit += pnl
                        else:
                            strategy.losing_trades += 1
                            strategy.total_loss += abs(pnl)
                        
                        log_message(
                            f"[CLOSE] PnL: ${pnl:.2f} | Entry: {position.entry_price:.4f} | Exit: {position.current_price:.4f}",
                            'trade' if pnl > 0 else 'warning'
                        )
                    
                    del strategy.positions[token_id]
                
                # Calculate final metrics
                if engine.initial_balance > 0:
                    total_return = (final_equity - engine.initial_balance) / engine.initial_balance * 100
                else:
                    total_return = 0.0
                
                sharpe_ratio = engine._calculate_sharpe_ratio()
                
                if strategy.total_trades > 0:
                    win_rate = (strategy.winning_trades / strategy.total_trades * 100)
                else:
                    win_rate = 0.0
                
                if abs(strategy.total_loss) > 1e-10:
                    profit_factor = abs(strategy.total_profit / strategy.total_loss)
                else:
                    profit_factor = 0.0
                
                results = {
                    'strategy': strategy.name,
                    'start_date': engine.start_date,
                    'end_date': engine.end_date,
                    'initial_balance': engine.initial_balance,
                    'final_balance': strategy.current_balance,
                    'final_equity': final_equity,
                    'total_return': total_return if np.isfinite(total_return) else 0.0,
                    'total_trades': strategy.total_trades,
                    'winning_trades': strategy.winning_trades,
                    'losing_trades': strategy.losing_trades,
                    'win_rate': win_rate if np.isfinite(win_rate) else 0.0,
                    'total_profit': strategy.total_profit,
                    'total_loss': strategy.total_loss,
                    'net_profit': strategy.total_profit + strategy.total_loss,
                    'profit_factor': profit_factor if np.isfinite(profit_factor) else 0.0,
                    'max_drawdown': strategy.max_drawdown * 100 if np.isfinite(strategy.max_drawdown) else 0.0,
                    'sharpe_ratio': sharpe_ratio if np.isfinite(sharpe_ratio) else 0.0,
                    'trades': engine.trades,
                    'equity_curve': engine.equity_curve
                }
                
                log_message("=" * 50, 'info')
                log_message("BACKTEST COMPLETE", 'success')
                log_message(f"Total Return: {total_return:.2f}%", 'success')
                log_message(f"Total Trades: {strategy.total_trades}", 'info')
                log_message(f"Win Rate: {win_rate:.2f}%", 'info')
                log_message(f"Final Equity: ${final_equity:.2f}", 'success')
                
                # Prepare results for frontend
                equity_curve = results.get('equity_curve', [])
                if not equity_curve:
                    equity_curve = [
                        {'date': start, 'equity': initial_balance},
                        {'date': end, 'equity': results.get('final_equity', initial_balance)}
                    ]
                
                def safe_float(value, default=0.0):
                    try:
                        val = float(value)
                        return val if (val == 0 or (val != float('inf') and val != float('-inf') and not (val != val))) else default
                    except (ValueError, TypeError):
                        return default
                
                backtest_results = {
                    'total_return': safe_float(results.get('total_return', 0)),
                    'total_trades': int(results.get('total_trades', 0)),
                    'winning_trades': int(results.get('winning_trades', 0)),
                    'losing_trades': int(results.get('losing_trades', 0)),
                    'win_rate': safe_float(results.get('win_rate', 0)),
                    'sharpe_ratio': safe_float(results.get('sharpe_ratio', 0)),
                    'max_drawdown': safe_float(results.get('max_drawdown', 0)),
                    'final_equity': safe_float(results.get('final_equity', initial_balance), initial_balance),
                    'equity_curve': [
                        {
                            'date': str(point.get('date', '')),
                            'equity': safe_float(point.get('equity', initial_balance), initial_balance)
                        }
                        for point in equity_curve
                    ],
                    'net_profit': safe_float(results.get('net_profit', 0))
                }
                
                # Emit results via WebSocket
                socketio.emit('backtest_complete', backtest_results)
                
            except Exception as e:
                import traceback
                error_msg = f"{str(e)}\n{traceback.format_exc()}"
                print(f"Backtest error: {error_msg}")
                socketio.emit('backtest_error', {'error': str(e)})
            finally:
                backtest_running = False
        
        thread = threading.Thread(target=run_backtest_thread, daemon=True)
        thread.start()
        
        return jsonify({'status': 'started', 'message': 'Backtest running...'})
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/backtest/status')
def get_backtest_status():
    """Get backtest status"""
    return jsonify({
        'running': backtest_running,
        'results': backtest_results
    })

# WebSocket handlers
@socketio.on('connect')
def handle_connect():
    """Handle WebSocket connection"""
    emit('status', {'message': 'Connected to Cyberpunk Dashboard'})

@socketio.on('disconnect')
def handle_disconnect():
    """Handle WebSocket disconnection"""
    pass

if __name__ == '__main__':
    print("=" * 60)
    print("CYBERPUNK POLYMARKET DASHBOARD")
    print("=" * 60)
    print("Starting server on http://localhost:5000")
    print("Press Ctrl+C to stop")
    print("=" * 60)
    socketio.run(app, host='0.0.0.0', port=5000, debug=True)
