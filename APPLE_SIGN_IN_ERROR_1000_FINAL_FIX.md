# Apple Sign In Error 1000 - Final Fix Guide

## Error Details
```
Error: AuthorizationErrorCode.unknown
Message: The operation couldn't be completed. (com.apple.AuthenticationServices.AuthorizationError error 1000.)
```

## ✅ Verified (You've confirmed these)
- iCloud signed in
- 2FA enabled  
- Configurations correct

## 🔍 Most Likely Causes (in order of probability)

### 1. Service ID Return URL Mismatch (MOST COMMON)

**The Return URL in your Service ID must EXACTLY match what Firebase expects.**

#### Steps to Fix:

1. **Go to Apple Developer Portal → Certificates, Identifiers & Profiles**
2. **Click "Identifiers" → Find your Service ID** (the one configured for Sign in with Apple)
3. **Click on the Service ID → Click "Edit"**
4. **Check "Return URLs" section**

#### Critical Return URLs to Add/Verify:

For Firebase, you typically need:
```
https://YOUR-PROJECT-ID.firebaseapp.com/__/auth/handler
```

**BUT ALSO CHECK:**
- The exact URL format Firebase shows in your Firebase Console
- Go to Firebase Console → Authentication → Sign-in method → Apple → Check the "Return URL" shown there
- It should look like: `https://[PROJECT-ID].firebaseapp.com/__/auth/handler`

#### Action Items:
1. Copy the EXACT Return URL from Firebase Console
2. Add it to your Service ID Return URLs in Apple Developer Portal
3. Make sure there are NO trailing slashes or extra characters
4. Save the Service ID
5. **Wait 5-10 minutes** for changes to propagate
6. Try again

---

### 2. Provisioning Profile Missing Capability

**The provisioning profile used to sign the app must include "Sign in with Apple" capability.**

#### Steps to Verify:

1. **Go to Apple Developer Portal → Certificates, Identifiers & Profiles**
2. **Click "Profiles" → Find your App Store / Ad Hoc / Development profile**
3. **Click on the profile → Check "Capabilities" section**
4. **Verify "Sign in with Apple" is listed and enabled**

#### If Missing:
1. **Delete the old provisioning profile**
2. **Create a NEW provisioning profile** (this will include the capability)
3. **Download the new profile**
4. **In Xcode (or Codemagic):**
   - Make sure the new profile is used
   - Verify the capability is enabled in the project

---

### 3. App Entitlements Not in Release Build

**The entitlements file must be included in the release build.**

#### Verify in Codemagic/Xcode:

1. **Check `ios/Runner/Runner.entitlements` exists and contains:**
   ```xml
   <key>com.apple.developer.applesignin</key>
   <array>
       <string>Default</string>
   </array>
   ```

2. **In Xcode project settings:**
   - Go to "Signing & Capabilities"
   - Verify "Sign in with Apple" capability is shown
   - If not, add it manually

3. **In Codemagic build:**
   - Make sure the entitlements file is included in the build
   - Check build logs for any entitlements warnings

---

### 4. Bundle ID Mismatch

**Verify Bundle ID matches everywhere:**

1. **Apple Developer Portal → App ID:**
   - Bundle ID: `com.padelcore.app`
   - "Sign in with Apple" capability enabled

2. **Xcode Project:**
   - Bundle Identifier: `com.padelcore.app`
   - Same in all build configurations (Debug, Release)

3. **Firebase Console:**
   - iOS app Bundle ID: `com.padelcore.app`

4. **Service ID:**
   - Associated with the correct App ID (`com.padelcore.app`)

---

## 🚨 Critical: Service ID Configuration

### Service ID Setup Checklist:

1. **Service ID Identifier:**
   - Format: `com.padelcore.app.service` (or similar)
   - Must be unique

2. **Service ID Configuration:**
   - ✅ "Sign in with Apple" enabled
   - ✅ Primary App ID: `com.padelcore.app`
   - ✅ Return URLs: **MUST MATCH FIREBASE EXACTLY**

3. **Return URL Format:**
   ```
   https://[YOUR-PROJECT-ID].firebaseapp.com/__/auth/handler
   ```
   - Get the EXACT URL from Firebase Console
   - Copy-paste it (don't type it manually)
   - No trailing slashes
   - Use HTTPS (not HTTP)

---

## 🔧 Step-by-Step Fix Procedure

### Step 1: Get Exact Return URL from Firebase
1. Open Firebase Console
2. Go to Authentication → Sign-in method
3. Click on Apple provider
4. **Copy the Return URL shown there** (it's usually in the configuration section)

### Step 2: Update Service ID in Apple Developer Portal
1. Go to Apple Developer Portal
2. Identifiers → Service IDs
3. Find your Service ID for Sign in with Apple
4. Click Edit
5. Under "Return URLs", add/update with the EXACT URL from Firebase
6. Save

### Step 3: Regenerate Provisioning Profile (if needed)
1. Delete old provisioning profile
2. Create new one (it will automatically include the capability)
3. Download and use in your build

### Step 4: Verify Build Configuration
1. Check `ios/Runner.xcodeproj/project.pbxproj`:
   - Search for `com.apple.SignInWithApple`
   - Should show `enabled = 1;`

2. Check `ios/Runner/Runner.entitlements`:
   - Should contain the applesignin key

### Step 5: Wait and Test
1. **Wait 5-10 minutes** after updating Service ID (Apple needs time to propagate)
2. Build a new version
3. Test on real device

---

## 🎯 Most Likely Solution

**90% of error 1000 cases are caused by Return URL mismatch.**

The Return URL in your Service ID must be:
- **Exactly** what Firebase shows
- **No extra characters**
- **No missing characters**
- **HTTPS (not HTTP)**
- **No trailing slash**

---

## 📝 Verification After Fix

After making changes, verify:

1. ✅ Service ID Return URL matches Firebase exactly
2. ✅ Provisioning profile includes "Sign in with Apple"
3. ✅ App ID has "Sign in with Apple" capability
4. ✅ Bundle ID matches everywhere (`com.padelcore.app`)
5. ✅ Entitlements file is correct
6. ✅ Waited 5-10 minutes after Service ID update
7. ✅ Testing on real device (not simulator)

---

## 🔄 If Still Not Working

If error 1000 persists after all above:

1. **Regenerate Service ID:**
   - Create a completely new Service ID
   - Configure it from scratch
   - Update Firebase with new Service ID

2. **Check Apple Developer Account Status:**
   - Ensure account is active
   - No pending agreements
   - Payment method is valid

3. **Contact Apple Developer Support:**
   - Error 1000 can sometimes be an Apple-side issue
   - They can check your account configuration

---

## ⚠️ Important Notes

- **Service ID changes take 5-10 minutes to propagate**
- **Always test on a real device** (not simulator)
- **Make sure you're using the correct provisioning profile** (App Store for TestFlight)
- **Double-check Return URL** - one character difference will cause error 1000
