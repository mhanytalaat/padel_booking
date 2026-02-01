# Final FCM Debug Plan - App Store Production Issue

## Current Situation
- ✅ App installed from App Store (Production)
- ✅ Production APNs key configured in Firebase
- ✅ Entitlements set to `production`
- ✅ FCM token updated today
- ❌ Still getting `BadEnvironmentKeyInToken`

## The Problem
Even with correct setup, the FCM token might be "tainted" from previous configurations or Firebase is caching old settings.

## Solution: Force Complete Token Regeneration

### Step 1: Update notification_service.dart
I've updated the code to force delete the old token and generate a completely fresh one.

### Step 2: Test on App Store Version
1. Make sure you have the **App Store** version installed (not TestFlight)
2. Deploy the updated Flutter code:
   ```powershell
   flutter build ios --release
   ```
3. Upload to App Store or use Codemagic to build and distribute
4. Wait for App Store to process (or use Codemagic to upload to TestFlight temporarily for testing)
5. Install the new version
6. Login and allow notifications
7. Check Flutter console logs - you should see:
   ```
   🔄 Old token deleted, generating new token...
   ✅ NEW FCM Token: [token]
   ```
8. Create notification in Firestore
9. Check Cloud Functions logs

### Step 3: Verify APNs Key Configuration
While waiting for the build, double-check Firebase Console:
1. Go to: https://console.firebase.google.com/project/padelcore-app/settings/cloudmessaging
2. Under "Apple app configuration" → "Production APNs auth key"
3. Verify:
   - Key ID: `8J68UY727Z`
   - Team ID: `T4Y762MC96`
   - These should match what you see in: https://developer.apple.com/account/resources/authkeys/list

### Step 4: Alternative - Test with Android First
To isolate if this is iOS-specific:
1. Install app on Android device
2. Login and allow notifications
3. Create notification in Firestore
4. If Android works → confirms it's APNs configuration issue
5. If Android fails → service account or function code issue

## Why This Might Still Fail

If after complete token regeneration it still fails, then the issue is:

### Possibility 1: APNs Key Itself is Wrong
- The .p8 file might be for a different app
- The Key ID or Team ID might be wrong
- The key might be revoked in Apple Developer Portal

### Possibility 2: Bundle ID Mismatch
- APNs key might be configured for wrong bundle ID
- Check Firebase Console → Project Settings → iOS app
- Bundle ID should be: `com.padelcore.app`

### Possibility 3: Provisioning Profile Issue
- The App Store build might have been signed with wrong provisioning profile
- Check Codemagic build logs for signing details
- Verify provisioning profile has correct entitlements

## Next Actions

1. ✅ I've updated `notification_service.dart` to force token regeneration
2. ⏳ You need to build and deploy the new version
3. ⏳ Test again after new version is installed
4. ⏳ If still fails, we'll check APNs key details in Apple Developer Portal

## If You Want to Test NOW Without Rebuilding

You can manually delete the token from Firestore:
1. Go to Firestore: https://console.firebase.google.com/project/padelcore-app/firestore/data/users/xzfKrzEzuih28fnzIgSzkzSMoF03
2. Delete the `fcmToken` field
3. Delete the app from iPhone
4. Reinstall from App Store
5. Login and allow notifications (new token will be generated)
6. Test notification

This is quicker than rebuilding!
