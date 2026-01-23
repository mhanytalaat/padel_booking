# Troubleshooting: "Install" Instead of "Update"

## Problem
App Store/TestFlight shows **"Install"** instead of **"Update"**, even though:
- Bundle ID matches: `com.padelcore.app`
- Version is higher: `1.1.13+43`
- Same app record in App Store Connect

## Root Cause
iOS shows "Install" instead of "Update" when the **Bundle ID doesn't match** between the installed app and the new build.

## Critical Check: What Bundle ID Does the Old App Have?

### Method 1: Check on Device (Easiest)
1. On your iOS device, open **Settings** → **General** → **iPhone Storage** (or **iPad Storage**)
2. Find **"Padel Booking"** app
3. Tap on it
4. Look for **"Bundle ID"** or **"Identifier"**
5. **What does it say?**
   - If it says `com.padelcore.app` → Bundle ID matches ✅
   - If it says something else (e.g., `com.padelbooking.app`, `com.padelcore.booking`, etc.) → **This is the problem!** ❌

### Method 2: Check App Store Connect
1. Go to **App Store Connect** → **My Apps**
2. Check if there are **TWO separate apps**:
   - One named "Padel Booking" (old)
   - One named "PadelCore" (new)
3. If there are two apps, check their Bundle IDs:
   - Old app Bundle ID: `???`
   - New app Bundle ID: `com.padelcore.app`

### Method 3: Check Old Build Archive
If you have access to the old build:
1. Check the old Xcode project or build settings
2. What was the Bundle ID in the old build?

## Most Common Scenarios

### Scenario 1: Old App Has Different Bundle ID
**Old app Bundle ID:** `com.padelbooking.app` (or similar)
**New app Bundle ID:** `com.padelcore.app`

**Solution:** You have two options:
- **Option A:** Change the new app's Bundle ID to match the old one (not recommended if already published)
- **Option B:** Keep the new Bundle ID, but users will need to uninstall the old app first

### Scenario 2: Two Separate Apps in App Store Connect
**Problem:** There are two app records:
- App 1: "Padel Booking" with Bundle ID `com.padelbooking.app`
- App 2: "PadelCore" with Bundle ID `com.padelcore.app`

**Solution:** 
- If the old app is no longer needed, you can't merge them
- Users must uninstall the old app and install the new one
- Or, change the new app's Bundle ID to match the old one (requires republishing)

### Scenario 3: Team ID Mismatch
**Problem:** Old app was built with a different Apple Developer Team ID

**Check:**
1. App Store Connect → Your App → App Information
2. Check the **Team** or **Organization** field
3. Compare with your current Team ID: `T4Y762MC96`

## How to Fix

### If Old App Bundle ID is Different

**Option 1: Change New App to Match Old (If Old App is Published)**
1. Change Bundle ID in Xcode project to match old app
2. Update `GoogleService-Info.plist` from Firebase Console
3. Update Firebase project settings
4. Rebuild and upload

**Option 2: Keep New Bundle ID (Recommended if Old App Not Published)**
1. Users must uninstall old app
2. Install new app (it will show as "Install" because it's technically a different app)
3. This is expected behavior

### If Bundle IDs Match But Still Shows "Install"

**Check:**
1. **Provisioning Profile:** Ensure the new build uses the same provisioning profile type (App Store vs Ad Hoc)
2. **App Store Connect:** Verify the app record is the same
3. **Version Number:** Ensure new version is higher than old version
4. **Team ID:** Ensure both builds use the same Team ID

## Verification Steps

1. ✅ **Check old app Bundle ID** (Settings → iPhone Storage)
2. ✅ **Check App Store Connect** for duplicate apps
3. ✅ **Verify new build Bundle ID** (`com.padelcore.app`)
4. ✅ **Check version numbers** (old vs new)
5. ✅ **Verify Team ID** matches

## Expected Behavior

- **Same Bundle ID + Higher Version = "Update"** ✅
- **Different Bundle ID = "Install"** (even if same app name) ❌

## Next Steps

1. **First:** Check what Bundle ID the old app actually has
2. **Then:** Decide whether to change the new Bundle ID to match, or keep it different
3. **If keeping different:** Users will need to uninstall old app first

## Quick Test

To verify the Bundle ID of the installed app:
```bash
# On Mac, connect device and run:
xcrun simctl listapps booted | grep -A 5 "Padel"
# Or check device logs for bundle identifier
```

**Most Important:** Check the old app's Bundle ID first - that will tell us exactly what's wrong!
