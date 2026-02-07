@echo off
echo ========================================
echo Court Booking Notification Fix Deployer
echo ========================================
echo.
echo This will deploy the timezone fix to Firebase Functions
echo.
pause
echo.
echo Navigating to functions directory...
cd functions
echo.
echo Deploying sendCourtBookingReminders function...
call firebase deploy --only functions:sendCourtBookingReminders
echo.
echo ========================================
echo Deployment Complete!
echo ========================================
echo.
echo Next steps:
echo 1. Test by booking a court 2-3 hours in the future
echo 2. Check logs: firebase functions:log --only sendCourtBookingReminders
echo 3. Verify you receive notifications at correct times
echo.
pause
