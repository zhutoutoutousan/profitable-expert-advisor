# Cyberpunk Polymarket Trading Dashboard

A futuristic, cyberpunk-themed web-based GUI for the Polymarket trading framework.

## Features

- 🎮 **Cyberpunk Aesthetic**: Neon colors, glitch effects, and futuristic design
- 📊 **Real-time Market Data**: Live market prices and orderbook data
- 🎯 **Strategy Control**: Start/stop trading with customizable parameters
- 📈 **Performance Metrics**: Real-time P&L, win rate, and position tracking
- 💹 **Position Management**: Visual display of open positions with P&L
- 🔌 **WebSocket Updates**: Real-time data streaming

## Installation

```bash
cd polymarket/gui
pip install -r requirements.txt
```

## Running the Dashboard

```bash
python app.py
```

Then open your browser to: **http://localhost:5000**

## Usage

1. **Configure Strategy**:
   - Set threshold (probability deviation)
   - Set minimum confidence
   - Set initial balance
   - Select market category

2. **Start Trading**:
   - Click "START TRADING" button
   - Monitor real-time metrics
   - View open positions

3. **Monitor Performance**:
   - Watch balance and equity updates
   - Track win rate and P&L
   - View position details

4. **Stop Trading**:
   - Click "STOP TRADING" when done

## Controls

- **Threshold**: Probability deviation threshold (0.05 - 0.3)
- **Min Confidence**: Minimum confidence to trade (0.5 - 1.0)
- **Initial Balance**: Starting USDC balance
- **Category**: Market category to monitor (Crypto, Politics, Sports)

## Features

### Real-time Updates
- Market prices update every 2 seconds
- Strategy metrics update in real-time
- Position P&L calculated live

### Visual Feedback
- Neon color scheme (cyan, pink, green)
- Glitch effects and animations
- Status indicators
- Notification system

### Responsive Design
- Works on desktop and tablet
- Grid-based layout
- Scrollable market lists

## Troubleshooting

**Port already in use?**
- Change port in `app.py`: `socketio.run(app, port=5001)`

**Markets not loading?**
- Check internet connection
- Verify Polymarket API is accessible
- Check browser console for errors

**Trading not starting?**
- Ensure strategy parameters are valid
- Check that markets are available
- Review server logs for errors

## Customization

### Colors
Edit `static/style.css` CSS variables:
```css
:root {
    --neon-cyan: #00ffff;
    --neon-pink: #ff00ff;
    --neon-green: #00ff00;
}
```

### Update Frequency
Change in `static/script.js`:
```javascript
updateInterval = setInterval(..., 2000); // 2 seconds
```

## Screenshots

The dashboard features:
- Glitch text header with "POLYMARKET"
- Three-panel layout (Strategy, Markets, Performance)
- Bottom panel for positions
- Animated background grid
- Particle effects
- Neon glow effects

## Notes

- The dashboard runs in simulation mode by default
- For live trading, configure API credentials in `.env`
- All trading is done through the framework's strategy system
- WebSocket provides real-time updates when available

Enjoy your cyberpunk trading experience! 🚀💀
