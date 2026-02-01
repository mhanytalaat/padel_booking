# Check Exact Role Name

## Critical Check

The error is **THIRD_PARTY_AUTH_ERROR** which means the service account cannot authenticate.

You said you have these roles on `firebase-adminsdk-fbsvc@padelcore-app.iam.gserviceaccount.com`:
- Firebase Cloud Messaging API Admin ✅
- Firebase Admin SDK Administrator Service Agent ✅
- Service Account Token Creator ✅

## But You Might Be Missing This One:

**Firebase Cloud Messaging API Service Agent** 
- Role ID: `roles/firebase.cloudMessagingServiceAgent`
- This is DIFFERENT from "Firebase Cloud Messaging API Admin"

## Check Now:

1. Go to: https://console.cloud.google.com/iam-admin/iam?project=padelcore-app
2. Find: `firebase-adminsdk-fbsvc@padelcore-app.iam.gserviceaccount.com`
3. Look at the EXACT role names - do you see:
   - ✅ Firebase Cloud Messaging API Admin (you have this)
   - ❓ **Firebase Cloud Messaging API Service Agent** (DO YOU HAVE THIS?)

If you DON'T have "Firebase Cloud Messaging API Service Agent", that's the problem!

## Add It:

1. Click Edit on the service account
2. Add role: **Firebase Cloud Messaging API Service Agent**
3. Save
4. Wait 5 minutes
5. Redeploy

The "Service Agent" role is what allows the service account to **impersonate** the FCM service for OAuth2 authentication. The "Admin" role doesn't do that.
