# 🎉 New Features - How to Access

## 📅 Training Calendar

**File Location:** `lib/screens/training_calendar_screen.dart`

**What it does:**
- Shows monthly calendar view of all your training bookings
- Blue dots on dates with bookings
- Click any date to see booking details
- Navigate between months

**How to add navigation:**

### Option 1: Add to Home Screen
In `lib/screens/home_screen.dart`, add a card/button:

```dart
// Import at top
import 'training_calendar_screen.dart';

// In your home screen cards:
Card(
  child: ListTile(
    leading: Icon(Icons.calendar_month, color: Colors.blue),
    title: Text('Training Calendar'),
    subtitle: Text('View your bookings in calendar'),
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const TrainingCalendarScreen(),
        ),
      );
    },
  ),
)
```

### Option 2: Add to My Bookings Screen
In `lib/screens/my_bookings_screen.dart`, add icon button in AppBar:

```dart
actions: [
  IconButton(
    icon: Icon(Icons.calendar_month),
    tooltip: 'Calendar View',
    onPressed: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const TrainingCalendarScreen(),
        ),
      );
    },
  ),
]
```

---

## 📊 Monthly Reports

**File Location:** `lib/screens/monthly_reports_screen.dart`

**What it does:**
- Shows statistics for training and court bookings by month
- Total bookings, approved, pending counts
- Private vs Group breakdown
- Total cost for court bookings
- Venue-wise breakdown
- Export/view full report

**How to add navigation:**

Similar to Training Calendar, add to home screen or menu:

```dart
// Import at top
import 'monthly_reports_screen.dart';

// Add card/button
Card(
  child: ListTile(
    leading: Icon(Icons.assessment, color: Colors.green),
    title: Text('Monthly Reports'),
    subtitle: Text('View booking statistics'),
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const MonthlyReportsScreen(),
        ),
      );
    },
  ),
)
```

---

## 🔧 Court Calendar - Fixed!

**File:** `lib/screens/admin_calendar_grid_screen.dart`

**What changed:**
- Now shows 2-3 courts at a time (instead of squeezing all)
- Horizontally scrollable (works on web and mobile)
- Swipe left/right to see more courts

**No navigation needed** - Already accessible from Admin Dashboard → Court Booking

---

## ✅ Other Features Added

### 1. Phone Number Validation
- Users must enter phone number before booking
- Auto-saves to profile

### 2. Profile Picture Upload
- Upload from camera or gallery
- Works on web, Android, and iOS
- Max size: 2MB
- Stored in Firebase Storage

### 3. Private Booking Fix
- Now creates 1 booking request (not 4)
- Reserves all 4 slots with single request

---

**Need help adding navigation?** Let me know which screen you want to add these to!
