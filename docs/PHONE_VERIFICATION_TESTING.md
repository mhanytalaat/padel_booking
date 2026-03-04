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

## Summary

| What you want              | What to do |
|----------------------------|------------|
| Test with **real** SMS     | Enable Phone in Firebase, run on device, use Phone on login, enter real number. |
| "Test users" in console    | Only affects **Google/Apple** sign-in. Ignore for phone. |
| Test without SMS (dev)     | Add a test phone number + code in Firebase → Phone → Phone numbers for testing. |
