# Fix Codemagic Build Configuration

## The Problem

Your Codemagic build configuration has **flavor arguments that don't exist**:
- `--flavor ios-production -t lib/main_prod.dart` ❌
- `--flavor android-production -t lib/main_prod.dart` ❌

These files don't exist in your project, causing build failures.

## Solution: Update Codemagic Build Settings

### Option 1: Use codemagic.yaml (Recommended)

The `codemagic.yaml` file is already created and configured correctly. Make sure Codemagic is using it:

1. Go to **Codemagic** → Your App → **Settings**
2. Find **"Configuration source"** or **"Build configuration"**
3. Select **"Use codemagic.yaml"** (not "Use UI configuration")
4. Save

### Option 2: Fix UI Configuration

If you want to use UI configuration instead:

1. Go to **Build settings** in Codemagic
2. Find **"Build arguments"** section
3. **Remove** the flavor arguments:

   **For iOS:**
   - Change from: `--debug --flavor ios-production -t lib/main_prod.dart`
   - To: `--release` (for TestFlight) or `--debug` (for testing)

   **For Android:**
   - Change from: `--debug --flavor android-production -t lib/main_prod.dart`
   - To: `--release` (for Google Play) or `--debug` (for testing)

4. **Mode**: Select **"Release"** for production builds
5. Save

## Correct Build Arguments

### iOS (for TestFlight):
```
--release
```

### Android (for Google Play):
```
--release
```

### For Testing/Debug:
```
--debug
```

## What the codemagic.yaml Does

- ✅ Uses `flutter build ipa --release` (handles scheme automatically)
- ✅ Uses `flutter build appbundle --release` (for Android)
- ✅ No flavor arguments (since you don't have flavors configured)
- ✅ Proper CocoaPods installation

## Next Steps

1. **Either**: Use the `codemagic.yaml` file (select it in Codemagic settings)
2. **Or**: Update UI configuration to remove flavor arguments
3. **Build again** - should work now!

The scheme error will be fixed because `flutter build ipa` handles schemes automatically, unlike `xcodebuild` which requires explicit scheme specification.
