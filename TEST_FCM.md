# Test FCM Notification Function

## Quick Test

### Option 1: Manual Test in Firebase Console

1. **Go to Firestore:**
   - https://console.firebase.google.com/project/padelcore-app/firestore

2. **Create a notification document:**
   - Collection: `notifications`
   - Document ID: (auto-generate)
   - Fields:
     ```json
     {
       "userId": "YOUR_USER_ID_FROM_USERS_COLLECTION",
       "title": "Test Notification",
       "body": "Testing FCM function"
     }
     ```

3. **Check Function Logs:**
   ```powershell
   firebase functions:log --only onNotificationCreated
   ```

4. **Check the notification document:**
   - It should update with `status: "sent"` and `fcmMessageId` if successful
   - Or `status: "failed"` with `error` field if it failed

### Option 2: Use Test Script

1. **Install dependencies (if not done):**
   ```powershell
   cd functions
   npm install
   cd ..
   ```

2. **Run test script:**
   ```powershell
   node test_fcm_notification.js
   ```

3. **Check logs:**
   ```powershell
   firebase functions:log --only onNotificationCreated
   ```

## What to Look For

### ✅ Success:
```
✅ Firebase Admin initialized with service account key
   Service Account: firebase-adminsdk-fbsvc@padelcore-app.iam.gserviceaccount.com
=== FCM Function Start ===
Token found, sending FCM...
✅✅✅ SUCCESS! Message ID: projects/padelcore-app/messages/...
```

### ❌ Still Failing:
```
❌ ERROR Code: messaging/third-party-auth-error
❌ ERROR Message: Request is missing required authentication credential
```

## If It Still Fails

1. **Verify fresh service account key was downloaded**
2. **Check the notification document in Firestore** - it should have `status` and `error` fields
3. **Share the exact error message** from the logs
