# Cursor Chat History Backup Script
# This script backs up Cursor chat history and troubleshooting documentation

param(
    [string]$BackupLocation = ".\backups"
)

$ErrorActionPreference = "Continue"

# Create backup directory with timestamp
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$backupDir = Join-Path $BackupLocation "chat_history_$timestamp"
$troubleshootingDir = Join-Path $backupDir "troubleshooting_docs"
$cursorDataDir = Join-Path $backupDir "cursor_data"

Write-Host "Creating backup directory: $backupDir" -ForegroundColor Green
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
New-Item -ItemType Directory -Path $troubleshootingDir -Force | Out-Null
New-Item -ItemType Directory -Path $cursorDataDir -Force | Out-Null

# Backup troubleshooting documentation
Write-Host "`nBacking up troubleshooting documentation..." -ForegroundColor Yellow
$troubleshootingFiles = Get-ChildItem -Path "." -Filter "*.md" -File | Where-Object {
    $_.Name -match "(APPLE|CODEMAGIC|FIX|TROUBLESHOOT|CRITICAL|CHECK|VERIFY|TEST|NOTIFICATION|DEPLOY|ENABLE|ANDROID|IOS|BUILD|VERSION|INTEGRATION|LOCAL|DIRECT|FINAL|GET|HOW|SETUP|WINDOWS)" -or
    $_.Name -eq "README.md" -or
    $_.Name -eq "CHAT_HISTORY_BACKUP_GUIDE.md"
}

$troubleshootingCount = 0
foreach ($file in $troubleshootingFiles) {
    Copy-Item -Path $file.FullName -Destination $troubleshootingDir -ErrorAction SilentlyContinue
    $troubleshootingCount++
    Write-Host "  ✓ $($file.Name)" -ForegroundColor Gray
}

Write-Host "  Backed up $troubleshootingCount troubleshooting documents" -ForegroundColor Green

# Backup Cursor workspace storage
Write-Host "`nBacking up Cursor workspace storage..." -ForegroundColor Yellow
$workspaceStorage = Join-Path $env:APPDATA "Cursor\User\workspaceStorage"
if (Test-Path $workspaceStorage) {
    $workspaceBackup = Join-Path $cursorDataDir "workspaceStorage"
    Copy-Item -Path $workspaceStorage -Destination $workspaceBackup -Recurse -ErrorAction SilentlyContinue
    Write-Host "  ✓ Workspace storage backed up" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Workspace storage not found at: $workspaceStorage" -ForegroundColor Yellow
}

# Backup Cursor local data
Write-Host "`nBacking up Cursor local data..." -ForegroundColor Yellow
$localData = Join-Path $env:LOCALAPPDATA "Cursor"
if (Test-Path $localData) {
    $localBackup = Join-Path $cursorDataDir "localData"
    # Only copy specific subdirectories to avoid copying everything
    $subdirs = @("User", "logs", "CachedData")
    foreach ($subdir in $subdirs) {
        $sourcePath = Join-Path $localData $subdir
        if (Test-Path $sourcePath) {
            $destPath = Join-Path $localBackup $subdir
            Copy-Item -Path $sourcePath -Destination $destPath -Recurse -ErrorAction SilentlyContinue
            Write-Host "  ✓ $subdir backed up" -ForegroundColor Gray
        }
    }
    Write-Host "  ✓ Local data backed up" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Local data not found at: $localData" -ForegroundColor Yellow
}

# Search for chat/conversation files
Write-Host "`nSearching for chat/conversation files..." -ForegroundColor Yellow
$chatFiles = @()
$searchPaths = @(
    (Join-Path $env:APPDATA "Cursor"),
    (Join-Path $env:LOCALAPPDATA "Cursor")
)

foreach ($searchPath in $searchPaths) {
    if (Test-Path $searchPath) {
        $found = Get-ChildItem -Path $searchPath -Recurse -Include "*chat*", "*conversation*", "*.db", "*.sqlite", "*.sqlite3" -ErrorAction SilentlyContinue | Select-Object -First 20
        if ($found) {
            $chatFiles += $found
            Write-Host "  Found $($found.Count) potential chat files in $searchPath" -ForegroundColor Gray
        }
    }
}

if ($chatFiles.Count -gt 0) {
    $chatBackup = Join-Path $cursorDataDir "chat_files"
    New-Item -ItemType Directory -Path $chatBackup -Force | Out-Null
    foreach ($file in $chatFiles) {
        try {
            Copy-Item -Path $file.FullName -Destination $chatBackup -ErrorAction SilentlyContinue
            Write-Host "  ✓ $($file.Name)" -ForegroundColor Gray
        } catch {
            Write-Host "  ⚠ Could not copy $($file.Name): $_" -ForegroundColor Yellow
        }
    }
    Write-Host "  Backed up $($chatFiles.Count) chat-related files" -ForegroundColor Green
} else {
    Write-Host "  ⚠ No chat files found (this is normal if Cursor stores chats differently)" -ForegroundColor Yellow
}

# Create backup manifest
Write-Host "`nCreating backup manifest..." -ForegroundColor Yellow
$manifest = @{
    BackupDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    BackupLocation = $backupDir
    TroubleshootingDocs = $troubleshootingCount
    ChatFiles = $chatFiles.Count
    WorkspaceStorageBackedUp = Test-Path (Join-Path $cursorDataDir "workspaceStorage")
    LocalDataBackedUp = Test-Path (Join-Path $cursorDataDir "localData")
}

$manifestPath = Join-Path $backupDir "backup_manifest.json"
$manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $manifestPath -Encoding UTF8
Write-Host "  ✓ Manifest created" -ForegroundColor Green

# Create summary
Write-Host ("`n" + ("="*60)) -ForegroundColor Cyan
Write-Host "BACKUP COMPLETE" -ForegroundColor Green
Write-Host ("="*60) -ForegroundColor Cyan
Write-Host "Backup Location: $backupDir" -ForegroundColor White
Write-Host "Troubleshooting Docs: $troubleshootingCount" -ForegroundColor White
Write-Host "Chat Files: $($chatFiles.Count)" -ForegroundColor White
Write-Host "Manifest: $manifestPath" -ForegroundColor White
Write-Host "`nTo restore, use the restore script or manually copy files back." -ForegroundColor Yellow
Write-Host ("="*60) -ForegroundColor Cyan
