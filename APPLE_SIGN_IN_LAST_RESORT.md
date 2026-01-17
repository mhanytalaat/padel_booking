# Apple Sign In Error 1000 - Last Resort Fix

## Everything Verified But Still Error 1000

Since all configurations are correct and iCloud/2FA are enabled, let's try the **nuclear option**.

## Step 1: Double-Check Service ID Return URL (CRITICAL)

Go to **Apple Developer Portal** → **Identifiers** → **Services IDs** → `com.padelcore.hub.service`:

1. Click **Configure** next to "Sign in with Apple"
2. Look at **Return URLs** section
3. The URL must be **EXACTLY**:
   ```
   https://padelcore-app.firebaseapp.com/__/auth/handler
   ```
4. Check for:
   - ❌ Trailing slash: `https://...handler/` (WRONG)
   - ❌ Extra spaces
   - ❌ Different domain
   - ❌ Missing `__/auth/handler` part
5. If it's wrong, **fix it** and **Save**
6. Wait 10-15 minutes for changes to propagate

## Step 2: Regenerate Service ID (Nuclear Option)

If Step 1 doesn't work, completely recreate the Service ID:

### A. Delete Old Service ID
1. Apple Developer Portal → **Identifiers** → **Services IDs**
2. Find `com.padelcore.hub.service`
3. Click on it
4. Click **Remove** (red button)
5. Confirm deletion

### B. Create New Service ID
1. Click **+** button
2. Select **Services IDs** → **Continue**
3. **Description**: `PadelCore Apple Sign In`
4. **Identifier**: `com.padelcore.app.service` (different from before)
5. **Continue** → **Register**

### C. Configure New Service ID
1. Check **Sign in with Apple**
2. Click **Configure**
3. **Primary App ID**: `com.padelcore.app`
4. **Domains**: `padelcore-app.firebaseapp.com`
5. **Return URLs**: `https://padelcore-app.firebaseapp.com/__/auth/handler`
   - Type it manually, don't copy-paste
   - No trailing slash
   - Exact match
6. **Save** → **Continue** → **Save**

### D. Update Firebase
1. Firebase Console → **Authentication** → **Sign-in method** → **Apple**
2. **Service ID**: Update to `com.padelcore.app.service` (new one)
3. **Save**

### E. Rebuild
1. Increment build number
2. Build in Codemagic
3. Test fresh install

## Step 3: Verify Bundle ID One More Time

Check these all match **EXACTLY** `com.padelcore.app`:

- [ ] Apple Developer Portal → App ID
- [ ] Firebase Console → iOS app Bundle ID
- [ ] Xcode project (we verified this)
- [ ] Info.plist (uses variable, should resolve correctly)

## Step 4: Check if It's a TestFlight-Specific Issue

Sometimes TestFlight builds have different entitlements. Try:

1. Build a **development/ad-hoc** build instead of App Store
2. Install directly on device (not via TestFlight)
3. Test Apple Sign In

## Step 5: Contact Apple Developer Support

If nothing works, this might be an Apple-side issue:

1. Go to [Apple Developer Support](https://developer.apple.com/contact/)
2. Explain the issue
3. Mention you've verified all configurations
4. Ask if there's a known issue with your account/Service ID

## What to Share With Me

After trying these steps, share:

1. **Did you check the Return URL exactly?** (What does it say?)
2. **Did regenerating Service ID help?**
3. **What does the error message show now?** (The UI will show more details)
4. **Any other error details from console/logs?**

---

## Most Likely Fix

Based on all troubleshooting, the **most likely remaining issue** is:

**Service ID Return URL mismatch** - Even a tiny difference (trailing slash, extra space, wrong domain) causes error 1000.

Double-check the Return URL character-by-character!
