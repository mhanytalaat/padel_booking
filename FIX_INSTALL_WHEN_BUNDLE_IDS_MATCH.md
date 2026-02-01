# Fix: "Install" Instead of "Update" - Bundle IDs Match But Still Shows Install

## Current Situation

- ✅ **App Store Connect Bundle ID:** `com.padelcore.app`
- ✅ **Code Bundle ID:** `com.padelcore.app`
- ✅ **App Name in App Store Connect:** "PadelCore Hub"
- ❌ **TestFlight Shows:** "Install" instead of "Update"
- ❌ **Installed App Name:** "Padel Booking"

## Possible Causes (When Bundle IDs Match)

### 1. Installed App Has Different Bundle ID (Most Likely)

Even though App Store Connect shows `com.padelcore.app`, the **installed app on the device** might have been built with a different Bundle ID.

**How to Check:**
- The installed app name is "Padel Booking" but App Store Connect shows "PadelCore Hub"
- This suggests the installed app might have a different Bundle ID

**Solution:** Check what Bundle ID the installed app actually has:
1. Connect device to Mac
2. Open Xcode → Window → Devices and Simulators
3. Select your device
4. Find "Padel Booking" app
5. Check the Bundle ID shown there

### 2. Team ID Mismatch

The old app might have been built with a different Apple Developer Team ID.

**Check:**
- App Store Connect → "PadelCore Hub" → App Information → Team
- Compare with your current Team ID: `T4Y762MC96`

### 3. Provisioning Profile Issue

Different provisioning profiles might cause iOS to treat them as different apps.

**Check in Codemagic:**
- Which provisioning profile is being used?
- Is it the same one used for the old build?

### 4. App Store Connect App Record Issue

There might be two app records with the same Bundle ID (rare but possible).

**Check:**
- App Store Connect → My Apps
- Are there multiple apps with Bundle ID `com.padelcore.app`?

## Most Likely Solution

Since the installed app is named "Padel Booking" but App Store Connect shows "PadelCore Hub", the **installed app likely has a different Bundle ID**.

**The installed app was probably built with:**
- Bundle ID: `com.padelbooking.app` (or similar)
- App Name: "Padel Booking"

**But the new build has:**
- Bundle ID: `com.padelcore.app`
- App Name: "PadelCore Hub"

## Solution Options

### Option 1: Change Code to Match Installed App (If Installed App Bundle ID is Different)

1. Find the actual Bundle ID of the installed app
2. Update code to match that Bundle ID
3. Rebuild and upload

### Option 2: Users Must Uninstall Old App First

If the old app has a different Bundle ID, users need to:
1. Uninstall "Padel Booking"
2. Install "PadelCore Hub" (new app)

This is expected behavior when Bundle IDs are different.

## Next Steps

**Please check:**

1. **What Bundle ID does the installed app have?**
   - Connect device to Mac
   - Xcode → Window → Devices and Simulators → Select device → Find "Padel Booking" → Check Bundle ID
   - OR check old build archive/Xcode project if available

2. **What Team ID is in App Store Connect?**
   - App Store Connect → "PadelCore Hub" → App Information → Team

3. **Check Codemagic iOS build configuration:**
   - Which Bundle ID is Codemagic building with?
   - Which provisioning profile is it using?

Once we know the installed app's Bundle ID, we can fix it!
