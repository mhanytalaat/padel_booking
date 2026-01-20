# Apple Sign In Error 1000 - Deep Troubleshooting

## Error 1000 Analysis

Error 1000 happens **BEFORE** Firebase - it occurs when calling `SignInWithApple.getAppleIDCredential()`. This means the issue is with Apple's configuration, not Firebase.

---

## Step-by-Step Troubleshooting

### 1. Verify You're Testing on Real Device

**CRITICAL**: Error 1000 often occurs on simulator even with correct configuration.

- [ ] Are you testing on a **real iOS device**? (Not simulator)
- [ ] If on simulator, try a real device first

---

### 2. Check Bundle ID Consistency

Error 1000 can occur if bundle IDs don't match exactly.

**Verify these all match EXACTLY: `com.padelcore.app`**

#### A. Xcode Project
1. Open `ios/Runner.xcworkspace` in Xcode
2. Select **Runner** target
3. **Signing & Capabilities** tab
4. **Bundle Identifier** must be: `com.padelcore.app`
5. If different, change it to `com.padelcore.app`

#### B. Apple Developer Portal - App ID
1. Go to Apple Developer Portal → Identifiers → App IDs
2. Find `com.padelcore.app`
3. Verify it matches exactly

#### C. Firebase Console
1. Firebase Console → Project Settings
2. iOS app → Bundle ID must be: `com.padelcore.app`

#### D. Info.plist
- Should use `$(PRODUCT_BUNDLE_IDENTIFIER)` which resolves to `com.padelcore.app`

---

### 3. Verify Entitlements File

#### A. File Exists
- [ ] File exists: `ios/Runner/Runner.entitlements`
- [ ] Contains:
```xml
<key>com.apple.developer.applesignin</key>
<array>
    <string>Default</string>
</array>
```

#### B. Linked in Xcode
1. Open Xcode → Runner target
2. **Signing & Capabilities** tab
3. Look for **Sign in with Apple** capability
4. If missing, click **+ Capability** → Add **Sign in with Apple**
5. This should automatically link the entitlements file

#### C. Verify in project.pbxproj
- The entitlements file should be referenced in the Xcode project

---

### 4. Check Apple Developer Portal - App ID

#### A. Capability Enabled
1. Apple Developer Portal → Identifiers → App IDs → `com.padelcore.app`
2. **Capabilities** section
3. **Sign in with Apple** must be **checked/enabled**
4. If not, enable it and **Save**

#### B. Primary App ID Configuration
1. Click **Edit** next to "Sign in with Apple"
2. Should be set to **"Enable as a primary App ID"**
3. **Save**

---

### 5. Check Service ID Configuration

#### A. Service ID Exists
- Service ID: `com.padelcore.hub.service`
- **Sign in with Apple** is enabled

#### B. Primary App ID
1. Service ID → Configure → Sign in with Apple
2. **Primary App ID** must be: `com.padelcore.app`
3. If different, change it

#### C. Return URLs
- Domain: `padelcore-app.firebaseapp.com`
- Return URL: `https://padelcore-app.firebaseapp.com/__/auth/handler`
- Must be EXACTLY this (no trailing slash, no extra characters)

---

### 6. Check Code Implementation

The code looks correct, but let's verify:

#### Current Implementation
```dart
final appleCredential = await SignInWithApple.getAppleIDCredential(
  scopes: [
    AppleIDAuthorizationScopes.email,
    AppleIDAuthorizationScopes.fullName,
  ],
);
```

#### Potential Issue: Scopes
If email scope causes issues, try requesting only what's needed:

**Option 1: Try without email scope** (if email not required immediately)
```dart
final appleCredential = await SignInWithApple.getAppleIDCredential(
  scopes: [
    AppleIDAuthorizationScopes.fullName,
  ],
);
```

**Option 2: Try with no scopes** (minimal request)
```dart
final appleCredential = await SignInWithApple.getAppleIDCredential(
  scopes: [],
);
```

---

### 7. Check Xcode Project Settings

#### A. Signing Certificate
1. Xcode → Runner target → Signing & Capabilities
2. **Team** must be selected (T4Y762MC96)
3. **Provisioning Profile** should be automatic or valid

#### B. Build Settings
1. Xcode → Runner target → Build Settings
2. Search for "Code Signing Entitlements"
3. Should be: `Runner/Runner.entitlements`

---

### 8. Clean Build and Reinstall

Sometimes cached configurations cause issues:

```bash
# Clean Flutter
flutter clean

# Clean iOS
cd ios
rm -rf Pods
rm -rf Podfile.lock
rm -rf .symlinks
rm -rf Flutter/Flutter.framework
rm -rf Flutter/Flutter.podspec
pod deintegrate
pod install
cd ..

# Get dependencies
flutter pub get

# Delete app from device
# Then rebuild and install fresh
```

---

### 9. Check Provisioning Profile

#### A. Verify in Xcode
1. Xcode → Runner target → Signing & Capabilities
2. Check **Provisioning Profile** status
3. Should show "Valid" or "Managed by Xcode"

#### B. Check in Apple Developer Portal
1. Apple Developer Portal → Profiles
2. Find profile for `com.padelcore.app`
3. Should include "Sign in with Apple" capability
4. If not, regenerate the profile

---

### 10. Test with Minimal Code

Create a test to isolate the issue:

```dart
// Test if Apple Sign In is available
bool isAvailable = await SignInWithApple.isAvailable();
print('Apple Sign In available: $isAvailable');

// Try with minimal scopes
try {
  final credential = await SignInWithApple.getAppleIDCredential(
    scopes: [], // No scopes
  );
  print('Success! User ID: ${credential.userIdentifier}');
} catch (e) {
  print('Error: $e');
  print('Error code: ${e.code}');
  print('Error message: ${e.message}');
}
```

---

## Most Common Causes of Error 1000

1. **Testing on Simulator** (40%)
   - Solution: Test on real device

2. **Bundle ID Mismatch** (30%)
   - Solution: Verify all bundle IDs match exactly

3. **Capability Not Enabled in App ID** (15%)
   - Solution: Enable in Apple Developer Portal

4. **Entitlements Not Linked** (10%)
   - Solution: Add capability in Xcode

5. **Service ID Configuration** (5%)
   - Solution: Verify Primary App ID and Return URLs

---

## Quick Diagnostic Checklist

Run through these in order:

- [ ] Testing on **real iOS device** (not simulator)
- [ ] Bundle ID is `com.padelcore.app` everywhere
- [ ] App ID has "Sign in with Apple" capability enabled
- [ ] Entitlements file exists and is linked in Xcode
- [ ] Xcode shows "Sign in with Apple" capability added
- [ ] Service ID Primary App ID = `com.padelcore.app`
- [ ] Service ID Return URL = `https://padelcore-app.firebaseapp.com/__/auth/handler`
- [ ] Clean build and fresh install
- [ ] Provisioning profile includes the capability

---

## Next Steps

1. **Start with device check** - Are you on a real device?
2. **Verify bundle ID** - Check Xcode project settings
3. **Check capability** - Verify in Apple Developer Portal
4. **Clean rebuild** - Full clean and fresh install
5. **Try minimal scopes** - Test with empty scopes array

Let me know which step reveals the issue!
