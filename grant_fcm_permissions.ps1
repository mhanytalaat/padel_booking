# Grant FCM Permissions to Default App Engine Service Account
# This is the service account that Cloud Functions use by default

$PROJECT_ID = "padelcore-app"
$DEFAULT_SERVICE_ACCOUNT = "$PROJECT_ID@appspot.gserviceaccount.com"

Write-Host "Granting FCM permissions to default service account..." -ForegroundColor Yellow
Write-Host "Project: $PROJECT_ID" -ForegroundColor Cyan
Write-Host "Service Account: $DEFAULT_SERVICE_ACCOUNT" -ForegroundColor Cyan
Write-Host ""

# Check if gcloud is installed
try {
    $gcloudVersion = gcloud --version 2>&1
    Write-Host "✅ gcloud CLI found" -ForegroundColor Green
} catch {
    Write-Host "❌ gcloud CLI not found. Please install Google Cloud SDK first." -ForegroundColor Red
    Write-Host "   Download from: https://cloud.google.com/sdk/docs/install" -ForegroundColor Yellow
    exit 1
}

# Enable FCM API first
Write-Host "1. Enabling Firebase Cloud Messaging API..." -ForegroundColor Yellow
gcloud services enable firebasecloudmessaging.googleapis.com --project=$PROJECT_ID 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "   ✅ FCM API enabled" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  FCM API might already be enabled or there was an error" -ForegroundColor Yellow
}

# Grant Firebase Cloud Messaging API Service Agent role
Write-Host "2. Granting Firebase Cloud Messaging API Service Agent role..." -ForegroundColor Yellow
gcloud projects add-iam-policy-binding $PROJECT_ID `
    --member="serviceAccount:$DEFAULT_SERVICE_ACCOUNT" `
    --role="roles/firebase.cloudMessagingServiceAgent" `
    --condition=None 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "   ✅ Role granted: firebase.cloudMessagingServiceAgent" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  Error granting role (might already be granted)" -ForegroundColor Yellow
}

# Grant Firebase Admin SDK Administrator Service Agent role
Write-Host "3. Granting Firebase Admin SDK Administrator Service Agent role..." -ForegroundColor Yellow
gcloud projects add-iam-policy-binding $PROJECT_ID `
    --member="serviceAccount:$DEFAULT_SERVICE_ACCOUNT" `
    --role="roles/firebase.adminsdk.adminServiceAgent" `
    --condition=None 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "   ✅ Role granted: firebase.adminsdk.adminServiceAgent" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  Error granting role (might already be granted)" -ForegroundColor Yellow
}

# Grant Service Account Token Creator role (for OAuth)
Write-Host "4. Granting Service Account Token Creator role..." -ForegroundColor Yellow
gcloud projects add-iam-policy-binding $PROJECT_ID `
    --member="serviceAccount:$DEFAULT_SERVICE_ACCOUNT" `
    --role="roles/iam.serviceAccountTokenCreator" `
    --condition=None 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "   ✅ Role granted: iam.serviceAccountTokenCreator" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  Error granting role (might already be granted)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "="*60 -ForegroundColor Cyan
Write-Host "PERMISSIONS GRANTED" -ForegroundColor Green
Write-Host "="*60 -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠️  IMPORTANT: Wait 2-3 minutes for IAM changes to propagate!" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Wait 2-3 minutes" -ForegroundColor White
Write-Host "2. Redeploy the function:" -ForegroundColor White
Write-Host "   cd functions" -ForegroundColor Gray
Write-Host "   firebase deploy --only functions:onNotificationCreated" -ForegroundColor Gray
Write-Host "3. Test by creating a notification in Firestore" -ForegroundColor White
Write-Host ""

# Verify current IAM bindings
Write-Host "Checking current IAM bindings for $DEFAULT_SERVICE_ACCOUNT..." -ForegroundColor Yellow
gcloud projects get-iam-policy $PROJECT_ID `
    --flatten="bindings[].members" `
    --filter="bindings.members:serviceAccount:$DEFAULT_SERVICE_ACCOUNT" `
    --format="table(bindings.role)" 2>&1 | Select-Object -First 20
