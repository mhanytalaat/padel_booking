# Quick Fix: Grant FCM Permissions (No gcloud CLI)

## Your Service Account Email
```
firebase-adminsdk-fbsvc@padelcore-app.iam.gserviceaccount.com
```

## Quick Steps (5 minutes)

### 1. Open Google Cloud Console
👉 https://console.cloud.google.com/iam-admin/iam?project=padelcore-app

### 2. Find Your Service Account
- Search for: `firebase-adminsdk-fbsvc`
- Or look for any account with `firebase-adminsdk-` prefix

### 3. Click Edit (Pencil Icon)
- Click the pencil icon next to the service account

### 4. Add These 3 Roles (Click "ADD ANOTHER ROLE" for each):

1. **Firebase Cloud Messaging API Service Agent**
   - Search: `Firebase Cloud Messaging API Service Agent`
   - Select it
   - Click **SAVE**

2. **Firebase Admin SDK Administrator Service Agent**
   - Click "ADD ANOTHER ROLE" again
   - Search: `Firebase Admin SDK Administrator Service Agent`
   - Select it
   - Click **SAVE**

3. **Service Account Token Creator**
   - Click "ADD ANOTHER ROLE" again
   - Search: `Service Account Token Creator`
   - Select it
   - Click **SAVE**

### 5. Enable FCM API
👉 https://console.cloud.google.com/apis/library/firebasecloudmessaging.googleapis.com?project=padelcore-app
- Click **ENABLE**

### 6. Wait 3-5 Minutes
IAM changes need time to propagate

### 7. Redeploy
```powershell
cd functions
firebase deploy --only functions:onNotificationCreated
```

### 8. Test
Create a notification in Firestore and check logs!

## Done! ✅

If you still get errors after 5 minutes, the service account might need different permissions. Let me know!
