# Deploy and Test - Everything is Configured

## ✅ Already Configured
- FCM API: Enabled
- Service Account: `padelcore-app@appspot.gserviceaccount.com` has:
  - Firebase Cloud Messaging API Admin ✅
  - Service Account Token Creator ✅
  - Firebase Admin ✅

## Deploy

```powershell
cd functions
firebase deploy --only functions:onNotificationCreated
```

## Test

Create a notification in Firestore with:
```json
{
  "userId": "YOUR_USER_ID",
  "title": "Test",
  "body": "Test"
}
```

## Check Logs

```powershell
firebase functions:log --only onNotificationCreated
```

Should see:
```
✅ Firebase Admin initialized with default credentials
   Using App Engine default service account (padelcore-app@appspot.gserviceaccount.com)
=== FCM Function Start ===
Token found, sending FCM...
✅✅✅ SUCCESS! Message ID: ...
```

If it still fails, the error message will tell us what's wrong.
