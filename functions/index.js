/**
 * External API for court booking (1 location).
 * Other app: GET location/slots, POST create booking, DELETE cancel.
 * Auth: x-api-key header. Set API key in Firebase: firebase functions:config:set external.api_key="YOUR_KEY"
 */

const functions = require('firebase-functions');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

admin.initializeApp();

const COLL = {
  courtLocations: 'courtLocations',
  courtBookings: 'courtBookings',
  cancellationLogs: 'courtBookingCancellationLogs',
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

// DELETE /cancelBooking?bookingId=xxx — marks cancelledBy then delete (trigger logs it)
exports.cancelBooking = functions.https.onRequest(async (req, res) => {
  if (cors(req, res)) return;
  if (!checkAuth(req, res)) return;

  const bookingId = (req.query.bookingId || '').trim();
  if (!bookingId) {
    res.status(400).json({ error: 'Missing bookingId' });
    return;
  }

  try {
    const docRef = admin.firestore().collection(COLL.courtBookings).doc(bookingId);
    const doc = await docRef.get();
    if (!doc.exists) {
      res.status(404).json({ error: 'Booking not found' });
      return;
    }
    await docRef.update({
      cancelledBy: 'external_api',
      cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await docRef.delete();
    res.json({ message: 'Booking cancelled' });
  } catch (e) {
    res.status(500).json({ error: String(e.message) });
  }
});

// Scheduled: send 5-hour reminders for upcoming bundle sessions (runs every hour)
exports.sendBundleSessionReminders = onSchedule('every 60 minutes', async (_event) => {
  const now = new Date();
  const windowStart = new Date(now.getTime() + 4.5 * 60 * 60 * 1000);
  const windowEnd   = new Date(now.getTime() + 5.5 * 60 * 60 * 1000);

  const snap = await admin.firestore()
    .collection('bundleSessions')
    .where('attendanceStatus', '==', 'scheduled')
    .get();

  const toRemind = [];
  for (const doc of snap.docs) {
    const data = doc.data();
    if (data.bookingStatus !== 'approved') continue;
    if (data.reminderSent5h === true) continue;
    const sessionTime = parseTime(data.time, (() => {
      const [y, m, d] = (data.date || '').split('-').map(Number);
      return new Date(y, m - 1, d);
    })());
    if (!sessionTime) continue;
    if (sessionTime >= windowStart && sessionTime <= windowEnd) {
      toRemind.push({ id: doc.id, ...data });
    }
  }

  if (toRemind.length === 0) {
    console.log('No bundle sessions require a 5-hour reminder.');
    return;
  }

  // Batch-fetch parent bundles for userName
  const bundleIds = [...new Set(toRemind.map((s) => s.bundleId))];
  const bundleMap = {};
  await Promise.all(bundleIds.map(async (bundleId) => {
    const bdoc = await admin.firestore().collection('bundles').doc(bundleId).get();
    if (bdoc.exists) bundleMap[bundleId] = bdoc.data();
  }));

  // Batch-fetch user FCM tokens
  const userIds = [...new Set(toRemind.map((s) => s.userId))];
  const tokenMap = {};
  await Promise.all(userIds.map(async (uid) => {
    const udoc = await admin.firestore().collection('users').doc(uid).get();
    if (udoc.exists) tokenMap[uid] = udoc.data().fcmToken || null;
  }));

  const db = admin.firestore();
  const batch = db.batch();
  const fcmPromises = [];

  for (const session of toRemind) {
    const bundle = bundleMap[session.bundleId];
    if (!bundle || bundle.status !== 'active') continue;

    const userName = bundle.userName || 'Player';
    const { userId, venue, time, date, coach } = session;
    const coachNote = coach ? ` (Coach: ${coach})` : '';

    const userTitle = '⏰ Training Session Reminder';
    const userBody  = `Your training session at ${venue} is in 5 hours! (${time} on ${date})`;
    const adminTitle = '⏰ Training Session in 5 Hours';
    const adminBody  = `${userName}'s training at ${venue} on ${date} at ${time}${coachNote}`;

    batch.set(db.collection('notifications').doc(), {
      type: 'bundle_session_reminder',
      userId, bundleId: session.bundleId, sessionId: session.id,
      venue, time, date, coach: coach || '',
      title: userTitle, body: userBody, message: userBody,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      read: false,
    });

    batch.set(db.collection('notifications').doc(), {
      type: 'bundle_session_reminder',
      userId, userName, bundleId: session.bundleId, sessionId: session.id,
      venue, time, date, coach: coach || '',
      isAdminNotification: true,
      title: adminTitle, body: adminBody, message: adminBody,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      read: false,
    });

    batch.update(db.collection('bundleSessions').doc(session.id), { reminderSent5h: true });

    const token = tokenMap[userId];
    if (token) {
      fcmPromises.push(
        admin.messaging().send({
          token,
          notification: { title: userTitle, body: userBody },
          data: { type: 'bundle_session_reminder', bundleId: session.bundleId, sessionId: session.id },
        }).catch((err) => console.warn(`FCM user ${userId}:`, err.message))
      );
    }

    fcmPromises.push(
      admin.messaging().send({
        topic: 'training_session_reminders',
        notification: { title: adminTitle, body: adminBody },
        data: { type: 'bundle_session_reminder', bundleId: session.bundleId, sessionId: session.id },
      }).catch((err) => console.warn('FCM admin topic:', err.message))
    );
  }

  await batch.commit();
  await Promise.all(fcmPromises);
  console.log(`Sent 5-hour reminders for ${toRemind.length} bundle session(s).`);
});

// When any court booking is deleted: log cancellation and notify (app or external API)
exports.onCourtBookingDeleted = functions.firestore
  .document(`${COLL.courtBookings}/{bookingId}`)
  .onDelete(async (snap, context) => {
    const data = snap.data();
    const bookingId = context.params.bookingId;
    const cancelledBy = data?.cancelledBy || 'unknown';
    const cancelledAt = data?.cancelledAt || admin.firestore.Timestamp.now();

    const logEntry = {
      bookingId,
      locationId: data?.locationId ?? '',
      locationName: data?.locationName ?? '',
      date: data?.date ?? '',
      courts: data?.courts ?? {},
      userId: data?.userId ?? '',
      bookedBy: data?.bookedBy ?? '',
      cancelledBy,
      cancelledAt,
      source: cancelledBy === 'external_api' ? 'external_api' : 'app',
      guestName: data?.guestName ?? null,
      guestPhone: data?.guestPhone ?? null,
      timeRange: data?.timeRange ?? null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await admin.firestore().collection(COLL.cancellationLogs).add(logEntry);

    const locationName = logEntry.locationName || 'Unknown';
    const shortDate = logEntry.date || '';
    const body = `Booking cancelled at ${locationName} for ${shortDate} (${logEntry.source})`;
    try {
      await admin.messaging().send({
        topic: 'booking_cancellations',
        notification: {
          title: 'Court booking cancelled',
          body,
        },
        data: {
          type: 'court_booking_cancelled',
          bookingId,
          locationId: String(logEntry.locationId),
          source: logEntry.source,
        },
      });
    } catch (err) {
      console.warn('FCM send failed (topic may have no subscribers):', err.message);
    }
  });
