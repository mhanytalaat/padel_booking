# Apple Sign In Error 1000 - Complete Fix Guide

## Critical Issue: Error 1000 happens at Apple level (before Firebase)

This means the problem is in Apple Developer Portal configuration, NOT in the code.

## 🔴 MOST COMMON CAUSE: Service ID Mismatch Between Firebase and Apple

**This is likely your issue!** The Service ID in Firebase Console must EXACTLY match the Service ID in Apple Developer Portal.

---

## Step 1: Verify Service ID Match (CRITICAL)

### In Apple Developer Portal:
1. Go to **Identifiers → Service IDs**
2. Find your Service ID (e.g., `com.padelcore.hub.s...`)
3. **Copy the FULL Service ID identifier** (e.g., `com.padelcore.hub.service`)

### In Firebase Console:
1. Go to **Authentication → Sign-in method → Apple**
2. Check the **Service ID** field
3. **It MUST match EXACTLY** what you have in Apple Developer Portal

### ⚠️ If they don't match:
- Update Firebase Console with the EXACT Service ID from Apple Developer Portal
- Save in Firebase
- Wait 5 minutes
- Test again

---

## Step 2: Verify Private Key Configuration

### In Apple Developer Portal:
1. Go to **Keys**
2. Find the key you created for Sign in with Apple
3. **Copy the Key ID** (e.g., `ABC123DEF4`)
4. **Download the .p8 file** (if you still have it)
5. **Note your Team ID** (found in top right of Apple Developer Portal)

### In Firebase Console:
1. Go to **Authentication → Sign-in method → Apple**
2. Verify:
   - **Team ID** matches your Apple Developer Team ID
   - **Key ID** matches the Key ID from Apple Developer Portal
   - **Private Key** is the content of the .p8 file (without headers/footers)

### ⚠️ If Key is Wrong:
- The key might be revoked or expired
- Create a NEW key in Apple Developer Portal
- Download the new .p8 file
- Update Firebase with new Key ID and private key

---

## Step 3: Verify App ID Capability

### In Apple Developer Portal:
1. Go to **Identifiers → App IDs**
2. Find `com.padelcore.app`
3. Click on it → Check **"Sign in with Apple"** is enabled
4. If not enabled, enable it and save

### In Xcode Project (if you have access):
1. Open `ios/Runner.xcodeproj` in Xcode
2. Select **Runner** target
3. Go to **Signing & Capabilities**
4. Verify **"Sign In with Apple"** capability is present
5. If missing, click **+ Capability** and add it

---

## Step 4: Verify Provisioning Profile

### Critical: The provisioning profile MUST include "Sign in with Apple"

1. Go to **Apple Developer Portal → Profiles**
2. Find your **App Store** or **Ad Hoc** profile (the one used for TestFlight)
3. Click on it
4. Check **"Sign in with Apple"** is listed under Capabilities
5. **If missing:**
   - Delete the old profile
   - Create a NEW profile (it will automatically include the capability)
   - Download the new profile
   - Use it in your build

---

## Step 5: Verify Bundle ID Match

Check these THREE places have IDENTICAL bundle ID:

1. **Apple Developer Portal → App ID**: `com.padelcore.app`
2. **Xcode Project**: `com.padelcore.app`
3. **Firebase Console → iOS App**: `com.padelcore.app`

Even a single character difference will cause error 1000.

---

## Step 6: Verify Service ID Configuration

### In Apple Developer Portal → Service ID:
1. **Primary App ID**: Must be `com.padelcore.app` (or your App ID)
2. **Domains and Subdomains**: `padelcore-app.firebaseapp.com`
3. **Return URLs**: `https://padelcore-app.firebaseapp.com/__/auth/handler`
   - Must be EXACT (no trailing slash, correct capitalization)

---

## Step 7: Complete Verification Checklist

Before testing, verify ALL of these:

- [ ] App ID has "Sign in with Apple" enabled in Apple Developer Portal
- [ ] Service ID exists and has correct Return URL
- [ ] Service ID in Firebase matches Service ID in Apple Developer Portal **EXACTLY**
- [ ] Team ID in Firebase matches your Apple Developer Team ID
- [ ] Key ID in Firebase matches the Key ID in Apple Developer Portal
- [ ] Private Key in Firebase is the correct .p8 file content
- [ ] Bundle ID is `com.padelcore.app` in ALL three places (Apple, Xcode, Firebase)
- [ ] Provisioning profile includes "Sign in with Apple" capability
- [ ] Testing on REAL device (not simulator)
- [ ] Device is signed into iCloud
- [ ] Device has 2FA enabled
- [ ] Waited 5-10 minutes after any configuration changes

---

## 🎯 Most Likely Fix for Your Case

Based on your situation, the **MOST LIKELY** issue is:

### Issue #1: Service ID Mismatch
- Firebase has one Service ID
- Apple Developer Portal has a different Service ID
- **Fix**: Make them match EXACTLY

### Issue #2: Wrong/Revoked Private Key
- The private key in Firebase might be wrong or revoked
- **Fix**: Create new key, update Firebase

### Issue #3: Provisioning Profile Missing Capability
- The profile used to sign the app doesn't have "Sign in with Apple"
- **Fix**: Create new profile, rebuild app

---

## 🔧 Immediate Action Plan

1. **Check Service ID match** (Firebase vs Apple) - This is #1 priority
2. **Verify private key** is correct and not revoked
3. **Check provisioning profile** has the capability
4. **Rebuild app** with correct profile
5. **Test on real device**

---

## 📝 What to Send Me If Still Not Working

If after all checks it still fails, send:

1. **Service ID from Apple Developer Portal**: `com.padelcore.hub.s...` (full identifier)
2. **Service ID from Firebase Console**: (what's configured there)
3. **Team ID**: (from Apple Developer Portal)
4. **Key ID**: (from Apple Developer Portal)
5. **Bundle ID**: (confirm it's `com.padelcore.app` everywhere)
6. **Build type**: (Debug, Release, or TestFlight)
7. **Exact error message**: (full text)

---

## ⚡ Quick Test

After making changes:

1. **Wait 5-10 minutes** (Apple needs time to propagate)
2. **Build new version** (increment build number)
3. **Install on real device**
4. **Test Apple Sign In**

If it works, great! If not, the Service ID mismatch is almost certainly the issue.
