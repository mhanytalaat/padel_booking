# Spark Platform Integration

## Quick start

Run with your credentials (do not commit these):

```bash
flutter run --dart-define=SPARK_API_KEY=your_api_key --dart-define=SPARK_BEARER_TOKEN=your_jwt_token
```

Note: Bearer tokens expire (e.g. 30d). Refresh when needed and pass the new token.

## Firestore configuration

**Where:** Firebase Console → Firestore Database → `courtLocations` collection → choose a location document.

Add these fields **on the same document** as `name`, `address`, `courts`, etc.:

1. **sparkLocationId** (number) – Spark's location ID, e.g. `1`
2. **sparkCourtToSpaceId** (map, optional) – maps our court IDs to Spark space IDs:
   - `Court 1` → `1`
   - `Court 2` → `2`
   - etc.

Example document shape:
```
courtLocations / <your-location-id>
  name: "Padel Club"
  address: "..."
  courts: { ... }
  sparkLocationId: 1
  sparkCourtToSpaceId: { "Court 1": 1, "Court 2": 2 }
```

## API endpoints (Postman)

| Method | Path | Use |
|--------|------|-----|
| POST | `/api/v1/external-bookings` | Create booking |
| DELETE | `/api/v1/external-bookings/{id}` | Cancel booking |
| GET | `/api/v1/locations` | List locations |
| GET | `/api/v1/locations/{id}/spaces` | Get courts/spaces |
| GET | `/api/v1/locations/{id}/slots?date=YYYY-MM-DD` | Get available slots |

## Flow

1. User books courts in the app → saved to Firestore.
2. If `sparkLocationId` exists on the location:
   - Fetch slots from Spark for that date.
   - Map our court+time selections to Spark slot IDs.
   - Call Spark `createBooking` with `slotIds`, `firstName`, `lastName`, `phoneNumber`.
3. If Spark fails, the Firestore booking still succeeds; the error is logged.

## Files

- `lib/config/spark_config.dart` – API key and Bearer token
- `lib/services/spark_api_service.dart` – HTTP client
- `lib/screens/court_booking_confirmation_screen.dart` – Spark sync after booking
