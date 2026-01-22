# Court Booking Integration API Guide

This guide explains how to integrate your Padel Booking system with external applications to sync court bookings for specific locations.

## Overview

The integration uses **Firebase Cloud Functions** to provide:
- **REST API endpoints** for reading and creating bookings
- **Webhooks** for real-time notifications when bookings change
- **Location-based filtering** to sync only specific locations

## Setup Instructions

### 1. Install Firebase Functions

```bash
# Install Firebase CLI if not already installed
npm install -g firebase-tools

# Login to Firebase
firebase login

# Initialize Functions (if not already done)
cd functions
npm install
```

### 2. Configure Sync Locations

Set which locations should be synced with your external app:

```bash
# Set location IDs to sync (comma-separated)
firebase functions:config:set sync.location_ids="location_id_1,location_id_2"

# Set your webhook URL (where to send notifications)
firebase functions:config:set webhook.url="https://your-external-app.com/webhook"

# Set API key for authentication
firebase functions:config:set api.key="your-secret-api-key-here"
```

### 3. Deploy Functions

```bash
firebase deploy --only functions
```

## API Endpoints

All endpoints require an `X-API-Key` header with your configured API key.

### Base URL
```
https://us-central1-padelcore-app.cloudfunctions.net
```

### 1. Get Court Bookings

**GET** `/getCourtBookings`

Get all bookings for a location (optionally filtered by date).

**Query Parameters:**
- `locationId` (required): The location ID to fetch bookings for
- `date` (optional): Filter by date (format: `YYYY-MM-DD`)

**Example Request:**
```bash
curl -X GET \
  "https://us-central1-padelcore-app.cloudfunctions.net/getCourtBookings?locationId=xxx&date=2024-01-22" \
  -H "X-API-Key: your-secret-api-key-here"
```

**Example Response:**
```json
{
  "success": true,
  "count": 2,
  "bookings": [
    {
      "id": "booking_id_1",
      "userId": "user_id_1",
      "locationId": "location_id_1",
      "locationName": "Club 13",
      "locationAddress": "Sheikh Zayed",
      "date": "2024-01-22",
      "courts": {
        "Court 1": ["9:00 AM", "9:30 AM", "10:00 AM"],
        "Court 2": ["2:00 PM", "2:30 PM"]
      },
      "totalCost": 400,
      "pricePer30Min": 200,
      "status": "confirmed",
      "selectedDate": "2024-01-22T00:00:00.000Z",
      "createdAt": "2024-01-21T10:30:00.000Z",
      "timeRange": "From 9:00 AM to 10:00 AM : 1 hour",
      "duration": 1
    }
  ]
}
```

### 2. Get Availability

**GET** `/getAvailability`

Get booked time slots for a location and date.

**Query Parameters:**
- `locationId` (required): The location ID
- `date` (required): Date to check (format: `YYYY-MM-DD`)

**Example Request:**
```bash
curl -X GET \
  "https://us-central1-padelcore-app.cloudfunctions.net/getAvailability?locationId=xxx&date=2024-01-22" \
  -H "X-API-Key: your-secret-api-key-here"
```

**Example Response:**
```json
{
  "success": true,
  "locationId": "location_id_1",
  "date": "2024-01-22",
  "locationName": "Club 13",
  "totalCourts": 5,
  "bookedSlots": {
    "Court 1": ["9:00 AM", "9:30 AM", "10:00 AM"],
    "Court 2": ["2:00 PM", "2:30 PM"],
    "Court 3": [],
    "Court 4": [],
    "Court 5": []
  }
}
```

### 3. Create Court Booking

**POST** `/createCourtBooking`

Create a new court booking from your external system.

**Request Body:**
```json
{
  "locationId": "location_id_1",
  "userId": "user_id_from_your_system",
  "date": "2024-01-22",
  "courts": {
    "Court 1": ["9:00 AM", "9:30 AM", "10:00 AM"]
  },
  "totalCost": 600,
  "pricePer30Min": 200
}
```

**Example Request:**
```bash
curl -X POST \
  "https://us-central1-padelcore-app.cloudfunctions.net/createCourtBooking" \
  -H "X-API-Key: your-secret-api-key-here" \
  -H "Content-Type: application/json" \
  -d '{
    "locationId": "xxx",
    "userId": "user_123",
    "date": "2024-01-22",
    "courts": {
      "Court 1": ["9:00 AM", "9:30 AM"]
    },
    "totalCost": 400,
    "pricePer30Min": 200
  }'
```

**Example Response:**
```json
{
  "success": true,
  "bookingId": "new_booking_id",
  "message": "Booking created successfully"
}
```

### 4. Update Booking Status

**PATCH** `/updateCourtBooking/:bookingId`

Update a booking (e.g., cancel it).

**Request Body:**
```json
{
  "status": "cancelled"
}
```

**Example Request:**
```bash
curl -X PATCH \
  "https://us-central1-padelcore-app.cloudfunctions.net/updateCourtBooking/booking_id_123" \
  -H "X-API-Key: your-secret-api-key-here" \
  -H "Content-Type: application/json" \
  -d '{"status": "cancelled"}'
```

## Webhooks

Your external application will receive POST requests at your configured webhook URL when bookings change.

### Webhook Events

1. **`booking_created`** - New booking created
2. **`booking_updated`** - Booking status or details changed
3. **`booking_cancelled`** - Booking was cancelled

### Webhook Payload Format

```json
{
  "event": "booking_created",
  "timestamp": "2024-01-22T10:30:00.000Z",
  "data": {
    "bookingId": "booking_id_1",
    "userId": "user_id_1",
    "locationId": "location_id_1",
    "locationName": "Club 13",
    "date": "2024-01-22",
    "courts": {
      "Court 1": ["9:00 AM", "9:30 AM"]
    },
    "status": "confirmed",
    "totalCost": 400,
    "selectedDate": "2024-01-22T00:00:00.000Z",
    "createdAt": "2024-01-21T10:30:00.000Z"
  }
}
```

### Webhook Endpoint Requirements

Your webhook endpoint should:
- Accept POST requests
- Return HTTP 200 status on success
- Handle timeouts gracefully (webhooks have 5-second timeout)
- Be idempotent (handle duplicate events)

## Location Filtering

Only bookings for locations in your `sync.location_ids` configuration will be:
- Returned by API endpoints
- Sent via webhooks
- Accessible through the API

To add/remove locations:
```bash
# Update sync locations
firebase functions:config:set sync.location_ids="location_1,location_2,location_3"

# Redeploy functions
firebase deploy --only functions
```

## Authentication

All API endpoints require an `X-API-Key` header:

```
X-API-Key: your-secret-api-key-here
```

Set your API key:
```bash
firebase functions:config:set api.key="your-secret-key"
firebase deploy --only functions
```

## Error Responses

```json
{
  "error": "Error message",
  "message": "Detailed error description"
}
```

Common status codes:
- `200` - Success
- `201` - Created
- `400` - Bad Request (missing parameters)
- `401` - Unauthorized (invalid API key)
- `403` - Forbidden (location not in sync list)
- `404` - Not Found
- `500` - Internal Server Error

## Testing Locally

```bash
# Start Firebase emulators
firebase emulators:start --only functions

# Test endpoint locally
curl -X GET \
  "http://localhost:5001/padelcore-app/us-central1/getCourtBookings?locationId=xxx" \
  -H "X-API-Key: your-secret-api-key-here"
```

## Security Best Practices

1. **Use HTTPS** - All endpoints use HTTPS by default
2. **Rotate API keys** regularly
3. **Validate webhook signatures** (add signature verification if needed)
4. **Rate limiting** - Consider adding rate limiting for production
5. **Monitor logs** - Check Firebase Functions logs for errors

## Example Integration Code

### JavaScript/Node.js

```javascript
const axios = require('axios');

const API_BASE = 'https://us-central1-padelcore-app.cloudfunctions.net';
const API_KEY = 'your-secret-api-key-here';

// Get bookings for a location
async function getBookings(locationId, date) {
  const response = await axios.get(`${API_BASE}/getCourtBookings`, {
    params: { locationId, date },
    headers: { 'X-API-Key': API_KEY }
  });
  return response.data.bookings;
}

// Create a booking
async function createBooking(bookingData) {
  const response = await axios.post(
    `${API_BASE}/createCourtBooking`,
    bookingData,
    { headers: { 'X-API-Key': API_KEY } }
  );
  return response.data;
}
```

### Python

```python
import requests

API_BASE = 'https://us-central1-padelcore-app.cloudfunctions.net'
API_KEY = 'your-secret-api-key-here'

def get_bookings(location_id, date=None):
    params = {'locationId': location_id}
    if date:
        params['date'] = date
    
    response = requests.get(
        f'{API_BASE}/getCourtBookings',
        params=params,
        headers={'X-API-Key': API_KEY}
    )
    return response.json()['bookings']
```

## Support

For issues or questions, check:
- Firebase Functions logs: `firebase functions:log`
- Firebase Console → Functions → Logs
