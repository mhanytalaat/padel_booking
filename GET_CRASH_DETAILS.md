# How to Get Crash Details from App Store Connect

## Step 1: View Full Crash Report

1. Go to **App Store Connect** → **TestFlight** → **Crashes**
2. Click on the crash entry (the one from Jan 9, 2026 at 8:00 PM)
3. You should see more details below the basic info

## Step 2: Look for These Sections

The crash report should have:

### Exception Type
- Look for: `NSException`, `SIGABRT`, `SIGSEGV`, `EXC_BAD_ACCESS`, etc.

### Exception Message
- The actual error message
- Look for: `Firebase`, `GoogleService`, `Bundle`, etc.

### Stack Trace
- The long list of function calls
- The **first few lines** are most important
- Look for your app's code or Firebase code

### Thread 0 (Main Thread)
- Usually where the crash happens
- Look for the top of the stack trace

## Step 3: Common Crash Patterns to Look For

### Firebase Initialization
```
FirebaseApp.configure() was not called
GoogleService-Info.plist not found
Invalid API key
```

### Missing Files
```
Could not find GoogleService-Info.plist
Bundle identifier mismatch
```

### Memory Issues
```
EXC_BAD_ACCESS
SIGSEGV
```

## Step 4: Share the Details

Please share:
1. **Exception Type** (e.g., NSException, SIGABRT)
2. **Exception Message** (the error text)
3. **First 10-15 lines of the stack trace** (from Thread 0)
4. **When it crashes** (immediately on launch? after login?)

## Alternative: Download Crash Log

If available:
1. In the crash report, look for a **"Download"** or **"Export"** button
2. Download the `.crash` file
3. Open it in a text editor
4. Look for the exception and stack trace

## What to Look For

The crash log will show something like:

```
Exception Type:  EXC_CRASH (SIGABRT)
Exception Codes: 0x0000000000000000, 0x0000000000000000
Exception Note:  EXC_CORPSE_NOTIFY
Triggered by Thread:  0

Application Specific Information:
*** Terminating app due to uncaught exception 'NSInvalidArgumentException', 
reason: '*** -[__NSArrayM insertObject:atIndex:]: object cannot be nil'
```

The **reason** line is the key - it tells you exactly what went wrong!
