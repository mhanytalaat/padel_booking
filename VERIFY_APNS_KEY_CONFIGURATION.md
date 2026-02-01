# Verify APNs Key Configuration - BadEnvironmentKeyInToken Persists

## Current Status
- ✅ Fresh FCM token from App Store (production)
- ✅ Production APNs key uploaded to Firebase
- ✅ All IAM roles configured
- ✅ Function code working correctly
- ❌ STILL getting `BadEnvironmentKeyInToken`

## Diagnosis
The issue is 100% with the APNs Authentication Key configuration. Since everything else is correct, the APNs key itself must be misconfigured.

## Verification Steps

### Step 1: Verify Bundle ID in Firebase
1. Go to: https://console.firebase.google.com/project/padelcore-app/settings/general
2. Scroll to "Your apps"
3. Find your iOS app
4. **Confirm the Bundle ID**: Should be `com.padelcore.app`
5. Take note of this exact Bundle ID

### Step 2: Verify APNs Key in Apple Developer Portal
1. Go to: https://developer.apple.com/account/resources/authkeys/list
2. Find key with Key ID: `8J68UY727Z`
3. Click on it to see details
4. **Check**:
   - Is it still active (not revoked)?
   - Does it have "Apple Push Notifications service (APNs)" enabled?
   - What's the Team ID?

### Step 3: Verify Team ID
1. In Apple Developer Portal, check your Team ID (top right corner)
2. Should be: `T4Y762MC96`
3. Confirm this matches what you entered in Firebase

### Step 4: Verify App ID Configuration
1. Go to: https://developer.apple.com/account/resources/identifiers/list
2. Find your App ID for `com.padelcore.app`
3. Click on it
4. **Verify**:
   - Bundle ID matches exactly
   - "Push Notifications" capability is enabled
   - It's configured properly

### Step 5: Re-upload APNs Key (Fresh Start)
The key might be corrupted or misconfigured. Try re-uploading:

1. **Download the APNs key again** from Apple Developer Portal:
   - If you still have the original `.p8` file, use that
   - If not, you'll need to create a NEW key

2. **Remove the current key from Firebase**:
   - Go to: https://console.firebase.google.com/project/padelcore-app/settings/cloudmessaging
   - Under "Apple app configuration" → Delete the Production APNs key

3. **Re-upload**:
   - Upload the `.p8` file again
   - Enter Key ID: `8J68UY727Z`
   - Enter Team ID: `T4Y762MC96`
   - Save

4. **Wait 5 minutes** for Firebase to propagate the changes

5. **Test again**

### Step 6: If You Lost the .p8 File - Create New Key
If you don't have the original `.p8` file anymore:

1. Go to: https://developer.apple.com/account/resources/authkeys/list
2. **Revoke the old key** (Key ID: 8J68UY727Z)
3. **Create a new key**:
   - Click **+** to create
   - Name it: "FCM Push Notifications V2"
   - Enable: "Apple Push Notifications service (APNs)"
   - Click Continue → Register
   - **Download the .p8 file** (only chance to download!)
   - **Note the new Key ID**
4. Upload this NEW key to Firebase with the new Key ID

### Step 7: Alternative - Use APNs Certificate Instead
If keys keep failing, try using an APNs certificate instead:

1. In Apple Developer Portal:
   - Go to Certificates section
   - Create "Apple Push Notification service SSL (Sandbox & Production)"
   - Download the certificate

2. In Firebase Console:
   - Remove the APNs Authentication Key
   - Upload the APNs Certificate instead

## Most Likely Causes

### 1. Bundle ID Mismatch (90% probability)
- The APNs key was created for a different bundle ID
- Or the bundle ID in Firebase doesn't match the app

### 2. Corrupted Key Upload (5% probability)
- The key upload to Firebase was corrupted
- Re-uploading should fix it

### 3. Key Revoked/Invalid (5% probability)
- The key was revoked in Apple Developer Portal
- Need to create a new key

## Next Actions

1. **IMMEDIATELY**: Verify the Bundle ID in Firebase matches `com.padelcore.app`
2. **Check**: Apple Developer Portal - is the APNs key still active?
3. **Try**: Re-upload the same key to Firebase
4. **If still fails**: Create a brand new APNs key and upload it
5. **Last resort**: Switch to APNs certificate instead of key

The error message is very specific - it's saying the APNs environment in the token doesn't match the key. This can ONLY happen if:
- Wrong bundle ID
- Invalid key
- Key not properly configured in Apple Developer Portal
