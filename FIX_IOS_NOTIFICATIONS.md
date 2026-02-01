# iOS Notifications Fix

## Issues Found and Fixed

### 1. ✅ iOS Background Notifications Not Showing
**Problem:** iOS wasn't showing system notifications when app is in background/closed

**Fixed:**
- Added `UIBackgroundModes` to `Info.plist` with `remote-notification`
- Updated `AppDelegate.swift` to handle foreground notifications properly
- Added notification delegate to show banners/alerts/sounds

### 2. ⚠️ Timestamp Shows "22 Hours Ago"
**Possible Causes:**
- Old notification in the list (check if multiple notifications exist)
- Firestore serverTimestamp() taking time to populate
- Timezone issue (server vs local time)

**Solution:** Will be resolved after rebuild. If persists, check:
- Delete old notifications from Firestore
- Verify timestamp field is populated correctly

### 3. ⚠️ Default Title/Body in Notification
**Current Status:** FCM logs show defaults being used
- FCM function is working correctly
- Notification document should have proper title/body
- May need to verify notification document structure in Firestore

## Changes Made

### `ios/Runner/Info.plist`
```xml
Added:
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
</array>
```

### `ios/Runner/AppDelegate.swift`
```swift
Added:
- UNUserNotificationCenter delegate setup
- Foreground notification handler to show banners/sounds/badges
```

## What to Test After Next Build

1. **System Notifications (Critical)**
   - Approve/reject a booking from admin panel
   - Check if iOS system notification appears
   - Test with app in foreground, background, and closed

2. **Notification Content**
   - Verify notification shows proper title and message
   - Should see "✅ Booking Confirmed!" not "Notification"
   - Should see booking details not "you have a new notification"

3. **Timestamp**
   - Check if timestamp shows "Just now" or "X minutes ago"
   - Should not show "22 hours ago" for new notifications

4. **In-App Notifications**
   - Verify notifications appear in notifications screen
   - Check unread count badge
   - Verify marking as read works

## Debug Steps (If Still Not Working)

### Check Firestore Notification Document
Go to Firebase Console → Firestore → `notifications` collection

Verify structure:
```json
{
  "type": "booking_status",
  "userId": "...",
  "title": "✅ Booking Confirmed!",  ← Should have this
  "body": "Your booking at...",      ← Should have this
  "timestamp": Timestamp,            ← Should be recent
  "read": false
}
```

### Check Cloud Functions Logs
Go to Firebase Console → Functions → Logs

Look for:
- ✅ "SUCCESS (iOS)! Message ID: projects/..."
- ❌ Any error messages
- The title/body values being sent

### Check iOS Device Settings
1. Settings → PadelCore → Notifications
2. Verify:
   - Allow Notifications: ON
   - Banners: ON
   - Sounds: ON
   - Badges: ON

### Test FCM Token
In Firestore, check your user document:
```json
{
  "fcmToken": "...",
  "fcmTokens": {
    "iOS": {
      "token": "...",
      "updatedAt": Timestamp
    }
  }
}
```

## Next Build

Build number incremented to 61 for testing these fixes.

After building:
1. Install new version on device
2. Grant notification permissions if prompted
3. Test booking approval/rejection
4. Monitor Cloud Functions logs during test
5. Report results
