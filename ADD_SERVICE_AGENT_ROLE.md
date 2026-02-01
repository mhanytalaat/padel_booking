# Add Firebase Cloud Messaging API Service Agent Role

## The Issue

Even though you have "Firebase Cloud Messaging API Admin", the Admin SDK needs the **"Firebase Cloud Messaging API Service Agent"** role specifically.

These are **different roles**:
- **Firebase Cloud Messaging API Admin** - Full admin access
- **Firebase Cloud Messaging API Service Agent** - Required for Admin SDK to authenticate with FCM API

## Quick Fix

### Add This Role to `padelcore-app@appspot.gserviceaccount.com`:

1. Go to: https://console.cloud.google.com/iam-admin/iam?project=padelcore-app

2. Find: `padelcore-app@appspot.gserviceaccount.com`

3. Click **Edit** (pencil icon)

4. Click **ADD ANOTHER ROLE**

5. Search for and select: **Firebase Cloud Messaging API Service Agent**
   - (NOT "Firebase Cloud Messaging API Admin" - that's different!)

6. Click **SAVE**

7. Wait 3-5 minutes

8. Test again

## Why This Role is Needed

The Admin SDK uses service account impersonation to call FCM. The "Service Agent" role allows the service account to act as the FCM API service, which is what the Admin SDK needs for authentication.

The "Admin" role gives you management permissions, but doesn't allow the service account to authenticate as the FCM service itself.

## After Adding the Role

The function should work. The service account will have:
- ✅ Firebase Cloud Messaging API Service Agent (NEW - needed for auth)
- ✅ Firebase Cloud Messaging API Admin (you already have this)
- ✅ Service Account Token Creator (you already have this)
- ✅ Firebase Admin (you already have this)
