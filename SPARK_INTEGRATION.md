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

4. **Get real IDs and test the API in Postman** – see [Postman: get real IDs and test](#postman-get-real-ids-and-test) below. The collection is in `docs/spark/Integrations.postman_collection.json`.

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

## Postman: get real IDs and test

The repo includes a Postman collection and an example environment so you can call Spark's API (no CORS in Postman).

**Files**
- `docs/spark/Integrations.postman_collection.json` – requests: Get Locations, Get Location Spaces, Get Location Slots, Book (Create), Cancel.
- `docs/spark/Spark.postman_environment.example.json` – example env with `externalClientURL` and `externalClientAPIKey`.

**Setup in Postman**

1. **Import the collection**  
   Postman → Import → select `docs/spark/Integrations.postman_collection.json`.

2. **Create an environment**  
   - Environments → Create / Import. You can use `Spark.postman_environment.example.json` as a template.  
   - Set **externalClientURL**: `https://external-client-staging.sparkplatform.app`  
   - Set **externalClientAPIKey**: your Spark API key (the one you use with `--dart-define=SPARK_API_KEY=...`).  
   - Save and select this environment (top-right dropdown).

3. **Get the real IDs from Spark**  
   - **Get Locations** – run it. In the response, find the location that matches your venue (e.g. PadelCore 3). Note its **id** (e.g. `1`). That is your **sparkLocationId** in Firestore.  
   - **Get Location Spaces** – change the URL path if needed: `/api/v1/locations/1/spaces` (use the id from step above). Run it. Note each space's **id** and which court it is. Map your app's court ids (e.g. `court_1`, `court_2`, …) to these space ids and fill **sparkCourtToSpaceId** in Firestore.  
   - **Get Location Slots** – use the same location id and set `date` to a date you want to book (e.g. `?date=2026-02-25`). Run it. The response shows available slots. Each slot has an **id** (or **slotId**); it may be a simple number or a composite string. The app uses this id when calling Book (Create).

4. **Update Firestore**  
   On the **location** document in `courtLocations`: set **sparkLocationId** to the location id from Get Locations, and **sparkCourtToSpaceId** to the map you built from Get Location Spaces (e.g. `court_1` → 1, `court_2` → 2, …). Values can be number or string.

5. **Optional: test Book and Cancel in Postman**  
   - **Book (Create)** – edit the body: use a real `slotIds` value from Get Location Slots (one or more ids), and real `firstName`, `lastName`, `phoneNumber`. Send. Note the **id** in the response; that is **sparkExternalBookingId**.  
   - **Cancel** – set the URL to `.../external-bookings/<id>` with the id from the create response, then Send.

**SlotIds format**  
Spark's Book API accepts `slotIds` as an array of strings. Each string may be a simple id or a composite (e.g. `120#2026-10-14T10:30:00.000+03:00#...`). The app uses whatever id format the GET slots response returns; the service was updated to support both.

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

## Troubleshooting when booking (Windows / profile run)

When you run with `--dart-define=SPARK_API_KEY=...`, watch the **terminal** (where `flutter run -d windows --profile` is running) when you confirm a booking. You should see lines like:

- **`[Spark] API configured: true`** – API key was passed correctly. If `false`, the key wasn’t picked up (check `--dart-define=SPARK_API_KEY=...`).
- **`[Spark] Location sparkLocationId: 1`** (or a number) – This location is wired to Spark. If you see **`not set`**, add **sparkLocationId** (and **sparkCourtToSpaceId**) on the location document in Firestore (see [Firestore configuration](#firestore-configuration)).
- **`[Spark] Resolved slotIds: 2 (...)`** – Number of Spark slot IDs we’re sending. If **0**, either the location has no `sparkCourtToSpaceId`, or the chosen time didn’t match Spark’s slots (check date format and that Spark has slots for that date).
- **`[Spark] Sync skipped: ...`** – Spark was not called (e.g. no API key or no slotIds). Read the message.
- **`[Spark] API sync failed: 401 ...`** (or 4xx/5xx) – Request reached Spark but failed (bad key, validation, server error). Check status code and message.
- **`[Spark] Success: sparkExternalBookingId=... saved to Firestore`** – Integration worked; the Firestore booking document now has **sparkExternalBookingId**.

**Quick checks:**

1. **Firestore** – For the location you’re booking, the document in `courtLocations` must have **sparkLocationId** (number) and **sparkCourtToSpaceId** (map court id → space id). Same document as `name`, `courts`, etc.
2. **Terminal** – After confirming a booking, look for the `[Spark]` lines above to see whether config, slot resolution, or the API call failed.
3. **Firestore after booking** – Open the new document in `courtBookings`. If Spark sync succeeded, it will have a field **sparkExternalBookingId** (value = Spark’s booking id). No field = sync was skipped or failed (use terminal logs to see why).

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
