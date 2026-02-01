# Extract Chat History from Cursor
$ErrorActionPreference = "Continue"

$wsPath = Join-Path $env:APPDATA "Cursor\User\workspaceStorage"
$outputFile = "extracted_chat_history.txt"

Write-Host "Searching for chat history in: $wsPath" -ForegroundColor Yellow

if (-not (Test-Path $wsPath)) {
    Write-Host "Workspace storage not found!" -ForegroundColor Red
    exit 1
}

$dirs = Get-ChildItem -Path $wsPath -Directory
Write-Host "Found $($dirs.Count) workspace directories" -ForegroundColor Green

$foundFiles = @()

foreach ($dir in $dirs) {
    Write-Host "`nChecking: $($dir.Name)" -ForegroundColor Cyan
    
    # Look for common chat/conversation file patterns
    $files = Get-ChildItem -Path $dir.FullName -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "chat|conversation|history|state|workspace" -or
        $_.Extension -match "json|db|sqlite|vscdb"
    }
    
    if ($files) {
        Write-Host "  Found $($files.Count) potential files" -ForegroundColor Green
        foreach ($file in $files) {
            $foundFiles += [PSCustomObject]@{
                Workspace = $dir.Name
                Path = $file.FullName
                Name = $file.Name
                Size = $file.Length
                Modified = $file.LastWriteTime
            }
            Write-Host "    - $($file.Name) ($([math]::Round($file.Length/1KB, 2)) KB)" -ForegroundColor Gray
        }
    }
}

# Write summary
Write-Host "`n" + ("="*60) -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Green
Write-Host ("="*60) -ForegroundColor Cyan
Write-Host "Total files found: $($foundFiles.Count)" -ForegroundColor White

if ($foundFiles.Count -gt 0) {
    $foundFiles | Format-Table -AutoSize
    $foundFiles | Export-Csv -Path "chat_files_found.csv" -NoTypeInformation
    Write-Host "`nFile list saved to: chat_files_found.csv" -ForegroundColor Green
    
    # Try to read JSON files
    Write-Host "`nAttempting to extract readable content..." -ForegroundColor Yellow
    $content = @()
    $content += "="*60
    $content += "CHAT HISTORY EXTRACTION - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $content += "="*60
    $content += ""
    
    foreach ($file in $foundFiles) {
        if ($file.Name -match "\.json$") {
            try {
                $jsonContent = Get-Content -Path $file.Path -Raw -ErrorAction SilentlyContinue
                if ($jsonContent) {
                    $content += ""
                    $content += "-"*60
                    $content += "File: $($file.Name)"
                    $content += "Workspace: $($file.Workspace)"
                    $content += "-"*60
                    $content += $jsonContent
                    $content += ""
                }
            } catch {
                Write-Host "  Could not read: $($file.Name)" -ForegroundColor Yellow
            }
        }
    }
    
    if ($content.Count -gt 5) {
        $content | Out-File -FilePath $outputFile -Encoding UTF8
        Write-Host "Extracted content saved to: $outputFile" -ForegroundColor Green
    } else {
        Write-Host "No readable JSON content found" -ForegroundColor Yellow
    }
}

Write-Host "`nDone!" -ForegroundColor Green
