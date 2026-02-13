/**
 * Strategy Component
 * Handles strategy controls and status
 */

export class StrategyComponent {
    constructor() {
        this.isActive = false;
        this.statusInterval = null;
    }

    initialize() {
        const startBtn = document.getElementById('startBtn');
        const stopBtn = document.getElementById('stopBtn');
        
        if (startBtn) startBtn.addEventListener('click', () => this.start());
        if (stopBtn) stopBtn.addEventListener('click', () => this.stop());
        
        this.updateStatus();
        this.startStatusUpdates();
    }

    async start() {
        try {
            const threshold = parseFloat(document.getElementById('threshold')?.value || 0.15);
            const confidence = parseFloat(document.getElementById('confidence')?.value || 0.7);
            const balance = parseFloat(document.getElementById('balance')?.value || 1000);
            const category = document.getElementById('category')?.value || '21';

            const response = await fetch('/api/strategy/start', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
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
                this.isActive = true;
                this.updateStatusIndicator(true);
                this.showNotification('TRADING STARTED', 'success');
            } else {
                this.showNotification('ERROR: ' + data.error, 'error');
            }
        } catch (error) {
            console.error('[Strategy] Error starting:', error);
            this.showNotification('ERROR STARTING TRADING', 'error');
        }
    }

    async stop() {
        try {
            const response = await fetch('/api/strategy/stop', {
                method: 'POST'
            });

            const data = await response.json();

            if (response.ok) {
                document.getElementById('startBtn').disabled = false;
                document.getElementById('stopBtn').disabled = true;
                this.isActive = false;
                this.updateStatusIndicator(false);
                this.showNotification('TRADING STOPPED', 'info');
            } else {
                this.showNotification('ERROR: ' + data.error, 'error');
            }
        } catch (error) {
            console.error('[Strategy] Error stopping:', error);
            this.showNotification('ERROR STOPPING TRADING', 'error');
        }
    }

    async updateStatus() {
        try {
            const response = await fetch('/api/strategy/status');
            const data = await response.json();

            document.getElementById('balanceValue').textContent = '$' + data.balance.toFixed(2);
            document.getElementById('equityValue').textContent = '$' + data.equity.toFixed(2);
            document.getElementById('positionsValue').textContent = data.positions;
            document.getElementById('tradesValue').textContent = data.trades;
            document.getElementById('winRateValue').textContent = data.win_rate.toFixed(1) + '%';
            
            const pnlElement = document.getElementById('pnlValue');
            const pnl = data.profit || 0;
            pnlElement.textContent = '$' + pnl.toFixed(2);
            pnlElement.style.color = pnl >= 0 ? 'var(--neon-green)' : 'var(--neon-pink)';
        } catch (error) {
            console.error('[Strategy] Error updating status:', error);
        }
    }

    updateStatusIndicator(active) {
        const statusDot = document.getElementById('statusDot');
        const statusText = document.getElementById('statusText');

        if (statusDot && statusText) {
            if (active) {
                statusDot.classList.add('active');
                statusText.textContent = 'ONLINE';
            } else {
                statusDot.classList.remove('active');
                statusText.textContent = 'OFFLINE';
            }
        }
    }

    startStatusUpdates() {
        this.statusInterval = setInterval(() => this.updateStatus(), 2000);
    }

    stopStatusUpdates() {
        if (this.statusInterval) {
            clearInterval(this.statusInterval);
            this.statusInterval = null;
        }
    }

    showNotification(message, type = 'info') {
        // Use global notification system if available
        if (window.showNotification) {
            window.showNotification(message, type);
        } else {
            console.log(`[${type.toUpperCase()}] ${message}`);
        }
    }
}
