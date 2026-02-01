# Cursor Chat History Restore Script
# This script restores Cursor chat history and troubleshooting documentation from a backup

param(
    [Parameter(Mandatory=$true)]
    [string]$BackupPath,
    
    [switch]$RestoreCursorData = $false,
    [switch]$RestoreTroubleshootingDocs = $true
)

$ErrorActionPreference = "Continue"

if (-not (Test-Path $BackupPath)) {
    Write-Host "Error: Backup path not found: $BackupPath" -ForegroundColor Red
    exit 1
}

# Read manifest if it exists
$manifestPath = Join-Path $BackupPath "backup_manifest.json"
if (Test-Path $manifestPath) {
    $manifest = Get-Content $manifestPath | ConvertFrom-Json
    Write-Host "Backup Date: $($manifest.BackupDate)" -ForegroundColor Green
    Write-Host "Troubleshooting Docs: $($manifest.TroubleshootingDocs)" -ForegroundColor Green
    Write-Host "Chat Files: $($manifest.ChatFiles)" -ForegroundColor Green
} else {
    Write-Host "Warning: Manifest not found. Proceeding with restore..." -ForegroundColor Yellow
}

# Restore troubleshooting documentation
if ($RestoreTroubleshootingDocs) {
    Write-Host "`nRestoring troubleshooting documentation..." -ForegroundColor Yellow
    $troubleshootingSource = Join-Path $BackupPath "troubleshooting_docs"
    if (Test-Path $troubleshootingSource) {
        $files = Get-ChildItem -Path $troubleshootingSource -Filter "*.md"
        $restoredCount = 0
        foreach ($file in $files) {
            $destPath = Join-Path "." $file.Name
            Copy-Item -Path $file.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
            $restoredCount++
            Write-Host "  ✓ Restored $($file.Name)" -ForegroundColor Gray
        }
        Write-Host "  Restored $restoredCount troubleshooting documents" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ Troubleshooting docs directory not found in backup" -ForegroundColor Yellow
    }
}

# Restore Cursor data (requires confirmation)
if ($RestoreCursorData) {
    Write-Host "`nWARNING: Restoring Cursor data will overwrite current Cursor settings!" -ForegroundColor Red
    $confirm = Read-Host "Are you sure you want to restore Cursor data? (yes/no)"
    
    if ($confirm -eq "yes") {
        $cursorDataSource = Join-Path $BackupPath "cursor_data"
        
        # Restore workspace storage
        $workspaceSource = Join-Path $cursorDataSource "workspaceStorage"
        if (Test-Path $workspaceSource) {
            $workspaceDest = Join-Path $env:APPDATA "Cursor\User\workspaceStorage"
            Write-Host "  Restoring workspace storage..." -ForegroundColor Yellow
            Copy-Item -Path $workspaceSource -Destination $workspaceDest -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  ✓ Workspace storage restored" -ForegroundColor Green
        }
        
        # Restore local data
        $localSource = Join-Path $cursorDataSource "localData"
        if (Test-Path $localSource) {
            $localDest = Join-Path $env:LOCALAPPDATA "Cursor"
            Write-Host "  Restoring local data..." -ForegroundColor Yellow
            $subdirs = Get-ChildItem -Path $localSource -Directory
            foreach ($subdir in $subdirs) {
                $destPath = Join-Path $localDest $subdir.Name
                Copy-Item -Path $subdir.FullName -Destination $destPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "  ✓ Restored $($subdir.Name)" -ForegroundColor Gray
            }
            Write-Host "  ✓ Local data restored" -ForegroundColor Green
        }
        
        # Restore chat files
        $chatSource = Join-Path $cursorDataSource "chat_files"
        if (Test-Path $chatSource) {
            Write-Host "  Chat files found in backup. Manual restoration may be required." -ForegroundColor Yellow
            Write-Host "  Location: $chatSource" -ForegroundColor Gray
        }
        
        Write-Host "`n⚠ Please restart Cursor for changes to take effect!" -ForegroundColor Yellow
    } else {
        Write-Host "  Skipping Cursor data restoration" -ForegroundColor Yellow
    }
} else {
    Write-Host "`nSkipping Cursor data restoration (use -RestoreCursorData to enable)" -ForegroundColor Gray
}

Write-Host ("`n" + ("="*60)) -ForegroundColor Cyan
Write-Host "RESTORE COMPLETE" -ForegroundColor Green
Write-Host ("="*60) -ForegroundColor Cyan
Write-Host "Backup Source: $BackupPath" -ForegroundColor White
Write-Host "Troubleshooting Docs Restored: $RestoreTroubleshootingDocs" -ForegroundColor White
Write-Host "Cursor Data Restored: $RestoreCursorData" -ForegroundColor White
Write-Host ("="*60) -ForegroundColor Cyan
