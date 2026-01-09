# Fix Codemagic "Scheme Runner not found" Error

## The Issue
Codemagic is reporting: `Scheme "Runner" not found from repository! Please reconfigure your project.`

## Solution

The scheme file exists at: `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`

### Option 1: Check Codemagic Build Configuration

In Codemagic, make sure:
1. **Build type**: Use `flutter build ipa` (not direct Xcode build)
2. **Workspace**: Should use `Runner.xcworkspace` (not `Runner.xcodeproj`)
3. **Scheme**: Should be set to "Runner" or left empty (Flutter will auto-detect)

### Option 2: Create codemagic.yaml (Recommended)

Create a `codemagic.yaml` file in the project root:

```yaml
workflows:
  ios-workflow:
    name: iOS Workflow
    max_build_duration: 120
    instance_type: mac_mini_m1
    environment:
      groups:
        - app_store_credentials
      flutter: stable
    scripts:
      - name: Get dependencies
        script: |
          flutter pub get
      - name: Install CocoaPods dependencies
        script: |
          cd ios
          pod install
          cd ..
      - name: Build iOS
        script: |
          flutter build ipa --release --export-options-plist export_options.plist
    artifacts:
      - build/ios/ipa/*.ipa
    publishing:
      email:
        recipients:
          - your-email@example.com
        notify:
          success: true
          failure: false
```

### Option 3: Verify Scheme is Shared

The scheme should be in: `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`

If it's not there, you can:
1. Open `ios/Runner.xcworkspace` in Xcode
2. Product → Scheme → Manage Schemes
3. Check "Shared" for Runner scheme
4. Save

### Option 4: Use Flutter Build Command

Codemagic should use:
```bash
flutter build ipa --release
```

NOT:
```bash
xcodebuild -workspace Runner.xcworkspace -scheme Runner
```

## Current Status

✅ Scheme file exists: `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`
✅ Scheme is properly configured
✅ GoogleService-Info.plist is now in Xcode project

## Next Steps

1. **Check Codemagic build settings** - Make sure it's using `flutter build ipa`
2. **Or create codemagic.yaml** - Use the YAML config above
3. **Verify workspace** - Codemagic should use `.xcworkspace` not `.xcodeproj`

The scheme file is correct, so this is likely a Codemagic configuration issue.
