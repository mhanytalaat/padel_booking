const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { GoogleAuth } = require("google-auth-library");
const fetch = require("node-fetch");

// 1. Initialize Firebase Admin for Firestore
if (admin.apps.length === 0) {
  try {
    const serviceAccount = require("./service-account-key.json");
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: serviceAccount.project_id || "padelcore-app"
    });
    console.log("✅ Firebase Admin initialized");
    console.log("   Service Account:", serviceAccount.client_email);
  } catch (error) {
    console.error("❌ FAILED to initialize Firebase:", error.message);
    throw error;
  }
}

// 2. Initialize Google Auth for FCM REST API (bypasses Admin SDK messaging issues)
let authClient = null;
let serviceAccount = null;
try {
  serviceAccount = require("./service-account-key.json");
  authClient = new GoogleAuth({
    credentials: serviceAccount,
    scopes: [
      'https://www.googleapis.com/auth/firebase.messaging',
      'https://www.googleapis.com/auth/cloud-platform'
    ]
  });
  console.log("✅ Google Auth initialized for FCM REST API");
} catch (error) {
  console.error("❌ FAILED to initialize Google Auth:", error.message);
}

// Helper function to send FCM notification
async function sendFCMNotification(token, title, body) {
  if (!authClient) {
    throw new Error("Google Auth client not initialized");
  }

  const accessTokenResponse = await authClient.getAccessToken();
  const accessToken = accessTokenResponse?.token || accessTokenResponse;
  
  if (!accessToken) {
    throw new Error("Failed to get access token from service account");
  }

  const projectId = serviceAccount?.project_id || "padelcore-app";
  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
  
  const message = {
    message: {
      token: token.trim(),
      notification: {
        title: title,
        body: body
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1
          }
        }
      },
      android: {
        notification: {
          sound: 'default',
          channelId: 'high_importance_channel'
        }
      }
    }
  };

  const response = await fetch(fcmUrl, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(message)
  });

  const responseText = await response.text();
  
  if (!response.ok) {
    console.error(`❌ FCM API Error for token ${token.substring(0, 20)}...: ${response.status}`);
    throw new Error(`FCM API error: ${response.status} - ${responseText}`);
  }

  const result = JSON.parse(responseText);
  return result.name;
}

// 2. Main function - Handles both user and admin notifications
exports.onNotificationCreated = functions.firestore
  .document("notifications/{notificationId}")
  .onCreate(async (snap, context) => {
    try {
      console.log("=== FCM Function Start ===");
      const notificationData = snap.data();
      const { userId, title = "Notification", body = "You have a new notification", isAdminNotification = false } = notificationData;

      // ADMIN NOTIFICATION: Send to admins and location-specific sub-admins
      if (isAdminNotification) {
        console.log("📢 Admin notification detected");
        
        // Get the venue/location from notification data
        const venue = notificationData.venue || notificationData.location || null;
        console.log(`Notification venue: ${venue}`);
        
        const sendPromises = [];
        
        // 1. Send to all main admins (identified by email/phone)
        const adminPhone = '+201006500506';
        const adminEmail = 'admin@padelcore.com';
        
        const allUsersSnapshot = await admin.firestore()
          .collection("users")
          .get();
        
        // Send to main admins
        allUsersSnapshot.forEach((userDoc) => {
          const userData = userDoc.data();
          const isMainAdmin = userData.phoneNumber === adminPhone || userData.email === adminEmail;
          
          if (isMainAdmin) {
            // Get all FCM tokens for this admin
            const fcmTokens = userData.fcmTokens || {};
            const legacyToken = userData.fcmToken;
            
            const allTokens = [];
            
            if (Object.keys(fcmTokens).length > 0) {
              Object.entries(fcmTokens).forEach(([platform, data]) => {
                if (data && data.token) {
                  allTokens.push({ platform, token: data.token });
                }
              });
            }
            
            if (legacyToken && !allTokens.some(t => t.token === legacyToken)) {
              allTokens.push({ platform: 'legacy', token: legacyToken });
            }
            
            if (allTokens.length > 0) {
              console.log(`Sending to main admin: ${userDoc.id} (${allTokens.length} devices)`);
              allTokens.forEach(({ platform, token }) => {
                console.log(`  → ${platform}: ${token.substring(0, 20)}...`);
                sendPromises.push(
                  sendFCMNotification(token, title, body)
                    .then((messageId) => {
                      console.log(`✅ Sent to main admin ${userDoc.id} (${platform}): ${messageId}`);
                    })
                    .catch((error) => {
                      console.error(`❌ Failed to send to main admin ${userDoc.id} (${platform}):`, error.message);
                    })
                );
              });
            } else {
              console.log(`⚠️ Main admin ${userDoc.id} has no FCM tokens`);
            }
          }
        });
        
        // 2. Send to sub-admins for this specific location
        if (venue) {
          console.log(`Looking for sub-admins for venue: "${venue}"`);
          console.log(`Venue type: ${typeof venue}, length: ${venue.length}`);
          
          // Find the location by name
          const locationsSnapshot = await admin.firestore()
            .collection("courtLocations")
            .where("name", "==", venue)
            .limit(1)
            .get();
          
          console.log(`Location query returned ${locationsSnapshot.size} results`);
          
          if (!locationsSnapshot.empty) {
            const locationDoc = locationsSnapshot.docs[0];
            const locationData = locationDoc.data();
            const subAdmins = locationData.subAdmins || [];
            
            console.log(`Found location "${venue}" (ID: ${locationDoc.id}) with ${subAdmins.length} sub-admin(s)`);
            console.log(`Sub-admin IDs: ${JSON.stringify(subAdmins)}`);
            
            if (subAdmins.length > 0) {
              // Get FCM tokens for each sub-admin
              for (const subAdminId of subAdmins) {
                try {
                  const subAdminDoc = await admin.firestore()
                    .collection("users")
                    .doc(subAdminId)
                    .get();
                  
                  if (subAdminDoc.exists) {
                    const subAdminData = subAdminDoc.data();
                    const fcmTokens = subAdminData.fcmTokens || {};
                    const legacyToken = subAdminData.fcmToken;
                    
                    const allTokens = [];
                    
                    if (Object.keys(fcmTokens).length > 0) {
                      Object.entries(fcmTokens).forEach(([platform, data]) => {
                        if (data && data.token) {
                          allTokens.push({ platform, token: data.token });
                        }
                      });
                    }
                    
                    if (legacyToken && !allTokens.some(t => t.token === legacyToken)) {
                      allTokens.push({ platform: 'legacy', token: legacyToken });
                    }
                    
                    if (allTokens.length > 0) {
                      console.log(`Sending to sub-admin: ${subAdminId} (location: ${venue}, ${allTokens.length} devices)`);
                      allTokens.forEach(({ platform, token }) => {
                        console.log(`  → ${platform}: ${token.substring(0, 20)}...`);
                        sendPromises.push(
                          sendFCMNotification(token, title, body)
                            .then((messageId) => {
                              console.log(`✅ Sent to sub-admin ${subAdminId} (${platform}): ${messageId}`);
                            })
                            .catch((error) => {
                              console.error(`❌ Failed to send to sub-admin ${subAdminId} (${platform}):`, error.message);
                            })
                        );
                      });
                    } else {
                      console.log(`⚠️ Sub-admin ${subAdminId} has no FCM tokens`);
                    }
                  } else {
                    console.log(`⚠️ Sub-admin user ${subAdminId} not found`);
                  }
                } catch (error) {
                  console.error(`Error getting sub-admin ${subAdminId}:`, error.message);
                }
              }
            } else {
              console.log(`No sub-admins assigned to location ${venue}`);
            }
          } else {
            console.log(`⚠️ Location not found with name: "${venue}"`);
            // Debug: Show all location names to help identify the mismatch
            try {
              const allLocations = await admin.firestore().collection("courtLocations").get();
              console.log(`Available locations in database (${allLocations.size}):`);
              allLocations.forEach(doc => {
                const data = doc.data();
                console.log(`  - ID: ${doc.id}, Name: "${data.name}", SubAdmins: ${(data.subAdmins || []).length}`);
              });
            } catch (debugError) {
              console.log(`Could not list locations: ${debugError.message}`);
            }
          }
        } else {
          console.log(`⚠️ No venue specified - only main admins notified`);
        }

        await Promise.all(sendPromises);
        console.log(`✅ Sent notification to ${sendPromises.length} admin/sub-admin devices`);
        return null;
      }

      // USER NOTIFICATION: Send to specific user
      console.log(`📱 User notification for: ${userId}`);
      
      const userDoc = await admin.firestore().collection("users").doc(userId).get();
      if (!userDoc.exists) {
        console.log("User not found");
        return null;
      }

      const userData = userDoc.data();
      
      // Get all FCM tokens for this user (supports multiple devices)
      const fcmTokens = userData.fcmTokens || {};
      const legacyToken = userData.fcmToken; // Backward compatibility
      
      // Collect all tokens from all platforms
      const allTokens = [];
      
      // Add tokens from new fcmTokens structure
      if (Object.keys(fcmTokens).length > 0) {
        Object.entries(fcmTokens).forEach(([platform, data]) => {
          if (data && data.token) {
            allTokens.push({ platform, token: data.token });
          }
        });
      }
      
      // Add legacy token if exists and not already in allTokens
      if (legacyToken && !allTokens.some(t => t.token === legacyToken)) {
        allTokens.push({ platform: 'legacy', token: legacyToken });
      }

      if (allTokens.length === 0) {
        console.log("No FCM tokens found");
        return null;
      }

      console.log(`Token(s) found for ${allTokens.length} device(s), sending FCM via REST API...`);
      
      const sendPromises = [];
      allTokens.forEach(({ platform, token }) => {
        console.log(`   → Sending to ${platform}: ${token.substring(0, 20)}...`);
        sendPromises.push(
          sendFCMNotification(token, title, body)
            .then((messageId) => {
              console.log(`✅ SUCCESS (${platform})! Message ID: ${messageId}`);
              return messageId;
            })
            .catch((error) => {
              console.error(`❌ Failed (${platform}):`, error.message);
              return null;
            })
        );
      });
      
      const results = await Promise.all(sendPromises);
      const successCount = results.filter(r => r !== null).length;
      console.log(`✅✅✅ Sent to ${successCount}/${allTokens.length} devices`);
      
      return results[0]; // Return first successful message ID for compatibility

    } catch (error) {
      console.error("❌ ERROR Code:", error.code);
      console.error("❌ ERROR Message:", error.message);
      
      if (error.code === 'messaging/third-party-auth-error') {
        console.error("❌❌❌ The service account lacks FCM permissions!");
      }
      
      return null;
    }
  });

// MATCH REMINDERS: Send notifications 30 mins, 10 mins, and on-time before matches
exports.sendMatchReminders = functions.pubsub
  .schedule('every 5 minutes')
  .onRun(async (context) => {
    console.log("🔔 Match Reminder Check Started");
    
    try {
      const now = new Date();
      const nowTime = now.getTime();
      
      // Get all tournaments that are in progress
      const tournamentsSnapshot = await admin.firestore()
        .collection('tournaments')
        .where('status', 'in', ['phase1', 'phase2', 'knockout'])
        .get();
      
      if (tournamentsSnapshot.empty) {
        console.log("No active tournaments found");
        return null;
      }
      
      console.log(`Found ${tournamentsSnapshot.size} active tournaments`);
      
      for (const tournamentDoc of tournamentsSnapshot.docs) {
        const tournamentData = tournamentDoc.data();
        const tournamentId = tournamentDoc.id;
        const tournamentName = tournamentData.name || 'Tournament';
        const status = tournamentData.status;
        
        console.log(`Checking ${tournamentName} (${status})`);
        
        // Get matches to check based on tournament type and status
        const matchesToCheck = [];
        
        // Check Phase 1 groups
        if (status === 'phase1' && tournamentData.phase1) {
          const phase1 = tournamentData.phase1;
          const groups = phase1.groups || {};
          
          for (const [groupName, groupData] of Object.entries(groups)) {
            if (groupData.schedule) {
              matchesToCheck.push({
                type: 'Phase 1 Group',
                name: groupName,
                schedule: groupData.schedule,
                groupName: groupName,
              });
            }
          }
        }
        
        // Check Phase 2 groups
        if (status === 'phase2' && tournamentData.phase2) {
          const phase2 = tournamentData.phase2;
          const groups = phase2.groups || {};
          
          for (const [groupName, groupData] of Object.entries(groups)) {
            if (groupData.schedule) {
              matchesToCheck.push({
                type: 'Phase 2 Group',
                name: groupName,
                schedule: groupData.schedule,
                groupName: groupName,
              });
            }
          }
        }
        
        // Check Knockout matches
        if (status === 'knockout' && tournamentData.knockout) {
          const knockout = tournamentData.knockout;
          
          // Quarter Finals
          if (knockout.quarterFinals) {
            for (const match of knockout.quarterFinals) {
              if (match.schedule) {
                matchesToCheck.push({
                  type: 'Quarter Final',
                  name: match.id,
                  schedule: match.schedule,
                });
              }
            }
          }
          
          // Semi Finals
          if (knockout.semiFinals) {
            for (const match of knockout.semiFinals) {
              if (match.schedule) {
                matchesToCheck.push({
                  type: 'Semi Final',
                  name: match.id,
                  schedule: match.schedule,
                });
              }
            }
          }
          
          // Final
          if (knockout.final && knockout.final.schedule) {
            matchesToCheck.push({
              type: 'Final',
              name: 'final',
              schedule: knockout.final.schedule,
            });
          }
        }
        
        // Process each match
        for (const match of matchesToCheck) {
          const startTime = match.schedule.startTime;
          const court = match.schedule.court || 'TBD';
          
          if (!startTime || startTime === 'TBD') continue;
          
          // Parse time (format: "7:45 PM")
          const matchTime = parseTime(startTime);
          if (!matchTime) {
            console.log(`⚠️  Could not parse time: ${startTime}`);
            continue;
          }
          
          // Calculate time difference in minutes
          const timeDiff = Math.floor((matchTime - nowTime) / (1000 * 60));
          
          // Send notifications at -30 mins, -10 mins, and on-time
          let shouldNotify = false;
          let notificationType = '';
          
          if (timeDiff >= 28 && timeDiff <= 32) {
            shouldNotify = true;
            notificationType = '30min';
          } else if (timeDiff >= 8 && timeDiff <= 12) {
            shouldNotify = true;
            notificationType = '10min';
          } else if (timeDiff >= -2 && timeDiff <= 2) {
            shouldNotify = true;
            notificationType = 'now';
          }
          
          if (shouldNotify) {
            // Check if we already sent this notification
            const notificationId = `${tournamentId}_${match.name}_${notificationType}`;
            const existingNotification = await admin.firestore()
              .collection('sentMatchNotifications')
              .doc(notificationId)
              .get();
            
            if (existingNotification.exists) {
              console.log(`Already sent ${notificationType} notification for ${match.name}`);
              continue;
            }
            
            // Get all registered users for this tournament
            const registrationsSnapshot = await admin.firestore()
              .collection('tournamentRegistrations')
              .where('tournamentId', '==', tournamentId)
              .where('status', '==', 'approved')
              .get();
            
            const sendPromises = [];
            const allDevices = [];
            
            for (const regDoc of registrationsSnapshot.docs) {
              const regData = regDoc.data();
              const userId = regData.userId;
              
              // Get user's FCM tokens (all devices)
              const userDoc = await admin.firestore()
                .collection('users')
                .doc(userId)
                .get();
              
              if (userDoc.exists) {
                const userData = userDoc.data();
                const fcmTokens = userData.fcmTokens || {};
                const legacyToken = userData.fcmToken;
                
                // Collect all tokens from all platforms
                if (Object.keys(fcmTokens).length > 0) {
                  Object.entries(fcmTokens).forEach(([platform, data]) => {
                    if (data && data.token) {
                      allDevices.push({ userId, platform, token: data.token });
                    }
                  });
                }
                if (legacyToken && !allDevices.some(d => d.token === legacyToken)) {
                  allDevices.push({ userId, platform: 'legacy', token: legacyToken });
                }
              }
            }
            
            if (allDevices.length > 0) {
              let title = '';
              let body = '';
              
              if (notificationType === '30min') {
                title = `⏰ Match Starting Soon!`;
                body = `Your ${match.type} match starts in 30 minutes at ${court}`;
              } else if (notificationType === '10min') {
                title = `⏰ Match Starting Very Soon!`;
                body = `Your ${match.type} match starts in 10 minutes at ${court}`;
              } else {
                title = `🎾 Match Starting NOW!`;
                body = `Your ${match.type} match is starting now at ${court}`;
              }
              
              // Send to all devices
              for (const { userId, platform, token } of allDevices) {
                sendPromises.push(
                  sendFCMNotification(token, title, body)
                    .then(() => console.log(`✅ Sent to ${userId} (${platform})`))
                    .catch(err => console.error(`❌ Failed to send to ${userId} (${platform}): ${err.message}`))
                );
              }
              
              await Promise.all(sendPromises);
              
              // Mark notification as sent
              await admin.firestore()
                .collection('sentMatchNotifications')
                .doc(notificationId)
                .set({
                  tournamentId,
                  matchName: match.name,
                  matchType: match.type,
                  notificationType,
                  sentAt: admin.firestore.FieldValue.serverTimestamp(),
                  deviceCount: allDevices.length,
                });
              
              console.log(`✅ Sent ${notificationType} notifications for ${match.type} - ${match.name} to ${allDevices.length} devices`);
            }
          }
        }
      }
      
      return null;
    } catch (error) {
      console.error("❌ Error in match reminders:", error);
      return null;
    }
  });

// Helper function to parse time string like "7:45 PM" to Date object
function parseTime(timeString) {
  try {
    const now = new Date();
    const match = timeString.match(/(\d+):(\d+)\s*(AM|PM)/i);
    
    if (!match) return null;
    
    let hours = parseInt(match[1]);
    const minutes = parseInt(match[2]);
    const meridiem = match[3].toUpperCase();
    
    if (meridiem === 'PM' && hours < 12) {
      hours += 12;
    } else if (meridiem === 'AM' && hours === 12) {
      hours = 0;
    }
    
    const matchDate = new Date(now);
    matchDate.setHours(hours, minutes, 0, 0);
    
    // If match time is in the past, assume it's tomorrow
    if (matchDate < now) {
      matchDate.setDate(matchDate.getDate() + 1);
    }
    
    return matchDate.getTime();
  } catch (error) {
    console.error("Error parsing time:", error);
    return null;
  }
}

// Helper function to parse date string like "2026-01-27" and time to DateTime
// NOTE: Assumes booking times are in Egypt timezone (UTC+2)
function parseDateTime(dateString, timeString) {
  try {
    console.log(`🔍 Parsing date: "${dateString}", time: "${timeString}"`);
    
    // Parse date (format: "2026-01-27" or "27/01/2026" or "2026-02-06")
    let year, month, day;
    
    if (dateString.includes('-')) {
      const parts = dateString.split('-');
      year = parseInt(parts[0]);
      month = parseInt(parts[1]) - 1; // JS months are 0-indexed
      day = parseInt(parts[2]);
      console.log(`   Parsed date parts: year=${year}, month=${month+1}, day=${day}`);
    } else if (dateString.includes('/')) {
      const parts = dateString.split('/');
      day = parseInt(parts[0]);
      month = parseInt(parts[1]) - 1;
      year = parseInt(parts[2]);
      console.log(`   Parsed date parts: year=${year}, month=${month+1}, day=${day}`);
    } else {
      console.log(`   ❌ Unknown date format`);
      return null;
    }
    
    // Parse time (format: "7:45 PM" or "2:00 AM")
    const timeMatch = timeString.trim().match(/(\d+):(\d+)\s*(AM|PM)/i);
    if (!timeMatch) {
      console.log(`   ❌ Could not match time pattern`);
      return null;
    }
    
    let hours = parseInt(timeMatch[1]);
    const minutes = parseInt(timeMatch[2]);
    const meridiem = timeMatch[3].toUpperCase();
    
    console.log(`   Time before conversion: ${hours}:${minutes} ${meridiem}`);
    
    if (meridiem === 'PM' && hours < 12) {
      hours += 12;
    } else if (meridiem === 'AM' && hours === 12) {
      hours = 0; // 12:00 AM = 00:00 (midnight)
    }
    
    console.log(`   Time after conversion: ${hours}:${minutes} (24-hour format)`);
    
    // Booking times from the app are in Egypt local time (UTC+2)
    // To convert to UTC, we subtract 2 hours from the local time
    // But Date.UTC already creates a UTC timestamp, so we need to treat input as local
    
    // Create the date treating the input time as Egypt local time (UTC+2)
    // Since Date.UTC treats input as UTC, we subtract 2 hours to get the actual UTC time
    const egyptLocalHours = hours;
    const egyptLocalMinutes = minutes;
    
    // Convert Egypt local time to UTC by subtracting 2 hours
    let utcHours = egyptLocalHours - 2;
    let utcDay = day;
    let utcMonth = month;
    let utcYear = year;
    
    // Handle day rollover if time goes negative
    if (utcHours < 0) {
      utcHours += 24;
      utcDay -= 1;
      
      // Handle month rollover
      if (utcDay < 1) {
        utcMonth -= 1;
        if (utcMonth < 0) {
          utcMonth = 11;
          utcYear -= 1;
        }
        // Get last day of previous month
        utcDay = new Date(utcYear, utcMonth + 1, 0).getDate();
      }
    }
    
    console.log(`   Egypt Local Time: ${egyptLocalHours}:${egyptLocalMinutes}`);
    console.log(`   UTC Time (after -2h): ${utcHours}:${egyptLocalMinutes}`);
    console.log(`   UTC Date: ${utcYear}-${utcMonth+1}-${utcDay}`);
    
    // Create UTC timestamp
    const timestamp = Date.UTC(utcYear, utcMonth, utcDay, utcHours, egyptLocalMinutes, 0, 0);
    const finalDate = new Date(timestamp);
    
    console.log(`   Final Date (UTC): ${finalDate.toUTCString()}`);
    console.log(`   Final Date (Egypt Local): ${new Date(timestamp + 2*60*60*1000).toUTCString()}`);
    console.log(`   Final Timestamp: ${timestamp}`);
    
    return timestamp;
  } catch (error) {
    console.error("Error parsing date/time:", error);
    return null;
  }
}

// NEW: AUTO-CREATE NOTIFICATION FOR COURT BOOKINGS
exports.onCourtBookingCreated = functions.firestore
  .document("courtBookings/{bookingId}")
  .onCreate(async (snap, context) => {
    try {
      console.log("=== Court Booking Notification Function Start ===");
      const bookingData = snap.data();
      const bookingId = context.params.bookingId;
      
      const userId = bookingData.userId;
      const locationName = bookingData.locationName || 'Court';
      const locationId = bookingData.locationId;
      const date = bookingData.date;
      const timeRange = bookingData.timeRange || '';
      const courtsCount = Object.keys(bookingData.courts || {}).length;
      const totalCost = bookingData.totalCost || 0;
      
      // Get user name
      let userName = 'User';
      try {
        const userDoc = await admin.firestore().collection('users').doc(userId).get();
        if (userDoc.exists) {
          const userData = userDoc.data();
          userName = userData.fullName || userData.firstName || 'User';
        }
      } catch (error) {
        console.log('Could not get user name:', error.message);
      }
      
      // Format date nicely
      let formattedDate = date;
      try {
        const dateObj = new Date(date);
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        formattedDate = `${months[dateObj.getMonth()]} ${dateObj.getDate()}, ${dateObj.getFullYear()}`;
      } catch (e) {
        console.log('Could not format date');
      }
      
      // Create admin notification
      await admin.firestore().collection('notifications').add({
        type: 'booking_request',
        title: '🎾 New Court Booking',
        body: `${userName} booked ${locationName} on ${formattedDate} at ${timeRange}`,
        isAdminNotification: true,
        venue: locationName,
        userId: userId,
        userName: userName,
        bookingId: bookingId,
        locationId: locationId,
        date: date,
        time: timeRange,
        courts: courtsCount,
        totalCost: totalCost,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        read: false,
        status: 'confirmed',
      });
      
      console.log(`✅ Created admin notification for court booking ${bookingId}`);
      console.log(`   User: ${userName}`);
      console.log(`   Location: ${locationName}`);
      console.log(`   Date: ${formattedDate}`);
      console.log(`   Time: ${timeRange}`);
      
      return null;
    } catch (error) {
      console.error("❌ Error creating court booking notification:", error);
      return null;
    }
  });

// TRAINING BOOKING REMINDERS: Send notifications 45 mins and 10 mins before booking time
exports.sendBookingReminders = functions.pubsub
  .schedule('every 5 minutes')
  .onRun(async (context) => {
    console.log("🔔 Training Booking Reminder Check Started");
    
    try {
      const now = new Date();
      const nowTime = now.getTime();
      
      // Get all approved training bookings
      const bookingsSnapshot = await admin.firestore()
        .collection('bookings')
        .where('status', '==', 'approved')
        .get();
      
      if (bookingsSnapshot.empty) {
        console.log("No approved training bookings found");
        return null;
      }
      
      console.log(`Found ${bookingsSnapshot.size} approved training bookings`);
      
      for (const bookingDoc of bookingsSnapshot.docs) {
        const bookingData = bookingDoc.data();
        const bookingId = bookingDoc.id;
        const userId = bookingData.userId;
        const venue = bookingData.location || bookingData.venue || 'Court';
        const time = bookingData.time;
        const date = bookingData.date;
        
        if (!time || !date) {
          console.log(`Skipping booking ${bookingId}: Missing time or date`);
          continue;
        }
        
        // Parse booking datetime
        const bookingTime = parseDateTime(date, time);
        if (!bookingTime) {
          console.log(`⚠️  Could not parse booking time: ${date} ${time}`);
          continue;
        }
        
        // Calculate time difference in minutes
        const timeDiff = Math.floor((bookingTime - nowTime) / (1000 * 60));
        
        // Send notifications at -45 mins and -10 mins
        let shouldNotify = false;
        let notificationType = '';
        
        if (timeDiff >= 43 && timeDiff <= 47) {
          shouldNotify = true;
          notificationType = '45min';
        } else if (timeDiff >= 8 && timeDiff <= 12) {
          shouldNotify = true;
          notificationType = '10min';
        }
        
        if (shouldNotify) {
          // Check if we already sent this notification
          const notificationId = `${bookingId}_${notificationType}`;
          const existingNotification = await admin.firestore()
            .collection('sentBookingReminders')
            .doc(notificationId)
            .get();
          
          if (existingNotification.exists) {
            console.log(`Already sent ${notificationType} reminder for booking ${bookingId}`);
            continue;
          }
          
          // Get user's FCM tokens (all devices)
          const userDoc = await admin.firestore()
            .collection('users')
            .doc(userId)
            .get();
          
          if (!userDoc.exists) {
            console.log(`User ${userId} not found`);
            continue;
          }
          
          const userData = userDoc.data();
          const fcmTokens = userData.fcmTokens || {};
          const legacyToken = userData.fcmToken;
          
          // Collect all tokens
          const allTokens = [];
          if (Object.keys(fcmTokens).length > 0) {
            Object.entries(fcmTokens).forEach(([platform, data]) => {
              if (data && data.token) {
                allTokens.push({ platform, token: data.token });
              }
            });
          }
          if (legacyToken && !allTokens.some(t => t.token === legacyToken)) {
            allTokens.push({ platform: 'legacy', token: legacyToken });
          }
          
          if (allTokens.length === 0) {
            console.log(`No FCM tokens for user ${userId}`);
            continue;
          }
          
          let title = '';
          let body = '';
          
          if (notificationType === '45min') {
            title = `⏰ Training Session Soon!`;
            body = `Your training session at ${venue} starts in 45 minutes! (${time} on ${date})`;
          } else if (notificationType === '10min') {
            title = `⏰ Training Starting Very Soon!`;
            body = `Your training session at ${venue} starts in 10 minutes! (${time} on ${date})`;
          }
          
          // Send notification to all devices
          try {
            console.log(`Sending ${notificationType} reminder to user ${userId} (${allTokens.length} devices)`);
            const devicePromises = [];
            allTokens.forEach(({ platform, token }) => {
              devicePromises.push(
                sendFCMNotification(token, title, body)
                  .then(() => console.log(`✅ Sent to ${platform}`))
                  .catch((err) => console.error(`❌ Failed ${platform}:`, err.message))
              );
            });
            
            await Promise.all(devicePromises);
            
            // Mark notification as sent
            await admin.firestore()
              .collection('sentBookingReminders')
              .doc(notificationId)
              .set({
                bookingId,
                userId,
                notificationType,
                deviceCount: allTokens.length,
                sentAt: admin.firestore.FieldValue.serverTimestamp(),
              });
            
            console.log(`✅ Sent ${notificationType} reminder for booking ${bookingId} to ${allTokens.length} devices`);
          } catch (error) {
            console.error(`Failed to send reminder: ${error.message}`);
          }
        }
      }
      
      return null;
    } catch (error) {
      console.error("❌ Error in training booking reminders:", error);
      return null;
    }
  });

// COURT BOOKING REMINDERS: Send notifications 5 hours, 30 mins, and 10 mins before court booking time
exports.sendCourtBookingReminders = functions.pubsub
  .schedule('every 5 minutes')
  .onRun(async (context) => {
    console.log("🔔 Court Booking Reminder Check Started");
    
    try {
      const now = new Date();
      const nowTime = now.getTime();
      
      // Get all confirmed court bookings
      const courtBookingsSnapshot = await admin.firestore()
        .collection('courtBookings')
        .where('status', '==', 'confirmed')
        .get();
      
      if (courtBookingsSnapshot.empty) {
        console.log("No confirmed court bookings found");
        return null;
      }
      
      console.log(`Found ${courtBookingsSnapshot.size} confirmed court bookings`);
      
      for (const bookingDoc of courtBookingsSnapshot.docs) {
        const bookingData = bookingDoc.data();
        const bookingId = bookingDoc.id;
        const userId = bookingData.userId;
        const locationName = bookingData.locationName || 'Court';
        const timeRange = bookingData.timeRange || '';
        const date = bookingData.date;
        
        if (!timeRange || !date) {
          console.log(`Skipping court booking ${bookingId}: Missing time or date`);
          continue;
        }
        
        // Extract start time from timeRange (e.g., "10:00 AM - 11:00 AM")
        const startTime = timeRange.split('-')[0]?.trim();
        if (!startTime) {
          console.log(`⚠️  Could not extract start time from: ${timeRange}`);
          continue;
        }
        
        // Parse booking datetime
        const bookingTime = parseDateTime(date, startTime);
        if (!bookingTime) {
          console.log(`⚠️  Could not parse court booking time: ${date} ${startTime}`);
          continue;
        }
        
        // Debug logging with detailed timestamps
        const bookingDate = new Date(bookingTime);
        const nowDate = new Date(nowTime);
        console.log(`📅 Booking ${bookingId}:`);
        console.log(`   Now (UTC): ${nowDate.toUTCString()}`);
        console.log(`   Now (Local): ${nowDate.toLocaleString()}`);
        console.log(`   Now (ISO): ${nowDate.toISOString()}`);
        console.log(`   Now (timestamp): ${nowTime}`);
        console.log(`   Booking (UTC): ${bookingDate.toUTCString()}`);
        console.log(`   Booking (Local): ${bookingDate.toLocaleString()}`);
        console.log(`   Booking (ISO): ${bookingDate.toISOString()}`);
        console.log(`   Booking (timestamp): ${bookingTime}`);
        console.log(`   Date string: "${date}", Time: "${startTime}"`);
        
        // Calculate time difference in minutes
        const timeDiff = Math.floor((bookingTime - nowTime) / (1000 * 60));
        const hoursDiff = (timeDiff / 60).toFixed(2);
        console.log(`   Time diff: ${timeDiff} minutes (${hoursDiff} hours)`);
        
        // Check if the booking time is in the past
        if (timeDiff < 0) {
          console.log(`   ⚠️ Booking is in the PAST! Skipping...`);
          continue;
        }
        
        // Send notifications at -5 hours (-300 mins), -30 mins, and -10 mins
        let shouldNotify = false;
        let notificationType = '';
        
        if (timeDiff >= 299 && timeDiff <= 301) {
          shouldNotify = true;
          notificationType = '5hours';
        } else if (timeDiff >= 29 && timeDiff <= 31) {
          shouldNotify = true;
          notificationType = '30min';
        } else if (timeDiff >= 9 && timeDiff <= 11) {
          shouldNotify = true;
          notificationType = '10min';
        }
        
        if (shouldNotify) {
          // Check if we already sent this notification
          const notificationId = `${bookingId}_${notificationType}`;
          const existingNotification = await admin.firestore()
            .collection('sentCourtBookingReminders')
            .doc(notificationId)
            .get();
          
          if (existingNotification.exists) {
            console.log(`Already sent ${notificationType} reminder for court booking ${bookingId}`);
            continue;
          }
          
          // Get user's FCM tokens (all devices)
          const userDoc = await admin.firestore()
            .collection('users')
            .doc(userId)
            .get();
          
          if (!userDoc.exists) {
            console.log(`User ${userId} not found`);
            continue;
          }
          
          const userData = userDoc.data();
          const fcmTokens = userData.fcmTokens || {};
          const legacyToken = userData.fcmToken;
          
          // Collect all tokens
          const allTokens = [];
          if (Object.keys(fcmTokens).length > 0) {
            Object.entries(fcmTokens).forEach(([platform, data]) => {
              if (data && data.token) {
                allTokens.push({ platform, token: data.token });
              }
            });
          }
          if (legacyToken && !allTokens.some(t => t.token === legacyToken)) {
            allTokens.push({ platform: 'legacy', token: legacyToken });
          }
          
          if (allTokens.length === 0) {
            console.log(`No FCM tokens for user ${userId}`);
            continue;
          }
          
          let title = '';
          let body = '';
          
          if (notificationType === '5hours') {
            title = `🎾 Court Booking Reminder`;
            body = `Your court booking at ${locationName} is in 5 hours! (${timeRange} on ${date})`;
          } else if (notificationType === '30min') {
            title = `⏰ Court Booking Soon!`;
            body = `Your court booking at ${locationName} starts in 30 minutes! (${timeRange})`;
          } else if (notificationType === '10min') {
            title = `⏰ Court Booking Starting Very Soon!`;
            body = `Your court booking at ${locationName} starts in 10 minutes! (${timeRange})`;
          }
          
          // Send notification to all devices
          try {
            console.log(`Sending ${notificationType} reminder to user ${userId} (${allTokens.length} devices)`);
            const devicePromises = [];
            allTokens.forEach(({ platform, token }) => {
              devicePromises.push(
                sendFCMNotification(token, title, body)
                  .then(() => console.log(`✅ Sent to ${platform}`))
                  .catch((err) => console.error(`❌ Failed ${platform}:`, err.message))
              );
            });
            
            await Promise.all(devicePromises);
            
            // Mark notification as sent
            await admin.firestore()
              .collection('sentCourtBookingReminders')
              .doc(notificationId)
              .set({
                bookingId,
                userId,
                notificationType,
                deviceCount: allTokens.length,
                sentAt: admin.firestore.FieldValue.serverTimestamp(),
              });
            
            console.log(`✅ Sent ${notificationType} reminder for court booking ${bookingId} to ${allTokens.length} devices`);
          } catch (error) {
            console.error(`Failed to send court reminder: ${error.message}`);
          }
        }
      }
      
      return null;
    } catch (error) {
      console.error("❌ Error in court booking reminders:", error);
      return null;
    }
  });

// BUNDLE APPROVAL NOTIFICATION: Send notification to user when their training bundle is approved
exports.onBundleApproved = functions.firestore
  .document("bundles/{bundleId}")
  .onUpdate(async (change, context) => {
    try {
      const beforeData = change.before.data();
      const afterData = change.after.data();
      const bundleId = context.params.bundleId;
      
      // Check if status changed from 'pending' to 'active'
      if (beforeData.status === 'pending' && afterData.status === 'active') {
        console.log(`=== Bundle Approved: ${bundleId} ===`);
        
        const userId = afterData.userId;
        const userName = afterData.userName || 'User';
        const sessions = afterData.totalSessions || 0;
        const players = afterData.playerCount || 0;
        
        // Get user's FCM tokens
        const userDoc = await admin.firestore()
          .collection('users')
          .doc(userId)
          .get();
        
        if (!userDoc.exists) {
          console.log(`User ${userId} not found`);
          return null;
        }
        
        const userData = userDoc.data();
        const fcmTokens = userData.fcmTokens || {};
        const legacyToken = userData.fcmToken;
        
        // Collect all tokens
        const allTokens = [];
        if (Object.keys(fcmTokens).length > 0) {
          Object.entries(fcmTokens).forEach(([platform, data]) => {
            if (data && data.token) {
              allTokens.push({ platform, token: data.token });
            }
          });
        }
        if (legacyToken && !allTokens.some(t => t.token === legacyToken)) {
          allTokens.push({ platform: 'legacy', token: legacyToken });
        }
        
        if (allTokens.length === 0) {
          console.log(`No FCM tokens for user ${userId}`);
          return null;
        }
        
        // Send notification
        const title = `✅ Training Bundle Approved!`;
        const body = `Your training bundle (${sessions} sessions for ${players} ${players === 1 ? 'player' : 'players'}) has been approved and is now active!`;
        
        const sendPromises = [];
        allTokens.forEach(({ platform, token }) => {
          sendPromises.push(
            sendFCMNotification(token, title, body)
              .then(() => console.log(`✅ Sent approval notification to ${platform}`))
              .catch((err) => console.error(`❌ Failed ${platform}:`, err.message))
          );
        });
        
        await Promise.all(sendPromises);
        console.log(`✅ Sent bundle approval notification to ${allTokens.length} devices`);
        
        // Also create an in-app notification
        await admin.firestore().collection('notifications').add({
          type: 'bundle_approved',
          userId: userId,
          bundleId: bundleId,
          title: title,
          body: body,
          read: false,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
        
        console.log(`✅ Created in-app notification for bundle approval`);
      }
      
      return null;
    } catch (error) {
      console.error("❌ Error in bundle approval notification:", error);
      return null;
    }
  });