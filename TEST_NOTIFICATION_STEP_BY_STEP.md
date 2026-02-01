# Step-by-Step Guide: Testing Push Notifications

## Prerequisites Checklist

Before testing, ensure:
- [ ] You're logged into the app on your device
- [ ] Notification permissions are granted
- [ ] Cloud Function is deployed (see Step 1)
- [ ] Your FCM token exists in Firestore (see Step 2)

---

## Step 1: Verify Cloud Function is Deployed

### Option A: Check via Firebase Console
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **padelcore-app**
3. Navigate to **Functions** (left sidebar)
4. Look for function: `onNotificationCreated`
5. Status should be **Active** (green)

### Option B: Check via Command Line
```bash
cd functions
firebase functions:list
```

You should see `onNotificationCreated` in the list.

### If Not Deployed:
```bash
cd functions
firebase login --reauth
firebase deploy --only functions:onNotificationCreated
```

---

## Step 2: Find Your User ID and Verify FCM Token

### Method 1: Via Firebase Console (Easiest)

1. **Go to Firebase Console** → **Firestore Database**
2. **Click on `users` collection**
3. **Find your user document** (look for your email or phone number)
4. **Click on the document** to open it
5. **Copy the Document ID** - this is your `userId` (looks like: `abc123xyz456...`)
6. **Check for `fcmToken` field**:
   - If it exists and has a value (long string starting with letters/numbers) → ✅ Good!
   - If it's missing or empty → ❌ Problem! (See troubleshooting below)

### Method 2: Via App Debug Logs

1. **Open your app** on your device
2. **Check the debug console/logs** for:
   ```
   FCM Token: [long string of characters]
   ```
3. **Note your user ID** from the logs (if printed)

### Method 3: Via Code (Temporary Debug)

Add this temporarily to your app to print your user ID:

```dart
final user = FirebaseAuth.instance.currentUser;
print('My User ID: ${user?.uid}');
```

---

## Step 3: Create Test Notification Document

### Via Firebase Console:

1. **Go to Firebase Console** → **Firestore Database**
2. **Click on `notifications` collection** (or create it if it doesn't exist)
3. **Click "Add document"** (or the "+" button)
4. **Document ID**: Leave as auto-generated (or create your own)
5. **Add these fields**:

| Field Name | Type | Value |
|------------|------|-------|
| `type` | string | `booking_status` |
| `userId` | string | **[YOUR_USER_ID_FROM_STEP_2]** |
| `message` | string | `Test notification - Your booking has been approved!` |
| `timestamp` | timestamp | Click "Set" → Select "Server timestamp" |
| `read` | boolean | `false` |

### Complete Example Document:

```json
{
  "type": "booking_status",
  "userId": "abc123xyz456...",  // ← Replace with YOUR actual user ID
  "message": "Test notification - Your booking has been approved!",
  "timestamp": [Server Timestamp],
  "read": false
}
```

### Optional Fields (for richer notifications):

```json
{
  "type": "booking_status",
  "userId": "abc123xyz456...",
  "bookingId": "test123",
  "status": "approved",
  "venue": "Test Venue",
  "time": "10:00 AM",
  "date": "2026-01-25",
  "message": "Your booking at Test Venue on 2026-01-25 at 10:00 AM has been approved!",
  "timestamp": [Server Timestamp],
  "read": false
}
```

---

## Step 4: Monitor Function Execution

### Option A: Via Firebase Console

1. **Go to Firebase Console** → **Functions**
2. **Click on `onNotificationCreated`**
3. **Click "Logs" tab**
4. **Watch for new log entries** after creating the notification document
5. **Look for**:
   - ✅ `Sent X notifications successfully`
   - ❌ `No FCM tokens found` (means token is missing)
   - ❌ Error messages (check details)

### Option B: Via Command Line

```bash
cd functions
firebase functions:log --only onNotificationCreated
```

Watch the terminal for logs after creating the notification.

---

## Step 5: Check Your Device

### Expected Behavior:

1. **If app is CLOSED/TERMINATED**:
   - You should receive a **system notification** (appears in notification tray)
   - Title: "Booking Status Update"
   - Body: "Test notification - Your booking has been approved!"

2. **If app is OPEN (foreground)**:
   - You should see a **local notification** (appears as overlay/toast)
   - Same title and body as above

3. **If app is in BACKGROUND**:
   - You should receive a **system notification**

### If You Don't Receive Notification:

See **Troubleshooting** section below.

---

## Step 6: Verify Notification Was Sent

### Check Firebase Cloud Messaging Reports:

1. **Go to Firebase Console** → **Cloud Messaging**
2. **Click "Reports" tab**
3. **Look for recent message deliveries**
4. **Check delivery statistics**:
   - Sent: Should show 1
   - Delivered: Should show 1 (if device is online)
   - Failed: Check if any failures

---

## Troubleshooting

### ❌ Problem: "No FCM tokens found" in logs

**Cause**: Your user document doesn't have an `fcmToken` field.

**Solution**:
1. **Open your app** on your device
2. **Make sure you're logged in**
3. **Grant notification permissions** when prompted
4. **Restart the app** (close completely and reopen)
5. **Check Firestore** again - `fcmToken` should now exist

**If still missing**:
- Check app logs for: `Error saving FCM token: ...`
- Verify notification permissions are granted in device settings
- For Android: Settings → Apps → PadelCore → Notifications (enable)
- For iOS: Settings → Notifications → PadelCore (enable)

---

### ❌ Problem: Function not triggering

**Possible causes**:
1. Function not deployed
2. Notification document was **updated** instead of **created** (function only triggers on CREATE)
3. Firestore rules blocking the creation

**Solution**:
1. **Verify function is deployed** (Step 1)
2. **Make sure you're CREATING a new document**, not updating an existing one
3. **Check Firestore rules** - ensure `notifications` collection allows writes:
   ```javascript
   match /notifications/{notificationId} {
     allow create: if request.auth != null;
   }
   ```

---

### ❌ Problem: Notification received but app doesn't open

**Cause**: Background handler might not be properly configured.

**Solution**:
- This is expected behavior - notifications should appear in the notification tray
- Tapping the notification should open the app (if `click_action` is configured)
- Check `AndroidManifest.xml` has `FLUTTER_NOTIFICATION_CLICK` intent filter

---

### ❌ Problem: Notification received when app is open, but NOT when app is closed

**Cause**: Background message handler might not be working.

**Solution**:
1. **Verify background handler is registered** in `main.dart`:
   ```dart
   FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
   ```
2. **Check that handler initializes Firebase** (should be in `notification_service.dart`)
3. **For Android**: Ensure app has notification permissions
4. **For iOS**: Ensure APNs is configured correctly

---

### ❌ Problem: Function logs show errors

**Check the error message**:
- `Error sending push notification: ...` → Check FCM configuration
- `No FCM tokens found` → See above
- `Permission denied` → Check Firestore security rules
- `Function timeout` → Function might be taking too long (check for infinite loops)

---

## Testing Admin Notifications

To test admin notifications:

1. **Create notification document** with:
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

2. **This will send to admin user** (phone: `+201006500506` or email: `admin@padelcore.com`)
3. **Make sure admin user has FCM token** in their user document

---

## Quick Test Checklist

- [ ] Cloud Function deployed (`onNotificationCreated`)
- [ ] Found my user ID from Firestore `users` collection
- [ ] Verified `fcmToken` exists in my user document
- [ ] Created test notification document in `notifications` collection
- [ ] Checked function logs - saw "Sent X notifications successfully"
- [ ] Received notification on device (when app closed)
- [ ] Received notification on device (when app open)

---

## Next Steps After Successful Test

Once notifications work:
1. **Remove test notification documents** from Firestore
2. **Test with real booking flow** (create a booking, approve it, etc.)
3. **Monitor function logs** for any issues
4. **Check Firebase Cloud Messaging reports** for delivery statistics

---

## Need Help?

If you're still having issues:
1. **Share function logs** (from Firebase Console or command line)
2. **Share your user document** (screenshot, hide sensitive data)
3. **Share notification document** you created
4. **Check device notification settings** (screenshot if possible)
