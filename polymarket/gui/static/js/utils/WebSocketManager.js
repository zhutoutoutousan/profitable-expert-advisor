/**
 * WebSocket Manager
 * Handles all WebSocket connections and events
 */

export class WebSocketManager {
    constructor(socket) {
        this.socket = socket;
        this.handlers = new Map();
        this.setup();
    }

    setup() {
        this.socket.on('connect', () => {
            console.log('[WebSocket] Connected to server');
        });

        this.socket.on('disconnect', () => {
            console.log('[WebSocket] Disconnected from server');
        });

        // Backtest events
        this.socket.on('backtest_log', (data) => {
            this.emit('backtest_log', data);
        });

        this.socket.on('backtest_trade', (data) => {
            this.emit('backtest_trade', data);
        });

        this.socket.on('backtest_equity', (data) => {
            this.emit('backtest_equity', data);
        });

        this.socket.on('backtest_complete', (data) => {
            this.emit('backtest_complete', data);
        });

        this.socket.on('backtest_error', (data) => {
            this.emit('backtest_error', data);
        });

        // Strategy events
        this.socket.on('strategy_update', (data) => {
            this.emit('strategy_update', data);
        });
    }

    on(event, handler) {
        if (!this.handlers.has(event)) {
            this.handlers.set(event, []);
        }
        this.handlers.get(event).push(handler);
    }

    off(event, handler) {
        if (this.handlers.has(event)) {
            const handlers = this.handlers.get(event);
            const index = handlers.indexOf(handler);
            if (index > -1) {
                handlers.splice(index, 1);
            }
        }
    }

    emit(event, data) {
        if (this.handlers.has(event)) {
            this.handlers.get(event).forEach(handler => handler(data));
        }
    }
}
