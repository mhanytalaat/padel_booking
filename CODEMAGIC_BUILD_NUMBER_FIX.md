# Fix Build Number Caching Issue in Codemagic

## Problem
Codemagic is caching build number 21 even though `pubspec.yaml` has version `1.1.2+23`.

## Solution: Add Pre-Build Script in Codemagic UI

Since you're using **Workflow Editor** for code signing (which works), add this script in the UI instead of YAML.

### Steps:

1. **Go to Codemagic** → Your app → **"Default Workflow"** → **Edit**

2. **Find "Build" section** → Look for **"Pre-build script"** or **"Scripts"** → **"Add script"**

3. **Add this script BEFORE the build step:**

```bash
#!/bin/bash
set -e
set -x

echo "=========================================="
echo "STEP 1: FIX BUILD NUMBER"
echo "=========================================="

# Extract version from pubspec.yaml
VERSION=$(grep "version:" pubspec.yaml | sed 's/version: //' | tr -d ' ')
VERSION_NAME=$(echo $VERSION | cut -d'+' -f1)
BUILD_NUMBER=$(echo $VERSION | cut -d'+' -f2)

echo "📦 Version from pubspec.yaml: $VERSION"
echo "   Version Name: $VERSION_NAME"
echo "   Build Number: $BUILD_NUMBER"

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

echo "✅ Generated.xcconfig created with build $BUILD_NUMBER"
cat ios/Flutter/Generated.xcconfig

# Verify the Info.plist will get correct values
echo ""
echo "=========================================="
echo "STEP 2: VERIFICATION"
echo "=========================================="
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" ios/Runner/Info.plist 2>/dev/null || echo "\$(PRODUCT_BUNDLE_IDENTIFIER)")
VERSION_KEY=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" ios/Runner/Info.plist)
BUILD_KEY=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" ios/Runner/Info.plist)

echo "📋 Bundle ID: $BUNDLE_ID"
echo "📋 Version Key: $VERSION_KEY (will be: $VERSION_NAME)"
echo "📋 Build Key: $BUILD_KEY (will be: $BUILD_NUMBER)"

# Verify CODE_SIGN_STYLE (don't fail if not found)
echo ""
echo "=========================================="
echo "STEP 3: VERIFY CODE SIGNING"
echo "=========================================="
cd ios
SIGN_STYLE=$(xcodebuild -showBuildSettings 2>/dev/null | grep "CODE_SIGN_STYLE" | head -1 || echo "CODE_SIGN_STYLE not found")
echo "🔐 Code Signing: $SIGN_STYLE"

# Check if it's Automatic (expected)
if echo "$SIGN_STYLE" | grep -q "Automatic"; then
  echo "   ✅ Automatic signing configured (correct)"
elif echo "$SIGN_STYLE" | grep -q "Manual"; then
  echo "   ⚠️  Manual signing detected (should be Automatic for Codemagic)"
else
  echo "   ℹ️  Unable to determine signing style (will use Codemagic defaults)"
fi

cd ..

# Prepare Spark API dart-defines for Flutter build
echo ""
echo "=========================================="
echo "STEP 4: SPARK DART-DEFINES"
echo "=========================================="
if [ -n "${SPARK_API_KEY:-}" ]; then
  FLUTTER_DART_DEFINES="--dart-define=SPARK_API_KEY=$SPARK_API_KEY"
  [ -n "${SPARK_BASE_URL:-}" ] && FLUTTER_DART_DEFINES="$FLUTTER_DART_DEFINES --dart-define=SPARK_BASE_URL=$SPARK_BASE_URL"
  [ -n "${SPARK_BEARER_TOKEN:-}" ] && FLUTTER_DART_DEFINES="$FLUTTER_DART_DEFINES --dart-define=SPARK_BEARER_TOKEN=$SPARK_BEARER_TOKEN"
  export FLUTTER_DART_DEFINES
  echo "✅ Spark dart-defines prepared (API key + optional Bearer)"
else
  export FLUTTER_DART_DEFINES=""
  echo "⚠️  SPARK_API_KEY not set - Spark sync will be disabled in app"
fi

echo ""
echo "=========================================="
echo "✅ PRE-BUILD CHECKS COMPLETE"
echo "=========================================="
```

4. **In "Build arguments"** (Flutter build section), use:
   ```
   --release --build-name=$FLUTTER_BUILD_NAME --build-number=$FLUTTER_BUILD_NUMBER $FLUTTER_DART_DEFINES
   ```
   Ensure SPARK_API_KEY is set in Codemagic → Environment variables (SPARK_BEARER_TOKEN and SPARK_BASE_URL optional).

5. **Keep your existing UI settings:**
   - ✅ iOS code signing: Enabled
   - ✅ App Store Connect: Enabled
   - ✅ All other distribution settings

6. **Save and rebuild**

## Alternative: Use the fix_build_number.sh script

I've created `fix_build_number.sh` in your project. You can:
1. Upload it to Codemagic
2. Reference it in the pre-build script: `bash fix_build_number.sh`

## Why This Works

- Pre-build script runs BEFORE the build
- It fixes `Generated.xcconfig` with the correct build number
- Your UI settings for code signing remain unchanged
- No YAML conflicts

## Verification

After building, check the logs for:
- "FIXING BUILD NUMBER"
- "Build number: 23" (should match your pubspec.yaml)
- The build should succeed with code signing
