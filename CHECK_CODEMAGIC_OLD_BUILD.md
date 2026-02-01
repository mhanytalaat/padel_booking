# Check Old Build Bundle ID in Codemagic

## How to Check Old Build Configuration in Codemagic

### Step 1: Check Build History

1. **Go to Codemagic** → Your app → **Builds**
2. **Find an old build** (the one that created "Padel Booking" app)
3. **Click on that build** to open build details
4. **Look for:**
   - Build logs
   - Build configuration
   - Bundle ID in the build output

### Step 2: Check Build Logs

In the old build logs, search for:
- `PRODUCT_BUNDLE_IDENTIFIER`
- `Bundle ID`
- `CFBundleIdentifier`
- `com.padel`

**What to look for:**
```
PRODUCT_BUNDLE_IDENTIFIER = com.padelcore.app
```
OR
```
PRODUCT_BUNDLE_IDENTIFIER = com.padelbooking.app
```
OR something else?

### Step 3: Check iOS Workflow Configuration

1. **Go to Codemagic** → Your app → **Workflows**
2. **Click on iOS workflow** (or "Default Workflow")
3. **Go to Build section**
4. **Check:**
   - Bundle ID configuration
   - Code signing settings
   - Xcode project settings

### Step 4: Check Build Artifacts

1. **In the old build**, check **Artifacts** section
2. **Download the `.ipa` file** (if available)
3. **Check the `.ipa` metadata** for Bundle ID

## What to Look For

In Codemagic build logs, search for these patterns:

```bash
# Search for Bundle ID in logs
grep -i "bundle.*id" build.log
grep -i "PRODUCT_BUNDLE_IDENTIFIER" build.log
grep -i "com.padel" build.log
```

## Expected Output

You should see something like:
```
PRODUCT_BUNDLE_IDENTIFIER = com.padelcore.app
```

OR

```
PRODUCT_BUNDLE_IDENTIFIER = com.padelbooking.app
```

## Quick Check: Compare Old vs New

**Old Build (Padel Booking):**
- Bundle ID: `???` (check in Codemagic)

**New Build (PadelCore Hub):**
- Bundle ID: `com.padelcore.app` (current code)

**If they're different → That's why it shows "Install" instead of "Update"!**

## Next Steps

Once you find the old Bundle ID in Codemagic:

1. **Tell me what Bundle ID the old build had**
2. **I'll update the code to match it**
3. **Rebuild and upload**
4. **It will show as "Update" ✅**

---

**Please check the old build in Codemagic and tell me what Bundle ID it shows!**
