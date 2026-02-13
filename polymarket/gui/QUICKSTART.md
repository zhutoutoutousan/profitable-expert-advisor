# Quick Start - Cyberpunk Dashboard

## 🚀 Get Started in 3 Steps

### Step 1: Install Dependencies

```bash
cd polymarket/gui
pip install -r requirements.txt
```

### Step 2: Run the Dashboard

**Windows:**
```bash
run.bat
```

**Linux/Mac:**
```bash
python app.py
```

### Step 3: Open in Browser

Open: **http://localhost:5000**

## 🎮 Using the Dashboard

### Starting Trading

1. **Set Parameters**:
   - **Threshold**: How much price deviation to trigger trades (0.15 = 15%)
   - **Min Confidence**: Minimum confidence level (0.7 = 70%)
   - **Initial Balance**: Starting USDC (e.g., 1000)
   - **Category**: Market category (Crypto, Politics, Sports)

2. **Click "START TRADING"**

3. **Monitor**:
   - Watch markets update in real-time
   - See your balance and equity
   - Track open positions
   - View performance metrics

### Features

- **Real-time Market Data**: Markets update every 2 seconds
- **Live Strategy Metrics**: Balance, equity, P&L, win rate
- **Position Tracking**: See all open positions with P&L
- **Cyberpunk Theme**: Neon colors, glitch effects, animations

## 🎨 Customization

### Change Colors

Edit `static/style.css`:

```css
:root {
    --neon-cyan: #00ffff;    /* Main color */
    --neon-pink: #ff00ff;    /* Accent */
    --neon-green: #00ff00;   /* Success */
}
```

### Change Update Frequency

Edit `static/script.js`:

```javascript
updateInterval = setInterval(..., 2000); // Change 2000 to desired ms
```

## 🐛 Troubleshooting

**Port 5000 already in use?**
- Edit `app.py`, change: `socketio.run(app, port=5001)`
- Then open: http://localhost:5001

**Markets not loading?**
- Check internet connection
- Verify Polymarket API is accessible
- Check browser console (F12) for errors

**Trading won't start?**
- Ensure all parameters are valid
- Check that markets are available
- Review terminal output for errors

## 💡 Tips

- Start with small balance for testing
- Use threshold 0.15-0.20 for balanced trading
- Monitor win rate - should be > 50% for good strategies
- Watch drawdown - keep it under 20%

Enjoy your cyberpunk trading! 💀🚀
