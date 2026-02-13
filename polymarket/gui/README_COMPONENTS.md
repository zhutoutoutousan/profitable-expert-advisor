# Component Architecture

The GUI has been refactored into a modular component-based architecture to prevent code bloat.

## Frontend Components

### `/static/js/components/`
- **MarketsComponent.js** - Market data fetching and display
- **StrategyComponent.js** - Strategy controls and status
- **PositionsComponent.js** - Position display
- **BacktestComponent.js** - Backtesting functionality

### `/static/js/utils/`
- **Notification.js** - Global notification system
- **WebSocketManager.js** - WebSocket event management

### `/static/js/app.js`
- Main application entry point
- Initializes all components
- Manages component lifecycle

## Backend Blueprints

### `/api/`
- **markets.py** - Market data endpoints
- **strategy.py** - Strategy control endpoints
- **backtest.py** - Backtesting endpoints
- **__init__.py** - Blueprint registration

## Benefits

1. **Separation of Concerns** - Each component handles one responsibility
2. **Reusability** - Components can be reused across different views
3. **Maintainability** - Easier to find and fix bugs
4. **Testability** - Components can be tested independently
5. **Scalability** - Easy to add new features without bloating existing code

## Usage

The app automatically loads all components on startup. Each component manages its own state and updates.
