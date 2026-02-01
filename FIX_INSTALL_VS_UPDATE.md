# Fix: "Install" Instead of "Update" on iOS

## Critical: Check App Store Connect First

**Step 1: Check App Store Connect**
1. Go to **App Store Connect** → **My Apps**
2. Find your app (the one showing "Padel Booking")
3. Click on it
4. Go to **App Information** (left sidebar)
5. Look at **Bundle ID** - **What does it say?**
   - If it says `com.padelcore.app` → Bundle ID matches, there's another issue
   - If it says something else (e.g., `com.padelbooking.app`) → **This is the problem!**

## Most Likely Scenario

The old app in App Store Connect has a **different Bundle ID** than `com.padelcore.app`.

**Common old Bundle IDs:**
- `com.padelbooking.app`
- `com.padelcore.booking`
- `com.padelbooking.padelcore`
- Or something similar

## Solution: Change New App to Match Old Bundle ID

If the old app has a different Bundle ID, we need to change the new app's Bundle ID to match it.

### What You Need to Tell Me

**Please check App Store Connect and tell me:**
1. What Bundle ID does the old app have?
2. Is the old app already published in the App Store?

Once I know the old Bundle ID, I can update all the necessary files.

## Files That Need to Be Updated (When You Provide Old Bundle ID)

1. ✅ `ios/Runner.xcodeproj/project.pbxproj` - Bundle Identifier
2. ✅ `ios/Runner/GoogleService-Info.plist` - Download new one from Firebase
3. ✅ `android/app/build.gradle.kts` - applicationId (if Android also needs to match)
4. ✅ Firebase Console - Update iOS app Bundle ID
5. ✅ Apple Developer Portal - Update App ID (if needed)

## Quick Check: What Bundle ID Does Your Old App Have?

**Option 1: App Store Connect (Easiest)**
- App Store Connect → My Apps → Your App → App Information → Bundle ID

**Option 2: On Device**
- Settings → General → iPhone Storage → "Padel Booking" → Look for Bundle ID

**Option 3: Check Old Build**
- If you have access to the old Xcode project or build archive, check the Bundle ID there

---

**Please check App Store Connect and tell me what Bundle ID the old app has, and I'll fix it immediately!**
