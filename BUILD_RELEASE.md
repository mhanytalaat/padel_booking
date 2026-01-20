# How to Build Android Release AAB

## Problem
Codemagic or local builds are creating **debug** AAB files, but Google Play Console requires **release** AAB files.

## Solution: Use --release Flag

### For Local Build (Terminal):
```powershell
flutter build appbundle --release
```

This will create: `build/app/outputs/bundle/release/app-release.aab`

### For Codemagic:
You need to configure Codemagic to build in release mode. Since you don't have access to the web UI, you can:

1. **Create a codemagic.yaml file** (if using YAML configuration)
2. **Or** use the command in Codemagic's build script

## Quick Fix: Build Release Locally

Since you're building via terminal, run:

```powershell
flutter clean
flutter pub get
flutter build appbundle --release
```

The release AAB will be at:
```
build/app/outputs/bundle/release/app-release.aab
```

## Codemagic Configuration

If you need to configure Codemagic to build release, you can create a `codemagic.yaml` file:

```yaml
workflows:
  android-workflow:
    name: Android Workflow
    max_build_duration: 120
    instance_type: mac_mini_m1
    environment:
      groups:
        - keystore_credentials
      flutter: stable
    scripts:
      - name: Get dependencies
        script: |
          flutter pub get
      - name: Build Android App Bundle
        script: |
          flutter build appbundle --release
    artifacts:
      - build/app/outputs/bundle/release/**/*.aab
    publishing:
      email:
        recipients:
          - your-email@example.com
```

## Verify Build Type

After building, check the file:
- **Debug**: `app-debug.aab` ❌ (won't work for Google Play)
- **Release**: `app-release.aab` ✅ (correct for Google Play)

## Upload to Google Play

Once you have `app-release.aab`:
1. Go to Google Play Console
2. Internal Testing or Closed Testing
3. Create new release
4. Upload `app-release.aab`
5. Add release notes
6. Review and release
