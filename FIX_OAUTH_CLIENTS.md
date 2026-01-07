# Fix: Manually Create OAuth Clients for Firebase Auth

## The Problem
Your `google-services.json` has empty `oauth_client: []` which causes "app not authorized" errors.

## Solution: Create OAuth Clients in Google Cloud Console

### Step 1: Go to Google Cloud Console
1. Open: https://console.cloud.google.com
2. Select project: **padelcore-app** (or search for it)

### Step 2: Navigate to Credentials
1. Click **APIs & Services** → **Credentials** (left sidebar)
2. Or go directly: https://console.cloud.google.com/apis/credentials?project=padelcore-app

### Step 3: Create OAuth 2.0 Client ID for Android
1. Click **+ CREATE CREDENTIALS** (top of page)
2. Select **OAuth client ID**
3. If prompted, configure OAuth consent screen first (use basic info)
4. In "Application type", select **Android**
5. Fill in:
   - **Name**: `PadelCore Android Client` (or any name)
   - **Package name**: `com.padelcore.app`
   - **SHA-1 certificate fingerprint**: `77:B8:4A:9C:0D:D0:D1:A4:8C:3D:1A:9D:0D:06:1F:81:1A:BE:94:27`
     (Your release SHA-1 - remove colons, use uppercase)
6. Click **CREATE**

### Step 4: Create Second OAuth Client for Debug
1. Click **+ CREATE CREDENTIALS** again
2. Select **OAuth client ID**
3. Application type: **Android**
4. Fill in:
   - **Name**: `PadelCore Android Debug Client`
   - **Package name**: `com.padelcore.app`
   - **SHA-1 certificate fingerprint**: `C2:E4:D5:72:01:DA:C0:33:88:99:93:10:1D:23:17:75:90:16:B8:19`
     (Your debug SHA-1)
5. Click **CREATE**

### Step 5: Wait and Re-download google-services.json
1. Wait 2-3 minutes for Google Cloud to sync with Firebase
2. Go back to Firebase Console → Project Settings
3. Find your Android app (`com.padelcore.app`)
4. Click **google-services.json** download button
5. Replace `android/app/google-services.json` with the new file
6. Check that `oauth_client` array now has entries (not empty)

### Step 6: Rebuild Your App
```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

## Alternative: Use Firebase CLI (if you have it installed)
```bash
firebase apps:list
firebase apps:android:sha:create com.padelcore.app --sha YOUR_SHA1
```

## Verify OAuth Clients Were Created
After downloading the new `google-services.json`, it should have:
```json
"oauth_client": [
  {
    "client_id": "1087756281644-xxxxx.apps.googleusercontent.com",
    "client_type": 1,
    "android_info": {
      "package_name": "com.padelcore.app",
      "certificate_hash": "xxxxx"
    }
  }
]
```

If `oauth_client` is still empty after creating OAuth clients, wait 5-10 minutes and download again.

