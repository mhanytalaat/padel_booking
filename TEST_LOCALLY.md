# How to Test iOS App Locally Before Uploading

## Option 1: Test on iOS Simulator (Easiest)

### Step 1: Open in Xcode
```bash
open ios/Runner.xcworkspace
```

### Step 2: Select Simulator
- In Xcode, click the device selector (top left)
- Choose an iPhone simulator (e.g., iPhone 15 Pro)

### Step 3: Run the App
- Click the Play button (▶️) or press `Cmd + R`
- Watch the console for errors

### Step 4: Check Console Logs
- In Xcode, open the **Debug Area** (View → Debug Area → Show Debug Area)
- Look for red error messages
- Check for Firebase initialization errors

## Option 2: Test on Physical Device (More Accurate)

### Step 1: Connect Your iPhone
- Connect iPhone via USB
- Trust the computer on your iPhone

### Step 2: Open in Xcode
```bash
open ios/Runner.xcworkspace
```

### Step 3: Select Your Device
- Click device selector → Select your iPhone
- You may need to sign in with your Apple ID

### Step 4: Configure Signing
- Select "Runner" in left sidebar
- Go to "Signing & Capabilities"
- Check "Automatically manage signing"
- Select your Team
- Verify Bundle Identifier is `com.padelcore.app`

### Step 5: Build and Run
- Click Play button (▶️) or `Cmd + R`
- First time: Trust the developer on your iPhone
  - Settings → General → VPN & Device Management → Trust Developer

### Step 6: View Crash Logs
- In Xcode: **Window → Devices and Simulators**
- Select your device → Click "View Device Logs"
- Look for crash logs with your app name

## Option 3: Build Release Version Locally

### Step 1: Clean Build
```bash
flutter clean
cd ios
rm -rf Pods Podfile.lock
pod install
cd ..
flutter pub get
```

### Step 2: Build Release
```bash
flutter build ios --release
```

### Step 3: Archive in Xcode
```bash
open ios/Runner.xcworkspace
```
- In Xcode: **Product → Archive**
- Wait for archive to complete
- Click "Distribute App"
- Choose "Development" or "Ad Hoc"
- Install on your device via Xcode

## Getting Crash Logs from Xcode

### Method 1: Device Logs
1. Connect device
2. Xcode → **Window → Devices and Simulators**
3. Select your device
4. Click **"View Device Logs"**
5. Filter by your app name
6. Look for crash logs (red icons)

### Method 2: Console Logs While Running
1. Run app from Xcode
2. Open **Debug Area** (View → Debug Area → Show Debug Area)
3. Watch for errors in real-time
4. Copy error messages

### Method 3: Organizer Crash Logs
1. Xcode → **Window → Organizer**
2. Click **"Crashes"** tab
3. Select your app
4. View crash reports

## Common Issues to Check

### 1. Firebase Initialization
Look for errors like:
- "FirebaseApp.configure() was not called"
- "GoogleService-Info.plist not found"
- "Invalid API key"

### 2. Missing Dependencies
Look for errors like:
- "No such module 'Firebase'"
- "Undefined symbol"

### 3. Code Signing
Look for errors like:
- "Code signing failed"
- "Provisioning profile not found"

## Recommended Testing Flow

1. **Test on Simulator First** (quick check)
   ```bash
   flutter run
   ```

2. **Test Release Build Locally** (catches release-specific issues)
   ```bash
   flutter build ios --release
   # Then run from Xcode
   ```

3. **Test on Physical Device** (most accurate)
   - Use Xcode to install and run
   - Check device logs

4. **Upload to TestFlight** (only after local testing passes)
   - Use Codemagic or Xcode Organizer

## Quick Test Commands

```bash
# Clean everything
flutter clean
cd ios && rm -rf Pods Podfile.lock && pod install && cd ..

# Get dependencies
flutter pub get

# Run on simulator
flutter run

# Build release
flutter build ios --release

# Open in Xcode
open ios/Runner.xcworkspace
```

## If App Crashes Immediately

1. **Check Xcode Console** - Look for the first error
2. **Check Device Logs** - Window → Devices → View Device Logs
3. **Check Firebase Config** - Verify GoogleService-Info.plist exists
4. **Check Bundle ID** - Must match Firebase project

## Next Steps After Testing Locally

Once you've tested locally and fixed any issues:
1. Commit your changes
2. Push to your repository
3. Build via Codemagic
4. Upload to TestFlight

This way you catch issues before uploading!
