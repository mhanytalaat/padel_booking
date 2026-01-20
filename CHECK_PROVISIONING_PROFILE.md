# Check Provisioning Profile for Sign in with Apple

## Critical Check: Provisioning Profile

Error 1000 often occurs when the **provisioning profile** doesn't include the "Sign in with Apple" capability, even if everything else is configured correctly.

## How to Check in Apple Developer Portal

### Step 1: Go to Provisioning Profiles
1. Go to [Apple Developer Portal](https://developer.apple.com/account/)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Click **Profiles** (on the left sidebar)

### Step 2: Find Your Profile
1. Look for profiles for `com.padelcore.app`
2. You should see profiles like:
   - **App Store** profile (for TestFlight/App Store)
   - **Ad Hoc** profile (for direct installation)
   - **Development** profile (for development)

### Step 3: Check Capabilities
1. Click on a profile (start with **App Store** profile)
2. Look at the **Capabilities** section
3. Check if **"Sign in with Apple"** is listed
4. If it's **NOT listed**, this is the problem!

### Step 4: Regenerate Profile
If "Sign in with Apple" is NOT in the profile:

**Option A: Delete and Let Codemagic Regenerate**
1. **Delete** the old profile(s) in Apple Developer Portal
2. Trigger a new build in Codemagic
3. Codemagic should automatically create a new profile with the capability

**Option B: Manually Regenerate**
1. In Apple Developer Portal → **Profiles**
2. Click **+** to create a new profile
3. Select **App Store** (or **Ad Hoc** for testing)
4. Select App ID: `com.padelcore.app`
5. Select your certificate
6. **Generate** the profile
7. Download and configure in Codemagic (if using manual signing)

## What to Look For

✅ **Good Profile:**
- Profile type: App Store
- App ID: `com.padelcore.app`
- Capabilities include: **Sign in with Apple** ✅
- Status: Active

❌ **Bad Profile:**
- Profile type: App Store
- App ID: `com.padelcore.app`
- Capabilities: (Sign in with Apple is **missing**)
- Status: Active

## Important Notes

- Even if the App ID has the capability enabled, the **provisioning profile** must also include it
- Codemagic should automatically regenerate profiles, but sometimes old profiles are cached
- Deleting old profiles forces regeneration with current App ID capabilities

## After Regenerating

1. Wait for Codemagic build to complete
2. Delete app from iPhone
3. Install fresh build
4. Test Apple Sign In

---

## Quick Checklist

- [ ] Go to Apple Developer Portal → Profiles
- [ ] Find profile for `com.padelcore.app`
- [ ] Check if "Sign in with Apple" is in capabilities
- [ ] If missing, delete profile and rebuild
- [ ] Test again
