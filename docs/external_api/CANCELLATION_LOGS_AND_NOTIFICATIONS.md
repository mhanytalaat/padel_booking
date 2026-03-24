# Cancellation logs and notifications

Every court booking cancellation is **logged** and **notified**, whether the user cancels in your app or the other app cancels via the API.

---

## 1. Logs (Firestore)

**Collection:** `courtBookingCancellationLogs`

A new document is created here whenever a `courtBookings` document is deleted (after it is marked with `cancelledBy` and `cancelledAt`).

| Field         | Description |
|---------------|-------------|
| `bookingId`   | Firestore document ID of the cancelled booking |
| `locationId`  | Location (e.g. 13 Padel) |
| `locationName`| e.g. "13 Padel" |
| `date`        | Booking date (YYYY-MM-DD) |
| `courts`      | Map of courtId → slot strings |
| `userId`      | User who had the booking (or "external-api") |
| `bookedBy`    | Who created the booking |
| `cancelledBy` | `"app"` or `"external_api"` |
| `cancelledAt` | Timestamp when cancelled |
| `source`      | `"app"` or `"external_api"` (same idea as cancelledBy) |
| `guestName`   | For external API bookings |
| `guestPhone`  | For external API bookings |
| `timeRange`   | Display time range if stored |
| `createdAt`   | When the log entry was written |

**Where to view:** Firebase Console → Firestore Database → `courtBookingCancellationLogs`.

**In the app:** Admin screen has a **Cancel Logs** tab that lists all cancellations (App + External API) from this collection. Open Admin → last tab "Cancel Logs".

---

## 2. Notifications (FCM topic)

When a cancellation is logged, a push notification is sent to the FCM topic:

**Topic name:** `booking_cancellations`

- **Title:** "Court booking cancelled"
- **Body:** e.g. "Booking cancelled at 13 Padel for 2026-03-15 (external_api)" or "(app)"
- **Data payload:** `type`, `bookingId`, `locationId`, `source`

**How to receive these notifications (e.g. for admins):**

In your Flutter app, subscribe to the topic when the user is an admin or when you want to receive cancellation alerts:

```dart
import 'package:firebase_messaging/firebase_messaging.dart';

// After user signs in (e.g. if admin)
await FirebaseMessaging.instance.subscribeToTopic('booking_cancellations');
```

Only devices that have subscribed will receive the notification. You can subscribe only for admin users or for a dedicated “staff” app.

---

## 3. Flow summary

| Who cancels        | What happens |
|--------------------|--------------|
| **User in your app** | App updates the booking with `cancelledBy: 'app'`, then deletes it. Cloud Function `onCourtBookingDeleted` runs → writes to `courtBookingCancellationLogs` and sends FCM to topic `booking_cancellations`. |
| **Other app (API)**  | API updates the booking with `cancelledBy: 'external_api'`, then deletes it. Same trigger runs → same log and same FCM. |

So you get one log entry and one notification per cancellation, and `source` / `cancelledBy` tells you whether it was the app or the external API.

---

## 4. Firestore rule for Cancel Logs tab

The Admin **Cancel Logs** tab reads `courtBookingCancellationLogs`. If the tab shows "Error" or empty, add a read rule for that collection. In `firestore.rules` (project root), add:

```
match /courtBookingCancellationLogs/{logId} {
  allow read: if request.auth != null;
  allow create: if false;
  allow update, delete: if false;
}
```

(Only Cloud Functions write to this collection; clients only read.)
