# PadelCore App - Comprehensive Testing Checklist

## 🔧 Pre-Build Checklist
- [ ] Run `flutter clean`
- [ ] Run `flutter pub get`
- [ ] Check for linter errors: `flutter analyze`
- [ ] Verify version incremented in `pubspec.yaml`
- [ ] Check Git status - all changes committed

---

## 📱 Installation & Setup (Both iOS & Android)

### iOS
- [ ] App installs without errors
- [ ] App icon displays correctly
- [ ] Launch screen shows properly
- [ ] No crash on first launch
- [ ] Permissions prompt for notifications appears

### Android
- [ ] App installs without errors
- [ ] App icon displays correctly
- [ ] Launch screen shows properly
- [ ] No crash on first launch
- [ ] Permissions prompt for notifications appears

---

## 🔐 Authentication Flow

### Sign Up
- [ ] Email/password sign up works
- [ ] Google sign-in works
- [ ] Apple sign-in works (iOS only)
- [ ] Phone authentication works
- [ ] Profile creation successful
- [ ] User redirected to home screen
- [ ] FCM token saved to Firestore

### Sign In
- [ ] Email/password sign in works
- [ ] Google sign-in works
- [ ] Apple sign-in works (iOS only)
- [ ] Phone authentication works
- [ ] FCM token refreshed on login
- [ ] User role detected correctly (admin/user)

### Sign Out
- [ ] Sign out works properly
- [ ] Redirected to login screen
- [ ] Session cleared

---

## 🏠 Home Screen

### Navigation
- [ ] All footer tabs work (Home, Bookings, Tournaments, Skills)
- [ ] Notification bell icon shows unread count
- [ ] Admin sees admin-specific UI elements
- [ ] Users see user-specific UI elements

### Features
- [ ] Carousel/banner images load
- [ ] Quick action buttons work
- [ ] Venue selection works
- [ ] Date picker works
- [ ] "Book Now" redirects properly

---

## 📅 Booking System

### Regular Bookings
- [ ] Can select venue
- [ ] Can select date
- [ ] Available time slots display correctly
- [ ] Can book **Group** training
- [ ] Can book **Private** training
- [ ] Can book recurring sessions
- [ ] Booking request submitted successfully
- [ ] User receives confirmation message
- [ ] Booking appears in "My Bookings"

### Training Bundles (NEW FEATURE)
- [ ] "Training Bundle" option appears in booking dialog
- [ ] Can select 1/4/8 sessions
- [ ] Can select 1-4 players
- [ ] Price calculates correctly for each configuration
- [ ] **New Bundle Request:**
  - [ ] Bundle request submitted
  - [ ] Appears in admin panel for approval
  - [ ] Admin receives notification
- [ ] **Use Existing Bundle:**
  - [ ] Active bundles display in dialog
  - [ ] Can select existing bundle
  - [ ] Session deducted from bundle
  - [ ] Remaining sessions update
- [ ] Bundle expiration date set (2 months)
- [ ] Multiple bundles per user work

---

## 🔔 Notifications System

### User Notifications (In-App)
- [ ] Notifications screen accessible
- [ ] Unread count shows in bell icon
- [ ] Booking approved notification received
- [ ] Booking rejected notification received
- [ ] Tournament approved notification received
- [ ] Bundle approved notification received (NEW)
- [ ] Payment confirmed notification received (NEW)
- [ ] Bundle almost finished notification (NEW)
- [ ] Can mark notifications as read
- [ ] Can mark all as read
- [ ] Timestamp shows correctly

### User Notifications (System/Push)
- [ ] **iOS:** Banner notification appears
- [ ] **iOS:** Sound plays
- [ ] **iOS:** Badge count updates
- [ ] **Android:** Notification appears
- [ ] **Android:** Sound plays
- [ ] Tapping notification opens app
- [ ] Notification shows correct title
- [ ] Notification shows correct message

### Admin Notifications
- [ ] **Booking Request:**
  - [ ] Notification appears in-app
  - [ ] System notification appears (iOS/Android)
  - [ ] Shows user name and venue
- [ ] **Bundle Request:** (NEW)
  - [ ] Notification appears in-app
  - [ ] System notification appears
  - [ ] Shows bundle details (sessions/players)
- [ ] **Tournament Registration:**
  - [ ] Notification appears in-app
  - [ ] System notification appears

---

## 👤 User Features

### My Bookings
- [ ] Pending bookings show
- [ ] Approved bookings show
- [ ] Rejected bookings show
- [ ] Correct status colors (orange/green/red)
- [ ] Booking details display correctly
- [ ] Filter by status works

### My Bundles (NEW)
- [ ] "My Bundles" section accessible
- [ ] Active bundles display
- [ ] Progress bar shows usage
- [ ] Remaining sessions count correct
- [ ] Payment status badge correct
- [ ] Session history displays
- [ ] Attended/Missed/Cancelled counts correct
- [ ] Can request new bundle
- [ ] Expiration date shows
- [ ] "Expiring soon" warning appears (7 days)

### Skills/Stats
- [ ] Skills screen accessible
- [ ] Radar charts display correctly
- [ ] Attack skills show properly
- [ ] Overall performance shows properly
- [ ] Label positions correct (Intelligence, Fundamentals, etc.)
- [ ] Admin can edit skills (if admin)

### Profile
- [ ] Profile displays user info
- [ ] Can edit first/last name
- [ ] Can edit phone number
- [ ] Can change password
- [ ] Can delete account

---

## 👨‍💼 Admin Panel

### Bookings Management
- [ ] All bookings display
- [ ] Can filter by status (Pending/Approved/Rejected)
- [ ] Can filter by date
- [ ] Can filter by venue
- [ ] Can approve bookings
- [ ] Can reject bookings
- [ ] User receives notification after approval/rejection
- [ ] Booking status updates in Firestore

### Training Bundles Management (NEW)
- [ ] "Training Bundles" tab accessible
- [ ] Pending bundle requests display
- [ ] Can approve bundle requests
- [ ] Expiration date set on approval (2 months)
- [ ] User receives approval notification
- [ ] **Payment Confirmation:**
  - [ ] Can confirm payment
  - [ ] Can select payment date
  - [ ] Payment status updates to "paid"
  - [ ] User receives payment confirmation notification
- [ ] **Active Bundles:**
  - [ ] Filter by Active/Completed/Expired
  - [ ] Shows total/used/remaining sessions
  - [ ] Progress bars display correctly
- [ ] **Bundle Details:**
  - [ ] User info displays
  - [ ] Session history shows
  - [ ] Can view all bundle sessions
- [ ] **Attendance Marking:**
  - [ ] Can mark session as Attended
  - [ ] Can mark session as Missed
  - [ ] Can mark session as Cancelled
  - [ ] Counters update correctly
  - [ ] Bundle status changes to "completed" when finished
- [ ] **Admin Actions:**
  - [ ] Can add notes to bundle
  - [ ] Can extend bundle expiration
  - [ ] Can cancel bundle
- [ ] **Bundle Pricing Config:**
  - [ ] Can view current pricing
  - [ ] Can edit pricing for 1/4/8 sessions
  - [ ] Can edit pricing for 1-4 players
  - [ ] Changes saved to Firestore

### Tournaments Management
- [ ] Can create parent tournament
- [ ] Can add weekly tournaments
- [ ] Can manage registrations
- [ ] Can approve/reject registrations
- [ ] Can assign teams
- [ ] Can start phases
- [ ] Can enter scores
- [ ] Bracket updates correctly

### Users Management
- [ ] All users display
- [ ] Can view user details
- [ ] Can edit user skills
- [ ] Can delete users
- [ ] Can assign roles (admin/sub-admin)

---

## 🏆 Tournaments

### User View
- [ ] Available tournaments display
- [ ] Can view tournament details
- [ ] Can register for tournament
- [ ] Registration request submitted
- [ ] Appears in "My Tournaments"

### Admin View
- [ ] Can see all registrations
- [ ] Can approve registrations
- [ ] Can manage tournament phases
- [ ] Bracket generates correctly

---

## 🔄 Real-time Updates

### Firestore Listeners
- [ ] Bookings update in real-time
- [ ] Notifications update in real-time
- [ ] Tournament data updates in real-time
- [ ] Bundle data updates in real-time (NEW)
- [ ] Skills update in real-time

### FCM Token Management
- [ ] Token saves on login
- [ ] Token updates on app restart
- [ ] Multiple devices supported
- [ ] iOS and Android tokens separate

---

## 🚨 Error Handling

### Network Errors
- [ ] Graceful handling when offline
- [ ] Error messages display properly
- [ ] App doesn't crash

### Firebase Errors
- [ ] Permission errors handled
- [ ] Missing data handled
- [ ] Invalid data handled

### UI Errors
- [ ] Form validation works
- [ ] Required fields checked
- [ ] Invalid inputs rejected

---

## 📊 Cloud Functions

### Notifications Function
- [ ] `onNotificationCreated` triggers
- [ ] Admin notifications work
- [ ] User notifications work
- [ ] Multiple devices receive notifications
- [ ] iOS notifications work
- [ ] Android notifications work

### Scheduled Functions
- [ ] `sendMatchReminders` runs every 5 minutes
- [ ] `sendBookingReminders` runs every 5 minutes
- [ ] 30-min reminders sent
- [ ] 10-min reminders sent
- [ ] "Now" reminders sent

### Check Firebase Console
- [ ] Go to Functions → Logs
- [ ] No errors in logs
- [ ] Functions completing successfully
- [ ] Response times acceptable (< 10s)

---

## 🎨 UI/UX

### General
- [ ] All screens responsive
- [ ] Scrolling smooth
- [ ] No layout overflow
- [ ] Colors consistent
- [ ] Fonts readable

### Dark Theme (if implemented)
- [ ] All screens display correctly
- [ ] Text readable
- [ ] Colors appropriate

### Accessibility
- [ ] Text size appropriate
- [ ] Touch targets adequate size
- [ ] Color contrast sufficient

---

## 🔐 Security

### Firestore Rules
- [ ] Users can only read their own data
- [ ] Users can only write their own data
- [ ] Admin can read all data
- [ ] Admin can write all data
- [ ] Proper role checks in place

### Authentication
- [ ] Password requirements enforced
- [ ] Session timeout works
- [ ] Token expiration handled

---

## 📱 Device-Specific

### iOS
- [ ] Tested on iPhone (iOS 14+)
- [ ] Tested on iPad
- [ ] Landscape orientation works
- [ ] Safe area insets respected
- [ ] Keyboard handling works
- [ ] Notifications work on all iOS versions

### Android
- [ ] Tested on Android 8+
- [ ] Different screen sizes work
- [ ] Back button works properly
- [ ] Notifications work on all Android versions

---

## 🧪 Edge Cases

### Bundles
- [ ] Bundle expires after 2 months
- [ ] Expired bundle can't be used
- [ ] Can't use more sessions than available
- [ ] Extra player fees calculated correctly
- [ ] Multiple bundles don't conflict
- [ ] Bundle session marking after expiration

### Bookings
- [ ] Can't book past dates
- [ ] Can't book blocked slots
- [ ] Can't exceed max users per slot
- [ ] Private booking blocks all slots

### Tournaments
- [ ] Can't register twice
- [ ] Can't register after deadline
- [ ] Team assignments don't conflict

---

## 📝 Data Integrity

### Firestore
- [ ] Check `bundles` collection
  - [ ] All fields present
  - [ ] Counters accurate
  - [ ] Dates/timestamps correct
- [ ] Check `bundleSessions` collection
  - [ ] Linked to correct bundle
  - [ ] Linked to correct booking
  - [ ] Status accurate
- [ ] Check `notifications` collection
  - [ ] Admin notifications have `isAdminNotification: true`
  - [ ] User notifications have `userId`
  - [ ] Timestamps correct

### User Documents
- [ ] `role` field present for admins
- [ ] `fcmToken` and `fcmTokens` saved
- [ ] Profile fields complete

---

## 🎯 Performance

### Load Times
- [ ] Home screen loads < 2s
- [ ] Booking screen loads < 2s
- [ ] Admin panel loads < 3s
- [ ] Images load progressively

### Firestore Queries
- [ ] Queries complete < 1s
- [ ] Pagination works if implemented
- [ ] No unnecessary reads

---

## 📤 Deployment

### Pre-Deployment
- [ ] All tests passed above
- [ ] No console errors
- [ ] No console warnings (critical)
- [ ] Linter clean
- [ ] Version incremented
- [ ] Git committed and pushed

### CodeMagic Build
- [ ] Build starts successfully
- [ ] No build errors
- [ ] APK/IPA generated
- [ ] App signed properly

### Post-Deployment
- [ ] TestFlight build available (iOS)
- [ ] Internal testing track available (Android)
- [ ] Download and install successful
- [ ] All features work as expected

---

## 🔧 Specific Version Testing

### Version 61 (Current Build)
**Focus Areas:**
- [ ] **Admin notifications for booking requests** ✅
  - [ ] Admin receives notification when user books
  - [ ] Notification document created in Firestore
  - [ ] Cloud Function logs show success
- [ ] **iOS system notifications** ✅
  - [ ] Banner appears on iOS
  - [ ] Sound plays
  - [ ] Badge updates
- [ ] **Training bundles system** ⭐NEW
  - [ ] All bundle features above

---

## 📋 Quick Smoke Test (5 minutes)

**After each build, run this quick test:**

1. **Install & Launch** (30s)
   - [ ] App installs
   - [ ] No crash on launch

2. **Login** (30s)
   - [ ] Sign in works
   - [ ] Redirected to home

3. **Create Booking** (1 min)
   - [ ] Can select date/time
   - [ ] Booking request submits

4. **Admin Notification** (30s)
   - [ ] Admin receives notification (in-app)
   - [ ] System notification appears

5. **Approve Booking** (30s)
   - [ ] Admin can approve
   - [ ] User receives notification

6. **Request Bundle** (1 min) ⭐NEW
   - [ ] Can select bundle options
   - [ ] Bundle request submits
   - [ ] Admin sees request

7. **Check Firestore** (1 min)
   - [ ] Booking created
   - [ ] Notification created
   - [ ] Bundle created (if tested)

---

## 🐛 Bug Tracking

**If any test fails, document:**
- Test that failed
- Expected behavior
- Actual behavior
- Steps to reproduce
- Device/OS version
- Screenshots/logs

---

## ✅ Sign-off

**Testing completed by:** _________________

**Date:** _________________

**Version tested:** _________________

**Build number:** _________________

**Status:** ⬜ Pass ⬜ Fail ⬜ Pass with issues

**Notes:**
_____________________________________________
_____________________________________________
_____________________________________________
