/**
 * Backtest Component
 * Handles backtesting functionality
 */

export class BacktestComponent {
    constructor() {
        this.equityData = [];
        this.chartCanvas = null;
        this.chartCtx = null;
        this.isRunning = false;
    }

    initialize() {
        // Set default dates
        const endDate = new Date();
        const startDate = new Date();
        startDate.setDate(startDate.getDate() - 30);
        
        const startInput = document.getElementById('backtestStart');
        const endInput = document.getElementById('backtestEnd');
        if (startInput) startInput.value = startDate.toISOString().split('T')[0];
        if (endInput) endInput.value = endDate.toISOString().split('T')[0];
        
        // Event listeners
        const runBtn = document.getElementById('runBacktestBtn');
        const clearBtn = document.getElementById('clearTerminalBtn');
        
        if (runBtn) runBtn.addEventListener('click', () => this.run());
        if (clearBtn) clearBtn.addEventListener('click', () => this.clearTerminal());
        
        // Initialize chart
        setTimeout(() => this.initChart(), 100);
    }

    initChart() {
        this.chartCanvas = document.getElementById('realtimeChart');
        if (!this.chartCanvas) return;
        
        this.chartCtx = this.chartCanvas.getContext('2d');
        const container = this.chartCanvas.parentElement;
        this.chartCanvas.width = container.clientWidth - 30;
        this.chartCanvas.height = 250;
        
        this.drawChart();
    }

    async run() {
        if (this.isRunning) {
            this.showNotification('Backtest already running', 'error');
            return;
        }

        const startDate = document.getElementById('backtestStart')?.value;
        const endDate = document.getElementById('backtestEnd')?.value;
        const balance = parseFloat(document.getElementById('backtestBalance')?.value || 1000);
        const threshold = parseFloat(document.getElementById('threshold')?.value || 0.15);
        const confidence = parseFloat(document.getElementById('confidence')?.value || 0.7);

        if (!startDate || !endDate) {
            this.showNotification('PLEASE SELECT START AND END DATES', 'error');
            return;
        }

        const btn = document.getElementById('runBacktestBtn');
        btn.disabled = true;
        btn.innerHTML = '<span>⏳ RUNNING...</span>';

        const statusDiv = document.getElementById('backtestStatus');
        statusDiv.innerHTML = '<div class="loading">RUNNING BACKTEST...</div>';
        statusDiv.style.display = 'block';

        this.clearTerminal();
        this.addTerminalLine('Starting backtest...', 'info');

        this.equityData = [];
        const tradesList = document.getElementById('tradesList');
        if (tradesList) {
            tradesList.innerHTML = '<div class="empty-state">No trades yet</div>';
        }

        setTimeout(() => this.initChart(), 100);

        try {
            const response = await fetch('/api/backtest/run', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
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
                this.isRunning = true;
                this.showNotification('BACKTEST STARTED', 'success');
            } else {
                this.showNotification('ERROR: ' + data.error, 'error');
                btn.disabled = false;
                btn.innerHTML = '<span>▶ RUN BACKTEST</span>';
            }
        } catch (error) {
            console.error('[Backtest] Error running backtest:', error);
            this.showNotification('ERROR RUNNING BACKTEST', 'error');
            btn.disabled = false;
            btn.innerHTML = '<span>▶ RUN BACKTEST</span>';
        }
    }

    displayResults(results) {
        const resultsDiv = document.getElementById('backtestResults');
        const statusDiv = document.getElementById('backtestStatus');
        
        if (resultsDiv && statusDiv) {
            document.getElementById('backtestReturn').textContent = 
                results.total_return.toFixed(2) + '%';
            document.getElementById('backtestTrades').textContent = results.total_trades;
            document.getElementById('backtestWinRate').textContent = 
                results.win_rate.toFixed(1) + '%';
            document.getElementById('backtestSharpe').textContent = 
                results.sharpe_ratio.toFixed(2);
            document.getElementById('backtestDrawdown').textContent = 
                results.max_drawdown.toFixed(2) + '%';
            document.getElementById('backtestEquity').textContent = 
                '$' + results.final_equity.toFixed(2);
            
            statusDiv.style.display = 'none';
            resultsDiv.style.display = 'block';
        }
    }

    clearTerminal() {
        const terminal = document.getElementById('terminalOutput');
        if (terminal) {
            terminal.innerHTML = '<div class="terminal-line">[SYSTEM] Terminal cleared...</div>';
        }
    }

    addTerminalLine(message, type = 'info') {
        const terminal = document.getElementById('terminalOutput');
        if (!terminal) return;
        
        const line = document.createElement('div');
        line.className = `terminal-line ${type}`;
        
        const timestamp = new Date().toLocaleTimeString();
        line.textContent = `[${timestamp}] ${message}`;
        
        terminal.appendChild(line);
        terminal.scrollTop = terminal.scrollHeight;
        
        const lines = terminal.querySelectorAll('.terminal-line');
        if (lines.length > 100) {
            lines[0].remove();
        }
    }

    updateChart(data) {
        if (!this.chartCtx) return;
        
        this.equityData.push({
            date: new Date(data.date),
            equity: data.equity,
            balance: data.balance,
            unrealized_pnl: data.unrealized_pnl
        });
        
        if (this.equityData.length > 1000) {
            this.equityData.shift();
        }
        
        this.drawChart();
    }

    drawChart() {
        if (!this.chartCtx || this.equityData.length === 0) return;
        
        const canvas = this.chartCanvas;
        const width = canvas.width;
        const height = canvas.height;
        const padding = 40;
        const chartWidth = width - padding * 2;
        const chartHeight = height - padding * 2;
        
        this.chartCtx.fillStyle = '#000';
        this.chartCtx.fillRect(0, 0, width, height);
        
        if (this.equityData.length < 2) return;
        
        const equities = this.equityData.map(d => d.equity);
        const minEquity = Math.min(...equities);
        const maxEquity = Math.max(...equities);
        const range = maxEquity - minEquity || 1;
        
        // Draw grid
        this.chartCtx.strokeStyle = 'rgba(0, 255, 255, 0.2)';
        this.chartCtx.lineWidth = 1;
        for (let i = 0; i <= 5; i++) {
            const y = padding + (chartHeight / 5) * i;
            this.chartCtx.beginPath();
            this.chartCtx.moveTo(padding, y);
            this.chartCtx.lineTo(width - padding, y);
            this.chartCtx.stroke();
        }
        
        // Draw equity curve
        this.chartCtx.strokeStyle = '#00ffff';
        this.chartCtx.lineWidth = 2;
        this.chartCtx.beginPath();
        
        this.equityData.forEach((point, index) => {
            const x = padding + (chartWidth / (this.equityData.length - 1)) * index;
            const y = padding + chartHeight - ((point.equity - minEquity) / range) * chartHeight;
            
            if (index === 0) {
                this.chartCtx.moveTo(x, y);
            } else {
                this.chartCtx.lineTo(x, y);
            }
        });
        
        this.chartCtx.stroke();
        
        // Draw labels
        this.chartCtx.fillStyle = '#00ffff';
        this.chartCtx.font = '10px Orbitron';
        this.chartCtx.fillText(`$${minEquity.toFixed(0)}`, 5, height - padding + 5);
        this.chartCtx.fillText(`$${maxEquity.toFixed(0)}`, 5, padding + 5);
    }

    addTrade(trade) {
        const tradesList = document.getElementById('tradesList');
        if (!tradesList) return;
        
        const emptyState = tradesList.querySelector('.empty-state');
        if (emptyState) emptyState.remove();
        
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
        
        while (tradesList.children.length > 50) {
            tradesList.removeChild(tradesList.lastChild);
        }
        
        const tradesCount = document.getElementById('tradesCount');
        if (tradesCount) {
            tradesCount.textContent = `${trade.total_trades} trades`;
        }
    }

    updateStats(data) {
        const equityEl = document.getElementById('realtimeEquity');
        const pnlEl = document.getElementById('realtimePnL');
        
        if (equityEl) equityEl.textContent = `$${data.equity.toFixed(2)}`;
        
        if (pnlEl) {
            const pnl = data.unrealized_pnl || 0;
            pnlEl.textContent = `${pnl >= 0 ? '+' : ''}$${pnl.toFixed(2)}`;
            pnlEl.className = pnl >= 0 ? 'pnl-positive' : 'pnl-negative';
        }
    }

    showNotification(message, type = 'info') {
        if (window.showNotification) {
            window.showNotification(message, type);
        } else {
            console.log(`[${type.toUpperCase()}] ${message}`);
        }
    }
}
