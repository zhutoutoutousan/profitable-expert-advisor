/**
 * Markets Component
 * Handles market data fetching and display
 */

export class MarketsComponent {
    constructor(containerId) {
        this.container = document.getElementById(containerId);
        this.markets = [];
        this.updateInterval = null;
    }

    async load() {
        try {
            console.log('[Markets] Loading markets from API...');
            
            // Show loading state
            if (this.container) {
                this.container.innerHTML = '<div class="empty-state">LOADING MARKETS...</div>';
            }
            
            const response = await fetch('/api/markets');
            
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
            
            const data = await response.json();
            
            console.log('[Markets] API response:', data);
            console.log('[Markets] Markets count:', data.markets ? data.markets.length : 0);
            
            if (data.markets && Array.isArray(data.markets)) {
                this.markets = data.markets;
                console.log('[Markets] Rendering', this.markets.length, 'markets');
                this.render();
            } else {
                console.error('[Markets] Invalid markets data:', data);
                this.showError('Invalid data format: ' + JSON.stringify(data).substring(0, 100));
            }
        } catch (error) {
            console.error('[Markets] Error loading markets:', error);
            this.showError('Failed to load markets: ' + error.message);
        }
    }

    render() {
        if (!this.container) return;
        
        if (this.markets.length === 0) {
            this.container.innerHTML = '<div class="empty-state">NO ACTIVE MARKETS</div>';
            return;
        }

        this.container.innerHTML = this.markets.map(market => {
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
    }

    showError(message) {
        if (this.container) {
            this.container.innerHTML = `<div class="empty-state">${message}</div>`;
        }
    }

    startAutoRefresh(interval = 30000) {
        this.updateInterval = setInterval(() => this.load(), interval);
    }

    stopAutoRefresh() {
        if (this.updateInterval) {
            clearInterval(this.updateInterval);
            this.updateInterval = null;
        }
    }
}
