# How to Set Up Apple Developer Credentials in Codemagic

## The Error
```
No valid code signing certificates were found
```

This means Codemagic needs your Apple Developer certificates to sign the app for TestFlight.

## Solution: Set Up Credentials in Codemagic

### Step 1: Go to Codemagic Settings

1. Go to **Codemagic** → **Teams** (or your account)
2. Click **"Code signing identities"** or **"Apple Developer"**
3. Click **"Add"** or **"Connect Apple Developer Account"**

### Step 2: Connect Apple Developer Account

**Option A: Automatic (Recommended)**
1. Click **"Connect Apple Developer Account"**
2. Sign in with your Apple ID
3. Codemagic will automatically fetch certificates and provisioning profiles

**Option B: Manual Upload**
1. Download certificates from Apple Developer Portal
2. Upload to Codemagic:
   - **Certificate**: `.p12` file
   - **Certificate password**: The password you set
   - **Provisioning profile**: `.mobileprovision` file

### Step 3: Create Credentials Group

1. In Codemagic, go to **Teams** → **Groups**
2. Create a new group called: `app_store_credentials`
3. Add your Apple certificates to this group:
   - **Certificate type**: App Store Distribution
   - **Bundle ID**: `com.padelcore.app`
   - **Provisioning profile**: App Store distribution profile

### Step 4: Link Group to Workflow

The `codemagic.yaml` already references:
```yaml
groups:
  - app_store_credentials
```

Make sure this group exists in Codemagic and contains your certificates.

## What You Need

1. **Apple Developer Account** (paid $99/year)
2. **App Store Distribution Certificate**
3. **Provisioning Profile** for `com.padelcore.app`
4. **Bundle ID** registered: `com.padelcore.app`

## Quick Setup Steps

1. **In Codemagic**:
   - Teams → Code signing → Add Apple Developer Account
   - Sign in with Apple ID
   - Select your team
   - Codemagic will auto-generate certificates

2. **Create Group**:
   - Teams → Groups → Create `app_store_credentials`
   - Add the certificates to this group

3. **Verify**:
   - The group name matches: `app_store_credentials`
   - Bundle ID is: `com.padelcore.app`
   - Certificate type is: **App Store Distribution** (not Development)

## Alternative: Use Codemagic's Automatic Signing

If you have an Apple Developer account connected, Codemagic can automatically manage certificates. Just make sure:
- Your Apple ID is connected in Codemagic
- Your team is selected
- Bundle ID `com.padelcore.app` is registered

## After Setting Up

Once credentials are configured:
1. Build will automatically use them
2. App will be signed for App Store/TestFlight
3. No more "No valid code signing certificates" error

## Need Help?

If you don't have an Apple Developer account:
- You need to enroll in Apple Developer Program ($99/year)
- Or use Codemagic's free tier for development builds only (limited)
