# Fix iOS App Store Connect Upload Error (UNEXPECTED_ERROR)

## The Problem
Error: `"iris-code": "UNEXPECTED_ERROR"` when uploading IPA to App Store Connect.

This usually means:
1. **Duplicate version/build number** - Version 1.1.7 build 37 already exists in App Store Connect
2. **Missing App Store Connect credentials** - API key or authentication issue
3. **Build configuration mismatch** - The build number in the IPA doesn't match what's expected

## Solution 1: Check App Store Connect for Existing Versions

1. Go to [App Store Connect](https://appstoreconnect.apple.com/)
2. Select your app: **PadelCore**
3. Go to **App Store** tab → **iOS App**
4. Check **TestFlight** tab:
   - Look for version **1.1.7** with build **37**
   - If it exists, you need to increment the build number

## Solution 2: Increment Build Number

If build 37 already exists, increment to 38:

1. **Update `pubspec.yaml`:**
   ```yaml
   version: 1.1.7+38
   ```

2. **Update `android/app/build.gradle.kts`:**
   ```kotlin
   versionCode = 38
   versionName = "1.1.7"
   ```

3. **Commit and push:**
   ```bash
   git add pubspec.yaml android/app/build.gradle.kts
   git commit -m "Bump version to 1.1.7 (build 38) - fix duplicate build number"
   git push
   ```

4. **Rebuild in Codemagic**

## Solution 3: Verify Codemagic iOS Workflow Settings

### Check Pre-Build Script
1. Go to Codemagic → Your app → **Default Workflow** → **Edit**
2. Find **Build** section → **Pre-build script**
3. Ensure the build number fix script is present (from `CODEMAGIC_BUILD_NUMBER_FIX.md`)

### Check Build Arguments
1. In **Build** section → **Build arguments**
2. Should be: `--release --build-name=1.1.7 --build-number=38`
   OR just: `--release` (if pre-build script sets environment variables)

### Check App Store Connect Publishing
1. In **Publishing** section → **App Store Connect**
2. Verify:
   - ✅ **Publish to App Store Connect** is enabled
   - ✅ **API Key** is configured correctly
   - ✅ **App Store Connect API Key** is valid and not expired

## Solution 4: Check App Store Connect API Key

1. Go to [App Store Connect](https://appstoreconnect.apple.com/)
2. Click your name (top right) → **Users and Access**
3. Go to **Keys** tab
4. Verify your API key:
   - ✅ Key exists and is active
   - ✅ Key has **App Manager** or **Admin** role
   - ✅ Key is not expired

5. In Codemagic:
   - Go to **App settings** → **Environment variables**
   - Verify `APP_STORE_CONNECT_API_KEY_ID` and `APP_STORE_CONNECT_ISSUER_ID` are set
   - Or check **Publishing** → **App Store Connect** → API key is uploaded

## Solution 5: Manual Upload (Alternative)

If automatic upload keeps failing:

1. **Download the IPA** from Codemagic artifacts
2. **Upload manually** via:
   - [App Store Connect](https://appstoreconnect.apple.com/) → Your app → **TestFlight** → **+** → Upload
   - Or use **Transporter** app (macOS)
   - Or use **Xcode** → Window → Organizer → Distribute App

## Solution 6: Check Build Logs

In Codemagic build logs, look for:
- Build number being used: Should show `37` or `38`
- Version name: Should show `1.1.7`
- App Store Connect authentication: Should show success
- Upload progress: Check where it fails

## Common Issues

### Issue: Build number mismatch
**Symptom:** Build succeeds but upload fails with UNEXPECTED_ERROR
**Fix:** Ensure pre-build script correctly sets `FLUTTER_BUILD_NUMBER` from `pubspec.yaml`

### Issue: Duplicate build number
**Symptom:** Error says version already exists
**Fix:** Increment build number in `pubspec.yaml` and rebuild

### Issue: API key expired
**Symptom:** Authentication fails
**Fix:** Generate new API key in App Store Connect and update Codemagic

### Issue: Wrong bundle identifier
**Symptom:** App not found in App Store Connect
**Fix:** Verify bundle ID matches: `com.padelcore.app`

## Verification Steps

After fixing, verify:
1. ✅ Build number in Codemagic logs matches `pubspec.yaml`
2. ✅ IPA file is created successfully
3. ✅ App Store Connect credentials are valid
4. ✅ No duplicate build numbers in App Store Connect
5. ✅ Upload completes without errors

## Current Version Info

- **Version:** 1.1.7
- **Build Number:** 37 (may need to increment to 38)
- **Bundle ID:** com.padelcore.app

## Next Steps

1. Check App Store Connect for existing build 37
2. If exists, increment to 38 in `pubspec.yaml`
3. Verify Codemagic pre-build script is working
4. Rebuild and retry upload
