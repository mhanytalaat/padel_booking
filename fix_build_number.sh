#!/bin/bash
# Script to fix build number in Codemagic
# Add this as a pre-build script in Codemagic UI

# Extract version from pubspec.yaml
VERSION=$(grep "version:" pubspec.yaml | sed 's/version: //' | tr -d ' ')
VERSION_NAME=$(echo $VERSION | cut -d'+' -f1)
BUILD_NUMBER=$(echo $VERSION | cut -d'+' -f2)

echo "=========================================="
echo "FIXING BUILD NUMBER"
echo "=========================================="
echo "Version from pubspec.yaml: $VERSION"
echo "Version name: $VERSION_NAME"
echo "Build number: $BUILD_NUMBER"
echo "=========================================="

# Set environment variables
export FLUTTER_BUILD_NAME="$VERSION_NAME"
export FLUTTER_BUILD_NUMBER="$BUILD_NUMBER"

# Force recreate Generated.xcconfig
rm -f ios/Flutter/Generated.xcconfig
mkdir -p ios/Flutter
cat > ios/Flutter/Generated.xcconfig << EOF
// This is a generated file; do not edit.
FLUTTER_ROOT=\$(PROJECT_DIR)/../Flutter
FLUTTER_APPLICATION_PATH=\$(PROJECT_DIR)/..
FLUTTER_TARGET=lib/main.dart
FLUTTER_BUILD_DIR=build
SYMROOT=\$(SOURCE_ROOT)/../build/ios
FLUTTER_BUILD_NAME=$VERSION_NAME
FLUTTER_BUILD_NUMBER=$BUILD_NUMBER
EOF

echo "Generated.xcconfig created:"
cat ios/Flutter/Generated.xcconfig

echo "=========================================="
echo "Build number fixed to: $BUILD_NUMBER"
echo "=========================================="
