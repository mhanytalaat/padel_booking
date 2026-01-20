# Fix Google Sign-In Error Code 10 (DEVELOPER_ERROR)

## The Problem
Error code 10 (`DEVELOPER_ERROR`) means the SHA-1 fingerprint of your app doesn't match what's registered in Firebase/Google Cloud Console.

## Solution: Add Missing SHA-1 Fingerprint

### Step 1: Get Your Current SHA-1 Fingerprint

#### For Release Build:
```bash
keytool -list -v -keystore android/padelcore-keystore.jks -alias padelcore -storepass PadelCore@2026 -keypass PadelCore@2026
```
Look for the line that says `SHA1:` and copy the fingerprint (remove colons).

#### For Debug Build:
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```
Or on Windows:
```bash
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

### Step 2: Add SHA-1 to Firebase

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **padelcore-app**
3. Click the gear icon ⚙️ → **Project Settings**
4. Scroll down to **Your apps** section
5. Find your Android app (`com.padelcore.app`)
6. Click **Add fingerprint** (or the SHA certificate fingerprints section)
7. Paste your SHA-1 fingerprint (with or without colons - both work)
8. Click **Save**

### Step 3: Create OAuth Client in Google Cloud Console

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select project: **padelcore-app**
3. Navigate to **APIs & Services** → **Credentials**
4. Click **+ CREATE CREDENTIALS** → **OAuth client ID**
5. Select **Android** as application type
6. Fill in:
   - **Name**: `PadelCore Android [Debug/Release]`
   - **Package name**: `com.padelcore.app`
   - **SHA-1 certificate fingerprint**: Your SHA-1 (with colons: `XX:XX:XX:...`)
7. Click **CREATE**

### Step 4: Wait and Re-download google-services.json

1. Wait 2-5 minutes for Google Cloud to sync with Firebase
2. Go back to Firebase Console → Project Settings
3. Find your Android app
4. Click **google-services.json** download button
5. Replace `android/app/google-services.json` with the new file
6. Verify the new `oauth_client` entries include your SHA-1

### Step 5: Rebuild Your App

```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

## Alternative: Use Firebase CLI

If you have Firebase CLI installed:

```bash
firebase apps:android:sha:create com.padelcore.app --sha YOUR_SHA1_HERE
```

## Verify Your google-services.json

After downloading, check that `oauth_client` array has entries with your SHA-1:

```json
"oauth_client": [
  {
    "client_id": "1087756281644-xxxxx.apps.googleusercontent.com",
    "client_type": 1,
    "android_info": {
      "package_name": "com.padelcore.app",
      "certificate_hash": "YOUR_SHA1_HERE"
    }
  }
]
```

## Common Issues

1. **Testing release build but only debug SHA-1 is registered**: Add release SHA-1
2. **Testing debug build but only release SHA-1 is registered**: Add debug SHA-1
3. **Both SHA-1s registered but still error**: Wait 5-10 minutes for sync, then re-download google-services.json
4. **Package name mismatch**: Ensure package name in google-services.json matches `com.padelcore.app`

## Current Registered SHA-1s (from google-services.json)

- Debug: `c2e4d57201dac033889993101d2317759016b819`
- Release: `77b84a9c0dd0d1a48c3d1a9d0d061f811abe9427`

If your current build's SHA-1 doesn't match either of these, you need to add it to Firebase.
