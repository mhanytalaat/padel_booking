const functions = require('firebase-functions');
const admin = require('firebase-admin');
const cors = require('cors')({ origin: true });
const axios = require('axios');

admin.initializeApp();

// Configuration: List of location IDs to sync with external system
// Add your location IDs here that should be synced
const SYNC_LOCATION_IDS = functions.config().sync?.location_ids?.split(',') || [];
const WEBHOOK_URL = functions.config().webhook?.url || ''; // Your external app's webhook endpoint

/**
 * Helper function to send webhook notification
 */
async function sendWebhook(event, data) {
  if (!WEBHOOK_URL) {
    console.log('Webhook URL not configured, skipping webhook');
    return;
  }

  try {
    await axios.post(WEBHOOK_URL, {
      event: event, // 'booking_created', 'booking_updated', 'booking_cancelled'
      timestamp: new Date().toISOString(),
      data: data,
    }, {
      timeout: 5000,
      headers: {
        'Content-Type': 'application/json',
      },
    });
    console.log(`Webhook sent successfully for event: ${event}`);
  } catch (error) {
    console.error(`Webhook failed for event ${event}:`, error.message);
    // Don't throw - webhook failures shouldn't break the booking process
  }
}

/**
 * Helper function to check if location should be synced
 */
function shouldSyncLocation(locationId) {
  return SYNC_LOCATION_IDS.length === 0 || SYNC_LOCATION_IDS.includes(locationId);
}

/**
 * REST API: Get court bookings for a specific location
 * GET /api/court-bookings?locationId=xxx&date=2024-01-22
 */
exports.getCourtBookings = functions.https.onRequest(async (req, res) => {
  return cors(req, res, async () => {
    try {
      // Validate API key (optional but recommended)
      const apiKey = req.headers['x-api-key'];
      if (!apiKey || apiKey !== functions.config().api?.key) {
        return res.status(401).json({ error: 'Unauthorized: Invalid API key' });
      }

      const locationId = req.query.locationId;
      const date = req.query.date; // Format: YYYY-MM-DD

      if (!locationId) {
        return res.status(400).json({ error: 'locationId is required' });
      }

      // Check if location should be synced
      if (!shouldSyncLocation(locationId)) {
        return res.status(403).json({ error: 'Location not configured for sync' });
      }

      let query = admin.firestore()
        .collection('courtBookings')
        .where('locationId', '==', locationId)
        .where('status', 'in', ['confirmed', 'pending']);

      if (date) {
        query = query.where('date', '==', date);
      }

      const snapshot = await query.get();
      const bookings = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data(),
        // Convert Firestore Timestamps to ISO strings
        selectedDate: doc.data().selectedDate?.toDate().toISOString(),
        createdAt: doc.data().createdAt?.toDate().toISOString(),
        cancellationDeadline: doc.data().cancellationDeadline?.toDate().toISOString(),
      }));

      return res.status(200).json({
        success: true,
        count: bookings.length,
        bookings: bookings,
      });
    } catch (error) {
      console.error('Error fetching court bookings:', error);
      return res.status(500).json({ error: 'Internal server error', message: error.message });
    }
  });
});

/**
 * REST API: Get availability for a location and date
 * GET /api/availability?locationId=xxx&date=2024-01-22
 */
exports.getAvailability = functions.https.onRequest(async (req, res) => {
  return cors(req, res, async () => {
    try {
      const apiKey = req.headers['x-api-key'];
      if (!apiKey || apiKey !== functions.config().api?.key) {
        return res.status(401).json({ error: 'Unauthorized: Invalid API key' });
      }

      const locationId = req.query.locationId;
      const date = req.query.date;

      if (!locationId || !date) {
        return res.status(400).json({ error: 'locationId and date are required' });
      }

      if (!shouldSyncLocation(locationId)) {
        return res.status(403).json({ error: 'Location not configured for sync' });
      }

      // Get location data
      const locationDoc = await admin.firestore()
        .collection('courtLocations')
        .doc(locationId)
        .get();

      if (!locationDoc.exists) {
        return res.status(404).json({ error: 'Location not found' });
      }

      const locationData = locationDoc.data();
      const courts = locationData.courts || 1;

      // Get all bookings for this location and date
      const bookingsSnapshot = await admin.firestore()
        .collection('courtBookings')
        .where('locationId', '==', locationId)
        .where('date', '==', date)
        .where('status', 'in', ['confirmed', 'pending'])
        .get();

      // Build availability map: courtId -> [booked time slots]
      const bookedSlots = {};
      for (let i = 1; i <= courts; i++) {
        bookedSlots[`Court ${i}`] = [];
      }

      bookingsSnapshot.docs.forEach(doc => {
        const bookingData = doc.data();
        const courts = bookingData.courts || {};
        Object.keys(courts).forEach(courtId => {
          const slots = courts[courtId] || [];
          if (!bookedSlots[courtId]) {
            bookedSlots[courtId] = [];
          }
          bookedSlots[courtId].push(...slots);
        });
      });

      return res.status(200).json({
        success: true,
        locationId: locationId,
        date: date,
        locationName: locationData.name,
        totalCourts: courts,
        bookedSlots: bookedSlots,
      });
    } catch (error) {
      console.error('Error fetching availability:', error);
      return res.status(500).json({ error: 'Internal server error', message: error.message });
    }
  });
});

/**
 * REST API: Create a court booking (for external systems)
 * POST /api/court-bookings
 * Body: { locationId, userId, date, courts: { "Court 1": ["9:00 AM", "9:30 AM"] }, ... }
 */
exports.createCourtBooking = functions.https.onRequest(async (req, res) => {
  return cors(req, res, async () => {
    try {
      const apiKey = req.headers['x-api-key'];
      if (!apiKey || apiKey !== functions.config().api?.key) {
        return res.status(401).json({ error: 'Unauthorized: Invalid API key' });
      }

      if (req.method !== 'POST') {
        return res.status(405).json({ error: 'Method not allowed' });
      }

      const {
        locationId,
        userId,
        date,
        courts,
        totalCost,
        pricePer30Min,
      } = req.body;

      if (!locationId || !userId || !date || !courts) {
        return res.status(400).json({ error: 'Missing required fields: locationId, userId, date, courts' });
      }

      if (!shouldSyncLocation(locationId)) {
        return res.status(403).json({ error: 'Location not configured for sync' });
      }

      // Get location data
      const locationDoc = await admin.firestore()
        .collection('courtLocations')
        .doc(locationId)
        .get();

      if (!locationDoc.exists) {
        return res.status(404).json({ error: 'Location not found' });
      }

      const locationData = locationDoc.data();

      // Create booking
      const bookingData = {
        userId: userId,
        locationId: locationId,
        locationName: locationData.name,
        locationAddress: locationData.address,
        date: date,
        selectedDate: admin.firestore.Timestamp.fromDate(new Date(date)),
        courts: courts,
        totalCost: totalCost || 0,
        pricePer30Min: pricePer30Min || locationData.pricePer30Min || 200,
        status: 'confirmed',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        cancellationDeadline: admin.firestore.Timestamp.fromDate(
          new Date(new Date(date).getTime() - 5 * 60 * 60 * 1000) // 5 hours before
        ),
        syncedFrom: 'external', // Mark as synced from external system
      };

      const bookingRef = await admin.firestore()
        .collection('courtBookings')
        .add(bookingData);

      const bookingId = bookingRef.id;

      // Send webhook notification
      await sendWebhook('booking_created', {
        bookingId: bookingId,
        ...bookingData,
        selectedDate: bookingData.selectedDate.toDate().toISOString(),
        createdAt: new Date().toISOString(),
      });

      return res.status(201).json({
        success: true,
        bookingId: bookingId,
        message: 'Booking created successfully',
      });
    } catch (error) {
      console.error('Error creating booking:', error);
      return res.status(500).json({ error: 'Internal server error', message: error.message });
    }
  });
});

/**
 * Firestore Trigger: Listen for new court bookings and send webhook
 * Only triggers for configured sync locations
 */
exports.onCourtBookingCreated = functions.firestore
  .document('courtBookings/{bookingId}')
  .onCreate(async (snap, context) => {
    const bookingData = snap.data();
    const locationId = bookingData.locationId;

    // Only sync if location is in sync list
    if (!shouldSyncLocation(locationId)) {
      console.log(`Location ${locationId} not in sync list, skipping webhook`);
      return null;
    }

    // Send webhook
    await sendWebhook('booking_created', {
      bookingId: snap.id,
      ...bookingData,
      selectedDate: bookingData.selectedDate?.toDate().toISOString(),
      createdAt: bookingData.createdAt?.toDate().toISOString(),
      cancellationDeadline: bookingData.cancellationDeadline?.toDate().toISOString(),
    });

    return null;
  });

/**
 * Firestore Trigger: Listen for booking updates (cancellations, status changes)
 */
exports.onCourtBookingUpdated = functions.firestore
  .document('courtBookings/{bookingId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const locationId = after.locationId;

    if (!shouldSyncLocation(locationId)) {
      return null;
    }

    // Check if booking was cancelled
    if (before.status !== 'cancelled' && after.status === 'cancelled') {
      await sendWebhook('booking_cancelled', {
        bookingId: change.after.id,
        ...after,
        selectedDate: after.selectedDate?.toDate().toISOString(),
        createdAt: after.createdAt?.toDate().toISOString(),
      });
    } else if (before.status !== after.status) {
      // Status changed
      await sendWebhook('booking_updated', {
        bookingId: change.after.id,
        oldStatus: before.status,
        newStatus: after.status,
        ...after,
        selectedDate: after.selectedDate?.toDate().toISOString(),
        createdAt: after.createdAt?.toDate().toISOString(),
      });
    }

    return null;
  });

/**
 * REST API: Update booking status
 * PATCH /api/court-bookings/:bookingId
 */
exports.updateCourtBooking = functions.https.onRequest(async (req, res) => {
  return cors(req, res, async () => {
    try {
      const apiKey = req.headers['x-api-key'];
      if (!apiKey || apiKey !== functions.config().api?.key) {
        return res.status(401).json({ error: 'Unauthorized: Invalid API key' });
      }

      if (req.method !== 'PATCH') {
        return res.status(405).json({ error: 'Method not allowed' });
      }

      const bookingId = req.path.split('/').pop();
      const updates = req.body;

      if (!bookingId) {
        return res.status(400).json({ error: 'bookingId is required' });
      }

      const bookingDoc = await admin.firestore()
        .collection('courtBookings')
        .doc(bookingId)
        .get();

      if (!bookingDoc.exists) {
        return res.status(404).json({ error: 'Booking not found' });
      }

      const bookingData = bookingDoc.data();
      if (!shouldSyncLocation(bookingData.locationId)) {
        return res.status(403).json({ error: 'Location not configured for sync' });
      }

      // Update booking
      await admin.firestore()
        .collection('courtBookings')
        .doc(bookingId)
        .update(updates);

      // Get updated booking
      const updatedDoc = await admin.firestore()
        .collection('courtBookings')
        .doc(bookingId)
        .get();

      const updatedData = updatedDoc.data();

      // Send webhook
      await sendWebhook('booking_updated', {
        bookingId: bookingId,
        ...updatedData,
        selectedDate: updatedData.selectedDate?.toDate().toISOString(),
        createdAt: updatedData.createdAt?.toDate().toISOString(),
      });

      return res.status(200).json({
        success: true,
        bookingId: bookingId,
        message: 'Booking updated successfully',
      });
    } catch (error) {
      console.error('Error updating booking:', error);
      return res.status(500).json({ error: 'Internal server error', message: error.message });
    }
  });
});
