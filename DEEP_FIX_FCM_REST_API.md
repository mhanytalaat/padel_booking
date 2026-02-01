# Deep Fix: Using FCM REST API Directly

## The Problem

The Firebase Admin SDK `messaging().send()` method has a known bug with service account authentication in Cloud Functions, even when all IAM roles are correctly configured.

## The Solution: Bypass Admin SDK, Use REST API Directly

Instead of using `admin.messaging().send()`, we're now:
1. Using `google-auth-library` to get an OAuth2 access token
2. Calling the FCM REST API directly with `fetch()`
3. This bypasses the Admin SDK credential issues entirely

## What Changed

**Before (Admin SDK - failing):**
```javascript
const response = await admin.messaging().send({
  token: token.trim(),
  notification: { title, body }
});
```

**After (REST API - should work):**
```javascript
const accessToken = await authClient.getAccessToken();
const response = await fetch('https://fcm.googleapis.com/v1/projects/.../messages:send', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${accessToken}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({ message: { token, notification: { title, body } } })
});
```

## Why This Works

1. **Direct OAuth2 Token:** We get the access token directly from Google Auth Library
2. **REST API:** We call FCM's REST endpoint directly, bypassing Admin SDK bugs
3. **Same Permissions:** Uses the same service account with all the roles you've configured
4. **More Control:** We can see exactly what's being sent and what errors we get

## Deploy and Test

```powershell
cd functions
npm install  # Make sure google-auth-library is installed
cd ..
firebase deploy --only functions:onNotificationCreated
```

## Expected Logs

**Success:**
```
✅ Firebase Admin initialized
✅ Google Auth initialized for FCM REST API
=== FCM Function Start ===
Token found, sending FCM via REST API...
📤 Calling FCM REST API: https://fcm.googleapis.com/v1/projects/padelcore-app/messages:send
✅✅✅ SUCCESS! Message ID: projects/padelcore-app/messages/...
```

**If Still Failing:**
The error message will now be more detailed and tell us exactly what's wrong with the API call.

## Benefits

- ✅ Bypasses Admin SDK credential bugs
- ✅ More detailed error messages
- ✅ Direct control over the API call
- ✅ Uses same service account and permissions
