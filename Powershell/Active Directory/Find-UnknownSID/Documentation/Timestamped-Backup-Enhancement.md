# Timestamped Backup Enhancement

## Overview

The Find-UnknownSID script has been enhanced to organize backup files into timestamped subfolders for better organization and auditability.

## Enhancement Details

### Before Enhancement
- All backup files were placed directly in the `.\Backup\` directory
- Multiple script runs would mix backup files together
- Difficult to identify which backups belonged to which script run
- Example: `.\Backup\CN_User_20250702_103631.xml`

### After Enhancement
- Each script run creates a dedicated timestamped subfolder
- All backup files for a single execution are organized together
- Easy identification of backups by execution time
- Example: `.\Backup\20250702_104232\CN_User_20250702_104233.xml`

## Directory Structure

```
Find-UnknownSID/
├── Backup/
│   ├── 20250702_104232/     # First script run (July 2, 2025 at 10:42:32 AM)
│   │   ├── CN_BackupTestUser_OU_OrphanedSIDTest_DC_mylab_DC_local_20250702_104233.xml
│   │   └── [other backup files from this run]
│   ├── 20250702_104316/     # Second script run (July 2, 2025 at 10:43:16 AM)
│   │   └── [backup files from this run]
│   └── 20250703_091245/     # Third script run (next day)
│       └── [backup files from this run]
└── [other script directories]
```

## Timestamp Format

The timestamp format follows the pattern: `yyyyMMdd_HHmmss`
- `yyyy`: 4-digit year
- `MM`: 2-digit month
- `dd`: 2-digit day
- `HH`: 2-digit hour (24-hour format)
- `mm`: 2-digit minute
- `ss`: 2-digit second

## Benefits

1. **Better Organization**: Each script run's backups are isolated in their own folder
2. **Audit Trail**: Easy to correlate backups with specific script executions
3. **Rollback Precision**: Can restore from a specific execution's backups
4. **Troubleshooting**: Simplified investigation of backup issues by execution time
5. **Retention Management**: Easy to implement backup retention policies by folder age

## Usage Examples

### Removal Operations (Automatic Backup Creation)
```powershell
# Script automatically creates timestamped backup subfolder
.\Find-UnknownSID.ps1 -Remove -SearchBase "OU=Users,DC=contoso,DC=com"
# Backups saved to: .\Backup\20250702_104232\
```

### Restore Operations (Using Timestamped Backup)
```powershell
# Restore from specific timestamped backup folder
.\Find-UnknownSID.ps1 -Restore -SearchBase "CN=User,OU=Users,DC=contoso,DC=com" -BackupPath ".\Backup\20250702_104232"
```

### Custom Backup Path with Timestamping
```powershell
# Even with custom backup path, timestamped subfolders are created
.\Find-UnknownSID.ps1 -Remove -SearchBase "OU=Users,DC=contoso,DC=com" -BackupPath "C:\CustomBackups"
# Backups saved to: C:\CustomBackups\20250702_104232\
```

## Technical Implementation

### Key Changes Made

1. **Main Script Enhancement** (`Find-UnknownSID.ps1`):
   - Added timestamped subfolder creation logic
   - Enhanced parameter documentation
   - Updated examples to reflect new structure

2. **Backup Path Logic**:
   - Base backup path (default or specified) is created if needed
   - Timestamped subfolder is created within the base path
   - All backup operations use the timestamped path

3. **Documentation Updates**:
   - Parameter help updated to explain timestamped organization
   - Examples updated to show timestamped paths
   - Restore examples demonstrate using timestamped backup folders

### Code Implementation
```powershell
# Create timestamped subfolder for this script run if performing removal operations
if ($Remove -and $effectiveBackupPath) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $timestampedBackupPath = Join-Path $effectiveBackupPath $timestamp

    if (-not (Test-Path $timestampedBackupPath)) {
        New-Item -Path $timestampedBackupPath -ItemType Directory -Force | Out-Null
        Write-ScriptLog "Created timestamped backup subfolder: $timestampedBackupPath" -Level Information -Component 'Main' -CorrelationId $CorrelationId
    }

    # Use the timestamped path for actual backup operations
    $effectiveBackupPath = $timestampedBackupPath
}
```

## Compatibility

- **Backward Compatible**: Existing backup files in the main backup directory remain accessible
- **Restore Compatible**: Restore operations can specify either timestamped subfolders or the main backup directory
- **Path Flexibility**: Works with both default (`.\Backup\`) and custom backup paths

## Testing Results

✅ **Timestamped subfolder creation**: Verified multiple runs create separate folders
✅ **Backup file placement**: Confirmed files are created in correct timestamped subfolders
✅ **Restore compatibility**: Verified restore operations can target timestamped backup folders
✅ **Path validation**: Confirmed both default and custom backup paths work correctly

## Migration Guide

No migration is required. The enhancement:
- Does not affect existing backup files
- Maintains compatibility with existing restore procedures
- Only affects new backup operations going forward

## Future Enhancements

Potential future improvements could include:
1. **Retention Management**: Automatic cleanup of old timestamped backup folders
2. **Backup Compression**: Compress individual timestamped folders to save space
3. **Metadata Indexing**: Create index files to quickly locate backups by criteria
4. **Parallel Execution**: Handle multiple concurrent script executions with unique timestamps

---

**Enhancement Completed**: July 2, 2025
**Author**: Jeffrey Stuhr
**Version**: 2.0.0+
