# Alternative FCM Solution - Using Service Account Key with Proper Permissions

## The Problem

The default App Engine service account doesn't have FCM permissions, and we're stuck in a loop trying to grant them.

## New Approach: Use Service Account Key + Grant Permissions

Instead of relying on default credentials, we'll:
1. Use the service account key file explicitly
2. Grant the required IAM roles to that specific service account
3. This gives us full control over permissions

## Step 1: Grant Permissions to Your Service Account

Run this script to grant permissions to the service account in your `service-account-key.json`:

```powershell
.\fix_service_account_permissions.ps1
```

This script will:
- Read your service account email from `functions/service-account-key.json`
- Grant `firebase.cloudMessagingServiceAgent` role
- Grant `firebase.adminsdk.adminServiceAgent` role
- Grant `iam.serviceAccountTokenCreator` role

## Step 2: Wait for IAM Propagation

**CRITICAL:** Wait 3-5 minutes after running the script. IAM changes take time to propagate across Google Cloud.

## Step 3: Redeploy Function

```bash
cd functions
firebase deploy --only functions:onNotificationCreated
```

## Step 4: Test

Create a notification in Firestore and check the logs. You should see:
- ✅ `Firebase Admin initialized`
- ✅ `Service Account: firebase-adminsdk-...@padelcore-app.iam.gserviceaccount.com`
- ✅ `SUCCESS! Message ID: ...`

## What Changed in the Code

The function now:
1. **Explicitly loads** the service account key
2. **Initializes with project ID** for proper scoping
3. **Logs the service account email** so you can verify which one is being used

## If This Still Doesn't Work

### Option A: Download a New Service Account Key

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select project: `padelcore-app`
3. Go to **Project Settings** → **Service Accounts**
4. Click **Generate New Private Key**
5. Download the JSON file
6. Replace `functions/service-account-key.json` with the new file
7. Run `.\fix_service_account_permissions.ps1` again
8. Redeploy

### Option B: Use Firebase Admin SDK with Application Default Credentials

If you have `gcloud` CLI authenticated, you can use:

```javascript
admin.initializeApp({
  projectId: "padelcore-app"
});
```

But this requires you to be authenticated with `gcloud auth application-default login`.

### Option C: Check Service Account in Google Cloud Console

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select project: `padelcore-app`
3. Go to **IAM & Admin** → **IAM**
4. Find your service account: `firebase-adminsdk-...@padelcore-app.iam.gserviceaccount.com`
5. Click **Edit** (pencil icon)
6. Manually add these roles:
   - `Firebase Cloud Messaging API Service Agent`
   - `Firebase Admin SDK Administrator Service Agent`
   - `Service Account Token Creator`
7. Click **SAVE**
8. Wait 3-5 minutes
9. Redeploy

## Verify Permissions

Check if roles are granted:

```bash
# Get your service account email from the JSON file first
$key = Get-Content functions\service-account-key.json | ConvertFrom-Json
$email = $key.client_email

# Check IAM bindings
gcloud projects get-iam-policy padelcore-app \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:$email" \
  --format="table(bindings.role)"
```

You should see the three roles listed.

## Why This Approach Works

1. **Explicit Service Account:** We know exactly which service account is being used
2. **Full Control:** We can grant permissions directly to that account
3. **No Ambiguity:** No guessing about which default service account is being used
4. **Works Everywhere:** Same approach works in Cloud Functions and locally

## Troubleshooting

### Error: "Permission denied" when running script

You need `Project IAM Admin` or `Owner` role. Ask your project owner to:
1. Run the script, OR
2. Grant you `Project IAM Admin` role

### Error: "Service account key file not found"

Make sure `functions/service-account-key.json` exists and is valid JSON.

### Still getting auth error after 5 minutes

1. Double-check the service account email in logs matches the one you granted permissions to
2. Verify FCM API is enabled:
   ```bash
   gcloud services list --enabled --project=padelcore-app | grep messaging
   ```
3. Try downloading a fresh service account key from Firebase Console
4. Check function logs for the exact service account email being used
