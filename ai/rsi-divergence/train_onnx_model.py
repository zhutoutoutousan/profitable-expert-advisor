"""
ONNX Model Training Script for RSI Divergence Classification
Trains a neural network to identify genuine RSI divergences and exports to ONNX format.
"""

import argparse
import os
import sys
import numpy as np
import pandas as pd
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers
from sklearn.preprocessing import MinMaxScaler, LabelEncoder
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix
import tf2onnx
import onnx
import pickle
from tqdm import tqdm


class RSIDivergenceTrainer:
    """
    Trainer class for creating ONNX models to classify RSI divergences.
    """
    
    def __init__(self, lookback: int = 60, num_classes: int = 5):
        """
        Initialize the trainer.
        
        Args:
            lookback: Number of bars to look back for prediction
            num_classes: Number of divergence classes (5: NONE + 4 divergence types)
        """
        self.lookback = lookback
        self.num_classes = num_classes
        self.scaler = MinMaxScaler()
        self.label_encoder = LabelEncoder()
        self.model = None
    
    def load_data(self, data_path: str) -> tuple:
        """
        Load labeled data from CSV file.
        
        Args:
            data_path: Path to labeled CSV file
        
        Returns:
            Tuple of (X, y) where X is features and y is labels
        """
        print(f"Loading data from {data_path}...")
        df = pd.read_csv(data_path, index_col=0, parse_dates=True)
        
        # Exclude label columns from features
        exclude_cols = ['divergence_type', 'divergence_confidence', 'divergence_strength']
        feature_cols = [col for col in df.columns if col not in exclude_cols]
        
        # Remove any remaining non-numeric columns
        feature_cols = [col for col in feature_cols if df[col].dtype in [np.float64, np.int64, np.float32, np.int32]]
        
        print(f"Using {len(feature_cols)} features: {feature_cols[:10]}...")
        
        # Prepare sequences
        X, y = [], []
        
        for i in range(self.lookback, len(df)):
            # Get feature sequence
            X.append(df[feature_cols].iloc[i - self.lookback:i].values)
            
            # Get label (divergence type at current bar)
            y.append(int(df['divergence_type'].iloc[i]))
        
        X = np.array(X)
        y = np.array(y)
        
        print(f"Created {len(X)} sequences")
        print(f"Label distribution: {np.bincount(y)}")
        
        return X, y, feature_cols
    
    def prepare_data(self, X: np.ndarray, y: np.ndarray) -> tuple:
        """
        Prepare and scale data for training.
        
        Args:
            X: Feature sequences
            y: Labels
        
        Returns:
            Tuple of (X_scaled, y_encoded, X_train, X_test, y_train, y_test)
        """
        # Scale features
        print("Scaling features...")
        original_shape = X.shape
        X_reshaped = X.reshape(-1, X.shape[-1])
        X_scaled = self.scaler.fit_transform(X_reshaped)
        X_scaled = X_scaled.reshape(original_shape)
        
        # Encode labels (already integers, but ensure they're 0-4)
        y_encoded = y.astype(int)
        
        # Split data (no shuffle to preserve temporal order)
        X_train, X_test, y_train, y_test = train_test_split(
            X_scaled, y_encoded, test_size=0.2, shuffle=False
        )
        
        print(f"Training samples: {len(X_train)}")
        print(f"Test samples: {len(X_test)}")
        
        return X_scaled, y_encoded, X_train, X_test, y_train, y_test
    
    def build_model(self, input_shape: tuple) -> keras.Model:
        """
        Build the neural network model for classification.
        
        Args:
            input_shape: Shape of input data (lookback, features)
        
        Returns:
            Compiled Keras model
        """
        model = keras.Sequential([
            # LSTM layers for sequence learning
            layers.LSTM(128, return_sequences=True, input_shape=input_shape),
            layers.Dropout(0.3),
            layers.LSTM(64, return_sequences=True),
            layers.Dropout(0.3),
            layers.LSTM(32),
            layers.Dropout(0.3),
            
            # Dense layers for classification
            layers.Dense(64, activation='relu'),
            layers.Dropout(0.2),
            layers.Dense(32, activation='relu'),
            layers.Dropout(0.2),
            layers.Dense(self.num_classes, activation='softmax')  # Multi-class classification
        ])
        
        model.compile(
            optimizer=keras.optimizers.Adam(learning_rate=0.001),
            loss='sparse_categorical_crossentropy',
            metrics=['accuracy']
        )
        
        return model
    
    def train(self, X_train: np.ndarray, y_train: np.ndarray,
              X_test: np.ndarray, y_test: np.ndarray,
              epochs: int = 50, batch_size: int = 32, verbose: int = 1):
        """
        Train the model.
        
        Args:
            X_train: Training features
            y_train: Training labels
            X_test: Test features
            y_test: Test labels
            epochs: Number of training epochs
            batch_size: Batch size for training
            verbose: Verbosity level
        """
        # Build model
        self.model = self.build_model((X_train.shape[1], X_train.shape[2]))
        
        print("\nModel architecture:")
        self.model.summary()
        
        # Handle class imbalance with class weights
        from sklearn.utils.class_weight import compute_class_weight
        class_weights = compute_class_weight(
            'balanced',
            classes=np.unique(y_train),
            y=y_train
        )
        class_weight_dict = {i: weight for i, weight in enumerate(class_weights)}
        
        print(f"\nClass weights: {class_weight_dict}")
        
        # Train model
        print("\nTraining model...")
        history = self.model.fit(
            X_train, y_train,
            batch_size=batch_size,
            epochs=epochs,
            validation_data=(X_test, y_test),
            verbose=verbose,
            class_weight=class_weight_dict,
            callbacks=[
                keras.callbacks.EarlyStopping(
                    monitor='val_loss',
                    patience=15,
                    restore_best_weights=True,
                    verbose=1
                ),
                keras.callbacks.ReduceLROnPlateau(
                    monitor='val_loss',
                    factor=0.5,
                    patience=5,
                    min_lr=0.0001,
                    verbose=1
                )
            ]
        )
        
        # Evaluate
        train_loss, train_acc = self.model.evaluate(X_train, y_train, verbose=0)
        test_loss, test_acc = self.model.evaluate(X_test, y_test, verbose=0)
        
        print(f"\nTraining - Loss: {train_loss:.4f}, Accuracy: {train_acc:.4f}")
        print(f"Test - Loss: {test_loss:.4f}, Accuracy: {test_acc:.4f}")
        
        # Classification report
        y_pred = self.model.predict(X_test, verbose=0)
        y_pred_classes = np.argmax(y_pred, axis=1)
        
        print("\nClassification Report:")
        print(classification_report(y_test, y_pred_classes, 
              target_names=['NONE', 'REGULAR_BULLISH', 'REGULAR_BEARISH', 
                          'HIDDEN_BULLISH', 'HIDDEN_BEARISH']))
        
        return history
    
    def export_to_onnx(self, output_path: str, num_features: int):
        """
        Export the trained model to ONNX format.
        
        Args:
            output_path: Path to save ONNX model
            num_features: Number of input features
        """
        if self.model is None:
            raise ValueError("Model must be trained before exporting")
        
        print(f"\nExporting model to ONNX format: {output_path}")
        
        # Create functional model from Sequential
        input_layer = keras.Input(shape=(self.lookback, num_features), name="input")
        x = input_layer
        
        # Rebuild model as functional
        for layer in self.model.layers:
            x = layer(x)
        
        functional_model = keras.Model(inputs=input_layer, outputs=x)
        
        # Convert to ONNX
        spec = (tf.TensorSpec((None, self.lookback, num_features), tf.float32, name="input"),)
        
        try:
            onnx_model_proto, _ = tf2onnx.convert.from_keras(
                functional_model,
                input_signature=spec,
                opset=13
            )
            
            onnx.save_model(onnx_model_proto, output_path)
            print(f"ONNX model saved to: {output_path}")
            
            # Verify ONNX model
            onnx_model = onnx.load(output_path)
            onnx.checker.check_model(onnx_model)
            print("ONNX model validation passed")
            
        except Exception as e:
            raise RuntimeError(f"Failed to export ONNX model: {str(e)}")
    
    def save_scaler(self, output_path: str):
        """Save the scaler for consistent normalization."""
        with open(output_path, 'wb') as f:
            pickle.dump(self.scaler, f)
        print(f"Scaler saved to: {output_path}")


def main():
    """Main function."""
    parser = argparse.ArgumentParser(description='Train ONNX model for RSI divergence classification')
    parser.add_argument('--data', type=str, required=True, 
                       help='Path to labeled CSV data file')
    parser.add_argument('--lookback', type=int, default=60, 
                       help='Number of bars to look back')
    parser.add_argument('--epochs', type=int, default=50, help='Training epochs')
    parser.add_argument('--batch-size', type=int, default=32, help='Batch size')
    parser.add_argument('--output', type=str, default='models', 
                       help='Output directory for ONNX model')
    
    args = parser.parse_args()
    
    # Create output directory
    os.makedirs(args.output, exist_ok=True)
    
    # Create trainer
    trainer = RSIDivergenceTrainer(lookback=args.lookback)
    
    try:
        # Load data
        X, y, feature_cols = trainer.load_data(args.data)
        
        # Prepare data
        X_scaled, y_encoded, X_train, X_test, y_train, y_test = trainer.prepare_data(X, y)
        
        # Train model
        trainer.train(X_train, y_train, X_test, y_test, 
                     epochs=args.epochs, batch_size=args.batch_size)
        
        # Export to ONNX
        num_features = len(feature_cols)
        model_name = "BTCUSD_H1_rsi_divergence_model.onnx"
        output_path = os.path.join(args.output, model_name)
        trainer.export_to_onnx(output_path, num_features)
        
        # Save scaler
        scaler_name = "BTCUSD_H1_rsi_divergence_scaler.pkl"
        scaler_path = os.path.join(args.output, scaler_name)
        trainer.save_scaler(scaler_path)
        
        # Save feature list
        features_name = "BTCUSD_H1_rsi_divergence_features.pkl"
        features_path = os.path.join(args.output, features_name)
        with open(features_path, 'wb') as f:
            pickle.dump(feature_cols, f)
        print(f"Feature list saved to: {features_path}")
        
        print(f"\n{'='*60}")
        print("Training completed successfully!")
        print(f"ONNX model saved to: {output_path}")
        print(f"{'='*60}\n")
        
    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
