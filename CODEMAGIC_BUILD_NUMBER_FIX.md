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
# Fix build number from pubspec.yaml
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

# Clear cached Generated.xcconfig
rm -f ios/Flutter/Generated.xcconfig

# Create new Generated.xcconfig with correct build number
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
```

4. **In "Build arguments"**, make sure you have:
   - `--release --build-name=$FLUTTER_BUILD_NAME --build-number=$FLUTTER_BUILD_NUMBER`
   
   OR just:
   - `--release`
   
   (The environment variables will be picked up automatically)

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
