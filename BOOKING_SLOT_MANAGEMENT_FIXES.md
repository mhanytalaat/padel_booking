# Booking Slot Management Fixes & Enhancements

## Date: February 6, 2026

## Issues Fixed & Features Added

### 1. ✅ Fixed Slot Counting Bug

**Problem**: Approved bookings were not properly reducing available slots. When two bookings were approved for the same time slot, the system still showed "4 spots available" because it was counting bookings (2) instead of slots reserved (could be 8 if both were private).

**Root Cause**: The slot counting logic was incrementing by 1 for each booking, regardless of how many slots that booking actually reserved.

**Solution**: Updated slot counting to use the `slotsReserved` field from each booking.

**Code Changes**:
```dart
// OLD (booking_page_screen.dart line 1039)
slotCounts[key] = (slotCounts[key] ?? 0) + 1;

// NEW
final slotsReserved = data['slotsReserved'] as int? ?? 1;
slotCounts[key] = (slotCounts[key] ?? 0) + slotsReserved;
```

**Files Modified**:
- `lib/screens/booking_page_screen.dart` (line ~1045)
- `lib/screens/home_screen.dart` (line ~1227)
- `lib/screens/home_screen_cursor.dart` (line ~896)

---

### 2. ✅ Added New Pricing Options for 1 Session

**Problem**: Only 1 and 2 player options existed for 1 session bundles. Need to add 3 and 4 player options.

**Solution**: Updated default pricing configuration to include:
- 3 players: 1750 EGP
- 4 players: 2000 EGP

**Code Changes**:
```dart
// Added to bundle_service.dart _getDefaultPricing()
'1_session': {
  '1_player': 1000,
  '2_players': 1500,
  '3_players': 1750,  // NEW
  '4_players': 2000,  // NEW
},
```

**Files Modified**:
- `lib/services/bundle_service.dart` (line ~28-34)

---

### 3. ✅ Implemented Private/Shared Booking Logic

**Problem**: Need different slot reservation behavior based on session count:
- 1 session → Should always book entire slot (private)
- 4/8 sessions → User should choose between private (whole slot) or shared (only their player count)

**Solution**: 
1. Added `isPrivateBooking` checkbox to bundle selector dialog for 4/8 sessions
2. Made 1 session automatically private (no checkbox needed)
3. Updated booking processing to respect the private/shared choice

#### A. Bundle Selector Dialog Updates

**Added State Variable**:
```dart
bool isPrivateBooking = false; // For 4/8 sessions: true = private, false = shared
```

**Added UI Checkbox** (for 4/8 sessions only):
```dart
if (selectedSessions > 1) ...[
  Container(
    // ... styling ...
    child: CheckboxListTile(
      value: isPrivateBooking,
      onChanged: (value) {
        setState(() {
          isPrivateBooking = value ?? false;
        });
      },
      title: const Text('Private Booking (Entire Time Slot)'),
      subtitle: Text(
        isPrivateBooking 
            ? 'You will have the court to yourself'
            : 'Share the court with others (if available)',
      ),
    ),
  ),
]
```

**Updated Return Value**:
```dart
Navigator.pop(context, {
  'sessions': selectedSessions,
  'players': selectedPlayers,
  'price': price,
  'dayTimeSchedule': dayTimeSchedule,
  'isPrivate': selectedSessions == 1 ? true : isPrivateBooking, // 1 session always private
});
```

**Files Modified**:
- `lib/widgets/bundle_selector_dialog.dart`

#### B. Booking Processing Updates

**Updated Logic**:
```dart
// OLD
final isPrivate = playerCount == 1;

// NEW
bool isPrivate = false;
if (bundleConfig != null) {
  playerCount = bundleConfig['players'] as int;
  // Get isPrivate from bundle config
  isPrivate = bundleConfig['isPrivate'] as bool? ?? false;
} else if (selectedBundleId != null) {
  final bundle = await BundleService().getBundleById(selectedBundleId);
  if (bundle != null) {
    playerCount = bundle.playerCount;
    isPrivate = playerCount == 1; // Fallback for existing bundles
  }
}
```

**Files Modified**:
- `lib/screens/booking_page_screen.dart` (line ~534-552)
- `lib/screens/home_screen.dart` (line ~514-530)

---

## How It Works Now

### Booking Flow:

1. **User selects venue, date, and time**
2. **Bundle selector dialog opens**:
   - Select number of sessions (1, 4, or 8)
   - Select number of players (1-4)
   - **For 4/8 sessions**: Choose private or shared
   - **For 1 session**: Automatically private (checkbox not shown)

3. **System calculates slots needed**:
   - Private booking: Reserves all 4 slots (maxUsersPerSlot)
   - Shared booking: Reserves only 1 slot per player

4. **Availability check**:
   - Counts actual slots reserved from approved bookings
   - Compares against maxUsersPerSlot (default: 4)
   - Shows accurate availability: "X spots available (Y/4)"

5. **Booking created** with `slotsReserved` field:
   - Private: `slotsReserved = 4`
   - Shared: `slotsReserved = 1`

---

## Data Model

### Booking Document Fields:
```dart
{
  'userId': string,
  'venue': string,
  'time': string,
  'date': string,
  'status': 'pending' | 'approved' | 'rejected',
  'isPrivate': boolean,
  'slotsReserved': integer, // 4 for private, 1 for shared
  // ... other fields
}
```

---

## Pricing Structure (Updated)

### 1 Session:
- 1 player: 1000 EGP
- 2 players: 1500 EGP
- **3 players: 1750 EGP** ✨ NEW
- **4 players: 2000 EGP** ✨ NEW

### 4 Sessions:
- 1 player: 3400 EGP
- 2 players: 2600 EGP
- 3 players: 2000 EGP
- 4 players: 1800 EGP

### 8 Sessions:
- 1 player: 6080 EGP
- 2 players: 3800 EGP
- 3 players: 2720 EGP
- 4 players: 2000 EGP

---

## Testing Checklist

- [ ] **Slot Counting**: Book 2 private sessions at same time → Should show "Full (4/4)" not "2 spots available"
- [ ] **1 Session Private**: Book 1 session → Should always reserve 4 slots (no checkbox shown)
- [ ] **4/8 Sessions Private**: Book 4 sessions with private checkbox → Should reserve 4 slots
- [ ] **4/8 Sessions Shared**: Book 4 sessions without private checkbox → Should reserve 1 slot
- [ ] **New Pricing**: Select 1 session with 3 players → Should show 1750 EGP
- [ ] **New Pricing**: Select 1 session with 4 players → Should show 2000 EGP
- [ ] **Availability Display**: Verify "X spots available (Y/4)" shows correct numbers
- [ ] **Mixed Bookings**: 1 private booking (4 slots) + 1 shared booking (1 slot) = Full (5/4 would be rejected)

---

## Edge Cases Handled

1. **Legacy Bookings**: Old bookings without `slotsReserved` default to 1 slot
2. **Partial Slot Availability**: Private booking correctly rejected if any slots are taken
3. **Concurrent Bookings**: Slot counting uses real-time data from Firestore
4. **Recurring Bookings**: Slot counting works for both regular and recurring bookings

---

## No Breaking Changes

All changes are backward compatible:
- Old bookings without `slotsReserved` field default to 1
- Existing bundle logic continues to work
- New features are additive only
