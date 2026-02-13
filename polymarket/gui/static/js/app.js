/**
 * Main Application Entry Point
 * Initializes all components and manages the application lifecycle
 */

import { MarketsComponent } from './components/MarketsComponent.js';
import { StrategyComponent } from './components/StrategyComponent.js';
import { PositionsComponent } from './components/PositionsComponent.js';
import { BacktestComponent } from './components/BacktestComponent.js';
import { Notification } from './utils/Notification.js';
import { WebSocketManager } from './utils/WebSocketManager.js';

class App {
    constructor() {
        this.components = {};
        this.wsManager = null;
    }

    async initialize() {
        console.log('[App] Initializing application...');

        // Initialize WebSocket
        if (window.io) {
            this.wsManager = new WebSocketManager(io());
            this.setupWebSocketHandlers();
        }

        // Initialize components
        this.components.markets = new MarketsComponent('marketsList');
        this.components.strategy = new StrategyComponent();
        this.components.positions = new PositionsComponent('positionsList');
        this.components.backtest = new BacktestComponent();

        // Initialize controls
        this.initializeControls();

        // Load initial data
        try {
            await this.components.markets.load();
            this.components.markets.startAutoRefresh(30000);
        } catch (error) {
            console.error('[App] Error loading markets:', error);
            if (this.components.markets.container) {
                this.components.markets.showError('Failed to load markets. Check console for details.');
            }
        }

        this.components.strategy.initialize();
        this.components.positions.load();
        this.components.backtest.initialize();

        // Start position updates
        setInterval(() => this.components.positions.load(), 5000);

        console.log('[App] Application initialized');
    }

    initializeControls() {
        // Threshold and confidence sliders
        const threshold = document.getElementById('threshold');
        const confidence = document.getElementById('confidence');
        const thresholdValue = document.getElementById('thresholdValue');
        const confidenceValue = document.getElementById('confidenceValue');

        if (threshold && thresholdValue) {
            threshold.addEventListener('input', (e) => {
                thresholdValue.textContent = parseFloat(e.target.value).toFixed(2);
            });
        }

        if (confidence && confidenceValue) {
            confidence.addEventListener('input', (e) => {
                confidenceValue.textContent = parseFloat(e.target.value).toFixed(2);
            });
        }
    }

    setupWebSocketHandlers() {
        if (!this.wsManager) return;

        // Backtest handlers
        this.wsManager.on('backtest_log', (data) => {
            this.components.backtest.addTerminalLine(data.message, data.type || 'info');
        });

        this.wsManager.on('backtest_trade', (data) => {
            this.components.backtest.addTrade(data);
            this.components.backtest.updateStats(data);
        });

        this.wsManager.on('backtest_equity', (data) => {
            this.components.backtest.updateChart(data);
            this.components.backtest.updateStats(data);
        });

        this.wsManager.on('backtest_complete', (data) => {
            this.components.backtest.displayResults(data);
            const btn = document.getElementById('runBacktestBtn');
            if (btn) {
                btn.disabled = false;
                btn.innerHTML = '<span>▶ RUN BACKTEST</span>';
            }
            this.components.backtest.isRunning = false;
        });

        this.wsManager.on('backtest_error', (data) => {
            this.components.backtest.addTerminalLine('ERROR: ' + data.error, 'error');
            Notification.show('BACKTEST ERROR: ' + data.error, 'error');
            const btn = document.getElementById('runBacktestBtn');
            if (btn) {
                btn.disabled = false;
                btn.innerHTML = '<span>▶ RUN BACKTEST</span>';
            }
            document.getElementById('backtestStatus').style.display = 'none';
            this.components.backtest.isRunning = false;
        });

        // Strategy handlers
        this.wsManager.on('strategy_update', (data) => {
            document.getElementById('balanceValue').textContent = '$' + data.balance.toFixed(2);
            document.getElementById('equityValue').textContent = '$' + data.equity.toFixed(2);
            document.getElementById('positionsValue').textContent = data.positions;
            document.getElementById('tradesValue').textContent = data.trades;
        });
    }
}

// Initialize app when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    const app = new App();
    app.initialize();
    window.app = app; // Make available globally for debugging
});
