# Fix FCM Permissions - Step by Step Guide

## Current Error
```
messaging/third-party-auth-error
Request is missing required authentication credential
```

## Solution: Grant IAM Roles to Default Service Account

### Step 1: Run the Permission Grant Script

```powershell
.\grant_fcm_permissions.ps1
```

This will:
- Enable FCM API
- Grant `firebase.cloudMessagingServiceAgent` role
- Grant `firebase.adminsdk.adminServiceAgent` role  
- Grant `iam.serviceAccountTokenCreator` role

### Step 2: Wait for Propagation

**CRITICAL:** Wait 2-3 minutes after running the script for IAM changes to propagate across Google Cloud.

### Step 3: Redeploy the Function

```bash
cd functions
firebase deploy --only functions:onNotificationCreated
```

### Step 4: Test

1. Create a notification document in Firestore:
   ```json
   {
     "userId": "YOUR_USER_ID",
     "title": "Test Notification",
     "body": "Testing FCM permissions"
   }
   ```

2. Check function logs:
   ```bash
   firebase functions:log --only onNotificationCreated
   ```

3. You should see:
   - ✅ `Firebase Admin initialized`
   - ✅ `SUCCESS! Message ID: ...`

## Alternative: Manual IAM Role Granting

If the script doesn't work, grant roles manually:

### Option A: Using Google Cloud Console

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select project: `padelcore-app`
3. Go to **IAM & Admin** → **IAM**
4. Find: `padelcore-app@appspot.gserviceaccount.com`
5. Click **Edit** (pencil icon)
6. Click **ADD ANOTHER ROLE**
7. Add these roles:
   - `Firebase Cloud Messaging API Service Agent`
   - `Firebase Admin SDK Administrator Service Agent`
   - `Service Account Token Creator`
8. Click **SAVE**

### Option B: Using gcloud CLI

```bash
# Set variables
PROJECT_ID="padelcore-app"
SERVICE_ACCOUNT="${PROJECT_ID}@appspot.gserviceaccount.com"

# Enable FCM API
gcloud services enable firebasecloudmessaging.googleapis.com --project=$PROJECT_ID

# Grant roles
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/firebase.cloudMessagingServiceAgent"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/firebase.adminsdk.adminServiceAgent"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/iam.serviceAccountTokenCreator"
```

## Verify Permissions

Check if roles are granted:

```bash
gcloud projects get-iam-policy padelcore-app \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:padelcore-app@appspot.gserviceaccount.com" \
  --format="table(bindings.role)"
```

You should see:
- `roles/firebase.cloudMessagingServiceAgent`
- `roles/firebase.adminsdk.adminServiceAgent`
- `roles/iam.serviceAccountTokenCreator`

## Troubleshooting

### Still Getting Error After Granting Roles?

1. **Wait longer:** IAM changes can take up to 5 minutes to propagate
2. **Check the service account:** Make sure you're granting to `padelcore-app@appspot.gserviceaccount.com`
3. **Verify FCM API is enabled:**
   ```bash
   gcloud services list --enabled --project=padelcore-app | grep messaging
   ```
4. **Check function logs** for the exact error message
5. **Try redeploying** the function after waiting

### Error: Permission Denied

If you get "Permission denied" when running the script:
- You need `Project IAM Admin` or `Owner` role in the project
- Ask your project owner to grant the roles

### Using a Different Service Account?

If you're using a custom service account (not the default):
1. Replace `padelcore-app@appspot.gserviceaccount.com` with your service account email
2. Run the same commands with your service account email

## Expected Logs After Fix

**Success:**
```
✅ Firebase Admin initialized
   Using default credentials (App Engine service account)
=== FCM Function Start ===
Token found, sending FCM...
✅✅✅ SUCCESS! Message ID: projects/padelcore-app/messages/0:...
```

**Still Failing:**
```
❌ ERROR Code: messaging/third-party-auth-error
❌ ERROR Message: Request is missing required authentication credential
```

If you still see the error after waiting 3-5 minutes and redeploying, the service account might need additional permissions or there's a different issue.

## Next Steps After Fix

Once it works:
1. ✅ Remove the service account key file from the function (not needed)
2. ✅ Test with different notification types
3. ✅ Monitor function logs for any issues
4. ✅ Set up error alerting if needed
