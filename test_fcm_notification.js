// Test FCM Notification Function
// Run this from the project root: node test_fcm_notification.js

const admin = require('firebase-admin');

// Initialize with service account
const serviceAccount = require('./functions/service-account-key.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'padelcore-app'
});

const db = admin.firestore();

async function testNotification() {
  try {
    console.log('🧪 Testing FCM Notification Function...\n');
    
    // Get a user ID from your users collection
    const usersSnapshot = await db.collection('users').limit(1).get();
    
    if (usersSnapshot.empty) {
      console.log('❌ No users found in Firestore. Please create a user first.');
      return;
    }
    
    const userId = usersSnapshot.docs[0].id;
    const userData = usersSnapshot.docs[0].data();
    
    console.log(`✅ Found user: ${userId}`);
    console.log(`   Email: ${userData.email || 'N/A'}`);
    console.log(`   FCM Token: ${userData.fcmToken ? '✅ Present' : '❌ Missing'}\n`);
    
    if (!userData.fcmToken) {
      console.log('⚠️  User has no FCM token. The function will skip sending.');
      console.log('   But we can still test if the function triggers.\n');
    }
    
    // Create test notification document
    console.log('📝 Creating test notification document...');
    const notificationRef = await db.collection('notifications').add({
      userId: userId,
      title: 'Test Notification',
      body: 'Testing FCM function - ' + new Date().toISOString(),
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      read: false
    });
    
    console.log(`✅ Notification document created: ${notificationRef.id}`);
    console.log('\n⏳ Waiting for function to process...');
    console.log('   Check function logs: firebase functions:log --only onNotificationCreated');
    console.log(`   Or check Firestore: notifications/${notificationRef.id}`);
    
    // Wait a bit and check status
    setTimeout(async () => {
      const doc = await notificationRef.get();
      const data = doc.data();
      
      console.log('\n📊 Notification Status:');
      console.log(`   Status: ${data.status || 'pending'}`);
      if (data.error) {
        console.log(`   Error: ${data.error}`);
      }
      if (data.fcmMessageId) {
        console.log(`   ✅ FCM Message ID: ${data.fcmMessageId}`);
      }
    }, 5000);
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    console.error(error);
  }
}

testNotification();
