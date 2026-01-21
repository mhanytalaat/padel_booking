# Fix Password Reset Email Not Sending

If you're getting a success message but not receiving the password reset email, this is a Firebase configuration issue. Follow these steps:

## Step 1: Check Authorized Domains

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **padelcore-app**
3. Go to **Authentication** → **Settings** → **Authorized domains**
4. Make sure these domains are listed:
   - `localhost` (for development)
   - `padelcore-app.firebaseapp.com` (your Firebase hosting domain)
   - Your custom domain (if you have one)
5. Click **Add domain** if any are missing

## Step 2: Check Email Templates

1. In Firebase Console, go to **Authentication** → **Templates**
2. Click on **Password reset** template
3. Make sure it's **Enabled**
4. Check that the email content looks correct
5. Click **Save** if you made any changes

## Step 3: Configure Custom SMTP (Recommended)

Firebase's default email sender often gets blocked by email providers. Setting up custom SMTP improves delivery:

1. In Firebase Console, go to **Authentication** → **Settings** → **Email templates**
2. Scroll down to **SMTP settings**
3. Click **Configure SMTP**
4. Choose one of these options:

### Option A: Use Gmail SMTP (Easiest)
- **SMTP Host**: `smtp.gmail.com`
- **SMTP Port**: `587`
- **Username**: Your Gmail address
- **Password**: Use an [App Password](https://support.google.com/accounts/answer/185833) (not your regular password)
- **Sender name**: `PadelCore`
- **Sender email**: Your Gmail address

### Option B: Use SendGrid (More Reliable)
1. Sign up at [SendGrid](https://sendgrid.com/)
2. Create an API key
3. Use these settings:
   - **SMTP Host**: `smtp.sendgrid.net`
   - **SMTP Port**: `587`
   - **Username**: `apikey`
   - **Password**: Your SendGrid API key
   - **Sender name**: `PadelCore`
   - **Sender email**: Your verified SendGrid email

### Option C: Use Your Own SMTP Server
- Use your domain's SMTP server settings
- This requires email hosting (e.g., Google Workspace, Microsoft 365)

## Step 4: Verify Email Sending Quota

1. In Firebase Console, go to **Usage and billing**
2. Check if you've exceeded email sending limits
3. Free tier: 100 emails/day
4. If exceeded, upgrade to Blaze plan or wait 24 hours

## Step 5: Test Email Delivery

1. Try sending a password reset email
2. Check:
   - **Inbox** (wait 1-2 minutes)
   - **Spam/Junk folder**
   - **Promotions folder** (Gmail)
3. If still not received:
   - Check Firebase Console → **Authentication** → **Users** → Check if user exists
   - Try a different email address
   - Check email provider's spam filters

## Step 6: Check Firebase Logs

1. In Firebase Console, go to **Functions** → **Logs** (if using Cloud Functions)
2. Or check **Authentication** → **Users** → Click on a user → Check activity logs
3. Look for any errors related to email sending

## Common Issues

### Issue: Emails going to spam
**Solution**: Configure custom SMTP with a verified domain

### Issue: "User not found" error
**Solution**: Make sure the email is registered in Firebase Authentication

### Issue: Email sent but link doesn't work
**Solution**: Check Authorized Domains (Step 1)

### Issue: Quota exceeded
**Solution**: Upgrade to Blaze plan or wait for quota reset

## Quick Test

After configuring, test with:
1. Use a Gmail account (most reliable for testing)
2. Send password reset
3. Check inbox and spam folder
4. Click the link within 1 hour (default expiration)

## Still Not Working?

1. **Check Firebase Status**: [status.firebase.google.com](https://status.firebase.google.com/)
2. **Contact Firebase Support**: If on Blaze plan, contact support
3. **Use Alternative**: Consider implementing phone-based password reset as backup
