# Sub-Admin Location Filtering - Summary

## What Changed

Updated the Cloud Function to support **location-based notification filtering** for sub-admins.

## How It Works Now

### Admin vs Sub-Admin

| Role | Receives Notifications |
|------|----------------------|
| **Admin** | ALL notifications from ALL locations |
| **Sub-Admin** | ONLY notifications from their assigned locations |
| **User** | Only their own notifications |

## Example Scenario

**Admin user:**
- Role: `admin`
- Gets: All booking notifications from all courts

**Sub-Admin user (Court 1 & 2):**
- Role: `sub-admin`
- Assigned Locations: `["Court 1", "Court 2"]`
- Gets: Only booking notifications for Court 1 and Court 2
- Does NOT get: Notifications for Court 3, Court 4, etc.

**Sub-Admin user (Training Center):**
- Role: `sub-admin`
- Assigned Locations: `["Training Center"]`
- Gets: Only booking notifications for Training Center
- Does NOT get: Court bookings

## Setting Up a Sub-Admin

### Step 1: Open Firestore
https://console.firebase.google.com/project/padelcore-app/firestore/data/users

### Step 2: Select User

### Step 3: Add Fields
1. **role**: `"sub-admin"` (string)
2. **assignedLocations**: `["Court 1", "Court 2"]` (array)

### Step 4: Make Sure They Login
Sub-admin must login to app and allow notifications to get FCM token.

## Venue Names Must Match!

**IMPORTANT:** The venue names in `assignedLocations` must **EXACTLY** match the venue names used in bookings.

If your app uses:
- `"Court 1"` → Use `"Court 1"` in assignedLocations
- `"court 1"` → Won't match! (case-sensitive)
- `"Court One"` → Won't match!

## Current Notification Behavior

### Booking Notifications ✅
- Include `venue` field
- Filtered by location for sub-admins
- Admins get all

### Tournament Notifications ⚠️
- No `venue` field currently
- Only sent to admins (not sub-admins)
- To fix: Add location parameter to tournament method

## Testing

### Test 1: Admin Gets Everything
1. Set user role to `"admin"`
2. Create booking at any venue
3. Admin receives notification ✅

### Test 2: Sub-Admin Gets Assigned Locations Only
1. Set user role to `"sub-admin"`
2. Set `assignedLocations: ["Court 1"]`
3. Create booking at Court 1 → Sub-admin receives ✅
4. Create booking at Court 2 → Sub-admin does NOT receive ❌
5. Admin receives both ✅

## Deploy

```powershell
cd functions
firebase deploy --only functions:onNotificationCreated
```

---

**Status: Ready to Deploy!**
