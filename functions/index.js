/**
 * External API for court booking (1 location).
 * Other app: GET location/slots, POST create booking, DELETE cancel.
 * Auth: x-api-key header. Set API key in Firebase: firebase functions:config:set external.api_key="YOUR_KEY"
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const COLL = {
  courtLocations: 'courtLocations',
  courtBookings: 'courtBookings',
};

// CORS for browser / mobile
function cors(req, res) {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, x-api-key');
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return true;
  }
  return false;
}

function getApiKey() {
  try {
    return functions.config().external?.api_key || process.env.EXTERNAL_API_KEY || '';
  } catch (_) {
    return process.env.EXTERNAL_API_KEY || '';
  }
}

function checkAuth(req, res) {
  const key = (req.headers['x-api-key'] || '').trim();
  const expected = getApiKey();
  if (!expected || key !== expected) {
    res.status(401).json({ error: 'Unauthorized: invalid or missing x-api-key' });
    return false;
  }
  return true;
}

// Parse "6:00 AM" / "11:00 PM" to Date (same day, ref date for day)
function parseTime(str, refDate) {
  const m = str.trim().match(/^(\d{1,2}):(\d{2})\s*(AM|PM)$/i);
  if (!m) return null;
  let h = parseInt(m[1], 10);
  const min = parseInt(m[2], 10);
  if (m[3].toUpperCase() === 'PM' && h !== 12) h += 12;
  if (m[3].toUpperCase() === 'AM' && h === 12) h = 0;
  return new Date(refDate.getFullYear(), refDate.getMonth(), refDate.getDate(), h, min, 0);
}

function formatTime(d) {
  const h = d.getHours();
  const m = d.getMinutes();
  const am = h < 12;
  const h12 = h === 0 ? 12 : h > 12 ? h - 12 : h;
  return `${h12}:${String(m).padStart(2, '0')} ${am ? 'AM' : 'PM'}`;
}

// Generate 30-min slots between open and close (same logic as Flutter app)
function generateSlots(openTime, closeTime, midnightPlayEndTime, refDate) {
  const open = parseTime(openTime || '6:00 AM', refDate);
  const close = parseTime(closeTime || '11:00 PM', refDate);
  if (!open || !close) return [];

  const slots = [];
  const dayEnd = new Date(refDate);
  dayEnd.setDate(dayEnd.getDate() + 1);
  dayEnd.setHours(0, 0, 0, 0);

  const isMidnightClose = close.getHours() === 0 && close.getMinutes() === 0;
  const regularEnd = isMidnightClose
    ? new Date(dayEnd.getTime() - 30 * 60 * 1000)
    : close;

  let current = new Date(open.getTime());
  while (current < regularEnd || current.getTime() === regularEnd.getTime()) {
    slots.push(formatTime(current));
    current.setTime(current.getTime() + 30 * 60 * 1000);
  }

  if (isMidnightClose && midnightPlayEndTime) {
    const midnightEnd = parseTime(midnightPlayEndTime, dayEnd);
    if (midnightEnd) {
      let mid = new Date(dayEnd.getTime());
      while (mid < midnightEnd) {
        slots.push(formatTime(mid));
        mid.setTime(mid.getTime() + 30 * 60 * 1000);
      }
    }
  }
  return slots;
}

// GET /getLocation?locationId=xxx
exports.getLocation = functions.https.onRequest(async (req, res) => {
  if (cors(req, res)) return;
  if (!checkAuth(req, res)) return;

  const locationId = (req.query.locationId || '').trim();
  if (!locationId) {
    res.status(400).json({ error: 'Missing locationId' });
    return;
  }

  try {
    const doc = await admin.firestore().collection(COLL.courtLocations).doc(locationId).get();
    if (!doc.exists) {
      res.status(404).json({ error: 'Location not found' });
      return;
    }
    const data = doc.data();
    res.json({
      id: doc.id,
      name: data.name,
      address: data.address,
      courts: data.courts || [],
      openTime: data.openTime || '6:00 AM',
      closeTime: data.closeTime || '11:00 PM',
      midnightPlayEndTime: data.midnightPlayEndTime || '4:00 AM',
    });
  } catch (e) {
    res.status(500).json({ error: String(e.message) });
  }
});

// GET /getSlots?locationId=xxx&date=YYYY-MM-DD
exports.getSlots = functions.https.onRequest(async (req, res) => {
  if (cors(req, res)) return;
  if (!checkAuth(req, res)) return;

  const locationId = (req.query.locationId || '').trim();
  const dateStr = (req.query.date || '').trim();
  if (!locationId || !dateStr) {
    res.status(400).json({ error: 'Missing locationId or date (YYYY-MM-DD)' });
    return;
  }

  const [y, m, d] = dateStr.split('-').map(Number);
  if (!y || !m || !d) {
    res.status(400).json({ error: 'Invalid date; use YYYY-MM-DD' });
    return;
  }
  const refDate = new Date(y, m - 1, d);

  try {
    const locSnap = await admin.firestore().collection(COLL.courtLocations).doc(locationId).get();
    if (!locSnap.exists) {
      res.status(404).json({ error: 'Location not found' });
      return;
    }
    const loc = locSnap.data();
    const courts = loc.courts || [];
    const allSlots = generateSlots(
      loc.openTime,
      loc.closeTime,
      loc.midnightPlayEndTime,
      refDate
    );

    const bookingsSnap = await admin.firestore()
      .collection(COLL.courtBookings)
      .where('locationId', '==', locationId)
      .where('date', '==', dateStr)
      .where('status', 'in', ['confirmed', 'pending'])
      .get();

    const bookedSet = new Set();
    bookingsSnap.docs.forEach((doc) => {
      const data = doc.data();
      const courtsMap = data.courts || {};
      Object.keys(courtsMap).forEach((courtId) => {
        const arr = courtsMap[courtId];
        if (Array.isArray(arr)) {
          arr.forEach((slot) => bookedSet.add(`${courtId}|${slot}`));
        }
      });
    });

    const courtsWithSlots = courts.map((c) => {
      const courtId = c.id || c.name;
      const available = allSlots.filter((slot) => !bookedSet.has(`${courtId}|${slot}`));
      return { courtId, name: c.name || courtId, availableSlots: available };
    });

    res.json({ locationId, date: dateStr, courts: courtsWithSlots });
  } catch (e) {
    res.status(500).json({ error: String(e.message) });
  }
});

// POST /createBooking — body: locationId, date, courts, firstName, lastName, phoneNumber
exports.createBooking = functions.https.onRequest(async (req, res) => {
  if (cors(req, res)) return;
  if (!checkAuth(req, res)) return;
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const body = req.body || {};
  const locationId = (body.locationId || '').trim();
  const date = (body.date || '').trim();
  const courts = body.courts;
  const firstName = (body.firstName || '').trim() || 'Guest';
  const lastName = (body.lastName || '').trim() || 'User';
  const phoneNumber = (body.phoneNumber || '').trim();

  if (!locationId || !date || !courts || typeof courts !== 'object') {
    res.status(400).json({ error: 'Missing locationId, date, or courts (map courtId -> [slot strings])' });
    return;
  }

  const courtsNormalized = {};
  for (const [courtId, slots] of Object.entries(courts)) {
    if (Array.isArray(slots)) {
      courtsNormalized[courtId] = slots.map((s) => String(s));
    }
  }
  if (Object.keys(courtsNormalized).length === 0) {
    res.status(400).json({ error: 'courts must have at least one court with slot array' });
    return;
  }

  try {
    const locSnap = await admin.firestore().collection(COLL.courtLocations).doc(locationId).get();
    if (!locSnap.exists) {
      res.status(404).json({ error: 'Location not found' });
      return;
    }
    const loc = locSnap.data();

    const slotStart = new Date(date + 'T00:00:00');
    const cancellationDeadline = new Date(slotStart.getTime() - 5 * 60 * 60 * 1000);
    if (cancellationDeadline < new Date()) {
      res.status(400).json({ error: 'Booking date too soon or in the past' });
      return;
    }

    const bookingData = {
      userId: body.userId || 'external-api',
      locationId,
      locationName: loc.name || '',
      locationAddress: loc.address || '',
      date,
      selectedDate: admin.firestore.Timestamp.fromDate(new Date(date)),
      bookingStartDate: admin.firestore.Timestamp.fromDate(new Date(date)),
      courts: courtsNormalized,
      totalCost: 0,
      pricePer30Min: 0,
      duration: 0,
      timeRange: '',
      status: 'confirmed',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      cancellationDeadline: admin.firestore.Timestamp.fromDate(cancellationDeadline),
      bookedBy: 'external-api',
      isSubAdminBooking: false,
      externalAppBooking: true,
      guestName: `${firstName} ${lastName}`.trim(),
      guestPhone: phoneNumber,
    };

    const ref = await admin.firestore().collection(COLL.courtBookings).add(bookingData);
    res.status(201).json({ bookingId: ref.id, message: 'Booking created' });
  } catch (e) {
    res.status(500).json({ error: String(e.message) });
  }
});

// DELETE /cancelBooking?bookingId=xxx
exports.cancelBooking = functions.https.onRequest(async (req, res) => {
  if (cors(req, res)) return;
  if (!checkAuth(req, res)) return;

  const bookingId = (req.query.bookingId || '').trim();
  if (!bookingId) {
    res.status(400).json({ error: 'Missing bookingId' });
    return;
  }

  try {
    const doc = await admin.firestore().collection(COLL.courtBookings).doc(bookingId).get();
    if (!doc.exists) {
      res.status(404).json({ error: 'Booking not found' });
      return;
    }
    await admin.firestore().collection(COLL.courtBookings).doc(bookingId).delete();
    res.json({ message: 'Booking cancelled' });
  } catch (e) {
    res.status(500).json({ error: String(e.message) });
  }
});
