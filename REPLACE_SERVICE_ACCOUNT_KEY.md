# Replace Service Account Key File

## The Issue

Even though the service account has all the correct roles, the key file might be:
- Corrupted
- Outdated
- Missing some internal metadata
- Not properly linked to the current permissions

## Solution: Download Fresh Service Account Key

1. **Go to Firebase Console:**
   - https://console.firebase.google.com/project/padelcore-app/settings/serviceaccounts/adminsdk

2. **Click "Generate New Private Key"**
   - This creates a fresh key with current permissions

3. **Download the JSON file**

4. **Replace the old key:**
   - Delete: `functions/service-account-key.json`
   - Copy the new downloaded file to: `functions/service-account-key.json`

5. **Redeploy:**
   ```powershell
   cd functions
   npm install  # Install updated firebase-admin
   firebase deploy --only functions:onNotificationCreated
   ```

## Why This Works

A fresh key file ensures:
- Proper linking to current IAM roles
- Correct internal metadata
- No corruption issues
- Latest authentication format

The new key will automatically have access to all the roles you've granted.
