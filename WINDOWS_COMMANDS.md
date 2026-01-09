# Windows PowerShell Commands for iOS Testing

## Quick Clean and Setup (PowerShell)

### Option 1: Use the Script (Easiest)
```powershell
.\clean_ios.ps1
```

### Option 2: Run Commands Manually

```powershell
# Clean Flutter
flutter clean

# Clean iOS Pods
cd ios
Remove-Item -Recurse -Force Pods -ErrorAction SilentlyContinue
Remove-Item -Force Podfile.lock -ErrorAction SilentlyContinue
pod install
cd ..

# Get Flutter dependencies
flutter pub get
```

## Common Commands (PowerShell Syntax)

### Run on Simulator
```powershell
flutter run
```

### Build Release
```powershell
flutter build ios --release
```

### Open in Xcode (Mac only)
```powershell
# This only works on Mac
open ios/Runner.xcworkspace
```

**Note:** If you're on Windows, you can't directly open Xcode. You'll need to:
1. Use a Mac (physical or virtual machine)
2. Or use Codemagic CI/CD to build

## Testing Options on Windows

Since you're on Windows, you have these options:

### Option 1: Use Codemagic (Recommended)
1. Push your code to Git
2. Build via Codemagic
3. Download the `.ipa` file
4. Install on iPhone via TestFlight or directly

### Option 2: Use a Mac (Physical or VM)
- Install macOS on a VM (VirtualBox/VMware)
- Or use a physical Mac
- Then follow the Mac instructions

### Option 3: Test Android First
```powershell
flutter run
# This will work on Windows for Android
```

## PowerShell vs Bash Differences

| Bash (Mac/Linux) | PowerShell (Windows) |
|------------------|----------------------|
| `&&` | `;` or separate lines |
| `rm -rf` | `Remove-Item -Recurse -Force` |
| `cd ios && pod install` | `cd ios; pod install` |

## Quick Reference

```powershell
# Clean everything
flutter clean
cd ios; Remove-Item -Recurse -Force Pods -ErrorAction SilentlyContinue; Remove-Item -Force Podfile.lock -ErrorAction SilentlyContinue; pod install; cd ..
flutter pub get

# Run app
flutter run

# Build iOS (requires Mac or Codemagic)
flutter build ios --release
```

## If You Don't Have a Mac

Since iOS development requires macOS, you have these options:

1. **Use Codemagic** (Easiest)
   - Push code to Git
   - Codemagic builds automatically
   - Download `.ipa` or upload to TestFlight

2. **Use MacStadium or similar cloud Mac service**
   - Rent a cloud Mac
   - Access via remote desktop
   - Build and test there

3. **Use a physical Mac**
   - Borrow or use a Mac
   - Follow the Mac instructions

4. **Focus on Android first**
   - Test Android version on Windows
   - Fix issues there
   - Then build iOS via Codemagic

## Next Steps

Since you're building via Codemagic:
1. Make sure your code is committed and pushed
2. Build via Codemagic
3. Check Codemagic logs for errors
4. If it builds successfully but crashes on device, check the crash logs in App Store Connect

The crash logs in App Store Connect should show the error even if you can't download them directly.
