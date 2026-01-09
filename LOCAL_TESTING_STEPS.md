# Step-by-Step: Test iOS App Locally Before Uploading

## ✅ RECOMMENDED: Test Locally FIRST, Then Upload via Codemagic

**Why?** You'll catch errors faster and save time!

---

## Step 1: Clean and Prepare

Open terminal in your project folder and run:

```bash
# Clean everything
flutter clean

# Clean iOS pods
cd ios
rm -rf Pods Podfile.lock
pod install
cd ..

# Get Flutter dependencies
flutter pub get
```

---

## Step 2: Open in Xcode

```bash
open ios/Runner.xcworkspace
```

**Important:** Use `.xcworkspace` NOT `.xcodeproj` (because of CocoaPods)

---

## Step 3: Configure Signing (First Time Only)

1. In Xcode, click **"Runner"** in the left sidebar (blue icon)
2. Select **"Signing & Capabilities"** tab
3. Check ✅ **"Automatically manage signing"**
4. Select your **Team** (your Apple ID)
5. Verify **Bundle Identifier** is `com.padelcore.app`

---

## Step 4A: Test on Simulator (Quick Test)

1. At the top of Xcode, click the device selector (shows "iPhone 15 Pro" or similar)
2. Choose any **iPhone Simulator** (e.g., iPhone 15 Pro)
3. Click the **Play button** (▶️) or press `Cmd + R`
4. Watch the **console at the bottom** for errors

**What to look for:**
- Red error messages
- Firebase initialization errors
- Any crashes

---

## Step 4B: Test on Physical Device (More Accurate)

### Connect Your iPhone:
1. Connect iPhone via USB cable
2. Unlock your iPhone
3. Trust the computer (if prompted)

### In Xcode:
1. Click device selector → Select your **iPhone**
2. First time: You may need to sign in with Apple ID
3. Click **Play button** (▶️) or `Cmd + R`
4. On iPhone: Go to **Settings → General → VPN & Device Management**
5. Trust the developer certificate
6. App should launch!

---

## Step 5: View Crash Logs in Xcode

### Method 1: Console While Running
- **View → Debug Area → Show Debug Area** (or press `Cmd + Shift + Y`)
- Watch for errors in real-time
- Copy any error messages

### Method 2: Device Logs (After Crash)
1. **Window → Devices and Simulators** (or `Cmd + Shift + 2`)
2. Select your device (left sidebar)
3. Click **"View Device Logs"** button
4. Look for crash logs (red icons with your app name)
5. Double-click a crash log to see details

### Method 3: Organizer Crash Reports
1. **Window → Organizer** (or `Cmd + Option + O`)
2. Click **"Crashes"** tab
3. Select your app
4. View crash reports

---

## Step 6: Check Common Issues

### Issue 1: Firebase Not Initializing
**Look for:** `FirebaseApp.configure() was not called` or `GoogleService-Info.plist not found`

**Fix:**
- Verify `ios/Runner/GoogleService-Info.plist` exists
- Check Xcode: Right-click Runner folder → Add Files → Select GoogleService-Info.plist

### Issue 2: Code Signing Error
**Look for:** `Code signing failed` or `Provisioning profile`

**Fix:**
- Xcode → Runner → Signing & Capabilities
- Check "Automatically manage signing"
- Select your Team

### Issue 3: Missing Dependencies
**Look for:** `No such module 'Firebase'`

**Fix:**
```bash
cd ios
pod install
cd ..
```

---

## Step 7: Build Release Version (Test Like TestFlight)

```bash
flutter build ios --release
```

Then in Xcode:
1. **Product → Archive**
2. Wait for archive to complete
3. Click **"Distribute App"**
4. Choose **"Development"** or **"Ad Hoc"**
5. Install on your device

This tests the exact same build that goes to TestFlight!

---

## Step 8: If Everything Works Locally

1. **Commit your changes:**
   ```bash
   git add .
   git commit -m "Fix iOS crash issues"
   git push
   ```

2. **Build via Codemagic** (or Xcode Organizer)

3. **Upload to TestFlight**

---

## Quick Commands Reference

```bash
# Clean everything
flutter clean && cd ios && rm -rf Pods Podfile.lock && pod install && cd .. && flutter pub get

# Run on simulator
flutter run

# Build release
flutter build ios --release

# Open in Xcode
open ios/Runner.xcworkspace
```

---

## Getting Crash Logs from App Store Connect (Alternative)

If "Open in Xcode" doesn't work:

1. Go to **App Store Connect → TestFlight → Crashes**
2. Click on a crash entry
3. Look for **"Download"** or **"Export"** button
4. Or copy the crash details manually

**Note:** Crash logs from TestFlight are often incomplete. Local testing gives better error messages!

---

## What to Share If You Need Help

If the app still crashes locally, share:
1. **Error message from Xcode console**
2. **Stack trace** (the long error text)
3. **When it crashes** (immediately on launch? after login?)
4. **Device model and iOS version**

This will help identify the exact issue!
