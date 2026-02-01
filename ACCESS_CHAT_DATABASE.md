# How to Access Cursor Chat History Database

## Your Project's Chat Database Location

**Workspace ID:** `a302f1b5644dce2da247d879b6bdd4c6`  
**Database Path:** `C:\Users\mhany\AppData\Roaming\Cursor\User\workspaceStorage\a302f1b5644dce2da247d879b6bdd4c6\state.vscdb`  
**Database Size:** ~3 MB (contains chat history)

## Quick Access Methods

### Method 1: Using SQLite Browser (Recommended)

1. **Download DB Browser for SQLite:**
   - https://sqlitebrowser.org/
   - Free, open-source SQLite GUI

2. **Open the Database:**
   - File → Open Database
   - Navigate to: `C:\Users\mhany\AppData\Roaming\Cursor\User\workspaceStorage\a302f1b5644dce2da247d879b6bdd4c6\`
   - Select `state.vscdb`

3. **Browse Tables:**
   - Look for tables with names like:
     - `ItemTable`
     - `Item`
     - `Chat`
     - `Conversation`
     - `History`
   - Click "Browse Data" tab to view contents

4. **Export Data:**
   - Right-click table → Export → CSV or JSON
   - Or use File → Export → Database to SQL

### Method 2: Using Python Script

If you have Python installed, use the script I created:

```bash
python extract_chat.py
```

This will extract all readable content from the database to `chat_history_extracted.txt`

### Method 3: Using Command Line (if SQLite3 is installed)

```powershell
# List all tables
sqlite3 "C:\Users\mhany\AppData\Roaming\Cursor\User\workspaceStorage\a302f1b5644dce2da247d879b6bdd4c6\state.vscdb" "SELECT name FROM sqlite_master WHERE type='table';"

# View a specific table (replace TABLE_NAME)
sqlite3 "C:\Users\mhany\AppData\Roaming\Cursor\User\workspaceStorage\a302f1b5644dce2da247d879b6bdd4c6\state.vscdb" "SELECT * FROM TABLE_NAME LIMIT 100;"
```

## Important Notes

⚠️ **Backup First!**  
Before accessing the database, make a backup:
```powershell
Copy-Item "C:\Users\mhany\AppData\Roaming\Cursor\User\workspaceStorage\a302f1b5644dce2da247d879b6bdd4c6\state.vscdb" -Destination "state.vscdb.backup"
```

⚠️ **Don't Modify While Cursor is Running**  
Close Cursor before accessing the database to avoid corruption.

⚠️ **Database Format**  
The `.vscdb` file is a SQLite database. Cursor may use custom table structures, so the exact schema may vary.

## Alternative: Use the Summary Document

For code review purposes, the **`COMPLETE_TROUBLESHOOTING_SUMMARY.md`** document contains:
- All major issues and solutions
- Key learnings from troubleshooting sessions
- Code changes made
- Configuration details

This summary is easier to read and review than raw chat history.

## Related Files

- `COMPLETE_TROUBLESHOOTING_SUMMARY.md` - Comprehensive summary (recommended for code review)
- `CHAT_HISTORY_BACKUP_GUIDE.md` - Complete index of all troubleshooting docs
- `extract_chat_from_db.ps1` - PowerShell script to extract data
- `extract_chat.py` - Python script to extract data (if Python available)
