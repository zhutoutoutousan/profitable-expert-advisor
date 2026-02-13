// Cyberpunk Dashboard JavaScript

const socket = io();
let updateInterval;

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    initializeControls();
    loadMarkets();
    startStatusUpdates();
    setupWebSocket();
    initializeBacktest();
});

// Control Initialization
function initializeControls() {
    const threshold = document.getElementById('threshold');
    const confidence = document.getElementById('confidence');
    const thresholdValue = document.getElementById('thresholdValue');
    const confidenceValue = document.getElementById('confidenceValue');
    const startBtn = document.getElementById('startBtn');
    const stopBtn = document.getElementById('stopBtn');

    threshold.addEventListener('input', (e) => {
        thresholdValue.textContent = parseFloat(e.target.value).toFixed(2);
    });

    confidence.addEventListener('input', (e) => {
        confidenceValue.textContent = parseFloat(e.target.value).toFixed(2);
    });

    startBtn.addEventListener('click', startTrading);
    stopBtn.addEventListener('click', stopTrading);
}

// Load Markets
async function loadMarkets() {
    try {
        console.log('[DEBUG] Loading markets from API...');
        const response = await fetch('/api/markets');
        const data = await response.json();
        
        console.log('[DEBUG] API response:', data);
        console.log('[DEBUG] Markets array:', data.markets);
        console.log('[DEBUG] Markets count:', data.markets ? data.markets.length : 0);
        
        if (data.markets && Array.isArray(data.markets)) {
            console.log('[DEBUG] Displaying', data.markets.length, 'markets');
            displayMarkets(data.markets);
        } else {
            console.error('[DEBUG] Invalid markets data:', data);
            document.getElementById('marketsList').innerHTML = 
                '<div class="empty-state">NO ACTIVE MARKETS (Invalid data format)</div>';
        }
    } catch (error) {
        console.error('Error loading markets:', error);
        document.getElementById('marketsList').innerHTML = 
            '<div class="loading">ERROR LOADING MARKETS: ' + error.message + '</div>';
    }
}

// Display Markets
function displayMarkets(markets) {
    const container = document.getElementById('marketsList');
    
    if (!container) {
        console.error('[DEBUG] marketsList container not found!');
        return;
    }
    
    console.log('[DEBUG] displayMarkets called with', markets.length, 'markets');
    
    if (!markets || markets.length === 0) {
        container.innerHTML = '<div class="empty-state">NO ACTIVE MARKETS</div>';
        return;
    }

    container.innerHTML = markets.map(market => {
        const question = market.question || market.event || 'Unknown Market';
        const yesPrice = (market.yes_price || 0) * 100;
        const noPrice = (market.no_price || 0) * 100;
        const spread = market.spread || Math.abs(yesPrice - noPrice) / 100;
        
        return `
        <div class="market-item">
            <div class="market-question">${question}</div>
            <div class="market-prices">
                <div class="price-yes">
                    YES: <span class="price-value">${yesPrice.toFixed(1)}%</span>
                </div>
                <div class="price-no">
                    NO: <span class="price-value">${noPrice.toFixed(1)}%</span>
                </div>
            </div>
            <div style="margin-top: 8px; font-size: 0.8rem; color: var(--text-secondary);">
                Spread: ${(spread * 100).toFixed(2)}%
            </div>
        </div>
        `;
    }).join('');
    
    console.log('[DEBUG] Markets displayed successfully');
}

// Start Trading
async function startTrading() {
    const threshold = parseFloat(document.getElementById('threshold').value);
    const confidence = parseFloat(document.getElementById('confidence').value);
    const balance = parseFloat(document.getElementById('balance').value);
    const category = document.getElementById('category').value;

    try {
        const response = await fetch('/api/strategy/start', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                threshold,
                min_confidence: confidence,
                initial_balance: balance,
                tag_id: parseInt(category)
            })
        });

        const data = await response.json();

        if (response.ok) {
            document.getElementById('startBtn').disabled = true;
            document.getElementById('stopBtn').disabled = false;
            updateStatus(true);
            showNotification('TRADING STARTED', 'success');
        } else {
            showNotification('ERROR: ' + data.error, 'error');
        }
    } catch (error) {
        console.error('Error starting trading:', error);
        showNotification('ERROR STARTING TRADING', 'error');
    }
}

// Stop Trading
async function stopTrading() {
    try {
        const response = await fetch('/api/strategy/stop', {
            method: 'POST'
        });

        const data = await response.json();

        if (response.ok) {
            document.getElementById('startBtn').disabled = false;
            document.getElementById('stopBtn').disabled = true;
            updateStatus(false);
            showNotification('TRADING STOPPED', 'info');
        } else {
            showNotification('ERROR: ' + data.error, 'error');
        }
    } catch (error) {
        console.error('Error stopping trading:', error);
        showNotification('ERROR STOPPING TRADING', 'error');
    }
}

// Status Updates
function startStatusUpdates() {
    updateInterval = setInterval(async () => {
        await updateStrategyStatus();
        await updatePositions();
    }, 2000);
}

// Update Strategy Status
async function updateStrategyStatus() {
    try {
        const response = await fetch('/api/strategy/status');
        const data = await response.json();

        document.getElementById('balanceValue').textContent = 
            '$' + data.balance.toFixed(2);
        document.getElementById('equityValue').textContent = 
            '$' + data.equity.toFixed(2);
        document.getElementById('positionsValue').textContent = 
            data.positions;
        document.getElementById('tradesValue').textContent = 
            data.trades;
        document.getElementById('winRateValue').textContent = 
            data.win_rate.toFixed(1) + '%';
        
        const pnlElement = document.getElementById('pnlValue');
        const pnl = data.profit || 0;
        pnlElement.textContent = '$' + pnl.toFixed(2);
        pnlElement.style.color = pnl >= 0 ? 'var(--neon-green)' : 'var(--neon-pink)';
    } catch (error) {
        console.error('Error updating status:', error);
    }
}

// Update Positions
async function updatePositions() {
    try {
        const response = await fetch('/api/strategy/positions');
        const data = await response.json();

        displayPositions(data.positions || []);
    } catch (error) {
        console.error('Error updating positions:', error);
    }
}

// Display Positions
function displayPositions(positions) {
    const container = document.getElementById('positionsList');

    if (positions.length === 0) {
        container.innerHTML = '<div class="empty-state">NO OPEN POSITIONS</div>';
        return;
    }

    container.innerHTML = positions.map(pos => {
        const isProfit = pos.pnl >= 0;
        return `
            <div class="position-card ${isProfit ? 'profit' : 'loss'}">
                <div class="position-header">
                    <div class="position-outcome">${pos.outcome}</div>
                    <div class="position-pnl ${isProfit ? 'positive' : 'negative'}">
                        ${isProfit ? '+' : ''}$${pos.pnl.toFixed(2)}
                    </div>
                </div>
                <div class="position-details">
                    <div>Size: ${pos.size.toFixed(2)}</div>
                    <div>Entry: ${(pos.entry_price * 100).toFixed(2)}%</div>
                    <div>Current: ${(pos.current_price * 100).toFixed(2)}%</div>
                    <div>P&L: ${pos.pnl_percent.toFixed(2)}%</div>
                </div>
            </div>
        `;
    }).join('');
}

// Update Status Indicator
function updateStatus(active) {
    const statusDot = document.getElementById('statusDot');
    const statusText = document.getElementById('statusText');

    if (active) {
        statusDot.classList.add('active');
        statusText.textContent = 'ONLINE';
    } else {
        statusDot.classList.remove('active');
        statusText.textContent = 'OFFLINE';
    }
}

// WebSocket Setup
function setupWebSocket() {
    socket.on('connect', () => {
        console.log('Connected to server');
    });

    socket.on('strategy_update', (data) => {
        // Real-time updates via WebSocket
        document.getElementById('balanceValue').textContent = 
            '$' + data.balance.toFixed(2);
        document.getElementById('equityValue').textContent = 
            '$' + data.equity.toFixed(2);
        document.getElementById('positionsValue').textContent = 
            data.positions;
        document.getElementById('tradesValue').textContent = 
            data.trades;
    });
    
    socket.on('backtest_log', (data) => {
        addTerminalLine(data.message, data.type || 'info');
    });
    
    socket.on('backtest_trade', (data) => {
        addTradeToList(data);
        updateRealtimeStats(data);
    });
    
    socket.on('backtest_equity', (data) => {
        updateRealtimeChart(data);
        updateRealtimeStats(data);
    });
    
    socket.on('backtest_complete', (data) => {
        displayBacktestResults(data);
    });
    
    socket.on('backtest_error', (data) => {
        addTerminalLine('ERROR: ' + data.error, 'error');
        showNotification('BACKTEST ERROR: ' + data.error, 'error');
        const btn = document.getElementById('runBacktestBtn');
        btn.disabled = false;
        btn.innerHTML = '<span>▶ RUN BACKTEST</span>';
        document.getElementById('backtestStatus').style.display = 'none';
    });
}

// Notification System
function showNotification(message, type = 'info') {
    // Simple notification - can be enhanced with a toast system
    console.log(`[${type.toUpperCase()}] ${message}`);
    
    // Create notification element
    const notification = document.createElement('div');
    notification.style.cssText = `
        position: fixed;
        top: 20px;
        right: 20px;
        padding: 15px 25px;
        background: rgba(0, 255, 255, 0.1);
        border: 2px solid var(--neon-cyan);
        color: var(--neon-cyan);
        font-family: 'Orbitron', sans-serif;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.1em;
        z-index: 10000;
        box-shadow: 0 0 20px var(--neon-cyan);
        animation: slideIn 0.3s ease;
    `;
    notification.textContent = message;
    
    document.body.appendChild(notification);
    
    setTimeout(() => {
        notification.style.animation = 'slideOut 0.3s ease';
        setTimeout(() => notification.remove(), 300);
    }, 3000);
}

// Backtesting Functions
function initializeBacktest() {
    // Set default dates (last 30 days)
    const endDate = new Date();
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - 30);
    
    document.getElementById('backtestStart').value = startDate.toISOString().split('T')[0];
    document.getElementById('backtestEnd').value = endDate.toISOString().split('T')[0];
    
    document.getElementById('runBacktestBtn').addEventListener('click', runBacktest);
    document.getElementById('clearTerminalBtn').addEventListener('click', clearTerminal);
    
    // Initialize real-time chart (wait for DOM to be ready)
    setTimeout(() => {
        initRealtimeChart();
    }, 100);
    
    // Clear trades list on new backtest
    const tradesList = document.getElementById('tradesList');
    if (tradesList) {
        tradesList.innerHTML = '<div class="empty-state">No trades yet</div>';
    }
    equityData = [];
}

function clearTerminal() {
    document.getElementById('terminalOutput').innerHTML = 
        '<div class="terminal-line">[SYSTEM] Terminal cleared...</div>';
}

function addTerminalLine(message, type = 'info') {
    const terminal = document.getElementById('terminalOutput');
    const line = document.createElement('div');
    line.className = `terminal-line ${type}`;
    
    const timestamp = new Date().toLocaleTimeString();
    line.textContent = `[${timestamp}] ${message}`;
    
    terminal.appendChild(line);
    terminal.scrollTop = terminal.scrollHeight;
    
    // Keep only last 100 lines
    const lines = terminal.querySelectorAll('.terminal-line');
    if (lines.length > 100) {
        lines[0].remove();
    }
}

// Real-time chart data
let equityData = [];
let chartCanvas = null;
let chartCtx = null;

function initRealtimeChart() {
    chartCanvas = document.getElementById('realtimeChart');
    if (!chartCanvas) return;
    
    chartCtx = chartCanvas.getContext('2d');
    equityData = [];
    
    // Set canvas size
    const container = chartCanvas.parentElement;
    chartCanvas.width = container.clientWidth - 30;
    chartCanvas.height = 250;
    
    // Draw initial chart
    drawChart();
}

function updateRealtimeChart(data) {
    if (!chartCtx) return;
    
    equityData.push({
        date: new Date(data.date),
        equity: data.equity,
        balance: data.balance,
        unrealized_pnl: data.unrealized_pnl
    });
    
    // Keep only last 1000 points
    if (equityData.length > 1000) {
        equityData.shift();
    }
    
    drawChart();
}

function drawChart() {
    if (!chartCtx || equityData.length === 0) return;
    
    const canvas = chartCanvas;
    const width = canvas.width;
    const height = canvas.height;
    const padding = 40;
    const chartWidth = width - padding * 2;
    const chartHeight = height - padding * 2;
    
    // Clear canvas
    chartCtx.fillStyle = '#000';
    chartCtx.fillRect(0, 0, width, height);
    
    if (equityData.length < 2) return;
    
    // Find min/max equity
    const equities = equityData.map(d => d.equity);
    const minEquity = Math.min(...equities);
    const maxEquity = Math.max(...equities);
    const range = maxEquity - minEquity || 1;
    
    // Draw grid
    chartCtx.strokeStyle = 'rgba(0, 255, 255, 0.2)';
    chartCtx.lineWidth = 1;
    for (let i = 0; i <= 5; i++) {
        const y = padding + (chartHeight / 5) * i;
        chartCtx.beginPath();
        chartCtx.moveTo(padding, y);
        chartCtx.lineTo(width - padding, y);
        chartCtx.stroke();
    }
    
    // Draw equity curve
    chartCtx.strokeStyle = '#00ffff';
    chartCtx.lineWidth = 2;
    chartCtx.beginPath();
    
    equityData.forEach((point, index) => {
        const x = padding + (chartWidth / (equityData.length - 1)) * index;
        const y = padding + chartHeight - ((point.equity - minEquity) / range) * chartHeight;
        
        if (index === 0) {
            chartCtx.moveTo(x, y);
        } else {
            chartCtx.lineTo(x, y);
        }
    });
    
    chartCtx.stroke();
    
    // Draw balance line
    chartCtx.strokeStyle = 'rgba(255, 0, 255, 0.5)';
    chartCtx.lineWidth = 1;
    chartCtx.beginPath();
    
    equityData.forEach((point, index) => {
        const x = padding + (chartWidth / (equityData.length - 1)) * index;
        const y = padding + chartHeight - ((point.balance - minEquity) / range) * chartHeight;
        
        if (index === 0) {
            chartCtx.moveTo(x, y);
        } else {
            chartCtx.lineTo(x, y);
        }
    });
    
    chartCtx.stroke();
    
    // Draw labels
    chartCtx.fillStyle = '#00ffff';
    chartCtx.font = '10px Orbitron';
    chartCtx.fillText(`$${minEquity.toFixed(0)}`, 5, height - padding + 5);
    chartCtx.fillText(`$${maxEquity.toFixed(0)}`, 5, padding + 5);
}

function addTradeToList(trade) {
    const tradesList = document.getElementById('tradesList');
    if (!tradesList) return;
    
    // Remove empty state
    const emptyState = tradesList.querySelector('.empty-state');
    if (emptyState) {
        emptyState.remove();
    }
    
    const tradeItem = document.createElement('div');
    tradeItem.className = `trade-item ${trade.action.toLowerCase()}`;
    
    const pnl = trade.trade_pnl || 0;
    const pnlClass = pnl >= 0 ? 'positive' : 'negative';
    const pnlSign = pnl >= 0 ? '+' : '';
    
    tradeItem.innerHTML = `
        <div class="trade-info">
            <div class="trade-action">${trade.action}</div>
            <div class="trade-details">
                Price: ${trade.price.toFixed(4)} | Size: $${trade.size.toFixed(2)} | 
                ${new Date(trade.timestamp).toLocaleTimeString()}
            </div>
        </div>
        <div class="trade-pnl ${pnlClass}">
            ${pnlSign}$${Math.abs(pnl).toFixed(2)}
        </div>
    `;
    
    tradesList.insertBefore(tradeItem, tradesList.firstChild);
    
    // Keep only last 50 trades
    while (tradesList.children.length > 50) {
        tradesList.removeChild(tradesList.lastChild);
    }
    
    // Update trades count
    const tradesCount = document.getElementById('tradesCount');
    if (tradesCount) {
        tradesCount.textContent = `${trade.total_trades} trades`;
    }
}

function updateRealtimeStats(data) {
    const equityEl = document.getElementById('realtimeEquity');
    const pnlEl = document.getElementById('realtimePnL');
    
    if (equityEl) {
        equityEl.textContent = `$${data.equity.toFixed(2)}`;
    }
    
    if (pnlEl) {
        const pnl = data.unrealized_pnl || 0;
        pnlEl.textContent = `${pnl >= 0 ? '+' : ''}$${pnl.toFixed(2)}`;
        pnlEl.className = pnl >= 0 ? 'pnl-positive' : 'pnl-negative';
    }
}

async function runBacktest() {
    const startDate = document.getElementById('backtestStart').value;
    const endDate = document.getElementById('backtestEnd').value;
    const balance = parseFloat(document.getElementById('backtestBalance').value);
    const threshold = parseFloat(document.getElementById('threshold').value);
    const confidence = parseFloat(document.getElementById('confidence').value);
    
    if (!startDate || !endDate) {
        showNotification('PLEASE SELECT START AND END DATES', 'error');
        return;
    }
    
    const btn = document.getElementById('runBacktestBtn');
    btn.disabled = true;
    btn.innerHTML = '<span>⏳ RUNNING...</span>';
    
    const statusDiv = document.getElementById('backtestStatus');
    statusDiv.innerHTML = '<div class="loading">RUNNING BACKTEST...</div>';
    statusDiv.style.display = 'block';
    
    // Clear terminal and add initial message
    clearTerminal();
    addTerminalLine('Starting backtest...', 'info');
    
    // Reset chart and trades
    equityData = [];
    const tradesList = document.getElementById('tradesList');
    if (tradesList) {
        tradesList.innerHTML = '<div class="empty-state">No trades yet</div>';
    }
    
    // Reinitialize chart
    setTimeout(() => {
        initRealtimeChart();
    }, 100);
    
    try {
        const response = await fetch('/api/backtest/run', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                start_date: startDate,
                end_date: endDate,
                initial_balance: balance,
                threshold: threshold,
                min_confidence: confidence
            })
        });
        
        const data = await response.json();
        
        if (response.ok) {
            showNotification('BACKTEST STARTED', 'success');
            // Results will come via WebSocket
        } else {
            showNotification('ERROR: ' + data.error, 'error');
            btn.disabled = false;
            btn.innerHTML = '<span>▶ RUN BACKTEST</span>';
        }
    } catch (error) {
        console.error('Error running backtest:', error);
        showNotification('ERROR RUNNING BACKTEST', 'error');
        btn.disabled = false;
        btn.innerHTML = '<span>▶ RUN BACKTEST</span>';
    }
}

function displayBacktestResults(results) {
    const resultsDiv = document.getElementById('backtestResults');
    const statusDiv = document.getElementById('backtestStatus');
    
    // Update metrics
    document.getElementById('backtestReturn').textContent = 
        results.total_return.toFixed(2) + '%';
    document.getElementById('backtestReturn').style.color = 
        results.total_return >= 0 ? 'var(--neon-green)' : 'var(--neon-pink)';
    
    document.getElementById('backtestTrades').textContent = results.total_trades;
    document.getElementById('backtestWinRate').textContent = 
        results.win_rate.toFixed(1) + '%';
    document.getElementById('backtestSharpe').textContent = 
        results.sharpe_ratio.toFixed(2);
    document.getElementById('backtestDrawdown').textContent = 
        results.max_drawdown.toFixed(2) + '%';
    document.getElementById('backtestEquity').textContent = 
        '$' + results.final_equity.toFixed(2);
    
    // Draw equity curve chart
    drawEquityChart(results.equity_curve);
    
    // Show results
    statusDiv.style.display = 'none';
    resultsDiv.style.display = 'block';
    
    // Re-enable button
    const btn = document.getElementById('runBacktestBtn');
    btn.disabled = false;
    btn.innerHTML = '<span>▶ RUN BACKTEST</span>';
    
    showNotification('BACKTEST COMPLETE', 'success');
}

function drawEquityChart(equityCurve) {
    const canvas = document.getElementById('backtestChart');
    const ctx = canvas.getContext('2d');
    
    if (!equityCurve || equityCurve.length === 0) {
        ctx.fillStyle = 'var(--text-secondary)';
        ctx.font = '14px Orbitron';
        ctx.fillText('No data available', 10, 100);
        return;
    }
    
    // Clear canvas
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    
    // Setup
    const padding = 40;
    const width = canvas.width - padding * 2;
    const height = canvas.height - padding * 2;
    
    // Find min/max for scaling
    const equities = equityCurve.map(p => p.equity);
    const minEquity = Math.min(...equities);
    const maxEquity = Math.max(...equities);
    const range = maxEquity - minEquity || 1;
    
    // Draw grid
    ctx.strokeStyle = 'rgba(0, 255, 255, 0.2)';
    ctx.lineWidth = 1;
    for (let i = 0; i <= 5; i++) {
        const y = padding + (height / 5) * i;
        ctx.beginPath();
        ctx.moveTo(padding, y);
        ctx.lineTo(canvas.width - padding, y);
        ctx.stroke();
    }
    
    // Draw equity curve
    ctx.strokeStyle = 'var(--neon-cyan)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    
    equityCurve.forEach((point, index) => {
        const x = padding + (width / (equityCurve.length - 1)) * index;
        const y = padding + height - ((point.equity - minEquity) / range) * height;
        
        if (index === 0) {
            ctx.moveTo(x, y);
        } else {
            ctx.lineTo(x, y);
        }
    });
    
    ctx.stroke();
    
    // Draw glow effect
    ctx.shadowBlur = 10;
    ctx.shadowColor = 'var(--neon-cyan)';
    ctx.stroke();
    
    // Draw labels
    ctx.fillStyle = 'var(--text-secondary)';
    ctx.font = '10px Orbitron';
    ctx.fillText('$' + minEquity.toFixed(0), 5, canvas.height - padding);
    ctx.fillText('$' + maxEquity.toFixed(0), 5, padding + 10);
}

// Add animations
const style = document.createElement('style');
style.textContent = `
    @keyframes slideIn {
        from {
            transform: translateX(100%);
            opacity: 0;
        }
        to {
            transform: translateX(0);
            opacity: 1;
        }
    }
    
    @keyframes slideOut {
        from {
            transform: translateX(0);
            opacity: 1;
        }
        to {
            transform: translateX(100%);
            opacity: 0;
        }
    }
`;
document.head.appendChild(style);
