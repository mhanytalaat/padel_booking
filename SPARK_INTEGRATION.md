# Spark Platform Integration

Syncs court bookings with Spark for multiple locations. Uses the **Integrations** API (Normal Integration).

- **Base URL:** `https://external-client-staging.sparkplatform.app`
- **Auth:** `x-api-key` header (Bearer token optional if required by your environment).

---

## What to do now (setup with new API key)

1. **Run the app with your API key** (do not commit the key):
   ```bash
   flutter run --dart-define=SPARK_API_KEY=YOUR_API_KEY_HERE
   ```
   Or build release:
   ```bash
   flutter build apk --dart-define=SPARK_API_KEY=YOUR_API_KEY_HERE
   ```

2. **Optional – use env var** so you don’t type the key each time:
   - Windows (PowerShell): `$env:SPARK_API_KEY="your_key"; flutter run --dart-define=SPARK_API_KEY=$env:SPARK_API_KEY`
   - Or add `SPARK_API_KEY` in VS Code launch config (see `.vscode/launch.json`).

3. **Configure Firestore** for each location you want to sync with Spark:
   - Firebase Console → Firestore → `courtLocations` → open the location document.
   - Add **sparkLocationId** (number) – Spark’s location ID.
   - Optionally add **sparkCourtToSpaceId** (map) – maps your court names to Spark space IDs.

4. **Test with Postman** using the Integrations collection they sent you; base URL is already `https://external-client-staging.sparkplatform.app`.

5. **CI/CD (e.g. Codemagic):** Set `SPARK_API_KEY` (and optionally `SPARK_BASE_URL`, `SPARK_BEARER_TOKEN`) in the pipeline’s environment variables; the existing scripts will pick them up.

---

## Complete the integration (testing on web)

1. **Run the app with the API key** (you're already doing this):
   ```bash
   flutter run -d chrome --dart-define=SPARK_API_KEY=YOUR_KEY
   ```
   Or `flutter run -d web-server`. Spark HTTP calls work on web; if the Spark API allows CORS from your origin, requests will succeed.

2. **Firestore** – Ensure one location (e.g. PadelCore 3) has:
   - `sparkLocationId`: number (e.g. `1`)
   - `sparkCourtToSpaceId`: map `court_1` → 1, `court_2` → 2, etc. (values number or string both work)

3. **Test create (book a court)**  
   - Log in, go to that location, pick a date and court(s) + time slot(s), confirm booking.  
   - In the browser devtools **Console** (F12), look for errors. If Spark sync fails you'll see e.g. `Spark API sync failed: ...`.  
   - In Firestore, open the new `courtBookings` document: if sync worked it should have a field **sparkExternalBookingId** (value = Spark's booking id).

4. **Test cancel**  
   - In "My Bookings", cancel a booking that has **sparkExternalBookingId**.  
   - The app calls Spark `DELETE /api/v1/external-bookings/{id}` so the slot is released there too.

5. **If you see CORS errors** – see [CORS on web](#cors-on-web) below.

6. **Optional – verify in Postman**  
   - `GET /api/v1/locations` and `GET /api/v1/locations/1/slots?date=YYYY-MM-DD` to confirm location and slots match.  
   - Then compare with a booking created from the app and the `sparkExternalBookingId` stored in Firestore.

---

## CORS on web

**What the error means:** When you run the app in the **browser** (Chrome, etc.), the page origin is e.g. `http://localhost:60135`. The browser sends requests to Spark at `https://external-client-staging.sparkplatform.app`. That’s a **cross-origin** request. For security, the browser first sends a “preflight” (OPTIONS) request and only allows the real request if the **server** responds with CORS headers such as `Access-Control-Allow-Origin`. Your error means Spark’s API is **not** sending those headers (or not allowing your origin), so the browser blocks the request. You cannot fix this from your Flutter/web code; the **Spark API server** must allow your origin.

**What to do:**

1. **Ask Spark** to enable CORS for:
   - Development: `http://localhost` (or `http://localhost:*` if they support a pattern), and/or your specific dev port.
   - Production: your deployed web URL (e.g. `https://your-app.web.app`, `https://yourdomain.com`).
   They need to respond to OPTIONS preflight and include headers like:  
   `Access-Control-Allow-Origin: <your-origin>`  
   (and often `Access-Control-Allow-Methods`, `Access-Control-Allow-Headers`).

2. **Test the integration without CORS** by running on a **non-web** platform. CORS only applies in the browser; on Android, iOS, Windows, or macOS the app talks to Spark directly and CORS is not involved:
   ```bash
   flutter run -d windows
   ```
   or use an Android emulator / device. Your same API key and Firestore config will work there.

3. **Postman** does not use the browser’s CORS policy, so Spark’s API can work in Postman even when it fails in the browser. Use Postman to confirm the API and key are valid.

---

## Quick start

Run with your API key (do not commit the key):

```bash
flutter run --dart-define=SPARK_API_KEY=your_api_key
```

Optional: override base URL or set Bearer token:

```bash
flutter run --dart-define=SPARK_API_KEY=your_key --dart-define=SPARK_BASE_URL=https://external-client-staging.sparkplatform.app --dart-define=SPARK_BEARER_TOKEN=optional_jwt
```

Build release:

```bash
flutter build apk --dart-define=SPARK_API_KEY=your_api_key
```

## Firestore configuration

**Where:** Firebase Console → Firestore Database → `courtLocations` collection → open the **location document** (e.g. the one whose `name` is "PadelCore 3" or your venue name).  
Do **not** add these fields inside each court sub-document; add them on the **same location document** that has `name`, `address`, `courts`, `sparkLocationId`, etc.

Add these fields **on the same document** as `name`, `address`, `courts`, etc.:

1. **sparkLocationId** – type **number** (not string). Spark’s location ID for this venue, e.g. `1`.
2. **sparkCourtToSpaceId** (optional) – type **map**. Add this **on the location document** (same level as `sparkLocationId`), **not** on each court. One map with one entry per court: keys = your **court `id`** values exactly as stored in `courts` (e.g. `"court_1"`, `"court_2"`, `"court_3"`, `"court_4"`), values = **numbers** (Spark’s space ID).  
   - If you have 4 courts with ids `court_1` … `court_4`, the map has 4 entries: `"court_1"` → `1`, `"court_2"` → `2`, `"court_3"` → `3`, `"court_4"` → `4`.  
   - Values should match the space IDs from Spark’s `GET /api/v1/locations/{id}/spaces`.

Example – **location document** (e.g. "PadelCore 3") with 4 courts whose `id` fields are `court_1` … `court_4`:

```
courtLocations / <location-doc-id>
  name: "PadelCore 3"
  address: "..."
  courts: [ { id: "court_1", name: "Court 1", ... }, { id: "court_2", ... }, ... ]
  sparkLocationId: 1
  sparkCourtToSpaceId: { "court_1": 1, "court_2": 2, "court_3": 3, "court_4": 4 }
```

- **sparkLocationId** and **sparkCourtToSpaceId** both live on this **location** document, not inside each court.
- In Firestore: `sparkLocationId` = Number; `sparkCourtToSpaceId` = Map with string keys (court id) and number values (Spark space ID). Do not store as strings.

## API endpoints (Integrations Postman collection)

| Method | Path | Use |
|--------|------|-----|
| POST | `/api/v1/external-bookings` | Create booking (body: `slotIds`, `firstName`, `lastName`, `phoneNumber`) |
| DELETE | `/api/v1/external-bookings/{id}` | Cancel booking (id from create response) |
| GET | `/api/v1/locations` | List locations |
| GET | `/api/v1/locations/{id}/spaces` | Get courts/spaces (optional `?spaceType=pickle_court`) |
| GET | `/api/v1/locations/{id}/slots?date=YYYY-MM-DD` | Get available slots |

## Flow

1. User books courts in the app → saved to Firestore.
2. If `sparkLocationId` exists on the location:
   - Fetch slots from Spark for that date.
   - Map our court+time selections to Spark slot IDs.
   - Call Spark `createBooking` with `slotIds`, `firstName`, `lastName`, `phoneNumber`.
3. If Spark create returns an `id`, it is stored on the Firestore booking as `sparkExternalBookingId`.
4. When the user cancels a court booking that has `sparkExternalBookingId`, the app calls Spark DELETE to cancel there too.
5. If Spark fails, the Firestore booking still succeeds; the error is logged.

## Files

- `lib/config/spark_config.dart` – Base URL, API key (Bearer optional)
- `lib/services/spark_api_service.dart` – HTTP client (book, cancel, locations, spaces, slots)
- `lib/screens/court_booking_confirmation_screen.dart` – Spark sync after booking, stores `sparkExternalBookingId`
- `lib/screens/my_bookings_screen.dart` – Spark cancel when user cancels court booking
