# Debug FCM Token Issue

## Current Situation

Even after reinstalling the app, we're still getting:
```
ApnsError: BadEnvironmentKeyInToken (403)
```

## What This Means

The FCM token stored in Firestore is STILL for the wrong environment, OR the token wasn't actually regenerated.

## Check Token in Firestore

1. Go to Firestore: https://console.firebase.google.com/project/padelcore-app/firestore
2. Navigate to: `users` collection → user ID: `xzfKrzEzuih28fnzIgSzkzSMoF03`
3. Check the `fcmToken` field
4. Check `fcmTokenUpdatedAt` timestamp

**Questions to answer:**
- Was `fcmTokenUpdatedAt` updated recently (after you reinstalled)?
- Did the `fcmToken` value change?

## Possible Causes

### 1. Token Wasn't Regenerated
- App didn't request notification permissions properly
- Token save failed silently
- User document doesn't exist yet

### 2. APNs Key Configuration Issue
Looking at your Firebase screenshot:
- You have both "Development APNs auth key" AND "Production APNs auth key"
- Both show: Key ID: `8J68UY727Z`, Team ID: `T4Y762MC96`

**This is suspicious!** Same Key ID for both means you uploaded the same .p8 file twice.

An APNs Authentication Key (.p8) works for BOTH environments, so:
- **Delete one of them** (keep only one - either Development or Production)
- Firebase will use it for both environments automatically

### 3. Token Environment Mismatch
Where did you install the app from?
- **TestFlight** = Production environment ✅
- **Xcode debug build** = Development environment ⚠️
- **App Store** = Production environment ✅

Your entitlements say `production`, so TestFlight or App Store should work.

## Next Steps

### Step 1: Check Firestore Token
Look at the user document and confirm:
- Does `fcmToken` exist?
- Was `fcmTokenUpdatedAt` updated today?

### Step 2: Fix APNs Key Configuration
In Firebase Console → Cloud Messaging:
1. **Delete the "Development APNs auth key"** (since you have production)
2. Keep only the "Production APNs auth key"
3. Wait 2-3 minutes for Firebase to update

### Step 3: Force Token Refresh in App
Add debug logging to see if token is being generated:

In `lib/services/notification_service.dart`, change line 69-73 to:

```dart
// Get FCM token
String? token = await _messaging.getToken();
debugPrint('🔥🔥🔥 FCM TOKEN GENERATION ATTEMPT 🔥🔥🔥');
if (token != null) {
  await _saveTokenToFirestore(token);
  debugPrint('✅ FCM Token saved: ${token.substring(0, 20)}...');
  debugPrint('   Full token length: ${token.length}');
} else {
  debugPrint('❌ FCM Token is NULL! Permission denied?');
}
```

Rebuild and reinstall. Check Flutter console logs.

### Step 4: Test with Android First
To isolate the issue, test with an Android device:
1. Install app on Android
2. Login and allow notifications
3. Create notification in Firestore
4. Check if it works

If Android works but iOS doesn't → APNs configuration issue
If both fail → Service account or code issue

## What We Know

✅ Service account has all required IAM roles
✅ FCM API is enabled
✅ APNs keys are uploaded to Firebase
✅ Function reaches FCM API successfully
❌ APNs rejects the token with environment mismatch

The issue is 100% related to APNs token/key environment matching.
