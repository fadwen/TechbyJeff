# Test Files for File System Operations Testing
# 
# This directory contains various test files for validating file system operations,
# security descriptors, and file handling scenarios in the Find-UnknownSID module.

File Inventory:
==============

1. **sample-acl.txt**
   - Contains sample Access Control List (ACL) data
   - Used for testing ACL parsing and security descriptor analysis
   - Format: SDDL (Security Descriptor Definition Language) strings

2. **large-file-10mb.txt**
   - 10MB test file for performance testing
   - Contains repeated text data for load testing
   - Used to test memory usage and processing speed

3. **unicode-filename-测试文件.txt**
   - Unicode filename testing
   - Tests international character support
   - Validates file path handling with non-ASCII characters

4. **readonly-file.txt**
   - Read-only attribute set
   - Tests file permission handling
   - Used for access control validation

5. **hidden-file.txt**
   - Hidden attribute set
   - Tests hidden file detection and processing
   - Used for comprehensive file system scanning

6. **compressed-file.txt.gz**
   - Compressed file for testing
   - Tests file type detection
   - Used for archive handling scenarios

7. **empty-file.txt**
   - Zero-byte file
   - Tests edge case handling
   - Used for boundary condition testing

8. **security-descriptors-sample.xml**
   - XML format security descriptor data
   - Contains nested permission structures
   - Used for complex security analysis testing

9. **json-config-sample.json**
   - JSON configuration file
   - Contains sample configuration data
   - Used for configuration parsing tests

10. **binary-data.bin**
    - Binary file with mixed content
    - Tests binary file handling
    - Used for file type detection validation

Test Scenarios:
==============

**File Access Testing:**
- Read operations on various file types
- Write operations with different permissions
- File locking and sharing scenarios
- Access denied error handling

**Security Descriptor Testing:**
- ACL parsing from text files
- SDDL string interpretation
- Permission inheritance validation
- Orphaned SID detection in file ACLs

**Performance Testing:**
- Large file processing
- Memory usage monitoring
- File I/O optimization
- Concurrent file access

**Error Handling:**
- Missing file scenarios
- Corrupted file handling
- Permission denied errors
- Network file access failures

**Encoding and Character Set Testing:**
- UTF-8 file processing
- Unicode filename handling
- ANSI to Unicode conversion
- Special character validation

Usage in Tests:
==============

```powershell
# Example test usage
$testFile = Join-Path $TestDataPath "Fixtures\test-files\sample-acl.txt"
$aclData = Get-Content $testFile
$securityDescriptor = ConvertFrom-SDDL $aclData

# Performance testing
$largeFile = Join-Path $TestDataPath "Fixtures\test-files\large-file-10mb.txt"
$processingTime = Measure-Command { 
    Process-LargeFile -FilePath $largeFile 
}

# Unicode testing
$unicodeFile = Join-Path $TestDataPath "Fixtures\test-files\unicode-filename-测试文件.txt"
Test-Path $unicodeFile | Should -Be $true
```

File Generation Commands:
========================

```powershell
# Generate large test file
1..1000000 | ForEach-Object { "Test line $_ with some additional content to increase file size." } | Out-File "large-file-10mb.txt"

# Create read-only file
"Read-only test content" | Out-File "readonly-file.txt"
Set-ItemProperty "readonly-file.txt" -Name IsReadOnly -Value $true

# Create hidden file
"Hidden test content" | Out-File "hidden-file.txt"
Set-ItemProperty "hidden-file.txt" -Name Attributes -Value "Hidden"

# Create empty file
New-Item "empty-file.txt" -ItemType File

# Create sample ACL data
@"
D:(A;;RPWPCCDCLCSWRCWDWOGA;;;S-1-5-21-1234567890-1234567890-1234567890-1001)
(A;;RPWPCCDCLCSWRCWDWOGA;;;S-1-5-21-1234567890-1234567890-1234567890-512)
(A;;RPWPCCDCLCSWRCWDWOGA;;;S-1-5-21-9999999999-9999999999-9999999999-1001)
"@ | Out-File "sample-acl.txt"
```

Security Notes:
==============
- All files are for testing purposes only
- No sensitive data should be stored in test files
- Files may contain sample security descriptors with fake SIDs
- Test files should be regenerated if they become corrupted
- Ensure proper cleanup after tests to avoid disk space issues

Maintenance:
===========
- Review file inventory monthly
- Regenerate large files if corrupted
- Update sample data as test scenarios evolve
- Clean up temporary files created during testing
- Monitor disk space usage in test environment
