# Extract Chat History from Cursor SQLite Database
$ErrorActionPreference = "Continue"

# The main project workspace
$workspaceId = "a302f1b5644dce2da247d879b6bdd4c6"
$dbPath = Join-Path $env:APPDATA "Cursor\User\workspaceStorage\$workspaceId\state.vscdb"
$outputFile = "chat_history_extracted.txt"

Write-Host "Extracting chat history from: $dbPath" -ForegroundColor Yellow

if (-not (Test-Path $dbPath)) {
    Write-Host "Database file not found!" -ForegroundColor Red
    exit 1
}

# Check if SQLite is available
$sqliteAvailable = $false
try {
    $null = sqlite3 --version 2>&1
    $sqliteAvailable = $true
} catch {
    Write-Host "SQLite3 command-line tool not found in PATH" -ForegroundColor Yellow
}

if ($sqliteAvailable) {
    Write-Host "Using sqlite3 command-line tool" -ForegroundColor Green
    
    # Try to extract data from common table names
    $tables = @("ItemTable", "Item", "Chat", "Conversation", "History", "State")
    $allContent = @()
    $allContent += "="*80
    $allContent += "CHAT HISTORY EXTRACTION FROM CURSOR DATABASE"
    $allContent += "Workspace: $workspaceId"
    $allContent += "Database: $dbPath"
    $allContent += "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $allContent += "="*80
    $allContent += ""
    
    foreach ($table in $tables) {
        Write-Host "Checking table: $table" -ForegroundColor Cyan
        try {
            $query = "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%$table%';"
            $tablesFound = sqlite3 $dbPath $query 2>&1
            if ($tablesFound -and $tablesFound -notmatch "Error") {
                Write-Host "  Found table: $tablesFound" -ForegroundColor Green
                
                # Get all data from the table
                $dataQuery = "SELECT * FROM $tablesFound;"
                $data = sqlite3 $dbPath $dataQuery 2>&1
                
                if ($data -and $data -notmatch "Error" -and $data.Length -gt 0) {
                    $allContent += ""
                    $allContent += "-"*80
                    $allContent += "TABLE: $tablesFound"
                    $allContent += "-"*80
                    $allContent += $data
                    $allContent += ""
                }
            }
        } catch {
            Write-Host "  Error checking table: $_" -ForegroundColor Yellow
        }
    }
    
    # Also try to get all table names
    Write-Host "`nGetting all table names..." -ForegroundColor Cyan
    $allTables = sqlite3 $dbPath "SELECT name FROM sqlite_master WHERE type='table';" 2>&1
    if ($allTables -and $allTables -notmatch "Error") {
        $allContent += ""
        $allContent += "-"*80
        $allContent += "ALL TABLES IN DATABASE"
        $allContent += "-"*80
        $allContent += $allTables
        $allContent += ""
        
        Write-Host "Found tables:" -ForegroundColor Green
        $allTables | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
        
        # Try to extract from each table
        foreach ($table in ($allTables -split "`n")) {
            if ($table -and $table.Trim()) {
                Write-Host "`nExtracting from: $table" -ForegroundColor Cyan
                try {
                    $countQuery = "SELECT COUNT(*) FROM `"$table`";"
                    $count = sqlite3 $dbPath $countQuery 2>&1
                    Write-Host "  Rows: $count" -ForegroundColor Gray
                    
                    if ([int]$count -gt 0 -and [int]$count -lt 10000) {
                        $dataQuery = "SELECT * FROM `"$table`" LIMIT 1000;"
                        $data = sqlite3 $dbPath $dataQuery 2>&1
                        
                        if ($data -and $data -notmatch "Error" -and $data.Length -gt 50) {
                            $allContent += ""
                            $allContent += "-"*80
                            $allContent += "TABLE: $table (showing first 1000 rows)"
                            $allContent += "-"*80
                            $allContent += $data
                            $allContent += ""
                        }
                    }
                } catch {
                    Write-Host "  Error: $_" -ForegroundColor Yellow
                }
            }
        }
    }
    
    $allContent | Out-File -FilePath $outputFile -Encoding UTF8
    Write-Host "`nExtracted content saved to: $outputFile" -ForegroundColor Green
    Write-Host "File size: $([math]::Round((Get-Item $outputFile).Length/1KB, 2)) KB" -ForegroundColor Gray
    
} else {
    Write-Host "`nSQLite3 not available. Creating Python script to extract data..." -ForegroundColor Yellow
    
    $pythonScript = @"
import sqlite3
import json
import sys
from pathlib import Path

db_path = r"$dbPath"
output_file = "chat_history_extracted.txt"

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Get all table names
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = cursor.fetchall()
    
    output = []
    output.append("="*80)
    output.append("CHAT HISTORY EXTRACTION FROM CURSOR DATABASE")
    output.append(f"Database: {db_path}")
    output.append(f"Date: {__import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    output.append("="*80)
    output.append("")
    
    for table in tables:
        table_name = table[0]
        output.append(f"\n{'='*80}")
        output.append(f"TABLE: {table_name}")
        output.append("="*80)
        
        try:
            # Get row count
            cursor.execute(f"SELECT COUNT(*) FROM `{table_name}`")
            count = cursor.fetchone()[0]
            output.append(f"Rows: {count}")
            output.append("")
            
            if count > 0 and count < 10000:
                # Get column names
                cursor.execute(f"PRAGMA table_info(`{table_name}`)")
                columns = [col[1] for col in cursor.fetchall()]
                output.append(f"Columns: {', '.join(columns)}")
                output.append("")
                
                # Get data (limit to first 1000 rows for readability)
                cursor.execute(f"SELECT * FROM `{table_name}` LIMIT 1000")
                rows = cursor.fetchall()
                
                for i, row in enumerate(rows, 1):
                    output.append(f"\nRow {i}:")
                    for col, val in zip(columns, row):
                        if val:
                            val_str = str(val)
                            # Truncate very long values
                            if len(val_str) > 500:
                                val_str = val_str[:500] + "... [truncated]"
                            output.append(f"  {col}: {val_str}")
        except Exception as e:
            output.append(f"Error reading table: {e}")
    
    conn.close()
    
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(output))
    
    print(f"Extraction complete! Saved to: {output_file}")
    
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
"@
    
    $pythonScript | Out-File -FilePath "extract_chat.py" -Encoding UTF8
    Write-Host "Python script created: extract_chat.py" -ForegroundColor Green
    Write-Host "Run: python extract_chat.py" -ForegroundColor Yellow
}
