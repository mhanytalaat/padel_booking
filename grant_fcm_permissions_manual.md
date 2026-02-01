# Manual FCM Permissions Grant (No gcloud CLI Needed)

Since you don't have `gcloud` CLI installed, here's how to grant permissions manually using the Google Cloud Console web interface.

## Step 1: Get Your Service Account Email

Your service account email is in `functions/service-account-key.json`:
```
firebase-adminsdk-fbsvc@padelcore-app.iam.gserviceaccount.com
```

## Step 2: Grant Permissions via Google Cloud Console

### Option A: Using IAM & Admin (Recommended)

1. **Go to Google Cloud Console:**
   - https://console.cloud.google.com/
   - Select project: `padelcore-app`

2. **Navigate to IAM:**
   - Click **IAM & Admin** → **IAM** (in left sidebar)

3. **Find Your Service Account:**
   - Search for: `firebase-adminsdk-fbsvc@padelcore-app.iam.gserviceaccount.com`
   - Or look for any account starting with `firebase-adminsdk-`

4. **Edit Permissions:**
   - Click the **pencil icon** (Edit) next to the service account
   - Click **ADD ANOTHER ROLE**

5. **Add These Three Roles (one at a time):**
   
   **Role 1:**
   - Type: `Firebase Cloud Messaging API Service Agent`
   - Select: `Firebase Cloud Messaging API Service Agent`
   - Click **SAVE**
   
   **Role 2:**
   - Click **ADD ANOTHER ROLE** again
   - Type: `Firebase Admin SDK Administrator Service Agent`
   - Select: `Firebase Admin SDK Administrator Service Agent`
   - Click **SAVE**
   
   **Role 3:**
   - Click **ADD ANOTHER ROLE** again
   - Type: `Service Account Token Creator`
   - Select: `Service Account Token Creator`
   - Click **SAVE**

6. **Done!** All three roles should now be listed for your service account.

### Option B: Using Service Accounts Page

1. **Go to Service Accounts:**
   - Navigate to **IAM & Admin** → **Service Accounts**

2. **Find Your Service Account:**
   - Look for: `firebase-adminsdk-fbsvc@padelcore-app.iam.gserviceaccount.com`

3. **Click on it** to open details

4. **Click "SHOW INFO PANEL"** (top right, icon with "i")

5. **Click "PRINCIPAL"** tab

6. **Click "GRANT ACCESS"**

7. **Add the three roles** (same as Option A)

## Step 3: Enable FCM API

1. **Go to APIs & Services:**
   - Navigate to **APIs & Services** → **Library**

2. **Search for "Firebase Cloud Messaging":**
   - Type: `Firebase Cloud Messaging API`

3. **Click on it** and click **ENABLE**

## Step 4: Wait and Redeploy

1. **Wait 3-5 minutes** for IAM changes to propagate

2. **Redeploy the function:**
   ```powershell
   cd functions
   firebase deploy --only functions:onNotificationCreated
   ```

3. **Test** by creating a notification in Firestore

## Verify Permissions

After granting, verify in IAM page:
- Your service account should show all three roles:
  - ✅ Firebase Cloud Messaging API Service Agent
  - ✅ Firebase Admin SDK Administrator Service Agent
  - ✅ Service Account Token Creator

## Alternative: Install gcloud CLI (Optional)

If you want to use the script later, install gcloud:

1. **Download Google Cloud SDK:**
   - https://cloud.google.com/sdk/docs/install
   - Choose "Windows" → Download installer

2. **Run the installer:**
   - Follow the installation wizard
   - Restart PowerShell after installation

3. **Authenticate:**
   ```powershell
   gcloud auth login
   ```

4. **Set project:**
   ```powershell
   gcloud config set project padelcore-app
   ```

5. **Then you can run the script:**
   ```powershell
   .\fix_service_account_permissions.ps1
   ```

## Quick Links

- **Google Cloud Console:** https://console.cloud.google.com/
- **IAM Page:** https://console.cloud.google.com/iam-admin/iam?project=padelcore-app
- **Service Accounts:** https://console.cloud.google.com/iam-admin/serviceaccounts?project=padelcore-app
- **APIs Library:** https://console.cloud.google.com/apis/library?project=padelcore-app
