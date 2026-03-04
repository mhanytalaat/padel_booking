# Phone verification – testing with a real number

Your app uses **Firebase Phone Authentication**. The "Testing" status and "Test users" you see in the console are for **Google (OAuth) sign-in only**. They do **not** restrict phone sign-in. You can test phone verification with a real number as below.

---

## 1. Firebase Console – enable Phone sign-in

1. Open [Firebase Console](https://console.firebase.google.com) → your project.
2. Go to **Authentication** → **Sign-in method**.
3. Click **Phone** and turn it **On** if it isn’t already. Save.

No need to add your number under "Phone numbers for testing" if you want **real** SMS. Test numbers are for fixed codes without sending SMS.

---

## 2. Run the app on a real device (not web or desktop)

Phone auth in this app is **only supported on Android and iOS**. It is disabled on:

- **Web** (browser)
- **Desktop**: Windows, macOS, Linux (Firebase Phone Auth is not supported there and can cause type errors)

Use for testing:

- **Android**: physical device or emulator with Google Play services.
- **iOS**: physical device or simulator.

When you **build** for iOS or Android (e.g. `flutter build apk`, `flutter build ios`, or run on a connected device), phone verification will work. Running on Windows (e.g. `flutter run -d windows`) will show Email/Google/Apple only; the Phone option is hidden and no error will occur.

```bash
flutter run
# Then choose your device (e.g. iPhone or Android device).
```

---

## 3. Sign in with Phone in the app

1. On the login screen, tap the **Phone** option (with Email and Google).
2. Enter your number in **E.164** format, e.g. **+201012345678** (Egypt: +2 then 11 digits).
3. Tap **Send OTP** (or equivalent). You should receive an SMS with a 6-digit code.
4. Enter the code and complete sign-in.

If you get **"app-not-authorized"** or similar, check in Firebase Console that the app’s package name (Android) / bundle ID (iOS) matches the one in your Firebase project under Project settings → Your apps.

---

## 4. Optional: test without real SMS (dev only)

To avoid sending real SMS during development:

1. Firebase Console → **Authentication** → **Sign-in method** → **Phone**.
2. Under **Phone numbers for testing**, add a number (e.g. +20 100 000 0000) and a fixed 6-digit code (e.g. 123456).
3. In the app, use that number; the fixed code will work without an SMS.

For **real** testing, don’t add your real number there (or remove it) so Firebase sends a real SMS.

---

## 5. Troubleshooting: "OTP sent" but no SMS received (iPhone / Android)

If the app says the code was sent but you never get an SMS, check the following in order.

### A. Test phone number (most common)

- In Firebase: **Authentication** → **Sign-in method** → **Phone** → **Phone numbers for testing**.
- If your number is listed there, Firebase **does not send a real SMS** — it expects you to enter the fixed code you set (e.g. 123456).
- **Fix:** Remove your number from the test list if you want real SMS, or use the fixed code you configured for that test number.

### B. Billing plan (required for real SMS)

- As of **September 2024**, phone auth SMS is **only available on the Blaze (pay-as-you-go) plan**. The free Spark plan no longer sends SMS.
- **Fix:** Firebase Console → **Project settings** (gear) → **Usage and billing** → upgrade to **Blaze**. You only pay above the free tier; typical low-volume apps stay within free quotas.

### C. SMS region not enabled

- Even on Blaze, SMS is blocked by default until you allow regions.
- **Fix:** Firebase Console → **Authentication** → **Settings** (or **Sign-in method** → Phone → settings). Find **SMS region policy** and **allow the region** where the phone number is (e.g. Egypt / Africa or the specific country). Without this, SMS will not be sent (you may see error 17006 in logs).

### D. Number format

- Use **E.164**: country code + number, no spaces, e.g. `+201012345678` for Egypt.
- **Fix:** Ensure the number in the app matches E.164 and is correct.

### E. iOS: APNs (optional but recommended)

- For smooth verification on iOS, Firebase can use APNs. **Authentication** → **Settings** → **Authorized domains** and ensure your app’s bundle ID is correct. For iOS, upload an **APNs auth key** (or certificate) in Project settings if you use phone auth in production.
- Missing APNs can sometimes affect delivery or cause extra verification steps; it’s not always the cause of “no SMS.”

### F. Carrier / delay

- Some carriers or regions delay or block verification SMS. Try **Resend OTP** after a minute, or another number or network (e.g. Wi‑Fi vs mobile data) to rule out carrier issues.

---

## Summary

| What you want              | What to do |
|----------------------------|------------|
| Test with **real** SMS     | Enable Phone in Firebase, run on device, use Phone on login, enter real number. |
| "Test users" in console    | Only affects **Google/Apple** sign-in. Ignore for phone. |
| Test without SMS (dev)     | Add a test phone number + code in Firebase → Phone → Phone numbers for testing. |
| "OTP sent" but no SMS      | Check: (1) Number not in test list, (2) Blaze plan, (3) SMS region enabled, (4) E.164 format. |
