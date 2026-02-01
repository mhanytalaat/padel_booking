# FCM Configuration Reference - Already Configured

**Date:** January 27, 2026  
**Status:** ✅ CONFIGURED - Do not ask about these again

## ✅ Already Configured

### 1. Firebase Cloud Messaging API
- **Status:** ✅ ENABLED
- **Location:** Google Cloud Console → APIs & Services
- **Note:** Already configured, do not check again

### 2. Available IAM Roles for Service Account

The following roles are available for assignment to the service account:

1. Cloud Functions Admin
2. Cloud Functions Invoker
3. Firebase Admin
4. **Firebase Admin SDK Administrator Service Agent** ✅ (Needed for FCM)
5. Firebase App Check Admin
6. Firebase Authentication Admin
7. **Firebase Cloud Messaging Admin** ✅ (Needed for FCM)
8. **Firebase Cloud Messaging API Admin** ✅ (Alternative for FCM)
9. **Service Account Token Creator** ✅ (Needed for FCM)
10. Storage Admin

## Required Roles for FCM

Based on the error and available roles, the service account needs:

1. ✅ **Firebase Admin SDK Administrator Service Agent** (Role #4)
2. ✅ **Firebase Cloud Messaging Admin** (Role #7) OR **Firebase Cloud Messaging API Admin** (Role #8)
3. ✅ **Service Account Token Creator** (Role #9)

## Service Account Email

```
firebase-adminsdk-fbsvc@padelcore-app.iam.gserviceaccount.com
```

## Quick Grant Instructions (If Needed)

1. Go to: https://console.cloud.google.com/iam-admin/iam?project=padelcore-app
2. Find: `firebase-adminsdk-fbsvc@padelcore-app.iam.gserviceaccount.com`
3. Click Edit (pencil icon)
4. Add these roles:
   - Firebase Admin SDK Administrator Service Agent
   - Firebase Cloud Messaging Admin (or Firebase Cloud Messaging API Admin)
   - Service Account Token Creator
5. Save

## Notes

- FCM API is already enabled - do not check again
- These roles are available - do not ask about configuration again
- User can install gcloud CLI if needed for automation
