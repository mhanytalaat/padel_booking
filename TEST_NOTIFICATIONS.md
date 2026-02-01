# Testing Push Notifications

## Prerequisites
1. Make sure you have an FCM token saved in Firestore:
   - Open your app and log in
   - Check Firestore console → `users` collection → your user document
   - Verify `fcmToken` field exists and has a value
   - If not, restart the app and grant notification permissions

## Testing Methods

### Method 1: Test Locally with Firebase Emulators (Recommended First)

1. **Install Firebase Tools** (if not already installed):
   ```bash
   npm install -g firebase-tools
   ```

2. **Start Firebase Emulators**:
   ```bash
   cd functions
   npm install
   firebase emulators:start --only functions,firestore
   ```

3. **Create Test Notification in Firestore Console**:
   - Go to Firebase Console → Firestore Database
   - Create collection: `notifications`
   - Add document with these fields:
     ```json
     {
       "type": "booking_status",
       "userId": "YOUR_USER_ID_HERE",
       "message": "Test notification message",
       "timestamp": [Server Timestamp],
       "read": false
     }
     ```

4. **Check Emulator Logs**:
   - Watch the terminal for function execution logs
   - You should see: "Sent X notifications successfully"

### Method 2: Test with Real Firebase (After Deploying)

1. **Deploy Functions**:
   ```bash
   cd functions
   firebase deploy --only functions:onNotificationCreated
   ```

2. **Create Test Notification in Firestore**:
   - Go to Firebase Console → Firestore Database
   - Create collection: `notifications` (if it doesn't exist)
   - Add document:
     ```json
     {
       "type": "booking_status",
       "userId": "YOUR_USER_ID_HERE",
       "bookingId": "test123",
       "status": "approved",
       "venue": "Test Venue",
       "time": "10:00 AM",
       "date": "2026-01-25",
       "message": "Your booking has been approved!",
       "timestamp": [Server Timestamp],
       "read": false
     }
     ```

3. **Check Function Logs**:
   ```bash
   firebase functions:log --only onNotificationCreated
   ```

### Method 3: Test Admin Notification

1. **Create Admin Notification**:
   ```json
   {
     "type": "booking_request",
     "userId": "some_user_id",
     "userName": "Test User",
     "phone": "+201234567890",
     "venue": "Test Venue",
     "time": "10:00 AM",
     "date": "2026-01-25",
     "bookingId": "test123",
     "status": "pending",
     "isAdminNotification": true,
     "timestamp": [Server Timestamp],
     "read": false
   }
   ```

   This will send notification to admin user (phone: +201006500506 or email: admin@padelcore.com)

## Troubleshooting

### No FCM Token Found
- Make sure user is logged in
- Check that notification permissions were granted
- Restart the app
- Check Firestore `users` collection for `fcmToken` field

### Function Not Triggering
- Check Firebase Console → Functions → Logs
- Verify the notification document was created (not updated)
- Check function deployment status

### Notification Not Received
- Verify FCM token is valid and not expired
- Check device notification settings
- For Android: Check notification channel is enabled
- For iOS: Verify APNs is configured correctly
- Check Firebase Console → Cloud Messaging → Reports

## Testing Checklist

- [ ] FCM token exists in Firestore `users` collection
- [ ] Notification permissions granted in app
- [ ] Function deployed (or emulator running)
- [ ] Test notification document created in `notifications` collection
- [ ] Function logs show successful execution
- [ ] Push notification received on device
