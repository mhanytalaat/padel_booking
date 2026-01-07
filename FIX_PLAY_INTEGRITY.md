# Fix: Play Integrity Token Error

## The Problem
Error: "Invalid app info in play_integrity_token"

This means Firebase is trying to use Google Play Integrity API for verification, but it's not properly configured.

## Solution: Enable Play Integrity API

### Step 1: Enable Play Integrity API in Google Cloud Console
1. Go to: https://console.cloud.google.com/apis/library?project=padelcore-app
2. Search for: **Play Integrity API**
3. Click on **Play Integrity API**
4. Click **ENABLE**
5. Wait for it to enable (usually instant)

### Step 2: Verify OAuth Clients Have Correct SHA Fingerprints
Make sure both OAuth clients in Google Cloud Console have the correct SHA-1 fingerprints:
- Debug: `C2:E4:D5:72:01:DA:C0:33:88:99:93:10:1D:23:17:75:90:16:B8:19`
- Release: `77:B8:4A:9C:0D:D0:D1:A4:8C:3D:1A:9D:0D:06:1F:81:1A:BE:94:27`

### Step 3: Alternative - Use Debug Build Without Play Integrity
For testing, you can build a debug APK that doesn't require Play Integrity:
```bash
flutter build apk --debug
```

Then install it on your emulator/device.

### Step 4: For Release Builds
Play Integrity is required for release builds. Make sure:
1. Play Integrity API is enabled
2. App is properly signed with release keystore
3. SHA fingerprints match in Firebase Console

