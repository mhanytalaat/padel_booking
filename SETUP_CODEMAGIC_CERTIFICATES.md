# Set Up Code Signing Certificates in Codemagic

## You Already Have:
✅ API Key: `codemagic-2` (Key ID: `8HRJ2UHKD3`)
✅ Issuer ID: `c34d1e02-e3e4-4ef1-baf1-0fe68633fc22`

## Step 1: Get Certificates from Apple Developer Portal

In Codemagic's "Code signing identities" page:

1. Click **"Get certificates from Apple Developer Portal"**
2. You'll need to enter:
   - **API Key ID**: `8HRJ2UHKD3`
   - **Issuer ID**: `c34d1e02-e3e4-4ef1-baf1-0fe68633fc22`
   - **API Key file**: Download the `.p8` file from Apple Developer Portal
     - Go to: https://developer.apple.com/account/resources/authkeys/list
     - Find "codemagic-2" key
     - Click "Download" to get the `.p8` file
     - Upload this file to Codemagic

3. Codemagic will automatically:
   - Fetch existing certificates
   - Create new ones if needed
   - Set up provisioning profiles for `com.padelcore.app`

## Step 2: Create Credentials Group

1. In Codemagic, go to **Teams** → **Groups**
2. Click **"Create group"** or **"Add group"**
3. Name it: `app_store_credentials`
4. Add the certificates to this group:
   - Select the App Store Distribution certificate
   - Select the provisioning profile for `com.padelcore.app`

## Step 3: Verify Setup

Make sure:
- ✅ Certificate type: **App Store Distribution** (for TestFlight)
- ✅ Bundle ID: `com.padelcore.app`
- ✅ Group name: `app_store_credentials`
- ✅ Provisioning profile is for App Store distribution

## Alternative: Generate New Certificate

If "Get certificates" doesn't work:

1. Click **"Generate certificate"**
2. Select:
   - **Certificate type**: App Store Distribution
   - **Bundle ID**: `com.padelcore.app`
3. Codemagic will create and manage it automatically

## After Setup

Once certificates are configured:
1. The `codemagic.yaml` will automatically use them
2. Builds will be signed for TestFlight
3. No more "No valid code signing certificates" error

## Quick Steps Summary

1. **In Codemagic**: Code signing identities → "Get certificates from Apple Developer Portal"
2. **Enter API Key details**:
   - Key ID: `8HRJ2UHKD3`
   - Issuer ID: `c34d1e02-e3e4-4ef1-baf1-0fe68633fc22`
   - Upload `.p8` file (download from Apple Developer Portal)
3. **Create group**: `app_store_credentials` and add certificates
4. **Build again** - should work!

The API key authentication is the easiest way - Codemagic will handle everything automatically!
