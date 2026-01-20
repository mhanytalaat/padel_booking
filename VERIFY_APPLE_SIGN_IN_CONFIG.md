# Quick Verification: Apple Sign In Configuration

## ⚡ 5-Minute Check

### 1. Service ID Match (MOST CRITICAL)
```
Apple Developer Portal → Service ID: com.padelcore.hub.s...
Firebase Console → Service ID: [CHECK IF IT MATCHES]
```
**If they don't match → This is your problem!**

### 2. Private Key Status
```
Apple Developer Portal → Keys → [Your Key] → Status: Active?
Firebase Console → Private Key: [Is it the correct .p8 content?]
```
**If key is revoked or wrong → Create new key, update Firebase**

### 3. Provisioning Profile
```
Apple Developer Portal → Profiles → [Your Profile] → Capabilities
Does it show "Sign in with Apple"?
```
**If missing → Delete profile, create new one**

### 4. Bundle ID Consistency
```
Apple Developer: com.padelcore.app
Xcode: com.padelcore.app
Firebase: com.padelcore.app
```
**All three must be IDENTICAL**

---

## 🎯 If Service IDs Don't Match

1. Go to Apple Developer Portal
2. Copy the EXACT Service ID (e.g., `com.padelcore.hub.service`)
3. Go to Firebase Console → Authentication → Sign-in method → Apple
4. Paste the EXACT Service ID
5. Save
6. Wait 5 minutes
7. Test again

**This fixes 90% of error 1000 cases!**
