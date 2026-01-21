# Fix Firebase Storage CORS Issue for Web

## Problem
Images uploaded to Firebase Storage are not loading on web, showing `statusCode: 0` errors. This is a CORS (Cross-Origin Resource Sharing) issue.

## Solution

### Step 1: Deploy Storage Rules
Make sure your `storage.rules` file is deployed:

```bash
firebase deploy --only storage
```

Or manually in Firebase Console:
1. Go to Firebase Console → Storage → Rules
2. Copy content from `storage.rules`
3. Paste and click "Publish"

### Step 2: Configure CORS in Firebase Storage

Firebase Storage requires CORS to be configured separately from security rules. You need to configure CORS using `gsutil` (Google Cloud Storage utility).

#### Option A: Using gsutil (Recommended)

1. **Install Google Cloud SDK** (if not already installed):
   - Download from: https://cloud.google.com/sdk/docs/install
   - Or use: `gcloud components install gsutil`

2. **Create a CORS configuration file** (`cors.json`):
   ```json
   [
     {
       "origin": ["*"],
       "method": ["GET", "HEAD"],
       "responseHeader": ["Content-Type", "Access-Control-Allow-Origin"],
       "maxAgeSeconds": 3600
     }
   ]
   ```

3. **Apply CORS configuration**:
   ```bash
   gsutil cors set cors.json gs://padelcore-app.firebasestorage.app
   ```

#### Option B: Using Firebase Console (if available)

1. Go to Firebase Console → Storage → Settings
2. Look for "CORS configuration" section
3. Add the CORS configuration:
   ```json
   [
     {
       "origin": ["*"],
       "method": ["GET", "HEAD"],
       "responseHeader": ["Content-Type", "Access-Control-Allow-Origin"],
       "maxAgeSeconds": 3600
     }
   ]
   ```

### Step 3: Verify

After configuring CORS, test the image loading again. The images should now load properly on web.

## Alternative: Use Firebase Storage with Authentication

If CORS configuration is not possible, you can:
1. Keep storage rules requiring authentication
2. Fetch images using authenticated requests
3. Convert to data URLs for display

This requires more complex code but works without CORS configuration.
