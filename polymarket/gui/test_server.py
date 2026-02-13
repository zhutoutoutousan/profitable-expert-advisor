"""Test server startup"""
import sys
from pathlib import Path

# Add paths
gui_dir = Path(__file__).parent
project_root = gui_dir.parent.parent
sys.path.insert(0, str(project_root))

print("Testing imports...")
try:
    from polymarket.api import GammaClient, ClobClient
    print("✓ API imports OK")
except Exception as e:
    print(f"✗ API import failed: {e}")
    sys.exit(1)

try:
    from polymarket.strategies.examples import SimpleProbabilityStrategy
    print("✓ Strategy imports OK")
except Exception as e:
    print(f"✗ Strategy import failed: {e}")
    sys.exit(1)

try:
    from flask import Flask
    print("✓ Flask import OK")
except Exception as e:
    print(f"✗ Flask import failed: {e}")
    sys.exit(1)

print("\nAll imports successful! Starting server...")
print("=" * 60)
