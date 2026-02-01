# Create New APNs Key - Step by Step

## Part 1: Apple Developer Portal

1. Go to: https://developer.apple.com/account/resources/authkeys/list

2. Click **"+"** (Create a key button)

3. Fill in:
   - **Key Name**: FCM Push V2
   - Check: **Apple Push Notifications service (APNs)**

4. Click **Continue**

5. Click **Register**

6. **CRITICAL**: Click **Download** immediately
   - The file will be named: `AuthKey_XXXXXXXX.p8` (where X's are the new Key ID)
   - **Save this file** - you can ONLY download it once!
   - **Note the Key ID** shown on screen (8-10 characters)

7. Your Team ID is: `T4Y762MC96` (you already have this)

## Part 2: Upload to Firebase

1. Go to: https://console.firebase.google.com/project/padelcore-app/settings/cloudmessaging

2. Scroll to **"Apple app configuration"**

3. Click **Delete** on the existing Production APNs auth key

4. Click **Upload**

5. Select the `.p8` file you just downloaded

6. Enter:
   - **Key ID**: [the new Key ID from step 6 above]
   - **Team ID**: `T4Y762MC96`

7. Click **Upload**

8. **Wait 5 minutes** for Firebase to propagate

## Part 3: Test

1. Create notification in Firestore:
   ```
   userId: xzfKrzEzuih28fnzIgSzkzSMoF03
   title: "New Key Test"
   body: "Testing with fresh APNs key"
   ```

2. Check Cloud Functions logs

If this works → DONE!
If still fails → We'll try Admin SDK code fix

## Save the .p8 File!

**IMPORTANT**: Save the `.p8` file somewhere safe:
- Don't lose it
- Back it up
- You'll need it if you ever need to re-upload

Once you complete this, let me know the result!
