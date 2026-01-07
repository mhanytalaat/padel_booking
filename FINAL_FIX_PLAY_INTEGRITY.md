# Final Fix: Play Integrity Token Error

## Critical Issue
Play Integrity API requires the app to be **registered in Google Play Console** (even if not published) OR installed from Play Store.

## Solution 1: Register App in Google Play Console (Recommended)

1. Go to: https://play.google.com/console
2. Create a new app (or use existing)
3. Fill in basic details:
   - App name: PadelCore
   - Default language: English
   - App type: App
   - Free or paid: Free
4. **Don't need to publish** - just create the app listing
5. Go to **Release** → **Setup** → **App integrity**
6. The app will be registered with package name `com.padelcore.app`

This registers your app with Google Play, which allows Play Integrity to work.

## Solution 2: Check API Key Restrictions

1. Go to: https://console.cloud.google.com/apis/credentials?project=padelcore-app
2. Find the API key: `AIzaSyC59LhvQ9mmD7ByUq_3Vx0OaDsdwXaQvmg`
3. Click on it to edit
4. Check **Application restrictions**:
   - If set to "Android apps", verify package name and SHA-1 match
   - **OR** try setting to "None" temporarily to test
5. Check **API restrictions**:
   - Should include: "Firebase Installations API", "Identity Toolkit API", "Play Integrity API"
   - **OR** set to "Don't restrict key" temporarily to test

## Solution 3: Verify All Fingerprints in Firebase

Make sure Firebase Console has ALL 4 fingerprints:
- Debug SHA-1: `C2:E4:D5:72:01:DA:C0:33:88:99:93:10:1D:23:17:75:90:16:B8:19`
- Debug SHA-256: `91:8E:70:A7:78:8E:E8:E8:BF:36:D0:5C:87:D1:D7:F3:DE:DC:47:6F:45:1A:09:77:73:8F:DB:2B:20:F0:75:B9`
- Release SHA-1: `77:B8:4A:9C:0D:D0:D1:A4:8C:3D:1A:9D:0D:06:1F:81:1A:BE:94:27`
- Release SHA-256: `A1:77:43:5B:76:C2:07:08:5F:B9:51:33:25:90:83:45:DC:32:9B:0A:A7:E4:71:7E:59:F9:98:3C:42:29:30:62`

## Solution 4: Wait 24 Hours

Sometimes Firebase/Google Cloud needs up to 24 hours to fully propagate all changes. If you've done everything above, wait and try again tomorrow.

## Quick Test: Remove API Key Restrictions

1. Google Cloud Console → APIs & Services → Credentials
2. Click on API key: `AIzaSyC59LhvQ9mmD7ByUq_3Vx0OaDsdwXaQvmg`
3. Set **Application restrictions** to **None** (temporarily)
4. Set **API restrictions** to **Don't restrict key** (temporarily)
5. Save
6. Rebuild and test

If this works, then add restrictions back one by one to find the issue.

