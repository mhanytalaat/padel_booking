# Fix APNs Key Issue - Immediate Actions

## The Problem
Everything is configured correctly (Bundle ID, Team ID, fresh production token), but still getting `BadEnvironmentKeyInToken`. This means the APNs key itself is the issue.

## Solution 1: Re-upload APNs Key (Try This First)

### Step 1: Go to Apple Developer Portal
https://developer.apple.com/account/resources/authkeys/list

Find the key with ID: `8J68UY727Z`

**Do you still have the `.p8` file saved on your computer?**
- Look in Downloads folder
- Or search for `*.p8` files
- The filename would be like: `AuthKey_8J68UY727Z.p8`

### Step 2A: If You Have the .p8 File
1. Go to Firebase Console: https://console.firebase.google.com/project/padelcore-app/settings/cloudmessaging
2. Scroll to "Apple app configuration"
3. Click **Delete** on the Production APNs auth key
4. Click **Upload** 
5. Select the `AuthKey_8J68UY727Z.p8` file
6. Enter Key ID: `8J68UY727Z`
7. Enter Team ID: `T4Y762MC96`
8. Click **Upload**
9. Wait 5 minutes
10. Test notification again

### Step 2B: If You DON'T Have the .p8 File (Create New Key)
1. Go to: https://developer.apple.com/account/resources/authkeys/list
2. Click **Revoke** on the old key (8J68UY727Z)
3. Click **+** to create a new key
4. Name: "FCM Production V2"
5. Enable: **Apple Push Notifications service (APNs)**
6. Click **Continue** → **Register**
7. **DOWNLOAD the .p8 file immediately** (you can only download once!)
8. Note the new **Key ID** (will be different)
9. Go to Firebase Console: https://console.firebase.google.com/project/padelcore-app/settings/cloudmessaging
10. Delete the old Production APNs auth key
11. Upload the NEW .p8 file
12. Enter the NEW Key ID
13. Enter Team ID: `T4Y762MC96`
14. Click **Upload**
15. Wait 5 minutes
16. Test notification again

## Solution 2: Switch to Admin SDK (Revert Code)

The REST API approach might have issues. Let's go back to using Firebase Admin SDK which is more reliable:

### Revert to Simple Admin SDK Code
I can update the functions code to use the simple Admin SDK approach with the latest version.

## Which Solution Do You Want?

**Option A**: Try re-uploading the APNs key (if you have the .p8 file)
**Option B**: Create a brand new APNs key
**Option C**: Revert to using Firebase Admin SDK in the code instead of REST API

Let me know which one and I'll guide you through it step by step.
