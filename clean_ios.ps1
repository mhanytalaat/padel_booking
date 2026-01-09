# PowerShell script to clean and rebuild iOS dependencies

Write-Host "Cleaning Flutter build..." -ForegroundColor Yellow
flutter clean

Write-Host "Cleaning iOS Pods..." -ForegroundColor Yellow
cd ios
if (Test-Path "Pods") {
    Remove-Item -Recurse -Force Pods
    Write-Host "Removed Pods directory" -ForegroundColor Green
}
if (Test-Path "Podfile.lock") {
    Remove-Item -Force Podfile.lock
    Write-Host "Removed Podfile.lock" -ForegroundColor Green
}

Write-Host "Installing CocoaPods dependencies..." -ForegroundColor Yellow
pod install

cd ..

Write-Host "Getting Flutter dependencies..." -ForegroundColor Yellow
flutter pub get

Write-Host "`nDone! You can now run:" -ForegroundColor Green
Write-Host "  flutter run" -ForegroundColor Cyan
Write-Host "  or" -ForegroundColor Cyan
Write-Host "  open ios/Runner.xcworkspace" -ForegroundColor Cyan
