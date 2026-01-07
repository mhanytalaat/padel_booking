# Troubleshooting SHA-1/SHA-256 Error

## Step 1: Get Debug Keystore Fingerprints

The debug keystore is located at: `C:\Users\YourUsername\.android\debug.keystore`

### Using Android Studio:
1. Open Android Studio
2. Click **Build** → **Generate Signed Bundle/APK**
3. Select **APK** → **Next**
4. Click **Create new...** (for debug keystore)
5. Or use existing debug keystore at: `%USERPROFILE%\.android\debug.keystore`
6. Password: `android`
7. Alias: `androiddebugkey`
8. Key password: `android`
9. View the SHA-1 and SHA-256 fingerprints

### Using Command Line:
```powershell
# Find your Java installation first (usually in Android Studio)
# Common paths:
# C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe
# C:\Program Files\Java\jdk-*\bin\keytool.exe

# Then run:
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

## Step 2: Add Debug Fingerprints to Firebase

1. Go to Firebase Console → Project Settings
2. Find your Android app (`com.padelcore.app`)
3. Click **Add fingerprint**
4. Add **Debug SHA-1**
5. Click **Add fingerprint** again
6. Add **Debug SHA-256**
7. **Download the updated google-services.json**
8. Replace `android/app/google-services.json`

## Step 3: Verify Release Fingerprints Match

From your screenshot, you have:
- SHA-1: `77:b8:4a:9c:0d:0d:0d:d1:a4:8c:3d:1a:9d:0d:06:1f:81:1a:be:94:27`
- SHA-256: `a1:77:43:5b:76:c2:07:08:5f:b9:51:33:25:90:83:45:dc:32:9b:0a:a7:e4:71:7e:59:f9:98:3c:42:29:30:62`

Verify these match your release keystore:
```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -list -v -keystore padelcore-keystore.jks -alias padelcore -storepass PadelCore@2026
```

## Step 4: Common Issues

1. **Testing in debug mode but only added release fingerprints** → Add debug fingerprints
2. **Testing in release mode but fingerprints don't match** → Verify release fingerprints
3. **Didn't download updated google-services.json** → Download and replace the file
4. **Fingerprints added but app not rebuilt** → Run `flutter clean` and rebuild
5. **Wrong package name** → Verify `com.padelcore.app` matches everywhere

## Step 5: After Adding All Fingerprints

1. Download updated `google-services.json` from Firebase
2. Replace `android/app/google-services.json`
3. Run:
   ```bash
   flutter clean
   flutter pub get
   flutter build apk --release  # or flutter run for debug
   ```

