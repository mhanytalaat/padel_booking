# Investigation: Missing FCM Tokens

## What Happened
User reports that after deleting the Development APNs key from Firebase Console, ALL fcmToken fields disappeared from ALL users in Firestore.

## Technical Reality
Deleting an APNs authentication key from Cloud Messaging settings should NOT affect Firestore data at all. These are completely separate systems:
- **APNs keys**: Stored in Firebase Cloud Messaging configuration
- **FCM tokens**: Stored in Firestore database (`users` collection)

## Possible Explanations

### 1. User Interface Issue
- Firestore Console might be experiencing a display issue
- Try refreshing the page or opening in incognito mode

### 2. Wrong Collection/View
- User might be looking at a different collection
- Verify you're in: `users` collection, not `notifications` or another collection

### 3. Security Rules Blocking View
- Firestore security rules might be preventing console access
- This could hide fields from view in the console

### 4. Accidental Manual Deletion
- User might have accidentally deleted the field while in the console
- Check Firestore activity logs if available

### 5. Filter Applied
- Firestore console might have a filter that hides the fcmToken field
- Check if any column filters are applied

## What to Check

### 1. Verify in Firestore Console
1. Go to: https://console.firebase.google.com/project/padelcore-app/firestore
2. Navigate to `users` collection
3. Open ANY user document
4. Look for `fcmToken` field
5. If you don't see it, check if other fields are visible (like `email`, `name`, etc.)

### 2. Check Using Firebase CLI
If you have Firebase CLI installed:
```bash
firebase firestore:get users/xzfKrzEzuih28fnzIgSzkzSMoF03
```

### 3. Query from Cloud Functions
We can add a debug function to check if tokens exist in the database.

## Solutions

### If Tokens Are Really Gone
Then all users need to:
1. Delete and reinstall the app
2. Login
3. Allow notifications
4. New tokens will be generated

### If Tokens Are Just Hidden
- Fix the UI/security rule issue
- Tokens are still there, just not visible

## Next Steps
1. User should verify in Firestore Console if tokens are really gone
2. Check if other user fields are visible
3. If tokens are gone, we need to understand HOW (this shouldn't be possible from deleting APNs key)
4. If tokens exist, it's just a display issue
