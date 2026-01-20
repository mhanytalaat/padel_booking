# Apple Sign In Configuration Checklist

## Error 1000 Fix Guide

This error typically means Apple Sign In is not properly configured in one of these places:
1. Firebase Console
2. Apple Developer Portal
3. Xcode Project

---

## Step 1: Firebase Console Configuration

### 1.1 Enable Apple Sign-In Provider
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **padelcore-app**
3. Go to **Authentication** → **Sign-in method**
4. Click on **Apple** provider
5. **Enable** it
6. **Save**

### 1.2 Configure OAuth Client (IMPORTANT)
You need to add your Apple Service ID here. But first, you need to create it in Apple Developer Portal (Step 2).

---

## Step 2: Apple Developer Portal Configuration

### 2.1 Enable Sign in with Apple Capability for App ID
1. Go to [Apple Developer Portal](https://developer.apple.com/account/)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Click **Identifiers**
4. Find your App ID: **com.padelcore.app**
5. Click on it to edit
6. Check **Sign in with Apple** capability
7. **Save**

### 2.2 Create a Service ID (REQUIRED for Firebase)
1. In **Identifiers**, click the **+** button
2. Select **Services IDs** → **Continue**
3. **Description**: `PadelCore Apple Sign In Service`
4. **Identifier**: `com.padelcore.app.signin` (or similar, must be unique)
5. **Continue** → **Register**

### 2.3 Configure Service ID
1. Click on your newly created Service ID
2. Check **Sign in with Apple**
3. Click **Configure**
4. **Primary App ID**: Select `com.padelcore.app`
5. **Website URLs**:
   - **Domains**: `padelcore-app.firebaseapp.com`
   - **Return URLs**: 
     - `https://padelcore-app.firebaseapp.com/__/auth/handler`
     - `https://padelcore-app.firebaseapp.com`
6. **Save** → **Continue** → **Save**

### 2.4 Get Your Team ID
1. In Apple Developer Portal, go to **Membership**
2. Note your **Team ID** (e.g., `T4Y762MC96` - you can see this in your Xcode project)

---

## Step 3: Add Service ID to Firebase

1. Go back to Firebase Console
2. **Authentication** → **Sign-in method** → **Apple**
3. In **OAuth code flow configuration**:
   - **Service ID**: Enter the Service ID you created (e.g., `com.padelcore.app.signin`)
   - **Apple Team ID**: Enter your Team ID (e.g., `T4Y762MC96`)
   - **Key ID**: Leave empty for now (only needed if using private key)
   - **Private Key**: Leave empty for now
4. **Save**

---

## Step 4: Verify Xcode Project

### 4.1 Check Bundle ID
1. Open `ios/Runner.xcworkspace` in Xcode
2. Select **Runner** target
3. Go to **Signing & Capabilities**
4. Verify **Bundle Identifier** is: `com.padelcore.app`

### 4.2 Check Sign in with Apple Capability
1. In **Signing & Capabilities** tab
2. Verify **Sign in with Apple** capability is added
3. If not, click **+ Capability** → Add **Sign in with Apple**

### 4.3 Verify Entitlements File
- File: `ios/Runner/Runner.entitlements`
- Should contain:
```xml
<key>com.apple.developer.applesignin</key>
<array>
    <string>Default</string>
</array>
```

---

## Step 5: Verify Code Configuration

The code should already be correct, but verify:

1. **Bundle ID matches everywhere**:
   - Firebase: `com.padelcore.app`
   - Apple Developer: `com.padelcore.app`
   - Xcode: `com.padelcore.app`
   - Info.plist: `$(PRODUCT_BUNDLE_IDENTIFIER)`

2. **Entitlements file is linked** in Xcode project

---

## Step 6: Test

1. **Clean build**:
   ```bash
   flutter clean
   cd ios
   pod deintegrate
   pod install
   cd ..
   flutter pub get
   ```

2. **Build and run** on a **real iOS device** (Sign in with Apple doesn't work on simulator for some configurations)

3. Try signing in with Apple

---

## Common Issues

### Issue: "The operation couldn't be completed. (com.apple.AuthenticationServices.AuthorizationError error 1000.)"

**Solutions:**
1. ✅ Service ID not created in Apple Developer Portal
2. ✅ Service ID not added to Firebase Console
3. ✅ Return URLs don't match in Service ID configuration
4. ✅ Sign in with Apple capability not enabled for App ID
5. ✅ Testing on simulator (try real device)

### Issue: "Invalid client" or "Invalid redirect URI"

**Solutions:**
1. Check Return URLs in Service ID match exactly:
   - `https://padelcore-app.firebaseapp.com/__/auth/handler`
2. Verify Service ID in Firebase matches the one in Apple Developer Portal

---

## Quick Checklist

- [ ] Apple Sign In enabled in Firebase Console
- [ ] Service ID created in Apple Developer Portal
- [ ] Service ID configured with correct Return URLs
- [ ] Service ID added to Firebase Console (OAuth configuration)
- [ ] Sign in with Apple capability enabled for App ID (`com.padelcore.app`)
- [ ] Bundle ID matches everywhere (`com.padelcore.app`)
- [ ] Entitlements file exists and is linked in Xcode
- [ ] Testing on real iOS device (not simulator)

---

## Need Help?

If you're still getting errors after following these steps:
1. Check Firebase Console → Authentication → Sign-in method → Apple for any error messages
2. Check Apple Developer Portal → Identifiers for any warnings
3. Verify you're using the correct Team ID
4. Make sure you're testing on a real device, not simulator
