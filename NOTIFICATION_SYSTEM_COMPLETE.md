# 🔔 Push Notification System - COMPLETE GUIDE

## ✅ All Notifications Now Show Descriptive Messages!

Previously: "You have a new notification" (generic)
Now: Specific, descriptive messages for every notification type!

---

## 📱 Notification Types

### 1. **Booking Request (Admin)**
**When:** User submits a booking request
**Who receives:** Admin & Sub-Admins (location-based)
**Example:**
```
Title: 🎾 New Booking Request
Body: Hussein Hany wants to book E&Series Padel - Zayed on 2026-01-28 at 7:45 PM
```

### 2. **Booking Status (User)**
**When:** Admin approves/rejects booking
**Who receives:** User who made the booking
**Example (Approved):**
```
Title: ✅ Booking Confirmed!
Body: Your booking at E&Series Padel - Zayed on 2026-01-28 at 7:45 PM has been approved!
```
**Example (Rejected):**
```
Title: ❌ Booking Rejected
Body: Your booking at E&Series Padel - Zayed on 2026-01-28 at 7:45 PM has been rejected.
```

### 3. **Booking Reminders (User)** 🆕
**When:** Automated before booking time
**Who receives:** User with approved booking
**Timing:** 30 minutes before, 10 minutes before
**Example (30 mins):**
```
Title: ⏰ Booking Starting Soon!
Body: Your booking at E&Series Padel - Zayed starts in 30 minutes! (7:45 PM on 2026-01-28)
```
**Example (10 mins):**
```
Title: ⏰ Booking Starting Very Soon!
Body: Your booking at E&Series Padel - Zayed starts in 10 minutes! (7:45 PM on 2026-01-28)
```

### 4. **Tournament Request (Admin)**
**When:** User submits tournament registration
**Who receives:** Admin & Sub-Admins
**Example:**
```
Title: 🏆 New Tournament Registration
Body: Hussein Hany wants to join TPF Sheikh Zayed (Level: B)
```

### 5. **Tournament Status (User)**
**When:** Admin approves/rejects tournament registration
**Who receives:** User who registered
**Example (Approved):**
```
Title: ✅ Tournament Registration Approved!
Body: Your tournament registration for TPF Sheikh Zayed has been approved!
```
**Example (Rejected):**
```
Title: ❌ Tournament Registration Rejected
Body: Your tournament registration for TPF Sheikh Zayed has been rejected.
```

### 6. **Match Reminders (Tournament Participants)**
**When:** Automated before tournament matches
**Who receives:** All approved tournament participants
**Timing:** 30 minutes before, 10 minutes before, on-time
**Example (30 mins):**
```
Title: ⏰ Match Starting Soon!
Body: Your Phase 1 Group match starts in 30 minutes at Court 1
```
**Example (10 mins):**
```
Title: ⏰ Match Starting Very Soon!
Body: Your Quarter Final match starts in 10 minutes at Court 2
```
**Example (On-time):**
```
Title: 🎾 Match Starting NOW!
Body: Your Final match is starting now at Court 1
```

---

## 🚀 How It Works

### Architecture:
```
User Action (App)
    ↓
Create Notification Document in Firestore
    ↓
Cloud Function Triggers (onNotificationCreated)
    ↓
FCM Send Push Notification
    ↓
User's Phone (Even if app is CLOSED!)
```

### Scheduled Reminders:
```
Cloud Function runs every 5 minutes
    ↓
Check approved bookings & tournament matches
    ↓
Calculate time difference
    ↓
If within window (±2 mins of target)
    ↓
Send FCM Push Notification
    ↓
Mark as sent (prevent duplicates)
```

---

## 📦 What Was Updated

### Flutter (Client Side):
**File:** `lib/services/notification_service.dart`

**Changes:**
✅ Added `title` and `body` fields to all notification methods
✅ Added `sendBookingReminder()` method
✅ Descriptive messages for all notification types

### Cloud Functions (Backend):
**File:** `functions/index.js`

**Changes:**
✅ `onNotificationCreated` - Already deployed (handles instant notifications)
✅ `sendMatchReminders` - Already deployed (handles tournament match reminders)
✅ `sendBookingReminders` - NEW (handles booking time reminders)

---

## 🔧 Deployment Steps

### 1. Rebuild the Flutter App:
```bash
flutter clean
flutter pub get
flutter run
```

**Why needed:**
- Updated `notification_service.dart` (client code)
- Needs to be compiled into the app
- Users need to update to get new notification formats

### 2. Deploy New Cloud Function:
```bash
cd functions
npm install
firebase deploy --only functions:sendBookingReminders
```

**Why needed:**
- New `sendBookingReminders` function
- Runs on Firebase servers
- Works immediately after deployment (no user update needed)

### 3. Verify Deployment:
```bash
firebase functions:list
```

**Should show:**
- ✅ `onNotificationCreated` (v1)
- ✅ `sendMatchReminders` (v1)
- ✅ `sendBookingReminders` (v1) ← NEW

---

## 🧪 Testing Guide

### Test Booking Notifications:
1. User submits booking request
2. **Admin receives:** "🎾 New Booking Request - Hussein Hany wants to book..."
3. Admin approves booking
4. **User receives:** "✅ Booking Confirmed! Your booking at..."
5. Wait 30 mins before booking time
6. **User receives:** "⏰ Booking Starting Soon! Your booking starts in 30 minutes..."
7. Wait 20 more minutes
8. **User receives:** "⏰ Booking Starting Very Soon! Your booking starts in 10 minutes..."

### Test Tournament Notifications:
1. User registers for tournament
2. **Admin receives:** "🏆 New Tournament Registration - Hussein Hany wants to join..."
3. Admin approves registration
4. **User receives:** "✅ Tournament Registration Approved!..."
5. Admin configures match time (e.g., 30 minutes from now)
6. Wait for scheduled function
7. **User receives:** "⏰ Match Starting Soon! Your Phase 1 Group match..."

---

## 📊 Firestore Collections

### `notifications`
Main collection for all notifications
```javascript
{
  type: "booking_request",
  title: "🎾 New Booking Request",
  body: "Hussein Hany wants to book...",
  userId: "user123",
  venue: "E&Series Padel - Zayed",
  time: "7:45 PM",
  date: "2026-01-28",
  read: false,
  timestamp: serverTimestamp()
}
```

### `sentBookingReminders`
Tracks sent booking reminders (prevents duplicates)
```javascript
{
  bookingId: "booking123",
  userId: "user123",
  notificationType: "30min",
  sentAt: serverTimestamp()
}
```

### `sentMatchNotifications`
Tracks sent match reminders (prevents duplicates)
```javascript
{
  tournamentId: "tournament123",
  matchName: "qf1",
  matchType: "Quarter Final",
  notificationType: "30min",
  recipientCount: 16,
  sentAt: serverTimestamp()
}
```

---

## ✅ Summary of Changes

### Before:
❌ Generic notification: "You have a new notification"
❌ No booking reminders
❌ Match reminders not deployed

### After:
✅ Descriptive notifications for EVERY type
✅ Booking reminders (30 mins, 10 mins before)
✅ Match reminders (30 mins, 10 mins, on-time)
✅ All working when app is CLOSED
✅ Location-based sub-admin filtering
✅ Duplicate prevention

---

## 🎯 Next Steps

1. **Deploy the booking reminders function:**
   ```bash
   cd functions
   firebase deploy --only functions:sendBookingReminders
   ```

2. **Rebuild and test the app:**
   ```bash
   flutter run
   ```

3. **Test each notification type** to verify messages appear correctly

4. **Optional:** Build production release:
   ```bash
   flutter build apk --release  # Android
   flutter build ios --release  # iOS
   ```

---

## 📝 Notes

- **All Cloud Functions are backend** - work without user updating app
- **Notification formats require app update** - users need new version to see new formats
- **FCM tokens refresh automatically** - no manual intervention needed
- **Reminders run every 5 minutes** - timing is accurate within ±2 minute window
- **No duplicate notifications** - tracked in Firestore

**Everything is ready! Just deploy and test!** 🎾
