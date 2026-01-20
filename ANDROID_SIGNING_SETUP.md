# Android Signing Setup for Google Play

## Problem
Error: "All uploaded bundles must be signed"

This means the AAB file was built without a release keystore signature.

## Solution 1: Configure Codemagic (Recommended)

### Step 1: Upload Keystore to Codemagic

1. Go to Codemagic → **Teams** → **Encrypted environment variables**
2. Find or create the group: **keystore_credentials**
3. Add the following variables:
   - **Variable name**: `CM_KEYSTORE` (or upload the file directly)
   - **Variable name**: `CM_KEYSTORE_PASSWORD` → Value: `PadelCore@2026` (your keystore password)
   - **Variable name**: `CM_KEY_PASSWORD` → Value: `PadelCore@2026` (your key password)
   - **Variable name**: `CM_KEY_ALIAS` → Value: `padelcore` (your key alias)

4. **Upload the keystore file**:
   - Click **Add file** in the `keystore_credentials` group
   - Upload `padelcore-keystore.jks`
   - Codemagic will make it available as `$CM_KEYSTORE_PATH` or similar

### Step 2: Verify codemagic.yaml

The `codemagic.yaml` has been updated to:
- Load the `keystore_credentials` group
- Set up the keystore file and `key.properties` before building
- Build a signed release AAB

### Step 3: Build on Codemagic

1. Push your changes to trigger a build
2. The build will automatically:
   - Copy the keystore file to `android/padelcore-keystore.jks`
   - Create `android/key.properties` with credentials
   - Build a signed release AAB

## Solution 2: Build Locally (For Testing)

If you want to build a signed AAB locally:

### Step 1: Prepare Files

1. **Copy keystore file** to `android/padelcore-keystore.jks`
2. **Create `android/key.properties`**:
   ```properties
   storePassword=PadelCore@2026
   keyPassword=PadelCore@2026
   keyAlias=padelcore
   ```

### Step 2: Build Release AAB

```powershell
cd C:\projects\padel_booking
flutter clean
flutter pub get
flutter build appbundle --release
```

The signed AAB will be at:
```
build/app/outputs/bundle/release/app-release.aab
```

### Step 3: Verify AAB is Signed

You can verify the AAB is signed using:
```powershell
# Using jarsigner (if you have Java installed)
& "C:\Program Files\Android\Android Studio\jbr\bin\jarsigner.exe" -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab
```

If signed correctly, you'll see: `jar verified.`

## Troubleshooting

### Issue: "Keystore file not found"
- **Solution**: Ensure `padelcore-keystore.jks` is in the `android/` directory (for local builds) or uploaded to Codemagic

### Issue: "key.properties not found"
- **Solution**: Create `android/key.properties` with the correct credentials

### Issue: "Wrong password"
- **Solution**: Verify the passwords in `key.properties` match your keystore

### Issue: Still getting "All uploaded bundles must be signed"
- **Solution**: 
  1. Verify you're building with `--release` flag (not `--debug`)
  2. Check that `build.gradle.kts` signing config is being applied
  3. Verify the AAB file name is `app-release.aab` (not `app-debug.aab`)

## Upload to Google Play

Once you have a signed `app-release.aab`:

1. Go to Google Play Console
2. Navigate to your app → **Testing** → **Closed testing** (or Internal/Open)
3. Click **Create new release**
4. Upload `app-release.aab`
5. Add release notes
6. Review and release
