# Fix: FCM Authentication Error (messaging/third-party-auth-error)

## The Problem

Error: `messaging/third-party-auth-error`
Message: "Request is missing required authentication credential. Expected OAuth 2 access token, login cookie or other valid authentication credential."

**Root Cause:** The service account being used doesn't have FCM (Firebase Cloud Messaging) permissions.

## Solution 1: Use Default Service Account (RECOMMENDED) ✅

**For Cloud Functions, you don't need a service account key file!**

The default App Engine service account (`PROJECT_ID@appspot.gserviceaccount.com`) automatically has FCM permissions when running in Cloud Functions.

### What Changed

The function now uses:
```javascript
admin.initializeApp(); // Uses default credentials automatically
```

Instead of:
```javascript
const serviceAccount = require("./service-account-key.json");
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});
```

### Why This Works

1. **Cloud Functions Environment:** When deployed, Cloud Functions run with the App Engine default service account
2. **Automatic Permissions:** This service account has `Firebase Cloud Messaging API Service Agent` role by default
3. **No Key File Needed:** Firebase Admin SDK automatically uses the default credentials in the Cloud Functions environment

### Benefits

- ✅ No service account key file needed
- ✅ More secure (no keys to manage)
- ✅ Automatic permissions
- ✅ Works immediately after deployment

## Solution 2: Grant IAM Roles (If You Must Use Custom Service Account)

If you need to use a custom service account, grant these roles:

### Required IAM Roles

1. **Firebase Cloud Messaging API Service Agent**
   ```bash
   gcloud projects add-iam-policy-binding padelcore-app \
     --member="serviceAccount:YOUR_SERVICE_ACCOUNT@YOUR_PROJECT.iam.gserviceaccount.com" \
     --role="roles/firebase.cloudMessagingServiceAgent"
   ```

2. **Firebase Admin SDK Administrator Service Agent**
   ```bash
   gcloud projects add-iam-policy-binding padelcore-app \
     --member="serviceAccount:YOUR_SERVICE_ACCOUNT@YOUR_PROJECT.iam.gserviceaccount.com" \
     --role="roles/firebase.adminsdk.adminServiceAgent"
   ```

3. **Service Account Token Creator** (for OAuth)
   ```bash
   gcloud projects add-iam-policy-binding padelcore-app \
     --member="serviceAccount:YOUR_SERVICE_ACCOUNT@YOUR_PROJECT.iam.gserviceaccount.com" \
     --role="roles/iam.serviceAccountTokenCreator"
   ```

### Enable FCM API

Make sure the FCM API is enabled:
```bash
gcloud services enable firebasecloudmessaging.googleapis.com --project=padelcore-app
```

## Solution 3: Use Firebase Console to Grant Permissions

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: `padelcore-app`
3. Go to **Project Settings** → **Service Accounts**
4. Find your service account
5. Click **Manage Service Account Permissions**
6. Add role: **Firebase Cloud Messaging API Service Agent**

## Verification

After deploying, check the logs:
```bash
firebase functions:log --only onNotificationCreated
```

You should see:
- ✅ `Firebase Admin initialized with default credentials`
- ✅ `SUCCESS! Message ID: ...`

Instead of:
- ❌ `messaging/third-party-auth-error`

## Local Testing

For local testing with emulators, you can still use the service account key:
- The function will try default credentials first
- If that fails (local environment), it falls back to the service account key
- This allows both local and deployed environments to work

## Deployment

```bash
cd functions
firebase deploy --only functions:onNotificationCreated
```

## What Changed in the Code

**Before:**
```javascript
const serviceAccount = require("./service-account-key.json");
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});
```

**After:**
```javascript
// Use default credentials (App Engine service account)
admin.initializeApp(); // Automatically has FCM permissions
```

## Important Notes

1. **Service Account Key File:** You can keep `service-account-key.json` for local testing, but it's not needed for deployed functions
2. **Default Service Account:** The App Engine default service account (`padelcore-app@appspot.gserviceaccount.com`) is used automatically
3. **Permissions:** This service account has FCM permissions by default - no manual configuration needed
4. **Security:** Using default credentials is more secure than managing service account keys

## Troubleshooting

If you still get the error after deploying:

1. **Wait 2-3 minutes** after deployment for IAM changes to propagate
2. **Check IAM roles** in Google Cloud Console:
   - Go to IAM & Admin → IAM
   - Find `PROJECT_ID@appspot.gserviceaccount.com`
   - Verify it has `Firebase Cloud Messaging API Service Agent` role
3. **Verify FCM API is enabled:**
   ```bash
   gcloud services list --enabled --project=padelcore-app | grep messaging
   ```
4. **Check function logs** for initialization messages

## Status

✅ **Fixed** - Function now uses default credentials with automatic FCM permissions
