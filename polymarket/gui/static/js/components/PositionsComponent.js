/**
 * Positions Component
 * Handles position display and updates
 */

export class PositionsComponent {
    constructor(containerId) {
        this.container = document.getElementById(containerId);
        this.positions = [];
    }

    async load() {
        try {
            const response = await fetch('/api/strategy/positions');
            const data = await response.json();
            this.positions = data.positions || [];
            this.render();
        } catch (error) {
            console.error('[Positions] Error loading positions:', error);
            this.showError('Failed to load positions');
        }
    }

    render() {
        if (!this.container) return;

        if (this.positions.length === 0) {
            this.container.innerHTML = '<div class="empty-state">NO OPEN POSITIONS</div>';
            return;
        }

        this.container.innerHTML = this.positions.map(pos => {
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

    showError(message) {
        if (this.container) {
            this.container.innerHTML = `<div class="empty-state">${message}</div>`;
        }
    }
}
