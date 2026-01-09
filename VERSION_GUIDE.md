# Version Number Guide

## Version Format

Flutter uses: `versionName+buildNumber`
- Example: `1.0.7+12`
  - `1.0.7` = Version Name (user-facing)
  - `12` = Build Number (internal, must always increase)

## Current Version

- **Version Name:** `1.0.7`
- **Build Number:** `12`
- **Full Version:** `1.0.7+12`

## When to Update

### Increment Build Number (+12 → +13)
- Every time you upload a new build
- Even for small fixes
- **Required** - App stores won't accept same build number

### Increment Version Name (1.0.7 → 1.0.8)
- New features
- Significant changes
- Major bug fixes

### Increment Major Version (1.0.7 → 2.0.0)
- Breaking changes
- Major redesign
- Complete rewrite

## Files to Update

1. **pubspec.yaml** - Main version (used by Flutter)
   ```yaml
   version: 1.0.7+12
   ```

2. **android/app/build.gradle.kts** - Android version
   ```kotlin
   versionCode = 12
   versionName = "1.0.7"
   ```

3. **iOS** - Automatically uses pubspec.yaml version via:
   - `CFBundleShortVersionString` = $(FLUTTER_BUILD_NAME) = 1.0.7
   - `CFBundleVersion` = $(FLUTTER_BUILD_NUMBER) = 12

## Quick Update Commands

### For a new build (increment build number):
```powershell
# Update pubspec.yaml: version: 1.0.7+13
# Update build.gradle.kts: versionCode = 13
```

### For a new feature (increment version):
```powershell
# Update pubspec.yaml: version: 1.0.8+13
# Update build.gradle.kts: versionCode = 13, versionName = "1.0.8"
```

## Version History

- `1.0.7+12` - Current (iOS crash fixes)
- `1.0.6+11` - Previous Android
- `1.0.0+2` - Previous iOS (TestFlight)
