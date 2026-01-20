# Apple Sign In Error 1000 - Verification Checklist

## Current Configuration
- **App Bundle ID**: `com.padelcore.app`
- **Service ID**: `com.padelcore.hub.service`
- **Team ID**: `T4Y762MC96`
- **Key ID**: `U3AM3M8VFQ`

## Critical Checks

### 1. Service ID Configuration in Apple Developer Portal

Go to: **Identifiers** → **Services IDs** → `com.padelcore.hub.service`

**Verify these settings:**

#### A. Sign in with Apple is Enabled
- [ ] Checkbox for "Sign in with Apple" is **checked**

#### B. Primary App ID Configuration
- [ ] Click **Configure** next to "Sign in with Apple"
- [ ] **Primary App ID** must be: `com.padelcore.app`
- [ ] If it's different, change it to `com.padelcore.app`

#### C. Return URLs (CRITICAL)
- [ ] **Domains**: `padelcore-app.firebaseapp.com`
- [ ] **Return URLs** must include EXACTLY:
  ```
  https://padelcore-app.firebaseapp.com/__/auth/handler
  ```
- [ ] Make sure there are NO trailing slashes or extra characters
- [ ] If the URL is different, update it

### 2. App ID Configuration

Go to: **Identifiers** → **App IDs** → `com.padelcore.app`

**Verify:**
- [ ] "Sign in with Apple" capability is **enabled/checked**
- [ ] If not enabled, enable it and save

### 3. Firebase Console Configuration

**Current settings look correct:**
- ✅ Service ID: `com.padelcore.hub.service`
- ✅ Team ID: `T4Y762MC96`
- ✅ Key ID: `U3AM3M8VFQ`
- ✅ Private Key: (configured)

**Additional check:**
- [ ] Make sure **Apple** provider is **Enabled** (toggle is ON)
- [ ] Click **Save** after verifying

### 4. Common Issues

#### Issue 1: Return URL Mismatch
**Symptom**: Error 1000
**Fix**: 
- In Apple Developer Portal → Service ID → Configure
- Return URL must be EXACTLY: `https://padelcore-app.firebaseapp.com/__/auth/handler`
- No trailing slash, no extra characters

#### Issue 2: Primary App ID Mismatch
**Symptom**: Error 1000
**Fix**:
- In Apple Developer Portal → Service ID → Configure
- Primary App ID must be: `com.padelcore.app`
- Not `com.padelcore.hub` or anything else

#### Issue 3: App ID Capability Not Enabled
**Symptom**: Error 1000
**Fix**:
- In Apple Developer Portal → Identifiers → App IDs → `com.padelcore.app`
- Enable "Sign in with Apple" capability

#### Issue 4: Testing on Simulator
**Symptom**: Error 1000
**Fix**: 
- Sign in with Apple may not work on simulator
- Test on a **real iOS device**

### 5. Step-by-Step Fix

1. **Go to Apple Developer Portal**
   - https://developer.apple.com/account/resources/identifiers/list/serviceId

2. **Click on `com.padelcore.hub.service`**

3. **Verify "Sign in with Apple" is checked**

4. **Click "Configure" next to "Sign in with Apple"**

5. **Check Primary App ID:**
   - Must be: `com.padelcore.app`
   - If different, select `com.padelcore.app` from dropdown

6. **Check Return URLs:**
   - Must include: `https://padelcore-app.firebaseapp.com/__/auth/handler`
   - If missing or different, add/update it
   - Click **Save**

7. **Go back to App ID:**
   - https://developer.apple.com/account/resources/identifiers/list/bundleId
   - Find `com.padelcore.app`
   - Verify "Sign in with Apple" capability is enabled

8. **Rebuild and test on real device**

### 6. Quick Test

After making changes:
1. Wait 5-10 minutes for changes to propagate
2. Clean build:
   ```bash
   flutter clean
   cd ios
   pod deintegrate
   pod install
   cd ..
   flutter pub get
   ```
3. Build and run on **real iOS device** (not simulator)
4. Try signing in with Apple

---

## Most Likely Issue

Based on error 1000, the most common causes are:

1. **Return URL mismatch** (90% of cases)
   - Check that Return URL in Service ID is EXACTLY: `https://padelcore-app.firebaseapp.com/__/auth/handler`

2. **Primary App ID mismatch** (5% of cases)
   - Check that Primary App ID in Service ID is `com.padelcore.app`

3. **App ID capability not enabled** (5% of cases)
   - Check that `com.padelcore.app` has "Sign in with Apple" enabled

---

## Need to Verify

Please check and confirm:
1. What is the **Primary App ID** set in your Service ID (`com.padelcore.hub.service`) configuration?
2. What are the **Return URLs** listed in the Service ID configuration?
3. Is "Sign in with Apple" capability enabled for the App ID (`com.padelcore.app`)?
