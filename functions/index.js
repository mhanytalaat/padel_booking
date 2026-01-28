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
        
        // Query all users with admin or sub-admin role
        const adminUsersSnapshot = await admin.firestore()
          .collection("users")
          .where("role", "in", ["admin", "sub-admin"])
          .get();
        
        if (adminUsersSnapshot.empty) {
          console.log("⚠️ No admin users found");
          return null;
        }

        console.log(`Found ${adminUsersSnapshot.size} admin/sub-admin users`);
        
        const sendPromises = [];
        adminUsersSnapshot.forEach((adminDoc) => {
          const adminData = adminDoc.data();
          const adminRole = adminData.role;
          const assignedLocations = adminData.assignedLocations || [];
          
          // Get all FCM tokens for this admin (supports multiple devices)
          const fcmTokens = adminData.fcmTokens || {};
          const legacyToken = adminData.fcmToken; // Backward compatibility
          
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
          
          // ADMIN: Gets all notifications
          if (adminRole === "admin") {
            if (allTokens.length > 0) {
              console.log(`Sending to admin: ${adminDoc.id} (${allTokens.length} devices)`);
              allTokens.forEach(({ platform, token }) => {
                console.log(`  → ${platform}: ${token.substring(0, 20)}...`);
                sendPromises.push(
                  sendFCMNotification(token, title, body)
                    .then((messageId) => {
                      console.log(`✅ Sent to admin ${adminDoc.id} (${platform}): ${messageId}`);
                    })
                    .catch((error) => {
                      console.error(`❌ Failed to send to admin ${adminDoc.id} (${platform}):`, error.message);
                    })
                );
              });
            } else {
              console.log(`⚠️ Admin ${adminDoc.id} has no FCM tokens`);
            }
          }
          
          // SUB-ADMIN: Only gets notifications for their assigned locations
          if (adminRole === "sub-admin") {
            // If no venue specified, don't send to sub-admins (only admins)
            if (!venue) {
              console.log(`⚠️ Sub-admin ${adminDoc.id} skipped - no venue in notification`);
              return;
            }
            
            // Check if venue is in sub-admin's assigned locations
            if (assignedLocations.length === 0) {
              console.log(`⚠️ Sub-admin ${adminDoc.id} has no assigned locations`);
              return;
            }
            
            if (assignedLocations.includes(venue)) {
              if (allTokens.length > 0) {
                console.log(`Sending to sub-admin: ${adminDoc.id} (location: ${venue}, ${allTokens.length} devices)`);
                allTokens.forEach(({ platform, token }) => {
                  sendPromises.push(
                    sendFCMNotification(token, title, body)
                      .then((messageId) => {
                        console.log(`✅ Sent to sub-admin ${adminDoc.id} (${platform}): ${messageId}`);
                      })
                      .catch((error) => {
                        console.error(`❌ Failed to send to sub-admin ${adminDoc.id} (${platform}):`, error.message);
                      })
                  );
                });
              } else {
                console.log(`⚠️ Sub-admin ${adminDoc.id} has no FCM tokens`);
              }
            } else {
              console.log(`⏭️ Sub-admin ${adminDoc.id} skipped - ${venue} not in assigned locations`);
            }
          }
        });

        await Promise.all(sendPromises);
        console.log(`✅ Sent notification to ${sendPromises.length} admins/sub-admins`);
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
function parseDateTime(dateString, timeString) {
  try {
    // Parse date (format: "2026-01-27" or "27/01/2026")
    let year, month, day;
    
    if (dateString.includes('-')) {
      const parts = dateString.split('-');
      year = parseInt(parts[0]);
      month = parseInt(parts[1]) - 1; // JS months are 0-indexed
      day = parseInt(parts[2]);
    } else if (dateString.includes('/')) {
      const parts = dateString.split('/');
      day = parseInt(parts[0]);
      month = parseInt(parts[1]) - 1;
      year = parseInt(parts[2]);
    } else {
      return null;
    }
    
    // Parse time (format: "7:45 PM")
    const timeMatch = timeString.match(/(\d+):(\d+)\s*(AM|PM)/i);
    if (!timeMatch) return null;
    
    let hours = parseInt(timeMatch[1]);
    const minutes = parseInt(timeMatch[2]);
    const meridiem = timeMatch[3].toUpperCase();
    
    if (meridiem === 'PM' && hours < 12) {
      hours += 12;
    } else if (meridiem === 'AM' && hours === 12) {
      hours = 0;
    }
    
    return new Date(year, month, day, hours, minutes, 0, 0).getTime();
  } catch (error) {
    console.error("Error parsing date/time:", error);
    return null;
  }
}

// BOOKING REMINDERS: Send notifications 30 mins and 10 mins before booking time
exports.sendBookingReminders = functions.pubsub
  .schedule('every 5 minutes')
  .onRun(async (context) => {
    console.log("🔔 Booking Reminder Check Started");
    
    try {
      const now = new Date();
      const nowTime = now.getTime();
      
      // Get all approved bookings
      const bookingsSnapshot = await admin.firestore()
        .collection('bookings')
        .where('status', '==', 'approved')
        .get();
      
      if (bookingsSnapshot.empty) {
        console.log("No approved bookings found");
        return null;
      }
      
      console.log(`Found ${bookingsSnapshot.size} approved bookings`);
      
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
        
        // Send notifications at -30 mins and -10 mins
        let shouldNotify = false;
        let notificationType = '';
        
        if (timeDiff >= 28 && timeDiff <= 32) {
          shouldNotify = true;
          notificationType = '30min';
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
          
          if (notificationType === '30min') {
            title = `⏰ Booking Starting Soon!`;
            body = `Your booking at ${venue} starts in 30 minutes! (${time} on ${date})`;
          } else if (notificationType === '10min') {
            title = `⏰ Booking Starting Very Soon!`;
            body = `Your booking at ${venue} starts in 10 minutes! (${time} on ${date})`;
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
      console.error("❌ Error in booking reminders:", error);
      return null;
    }
  });