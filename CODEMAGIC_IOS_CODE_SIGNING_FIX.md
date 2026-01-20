# Codemagic iOS Code Signing - Complete Troubleshooting Guide

## Problem Summary
iOS builds were failing with error: "No valid code signing certificates were found"

## Root Cause
- Certificates and provisioning profiles existed in Codemagic account
- But Codemagic wasn't automatically using them during builds
- Build arguments had invalid flavor references
- YAML configuration wasn't working for personal accounts (no groups available)

## Solution: Use Codemagic Workflow Editor

### Step 1: Fix Build Arguments
In Codemagic Workflow Editor → Build section:

**iOS Build Arguments:**
- ❌ **Wrong:** `--release --flavor ios-production -t lib/main_prod.dart`
- ✅ **Correct:** `--release`

**Android Build Arguments:**
- ❌ **Wrong:** `--release --flavor android-production -t lib/main_prod.dart`
- ✅ **Correct:** `--release`

**Web Build Arguments:**
- ❌ **Wrong:** `--release -t lib/main_prod.dart`
- ✅ **Correct:** `--release`

### Step 2: Enable iOS Code Signing
1. Go to Codemagic Workflow Editor
2. Scroll to **Distribution** section
3. Find **"iOS code signing[enabled]"**
4. Click on it to configure (if needed)
5. Codemagic will automatically use certificates from your account:
   - Certificate: `app_store_cert` (App Store Distribution)
   - Provisioning Profile: `Padelcore_provisioning` (for `com.padelcore.app`)

### Step 3: Verify Certificates in Codemagic
In Codemagic → Settings → Code signing identities:

**iOS Certificates:**
- ✅ `app_store_cert`
- Type: production (App Store Distribution)
- Team: Mohamed Hany Talaat
- Expires: January 09, 2027

**iOS Provisioning Profiles:**
- ✅ `Padelcore_provisioning`
- Type: app_store
- Team: Mohamed Hany Talaat
- Bundle ID: `com.padelcore.app`
- Expires: January 09, 2027

## What We Tried (That Didn't Work)

### Attempt 1: YAML Configuration with Groups
- **Issue:** Personal accounts don't have access to groups
- **Error:** "Group is required" when trying to add environment variables

### Attempt 2: API Key in YAML
- **Issue:** Codemagic wasn't using API key for automatic certificate fetching
- **Problem:** API key is only needed for TestFlight publishing, not code signing

### Attempt 3: xcode-project Configuration
- **Issue:** `xcode-project` is not a valid field in `environment` section
- **Error:** "extra fields not permitted"

### Attempt 4: Manual Certificate Installation Scripts
- **Issue:** Certificates weren't available in build environment
- **Problem:** Codemagic needs to automatically set them up

## Final Working Configuration

### codemagic.yaml (Minimal)
```yaml
workflows:
  ios-workflow:
    name: iOS Workflow
    max_build_duration: 120
    instance_type: mac_mini_m1
    environment:
      flutter: stable
      xcode: latest
      cocoapods: default
    scripts:
      - name: Get Flutter dependencies
        script: |
          flutter pub get
      - name: Install CocoaPods dependencies
        script: |
          cd ios
          pod install
          cd ..
      - name: Build iOS IPA
        script: |
          flutter build ipa --release
    artifacts:
      - build/ios/ipa/*.ipa
    publishing:
      email:
        recipients:
          - mhanytalaat@icloud.com
        notify:
          success: true
          failure: true
```

### Workflow Editor Settings
- **Build Arguments (iOS):** `--release` (no flavors)
- **iOS Code Signing:** Enabled
- **App Store Connect:** Enabled (for TestFlight publishing)
- **Mode:** Release

## Key Learnings

1. **Workflow Editor vs YAML:**
   - For personal accounts, Workflow Editor is easier for code signing
   - YAML works better for teams with groups

2. **Build Arguments:**
   - Don't use flavors (`--flavor`) unless you've configured them
   - Simple `--release` is enough for standard builds

3. **Code Signing:**
   - Certificates must be in Codemagic account first
   - Codemagic automatically uses them when "iOS code signing" is enabled
   - No need for API key for code signing (only for TestFlight publishing)

4. **Certificate Management:**
   - Use "Get certificates from Apple Developer Portal" in Codemagic
   - Or upload `.p12` certificate and `.mobileprovision` file manually
   - Certificates are automatically linked to builds when enabled

## Troubleshooting Checklist

If iOS builds fail with "No valid code signing certificates":

1. ✅ Check certificates exist in Codemagic → Code signing identities
2. ✅ Verify provisioning profile matches bundle ID (`com.padelcore.app`)
3. ✅ Ensure "iOS code signing" is enabled in Workflow Editor
4. ✅ Fix build arguments (remove invalid flavors)
5. ✅ Check certificate hasn't expired
6. ✅ Verify bundle ID matches in Xcode project and Codemagic

## Current Status

✅ **iOS builds are now working!**
- Certificate: `app_store_cert` (App Store Distribution)
- Provisioning Profile: `Padelcore_provisioning`
- Bundle ID: `com.padelcore.app`
- Build Command: `flutter build ipa --release`

## Next Steps

1. **TestFlight Publishing:**
   - Configure App Store Connect API key if you want automatic TestFlight uploads
   - Or manually upload IPA from build artifacts

2. **Version Management:**
   - Update version in `pubspec.yaml` before each new build
   - Update `android/app/build.gradle.kts` versionCode and versionName
   - iOS version is read from `pubspec.yaml`

3. **Android Builds:**
   - Similar process - ensure Android keystore is configured
   - Use Workflow Editor for easier configuration

---

**Date:** January 10, 2026
**Status:** ✅ Resolved - iOS builds working with Workflow Editor configuration
