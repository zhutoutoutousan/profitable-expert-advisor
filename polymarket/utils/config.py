"""
Configuration Management

Loads configuration from environment variables or config file.
"""

import os
from typing import Optional
from dotenv import load_dotenv

load_dotenv()


class Config:
    """Configuration class for Polymarket framework"""
    
    # API Configuration
    PRIVATE_KEY: Optional[str] = os.getenv('POLYMARKET_PRIVATE_KEY')
    CHAIN_ID: int = int(os.getenv('POLYMARKET_CHAIN_ID', '137'))
    SIGNATURE_TYPE: int = int(os.getenv('POLYMARKET_SIGNATURE_TYPE', '0'))
    FUNDER_ADDRESS: Optional[str] = os.getenv('POLYMARKET_FUNDER_ADDRESS')
    
    # API Keys (for authenticated endpoints)
    GAMMA_API_KEY: Optional[str] = os.getenv('POLYMARKET_GAMMA_API_KEY')
    CLOB_API_KEY: Optional[str] = os.getenv('POLYMARKET_CLOB_API_KEY')
    DATA_API_KEY: Optional[str] = os.getenv('POLYMARKET_DATA_API_KEY')
    
    # Trading Configuration
    DEFAULT_INITIAL_BALANCE: float = float(os.getenv('POLYMARKET_INITIAL_BALANCE', '1000.0'))
    MAX_POSITION_SIZE: float = float(os.getenv('POLYMARKET_MAX_POSITION_SIZE', '0.5'))
    MAX_TOTAL_EXPOSURE: float = float(os.getenv('POLYMARKET_MAX_TOTAL_EXPOSURE', '0.8'))
    
    # Rate Limiting
    REQUEST_DELAY: float = float(os.getenv('POLYMARKET_REQUEST_DELAY', '0.1'))  # 100ms between requests
    MAX_REQUESTS_PER_MINUTE: int = int(os.getenv('POLYMARKET_MAX_REQUESTS_PER_MINUTE', '60'))
    
    # Backtesting
    BACKTEST_START_DATE: Optional[str] = os.getenv('POLYMARKET_BACKTEST_START_DATE')
    BACKTEST_END_DATE: Optional[str] = os.getenv('POLYMARKET_BACKTEST_END_DATE')
    
    @classmethod
    def validate(cls) -> bool:
        """Validate that required configuration is present"""
        if not cls.PRIVATE_KEY:
            print("Warning: POLYMARKET_PRIVATE_KEY not set")
            return False
        if not cls.FUNDER_ADDRESS:
            print("Warning: POLYMARKET_FUNDER_ADDRESS not set")
            return False
        return True
