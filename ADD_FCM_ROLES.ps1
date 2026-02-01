# Add Required IAM Roles for FCM Notifications
# Run these commands in PowerShell or Command Prompt

# Set your project and service account
$PROJECT_ID = "padelcore-app"
$SERVICE_ACCOUNT = "padelcore-app@appspot.gserviceaccount.com"

# Add Firebase Admin role
gcloud projects add-iam-policy-binding $PROJECT_ID `
  --member="serviceAccount:$SERVICE_ACCOUNT" `
  --role="roles/firebase.admin"

# Add Cloud Messaging Admin role
gcloud projects add-iam-policy-binding $PROJECT_ID `
  --member="serviceAccount:$SERVICE_ACCOUNT" `
  --role="roles/cloudmessaging.admin"

# Add Service Account Token Creator role (important for OAuth)
gcloud projects add-iam-policy-binding $PROJECT_ID `
  --member="serviceAccount:$SERVICE_ACCOUNT" `
  --role="roles/iam.serviceAccountTokenCreator"

# Add Firebase Cloud Messaging API Service Agent role
gcloud projects add-iam-policy-binding $PROJECT_ID `
  --member="serviceAccount:$SERVICE_ACCOUNT" `
  --role="roles/firebase.cloudMessagingServiceAgent"

# Verify FCM API is enabled
gcloud services enable firebasecloudmessaging.googleapis.com --project=$PROJECT_ID

Write-Host "All roles added. Wait 2-3 minutes for propagation, then redeploy the function."
