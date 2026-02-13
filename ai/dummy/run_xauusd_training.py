"""
Quick script to train XAUUSD ONNX model

Run this to train a model for XAUUSD.
After training, you can use the model for backtesting or live trading.
"""

import sys
import os

# Ensure we're in the right directory
os.chdir(os.path.dirname(os.path.abspath(__file__)))

# Train the model
print("Training XAUUSD ONNX model...")
print("This will take several minutes...\n")

os.system('python train_onnx_model.py --symbol XAUUSD --timeframe H1 --lookback 60 --epochs 30 --batch-size 32')

print("\nTraining completed! Model saved to models/XAUUSD_H1_model.onnx")
print("Scaler saved to models/XAUUSD_H1_scaler.pkl")
