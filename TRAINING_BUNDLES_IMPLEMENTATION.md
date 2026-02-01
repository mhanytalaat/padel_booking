# Training Bundles System - Implementation Plan

## Overview
Training bundle system allowing users to purchase 1, 4, or 8 session packages with flexible player counts (1-4 players).

## Database Structure

### 1. `config/bundlePricing` Document
```javascript
{
  "1_session": {
    "1_player": 1000,
    "2_players": 1500
  },
  "4_sessions": {
    "1_player": 3400,
    "2_players": 2600,
    "3_players": 2000,
    "4_players": 1800
  },
  "8_sessions": {
    "1_player": 3400,
    "2_players": 2600,
    "3_players": 2720,
    "4_players": 2000
  }
}
```

### 2. `bundles` Collection
```javascript
{
  userId: "user123",
  userName: "John Doe",
  userPhone: "+201234567890",
  bundleType: 8, // 1, 4, or 8
  playerCount: 2, // 1-4 players
  totalSessions: 8,
  usedSessions: 0,
  attendedSessions: 0,
  missedSessions: 0,
  cancelledSessions: 0,
  remainingSessions: 8,
  price: 2600,
  paymentStatus: "pending", // pending/paid/completed
  paymentDate: null,
  paymentMethod: "transfer",
  paymentConfirmedBy: null, // userId of admin who confirmed
  requestDate: timestamp,
  approvalDate: null,
  approvedBy: null, // userId of admin who approved
  expirationDate: null, // Set to 2 months after approval
  status: "pending", // pending/active/completed/expired/cancelled
  notes: "",
  adminNotes: "",
  createdAt: timestamp,
  updatedAt: timestamp
}
```

### 3. `bundleSessions` Collection
```javascript
{
  bundleId: "bundle123",
  bookingId: "booking456", // Link to bookings collection
  userId: "user123",
  sessionNumber: 1, // 1-8
  date: "2026-02-01",
  time: "10:00 AM - 11:00 AM",
  venue: "Padel Avenue",
  coach: "Hany",
  playerCount: 2, // Can differ from bundle if extra fees paid
  extraPlayerFees: 0, // If player count increased
  bookingStatus: "pending", // pending/approved/rejected
  attendanceStatus: "scheduled", // scheduled/attended/missed/cancelled
  markedBy: null, // userId who marked attendance
  markedAt: null,
  notes: "",
  createdAt: timestamp,
  updatedAt: timestamp
}
```

## Features Implementation

### Phase 1: Configuration & Core Models
- [x] Bundle pricing configuration (Firestore)
- [ ] Bundle data models
- [ ] Helper functions for bundle calculations

### Phase 2: Booking Flow
- [ ] Add "Bundle" option to booking screen
- [ ] Bundle type selector (1/4/8 sessions)
- [ ] Player count selector
- [ ] Price calculator and display
- [ ] Bundle request submission
- [ ] Link bookings to bundles

### Phase 3: Admin Management
- [ ] Admin "Training Bundles" tab
- [ ] Pending bundle requests list
- [ ] Bundle approval interface
- [ ] Payment confirmation interface
- [ ] Active bundles overview
- [ ] Bundle details view
- [ ] Attendance marking interface
- [ ] Bundle pricing configuration UI
- [ ] Extend/cancel bundle actions

### Phase 4: User View
- [ ] "My Bundles" section in bookings
- [ ] Active bundles list
- [ ] Bundle details (progress, sessions remaining)
- [ ] Session history
- [ ] Payment status display
- [ ] Request new bundle button

### Phase 5: Notifications
- [ ] Admin: New bundle request
- [ ] User: Bundle approved
- [ ] User: Payment confirmed
- [ ] User: 1 session remaining
- [ ] User: Bundle completed
- [ ] User & Admin: Bundle expiring soon (7 days before)
- [ ] User & Admin: Bundle almost finished (1 session left)

### Phase 6: Attendance & Tracking
- [ ] Automatic attendance prompts after session
- [ ] Mark as: Attended/Missed/Cancelled
- [ ] Update bundle counters
- [ ] Session notes
- [ ] Attendance history

### Phase 7: Advanced Features
- [ ] Bundle expiration handling (2 months)
- [ ] Extra player fees calculation
- [ ] Multiple bundle management per user
- [ ] Bundle statistics for admin
- [ ] Export bundle data

## Business Rules

1. **Bundle Expiration:** 2 months from approval date
2. **Unused Sessions:** Forfeit after expiration (admin can extend exceptionally)
3. **Player Count:** Locked to purchased count, extra fees for additional players
4. **Multiple Bundles:** Users can have multiple active bundles simultaneously
5. **Session Booking:** Users can book multiple sessions at once from bundle
6. **Attendance:** Can be marked by admin or user after session time
7. **Payment Methods:** Transfer (primary), configurable
8. **Bundle Status Flow:** Pending → Active (after payment) → Completed/Expired

## Integration Points

1. **Existing Booking System:**
   - Detect active bundles when user books training
   - Option to deduct from bundle or pay separately
   - Link booking to bundle session

2. **Notifications:**
   - Extend existing notification service
   - Add bundle-specific notification types

3. **Admin Panel:**
   - New "Training Bundles" tab
   - Integrate with existing booking approval flow

4. **User Bookings:**
   - Add "My Bundles" section
   - Show bundle-linked bookings differently

## UI Components Needed

1. **BundleSelectorDialog** - Choose bundle type and players
2. **BundleCard** - Display bundle info card
3. **BundleProgressBar** - Visual progress indicator
4. **BundleSessionsList** - List of bundle sessions
5. **AttendanceMarkerDialog** - Mark attendance with notes
6. **BundlePricingConfig** - Admin configuration screen
7. **PaymentConfirmationDialog** - Admin payment confirmation

## Next Steps

1. Create bundle pricing configuration in Firestore
2. Build bundle selection UI in booking screen
3. Create admin bundle management interface
4. Implement user bundle view
5. Add notifications
6. Implement attendance tracking
7. Test end-to-end flow

## Testing Checklist

- [ ] User can request bundle with different types/player counts
- [ ] Admin receives notification for bundle request
- [ ] Admin can approve/reject bundle
- [ ] Admin can confirm payment
- [ ] Bundle becomes active after payment
- [ ] User can book sessions and deduct from bundle
- [ ] System detects bundle expiration (2 months)
- [ ] Attendance marking works correctly
- [ ] Counters update properly (used/remaining sessions)
- [ ] Notifications sent at correct times
- [ ] Extra player fees calculated correctly
- [ ] Multiple bundles per user work correctly
- [ ] Bundle pricing can be updated by admin
