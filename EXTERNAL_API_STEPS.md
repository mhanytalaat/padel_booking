# Option A: Backend API for the other mobile app (easiest & low cost)

Share one court location with another app: when they book you see it, when you book they see it. Use **Firebase Cloud Functions** (serverless, pay-per-use; free tier is generous).

---

## What you need

| Item | Purpose |
|------|--------|
| **1. API** | HTTP endpoints the other app calls: get location, get slots, create booking, cancel booking. |
| **2. Postman** | Collection + env so you (and the other team) can test the API. |
| **3. Staging URL** | Base URL for the other app (e.g. your Cloud Functions URL). Same URL can be used for staging and production, or use two Firebase projects. |

---

## Steps (overview)

1. Enable Blaze and set up Cloud Functions in your Firebase project.
2. Add the API code (this repo’s `functions/` folder) and deploy.
3. Create an API key and give the other app: **base URL**, **API key**, and **Postman collection**.
4. Optionally use a second Firebase project for staging (same steps, different project).

---

## Step 1: Firebase project and Blaze

- Go to [Firebase Console](https://console.firebase.google.com) → your project.
- **Billing:** Upgrade to **Blaze (pay as you go)**. Cloud Functions require Blaze. You only pay above the free tier (e.g. 2M invocations/month free; a small booking API usually stays free).
- Install Firebase CLI if you haven’t:
  ```bash
  npm install -g firebase-tools
  firebase login
  ```
- From the **padel_booking** folder (this repo has `firebase.json` and `functions/`):
  ```bash
  firebase use <your-project-id>
  ```
  If you use a different repo layout, run `firebase init functions` and choose JavaScript, then replace the generated `functions/` with this repo’s `functions/` code.

---

## Step 2: Add and deploy the API

- Ensure the `functions` folder from this repo is the one used by Firebase (same as in `firebase.json`).
- Install dependencies and deploy:
  ```bash
  cd functions
  npm install
  cd ..
  firebase deploy --only functions
  ```
- After deploy, the CLI prints the function URLs, e.g.:
  - `https://us-central1-<project-id>.cloudfunctions.net/getLocation`
  - `https://us-central1-<project-id>.cloudfunctions.net/getSlots`
  - etc.
- Your **base URL** for the other app is:  
  `https://us-central1-<project-id>.cloudfunctions.net`  
  (they call `baseUrl/getLocation`, `baseUrl/getSlots`, etc., or use the full URLs you give them).

---

## Step 3: API key and sharing with the other app

- **Create an API key** (any random string, e.g. 32 chars). Set it in Firebase (from the project root where `firebase.json` is):
  ```bash
  firebase functions:config:set external.api_key="YOUR_SECRET_KEY"
  ```
  Then **redeploy** so the new config is used:  
  `firebase deploy --only functions`
  - Alternatively you can use an env var `EXTERNAL_API_KEY` in Firebase (Console → Functions → environment config) if your hosting supports it; the code checks both.
- The other app sends the key in the **`x-api-key`** header on every request.
- Give the other app:
  1. **Base URL** – e.g. `https://us-central1-<project-id>.cloudfunctions.net`.
  2. **API key** – same value you set in config.
  3. **Postman collection** – import `docs/external_api/ExternalApi.postman_collection.json` and the env file `docs/external_api/ExternalApi.postman_environment.example.json`; they duplicate the env with their base URL and API key.

---

## Step 4: Staging (optional)

- **Cheapest:** Use the same project and same URLs. The other app points to your Cloud Functions URL; you can use a separate **location** in Firestore for “staging” (e.g. a test location document) and pass that `locationId` in requests.
- **Staging project:** Create a second Firebase project (e.g. “myapp-staging”), deploy the same functions there, and give the other app the staging base URL and a staging API key. No extra infra cost beyond Firebase free tier for the second project.

---

## API endpoints (what the other app will use)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/getLocation?locationId=<id>` | Get one location (courts, open/close times). |
| GET | `/getSlots?locationId=<id>&date=YYYY-MM-DD` | Get available slots per court for that date. |
| POST | `/createBooking` | Body: `locationId`, `date`, `courts` (courtId → array of slot strings), `firstName`, `lastName`, `phoneNumber`. Creates a booking in Firestore so your app and theirs stay in sync. |
| DELETE | `/cancelBooking?bookingId=<id>` | Cancel (delete) a booking. |

All requests must include header: **`x-api-key: <their API key>`**.

---

## Cost (summary)

- **Firebase Blaze:** You only pay for usage above free tier.
- **Cloud Functions:** Free tier ≈ 2M invocations/month. A small booking API is typically well within free tier.
- **Firestore:** Your existing reads/writes; a few extra for API calls. Free tier is 50K reads, 20K writes per day.
- **No fixed monthly server cost** – serverless.

---

## Files in this repo

- `functions/` – Cloud Functions code (`getLocation`, `getSlots`, `createBooking`, `cancelBooking`).
- `firebase.json` – Points Firebase CLI to `functions` folder.
- `docs/external_api/ExternalApi.postman_collection.json` – Postman collection for the API.
- `docs/external_api/ExternalApi.postman_environment.example.json` – Example env: set `baseUrl` (your Cloud Functions base URL) and `apiKey` (same as `external.api_key`).

After deploy, the other app uses the same Firestore data (courtBookings, courtLocations) through this API, so when they book you see it in your app and when you book they see it in theirs.
