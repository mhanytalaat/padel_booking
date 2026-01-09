#!/bin/bash
set -e

echo "🔧 Setting up iOS build environment..."

# Navigate to iOS directory
cd ios

# Clean previous pod installations
echo "🧹 Cleaning previous CocoaPods installation..."
rm -rf Pods
rm -rf Podfile.lock
rm -rf .symlinks
rm -rf Flutter/Flutter.framework
rm -rf Flutter/Flutter.podspec
rm -rf ~/Library/Caches/CocoaPods
rm -rf ~/Library/Developer/Xcode/DerivedData/*

# Update CocoaPods repo
echo "📦 Updating CocoaPods repository..."
pod repo update || true

# Install pods with verbose output for debugging
echo "📥 Installing CocoaPods dependencies..."
pod install --repo-update --verbose

# Verify installation
if [ -d "Pods" ]; then
  echo "✅ CocoaPods installation completed successfully!"
else
  echo "❌ CocoaPods installation failed!"
  exit 1
fi
