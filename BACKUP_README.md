# Chat History Backup System

## Quick Start

### Create a Backup
```powershell
.\backup_chat_history.ps1
```

This will create a timestamped backup in the `backups/` directory containing:
- All troubleshooting documentation (55+ markdown files)
- Cursor workspace storage data
- Cursor local application data
- Any chat/conversation files found

### Restore from Backup
```powershell
.\restore_chat_history.ps1 -BackupPath ".\backups\chat_history_2026-01-27_14-30-00"
```

Options:
- `-RestoreTroubleshootingDocs` (default: true) - Restore troubleshooting markdown files
- `-RestoreCursorData` (default: false) - Restore Cursor app data (requires confirmation)

## What Gets Backed Up

1. **Troubleshooting Documentation** (55+ files)
   - All `.md` files related to troubleshooting, fixes, and guides
   - Includes: Apple Sign-In fixes, Codemagic setup, iOS/Android issues, etc.

2. **Cursor Workspace Storage**
   - Location: `%APPDATA%\Cursor\User\workspaceStorage\`
   - Contains workspace-specific settings and potentially chat history

3. **Cursor Local Data**
   - Location: `%LOCALAPPDATA%\Cursor\`
   - Contains user settings, logs, and cached data

4. **Chat Files**
   - Searches for files with names containing "chat", "conversation"
   - Searches for database files (`.db`, `.sqlite`, `.sqlite3`)

## Backup Structure

```
backups/
└── chat_history_2026-01-27_14-30-00/
    ├── backup_manifest.json          # Backup metadata
    ├── troubleshooting_docs/         # All troubleshooting markdown files
    └── cursor_data/
        ├── workspaceStorage/          # Cursor workspace data
        ├── localData/                 # Cursor local data
        └── chat_files/                # Found chat/conversation files
```

## Manifest File

Each backup includes a `backup_manifest.json` with:
- Backup date and time
- Number of troubleshooting documents
- Number of chat files found
- Whether workspace storage was backed up
- Whether local data was backed up

## Important Notes

1. **Backups are excluded from git** by default (see `.gitignore`)
   - To track backups in git, remove `/backups/` from `.gitignore`

2. **Cursor chat history location** may vary
   - Cursor may store chats in different locations
   - The script searches common locations but may not find all chat data
   - Check `CHAT_HISTORY_BACKUP_GUIDE.md` for manual locations

3. **Restoring Cursor data** will overwrite current settings
   - Always backup current data before restoring
   - Restart Cursor after restoring data

4. **Troubleshooting docs are in git**
   - All troubleshooting markdown files are tracked in git
   - You can retrieve them from git history if needed
   - Use `CHAT_HISTORY_BACKUP_GUIDE.md` as an index

## Troubleshooting Index

See `CHAT_HISTORY_BACKUP_GUIDE.md` for a complete index of all 55+ troubleshooting documents, organized by:
- Error codes
- Platform (iOS, Android, Firebase, Codemagic)
- Issue type (code signing, crashes, authentication, etc.)

## Manual Backup

If the script doesn't work, you can manually backup:

1. **Troubleshooting docs**: Copy all `.md` files from project root
2. **Cursor data**: 
   - Copy `%APPDATA%\Cursor\User\workspaceStorage\`
   - Copy `%LOCALAPPDATA%\Cursor\User\`
3. **Search for chat files**:
   ```powershell
   Get-ChildItem -Path "$env:APPDATA\Cursor" -Recurse -Include "*chat*", "*.db" -ErrorAction SilentlyContinue
   ```

## Related Files

- `CHAT_HISTORY_BACKUP_GUIDE.md` - Complete guide and troubleshooting index
- `backup_chat_history.ps1` - Backup script
- `restore_chat_history.ps1` - Restore script
- All troubleshooting `.md` files in project root
