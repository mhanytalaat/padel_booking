# Fix Service Account Permissions for FCM
# This grants permissions to the service account in the service-account-key.json file

$PROJECT_ID = "padelcore-app"

# Read the service account email from the JSON file
$serviceAccountKeyPath = "functions\service-account-key.json"

if (-not (Test-Path $serviceAccountKeyPath)) {
    Write-Host "❌ Service account key file not found: $serviceAccountKeyPath" -ForegroundColor Red
    Write-Host "   Please ensure the file exists in the functions/ directory" -ForegroundColor Yellow
    exit 1
}

try {
    $serviceAccountKey = Get-Content $serviceAccountKeyPath | ConvertFrom-Json
    $SERVICE_ACCOUNT_EMAIL = $serviceAccountKey.client_email
    
    Write-Host "="*70 -ForegroundColor Cyan
    Write-Host "GRANTING FCM PERMISSIONS TO SERVICE ACCOUNT" -ForegroundColor Green
    Write-Host "="*70 -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Project ID: $PROJECT_ID" -ForegroundColor Cyan
    Write-Host "Service Account: $SERVICE_ACCOUNT_EMAIL" -ForegroundColor Cyan
    Write-Host ""
    
    # Check if gcloud is installed
    try {
        $null = gcloud --version 2>&1
        Write-Host "✅ gcloud CLI found" -ForegroundColor Green
    } catch {
        Write-Host "❌ gcloud CLI not found!" -ForegroundColor Red
        Write-Host "   Install from: https://cloud.google.com/sdk/docs/install" -ForegroundColor Yellow
        exit 1
    }
    
    # Enable FCM API
    Write-Host "1. Enabling Firebase Cloud Messaging API..." -ForegroundColor Yellow
    gcloud services enable firebasecloudmessaging.googleapis.com --project=$PROJECT_ID 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✅ FCM API enabled" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️  FCM API might already be enabled" -ForegroundColor Yellow
    }
    
    Write-Host ""
    
    # Grant Firebase Cloud Messaging API Service Agent role
    Write-Host "2. Granting Firebase Cloud Messaging API Service Agent role..." -ForegroundColor Yellow
    $result1 = gcloud projects add-iam-policy-binding $PROJECT_ID `
        --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" `
        --role="roles/firebase.cloudMessagingServiceAgent" `
        --condition=None 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✅ Role granted: firebase.cloudMessagingServiceAgent" -ForegroundColor Green
    } else {
        if ($result1 -match "already") {
            Write-Host "   ℹ️  Role already granted: firebase.cloudMessagingServiceAgent" -ForegroundColor Cyan
        } else {
            Write-Host "   ⚠️  Error: $result1" -ForegroundColor Yellow
        }
    }
    
    # Grant Firebase Admin SDK Administrator Service Agent role
    Write-Host "3. Granting Firebase Admin SDK Administrator Service Agent role..." -ForegroundColor Yellow
    $result2 = gcloud projects add-iam-policy-binding $PROJECT_ID `
        --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" `
        --role="roles/firebase.adminsdk.adminServiceAgent" `
        --condition=None 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✅ Role granted: firebase.adminsdk.adminServiceAgent" -ForegroundColor Green
    } else {
        if ($result2 -match "already") {
            Write-Host "   ℹ️  Role already granted: firebase.adminsdk.adminServiceAgent" -ForegroundColor Cyan
        } else {
            Write-Host "   ⚠️  Error: $result2" -ForegroundColor Yellow
        }
    }
    
    # Grant Service Account Token Creator role
    Write-Host "4. Granting Service Account Token Creator role..." -ForegroundColor Yellow
    $result3 = gcloud projects add-iam-policy-binding $PROJECT_ID `
        --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" `
        --role="roles/iam.serviceAccountTokenCreator" `
        --condition=None 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✅ Role granted: iam.serviceAccountTokenCreator" -ForegroundColor Green
    } else {
        if ($result3 -match "already") {
            Write-Host "   ℹ️  Role already granted: iam.serviceAccountTokenCreator" -ForegroundColor Cyan
        } else {
            Write-Host "   ⚠️  Error: $result3" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    Write-Host "="*70 -ForegroundColor Cyan
    Write-Host "PERMISSIONS GRANTED" -ForegroundColor Green
    Write-Host "="*70 -ForegroundColor Cyan
    Write-Host ""
    Write-Host "⚠️  CRITICAL: Wait 3-5 minutes for IAM changes to propagate!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Wait 3-5 minutes (IAM propagation delay)" -ForegroundColor White
    Write-Host "2. Redeploy the function:" -ForegroundColor White
    Write-Host "   cd functions" -ForegroundColor Gray
    Write-Host "   firebase deploy --only functions:onNotificationCreated" -ForegroundColor Gray
    Write-Host "3. Test by creating a notification in Firestore" -ForegroundColor White
    Write-Host ""
    
    # Verify current IAM bindings
    Write-Host "Verifying IAM bindings..." -ForegroundColor Yellow
    Write-Host ""
    gcloud projects get-iam-policy $PROJECT_ID `
        --flatten="bindings[].members" `
        --filter="bindings.members:serviceAccount:$SERVICE_ACCOUNT_EMAIL" `
        --format="table(bindings.role)" 2>&1 | Select-Object -First 20
    
} catch {
    Write-Host "❌ Error reading service account key: $_" -ForegroundColor Red
    Write-Host "   Make sure functions\service-account-key.json exists and is valid JSON" -ForegroundColor Yellow
    exit 1
}
