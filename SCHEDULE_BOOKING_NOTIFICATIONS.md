# Schedule Booking Notifications - 5 Hours Before

## Summary
✅ Notifications are working!
✅ New APNs Key: `KWF87PTH63`
✅ No app rebuild needed for scheduling - it's all Cloud Functions!

## Solution: Scheduled Cloud Function

Add a Cloud Function that runs every hour and sends notifications for bookings starting in 5 hours.

### Step 1: Update functions/index.js

Add this new function at the end of `functions/index.js`:

```javascript
// Run every hour and check for upcoming bookings
exports.sendUpcomingBookingNotifications = functions.pubsub
  .schedule('every 1 hours')
  .onRun(async (context) => {
    console.log('Checking for upcoming bookings...');
    
    try {
      const now = admin.firestore.Timestamp.now();
      const fiveHoursFromNow = new Date(now.toDate().getTime() + (5 * 60 * 60 * 1000));
      const sixHoursFromNow = new Date(now.toDate().getTime() + (6 * 60 * 60 * 1000));
      
      // Query bookings that start between 5-6 hours from now
      const bookingsSnapshot = await admin.firestore()
        .collection('bookings')
        .where('status', '==', 'approved')
        .where('bookingDateTime', '>=', admin.firestore.Timestamp.fromDate(fiveHoursFromNow))
        .where('bookingDateTime', '<=', admin.firestore.Timestamp.fromDate(sixHoursFromNow))
        .where('notificationSent', '==', false) // Only bookings that haven't been notified
        .get();
      
      console.log(`Found ${bookingsSnapshot.size} upcoming bookings`);
      
      const promises = [];
      
      bookingsSnapshot.forEach((doc) => {
        const booking = doc.data();
        const bookingId = doc.id;
        
        // Create notification for user
        const notificationPromise = admin.firestore().collection('notifications').add({
          userId: booking.userId,
          title: 'Upcoming Booking Reminder',
          body: `Your booking at ${booking.venue} is in 5 hours! (${booking.date} at ${booking.time})`,
          type: 'booking_reminder',
          bookingId: bookingId,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          read: false
        });
        
        // Mark booking as notified
        const updatePromise = doc.ref.update({
          notificationSent: true
        });
        
        promises.push(notificationPromise, updatePromise);
      });
      
      await Promise.all(promises);
      console.log(`✅ Sent ${bookingsSnapshot.size} booking reminders`);
      
      return null;
    } catch (error) {
      console.error('Error sending booking notifications:', error);
      return null;
    }
  });
```

### Step 2: Update Booking Schema

When creating bookings in your app, add these fields:
- `bookingDateTime`: Timestamp (combine date + time)
- `notificationSent`: false (boolean)
- `status`: 'approved' or 'pending'

Example booking document:
```javascript
{
  userId: "xzfKrzEzuih28fnzIgSzkzSMoF03",
  venue: "Court 1",
  date: "2026-01-28",
  time: "10:00 AM",
  bookingDateTime: Timestamp(2026-01-28 10:00:00), // IMPORTANT: Actual timestamp
  status: "approved",
  notificationSent: false,
  // ... other fields
}
```

### Step 3: Deploy

```powershell
cd functions
firebase deploy --only functions
```

This will deploy:
- `onNotificationCreated` (existing - sends notifications immediately)
- `sendUpcomingBookingNotifications` (NEW - runs every hour to check bookings)

### How It Works

1. **Every hour**, the function runs automatically
2. It queries bookings that start **between 5-6 hours from now**
3. For each booking found:
   - Creates a notification document (triggers immediate notification)
   - Marks booking as `notificationSent: true` (so it doesn't send again)
4. The notification appears on user's phone!

### Important Notes

1. **No app rebuild needed** - just deploy the Cloud Function
2. **Add index** - Firestore might prompt you to create a composite index for the query. Click the link in the error and create it.
3. **Test first** - Change `every 1 hours` to `every 1 minutes` for testing, then change back
4. **Booking DateTime** - Make sure your Flutter app saves bookings with a proper `bookingDateTime` timestamp field

### Testing

1. Create a test booking with `bookingDateTime` = 5 hours from now
2. Set `notificationSent: false`
3. Wait for the scheduled function to run (or trigger it manually in Firebase Console)
4. Check if notification appears!

## Cost

Scheduled functions run automatically, but:
- Running every hour = 24 invocations/day = ~730/month
- Firestore reads depend on # of bookings
- Should be within free tier for small apps

## Alternative: More Precise Timing

If you want notifications at exactly 5 hours before (not "within 5-6 hours"), you can:
1. Use Cloud Tasks (more complex but precise)
2. Schedule individual tasks when booking is created
3. Let me know if you need this!

---

**Next Steps:**
1. Add the scheduled function to `functions/index.js`
2. Deploy
3. Update your Flutter app to save `bookingDateTime` and `notificationSent` fields when creating bookings
4. Test!
