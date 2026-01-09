# iOS TestFlight Crash Troubleshooting Guide

## Step 1: Get Crash Logs from App Store Connect

1. Go to **App Store Connect** → Your App → **TestFlight** → **Crashes**
2. Download the crash logs for the 9 crashes
3. Look for the **exception type** and **stack trace** - this will tell you exactly what's failing

## Step 2: Common iOS Crash Causes & Fixes

### 1. Missing GoogleService-Info.plist
**Symptom**: App crashes immediately on launch with Firebase errors

**Fix**:
- Ensure `ios/Runner/GoogleService-Info.plist` exists
- Download it from Firebase Console → Project Settings → iOS App
- Make sure it's added to Xcode project (right-click Runner folder → Add Files → Select the file)

### 2. Firebase Initialization Errors
**Symptom**: Crashes during app startup

**Fix**: Already added error handling in `main.dart` - check if Firebase is properly configured

### 3. Missing Permissions in Info.plist
**Symptom**: Crashes when accessing certain features

**Check**: The Info.plist should have all required permissions. Currently configured:
- ✅ Google Sign-In URL schemes
- ✅ Application queries schemes

### 4. Code Signing Issues
**Symptom**: App won't install or crashes immediately

**Fix**:
- In Xcode, go to **Signing & Capabilities**
- Ensure **Automatically manage signing** is checked
- Verify the **Team** is selected
- Check **Bundle Identifier** matches `com.padelcore.app`

### 5. Pod Installation Issues
**Symptom**: Missing dependencies causing crashes

**Fix**: Run these commands:
```bash
cd ios
rm -rf Pods Podfile.lock
pod install --repo-update
cd ..
flutter clean
flutter pub get
```

### 6. Release Build Configuration
**Symptom**: Works in debug but crashes in release

**Fix**: Build a release version locally to test:
```bash
flutter build ios --release
```

## Step 3: Debug Steps

### Option A: Test Locally First
1. Build and run on a physical iOS device:
   ```bash
   flutter run --release
   ```
2. Check Xcode console for errors

### Option B: Add Crash Reporting
Add Firebase Crashlytics to get better crash reports:
```bash
flutter pub add firebase_crashlytics
```

### Option C: Check Xcode Console
1. Open `ios/Runner.xcworkspace` in Xcode
2. Connect a device
3. Run the app and check the console for errors

## Step 4: Check Specific Error Messages

Look at the crash logs from App Store Connect and search for:
- `NSException`
- `Firebase`
- `GoogleService-Info`
- `Bundle identifier`
- `Code signing`

## Step 5: Verify Firebase iOS Configuration

1. Go to Firebase Console → Project Settings → iOS App
2. Verify:
   - ✅ Bundle ID: `com.padelcore.app`
   - ✅ GoogleService-Info.plist is downloaded
   - ✅ APNs Authentication Key is configured (if using push notifications)

## Step 6: Test Build Configuration

Check `ios/Runner.xcodeproj/project.pbxproj`:
- Ensure `PRODUCT_BUNDLE_IDENTIFIER = com.padelcore.app`
- Ensure `IPHONEOS_DEPLOYMENT_TARGET = 15.0`

## Quick Fixes to Try

1. **Clean and rebuild**:
   ```bash
   flutter clean
   cd ios
   rm -rf Pods Podfile.lock
   pod install
   cd ..
   flutter pub get
   flutter build ios --release
   ```

2. **Verify GoogleService-Info.plist exists**:
   - Check `ios/Runner/GoogleService-Info.plist`
   - If missing, download from Firebase Console

3. **Check bundle identifier**:
   - In Xcode: Runner → General → Bundle Identifier should be `com.padelcore.app`

4. **Add error handling** (already done in main.dart)

## Next Steps

1. **Download crash logs** from App Store Connect
2. **Share the crash log** - look for the first error/exception
3. **Check if GoogleService-Info.plist exists** in your project
4. **Try building locally** with `flutter build ios --release` and test on a device

## Most Likely Causes

Based on common Flutter iOS issues:
1. **Missing GoogleService-Info.plist** (most common)
2. **Firebase initialization failing** (now has error handling)
3. **Code signing issues** (check Xcode settings)
4. **Missing dependencies** (run pod install)

Let me know what the crash logs say and I can provide a more specific fix!
