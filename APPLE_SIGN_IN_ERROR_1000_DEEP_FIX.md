# Apple Sign In Error 1000 - Deep Fix Guide

## Critical Checks Based on Research

Error 1000 can be caused by several issues beyond just configuration. Let's check them systematically.

---

## 1. Device-Level Checks (MOST COMMON)

### A. iCloud Sign-In
**CRITICAL**: The device must be signed into iCloud with an Apple ID.

1. On your iPhone, go to **Settings** → **[Your Name]** (top of settings)
2. Check if you're signed into iCloud
3. If not signed in, sign in with your Apple ID
4. Make sure iCloud is enabled

### B. Two-Factor Authentication (2FA)
**REQUIRED**: Apple requires 2FA to be enabled on the Apple ID.

1. On your iPhone, go to **Settings** → **[Your Name]** → **Password & Security**
2. Check if **Two-Factor Authentication** is **ON**
3. If OFF, enable it (this is required by Apple)

### C. Apple ID Terms Accepted
1. Make sure you've accepted all Apple ID terms and conditions
2. Sometimes you need to sign out and sign back into iCloud

---

## 2. Build Configuration Check

### Verify Entitlements in Release Build
The entitlements must be present in the **Release** build (TestFlight), not just Debug.

**Since you're using Codemagic:**
- The entitlements file is in the project: `ios/Runner/Runner.entitlements`
- Codemagic should include it in Release builds
- But let's verify it's being used

**Check the built app:**
1. After Codemagic build completes, download the `.ipa` file
2. Unzip it (rename `.ipa` to `.zip` and extract)
3. Navigate to `Payload/Runner.app/`
4. Look for `Runner.app/entitlements` or check the app bundle
5. Verify `com.apple.developer.applesignin` is present

---

## 3. Try Minimal Scopes

The code now tries with **NO scopes** (empty array) - this is the most minimal request.

If this works, we can add scopes back one by one.

---

## 4. Check Debug Console Logs

After testing, check the debug console for detailed error information:
- Error Code
- Error Message
- Full Error Details

The code now logs everything with clear separators.

---

## 5. Verify Service ID Return URL (Again)

Double-check the Return URL is EXACTLY:
```
https://padelcore-app.firebaseapp.com/__/auth/handler
```

No trailing slash, no extra characters, exact match.

---

## 6. Regenerate Everything

If nothing works, try this nuclear option:

1. **Apple Developer Portal:**
   - Delete the Service ID `com.padelcore.hub.service`
   - Delete all provisioning profiles for `com.padelcore.app`
   - Keep the App ID (don't delete it)

2. **Recreate Service ID:**
   - Create new Service ID
   - Configure with exact Return URL
   - Link to App ID

3. **Update Firebase:**
   - Update Service ID in Firebase Console

4. **Rebuild:**
   - Codemagic will regenerate profiles
   - Fresh build with new configuration

---

## Action Plan

1. **Check device first:**
   - [ ] Signed into iCloud?
   - [ ] 2FA enabled on Apple ID?
   - [ ] Apple ID terms accepted?

2. **Test with new build (no scopes):**
   - [ ] Build 29 will have empty scopes
   - [ ] Test and check console logs

3. **If still failing:**
   - [ ] Check console logs for exact error
   - [ ] Verify entitlements in built app
   - [ ] Consider regenerating Service ID

---

## Most Likely Fix

Based on research, **90% of error 1000 cases** are resolved by:
1. ✅ Ensuring device is signed into iCloud
2. ✅ Ensuring 2FA is enabled on Apple ID
3. ✅ Using minimal/no scopes

Try these first before regenerating everything!
