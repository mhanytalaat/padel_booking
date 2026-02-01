# Deploy Updated Notification Function

## Step 1: Re-authenticate with Firebase

Open PowerShell/Terminal and run:

```bash
cd C:\projects\padel_booking\functions
firebase login --reauth
```

Follow the prompts to authenticate in your browser.

## Step 2: Deploy the Function

After authentication succeeds, run:

```bash
firebase deploy --only functions:onNotificationCreated
```

This will deploy the updated code that uses `sendMulticast()` instead of `sendAll()`, which should fix the 404 error.

## Step 3: Test Again

After deployment completes:
1. Delete your old test notification document in Firestore
2. Create a new test notification document (with userId, type, message, read, timestamp)
3. Check the function logs - you should see success messages instead of 404 errors
4. Check your device - you should receive the push notification!

## What Changed

The function now uses:
- `send()` for single token (more reliable)
- `sendMulticast()` for multiple tokens (instead of the broken `sendAll()`)

This should resolve the `/batch` endpoint 404 error.
