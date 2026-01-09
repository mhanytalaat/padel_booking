# How to View Crash Details in App Store Connect

## Step 1: Click on the Crash Entry

In the crash table, you should see rows with:
- Date
- Build (e.g., "1.0.7 (12)")
- Device Model
- Version
- Comment

**Click directly on the row** (the entire row, not just one cell) to open the crash details.

## Step 2: Look for These Sections

After clicking, you should see:

### Basic Info (What you already see)
- Tester name
- Device info
- App version

### Crash Details (What we need)
Scroll down to find:
- **Exception Type**
- **Exception Codes**
- **Crashed Thread**
- **Application Specific Information**
- **Thread 0 Crashed** (stack trace)

## Step 3: If You Don't See Details

### Option A: Try Different View
- Look for tabs or sections like "Details", "Stack Trace", "Threads"
- Some crash reports have collapsible sections - try expanding them

### Option B: Check if Crash is Processed
- Sometimes crashes need time to process
- Try refreshing the page
- Check back in a few minutes

### Option C: Use Xcode (If Available)
1. Open Xcode
2. **Window → Organizer** (Cmd + Option + O)
3. Click **"Crashes"** tab
4. Select your app
5. View crash reports there

## Step 4: Alternative - Check TestFlight App

If you have TestFlight installed on your device:
1. Open TestFlight app
2. Go to your app
3. Sometimes crash details are shown there

## What to Look For

Even if you can't see full details, look for:
- Any error messages visible
- The "Comment" field (tester might have added info)
- Build number to confirm it's the right crash

## If Still Can't See Details

The crash might still be processing. Try:
1. Refresh the page
2. Wait 10-15 minutes
3. Check again
4. Or share a screenshot of what you see when you click on the crash
