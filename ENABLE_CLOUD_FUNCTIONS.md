# Enabling Cloud Functions in Firebase

## Step 1: Enable Cloud Functions API

You need to enable Cloud Functions API in your Google Cloud Console. Here's how:

### Option A: Via Firebase Console (Easiest)

1. **Go to [Firebase Console](https://console.firebase.google.com/)**
2. **Select your project**: `padelcore-app`
3. **Click on "Functions"** in the left sidebar
4. **If you see "Set up Functions" dialog**:
   - Click **"Continue"** button
   - This will automatically enable the Cloud Functions API
   - Wait for the setup to complete (may take 1-2 minutes)

### Option B: Via Google Cloud Console

1. **Go to [Google Cloud Console](https://console.cloud.google.com/)**
2. **Select your project**: `padelcore-app` (top dropdown)
3. **Navigate to**: APIs & Services → Library
4. **Search for**: "Cloud Functions API"
5. **Click on "Cloud Functions API"**
6. **Click "Enable"** button
7. **Wait for activation** (may take 1-2 minutes)

### Option C: Via Command Line (After Login)

After you login to Firebase CLI, you can enable it via:

```bash
gcloud services enable cloudfunctions.googleapis.com --project=padelcore-app
```

(Requires Google Cloud SDK installed)

---

## Step 2: Enable Cloud Build API (Required)

Cloud Functions also requires Cloud Build API:

1. **Go to [Google Cloud Console](https://console.cloud.google.com/)**
2. **Select project**: `padelcore-app`
3. **Navigate to**: APIs & Services → Library
4. **Search for**: "Cloud Build API"
5. **Click "Enable"**

---

## Step 3: Enable Cloud Logging API (Recommended)

For viewing function logs:

1. **Go to [Google Cloud Console](https://console.cloud.google.com/)**
2. **Select project**: `padelcore-app`
3. **Navigate to**: APIs & Services → Library
4. **Search for**: "Cloud Logging API"
5. **Click "Enable"**

---

## Step 4: Verify Setup

After enabling APIs, go back to Firebase Console:

1. **Firebase Console** → **Functions**
2. **You should see**: "Get started" or an empty functions list (not the setup dialog)
3. **This means**: Functions are enabled! ✅

---

## Step 5: Login to Firebase CLI

Open a terminal and run:

```bash
firebase login
```

This will open a browser window for authentication. Follow the prompts.

---

## Step 6: Initialize Functions (If Needed)

If functions aren't initialized yet:

```bash
cd functions
npm install
```

---

## Step 7: Deploy Your Function

Once everything is enabled:

```bash
cd functions
firebase deploy --only functions:onNotificationCreated
```

---

## Troubleshooting

### "API not enabled" error
- Make sure you enabled **Cloud Functions API** and **Cloud Build API**
- Wait 2-3 minutes after enabling for propagation

### "Permission denied" error
- Make sure you're logged in: `firebase login`
- Verify you have Owner/Editor role on the project

### "Billing required" error
- Cloud Functions requires a billing account (Blaze plan)
- Go to Firebase Console → Project Settings → Usage and billing
- Upgrade to Blaze plan (pay-as-you-go, has free tier)

---

## Quick Checklist

- [ ] Cloud Functions API enabled
- [ ] Cloud Build API enabled  
- [ ] Cloud Logging API enabled (optional but recommended)
- [ ] Firebase CLI logged in (`firebase login`)
- [ ] Functions dependencies installed (`cd functions && npm install`)
- [ ] Ready to deploy!
