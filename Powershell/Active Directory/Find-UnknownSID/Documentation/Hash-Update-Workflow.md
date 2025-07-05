# Hash Update Workflow for Secure Class Loading

## Overview

This document provides the step-by-step process for updating SHA256 hashes in the SecureClassImporter when class files are modified.

## When to Update Hashes

Update hashes whenever:
- Any class file content is modified
- New class files are added to the project
- Class files are removed from the project
- After code reviews that approve class changes

## Step-by-Step Workflow

### 1. Make Class File Changes
```powershell
# Example: Edit a class file
code .\Classes\ScriptConfiguration.ps1
```

### 2. Generate Updated Hashes
```powershell
# Navigate to project root
cd C:\temp\Find-UnknownSID

# Run the hash generator
.\Tools\Generate-ClassHashes.ps1 -OutputFormat PowerShell

# Alternative: Generate JSON format for records
.\Tools\Generate-ClassHashes.ps1 -OutputFormat JSON > .\Documentation\class-hashes-$(Get-Date -Format 'yyyy-MM-dd').json
```

### 3. Update SecureClassImporter.ps1
Open `Private\SecureClassImporter.ps1` and locate the `$approvedClasses` hashtable (around line 160).

Copy the new hash values from the generator output and update the corresponding entries:

```powershell
# Before (example)
'ScriptConfiguration.ps1' = @{
    RequiredTypes = @('ScriptConfiguration')
    Dependencies = @()
    Description = 'Core script configuration and validation functionality'
    ExpectedHash = 'OLD_HASH_VALUE_HERE'
    LastVerified = '2025-07-01'
}

# After (update with new hash and date)
'ScriptConfiguration.ps1' = @{
    RequiredTypes = @('ScriptConfiguration')
    Dependencies = @()
    Description = 'Core script configuration and validation functionality'
    ExpectedHash = 'NEW_HASH_VALUE_FROM_GENERATOR'
    LastVerified = '2025-07-02'
}
```

### 4. Test the Updates
```powershell
# Run the working test to verify hashes are correct
.\test-working-secure-loader.ps1

# Alternative: Run the comprehensive test
.\test-final-implementation.ps1
```

### 5. Verify Integrity Checking
Ensure that:
- All classes load successfully
- No integrity verification warnings appear
- All classes instantiate correctly
- The correlation ID is logged properly

### 6. Document Changes
```powershell
# Add entry to version control
git add .
git commit -m "Update class hashes after [description of changes]

- Updated [ClassName].ps1: [description]
- Hash verification updated in SecureClassImporter.ps1
- Tested with test-working-secure-loader.ps1

Correlation-ID: [latest-test-correlation-id]"
```

## Automated Hash Update Script

For convenience, here's a script to automate the hash update process:

```powershell
# update-class-hashes.ps1
param(
    [string]$Reason = "Routine hash update"
)

Write-Host "=== Automated Hash Update Process ===" -ForegroundColor Green
Write-Host "Reason: $Reason" -ForegroundColor Yellow

try {
    # Generate new hashes
    Write-Host "1. Generating new hashes..." -ForegroundColor Cyan
    $hashOutput = .\Tools\Generate-ClassHashes.ps1 -OutputFormat PowerShell

    # Save hash output for manual review
    $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $hashOutput | Out-File -FilePath ".\Documentation\generated-hashes-$timestamp.txt"
    Write-Host "   Hashes saved to: .\Documentation\generated-hashes-$timestamp.txt" -ForegroundColor Gray

    # Test current implementation
    Write-Host "2. Testing current implementation..." -ForegroundColor Cyan
    $testResult = .\test-working-secure-loader.ps1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✅ Current implementation working" -ForegroundColor Green
    } else {
        Write-Host "   ❌ Current implementation has issues - review needed" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "1. Review generated hashes in: .\Documentation\generated-hashes-$timestamp.txt" -ForegroundColor White
    Write-Host "2. Update SecureClassImporter.ps1 with new hash values" -ForegroundColor White
    Write-Host "3. Run .\test-working-secure-loader.ps1 to verify" -ForegroundColor White
    Write-Host "4. Commit changes to version control" -ForegroundColor White

    Write-Host ""
    Write-Host "Hash update process completed at: $(Get-Date)" -ForegroundColor Gray
}
catch {
    Write-Host "❌ Hash update process failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
```

## Security Considerations

### Hash Verification Failures
If you see warnings like:
```
WARNING: File integrity verification failed for ClassName.ps1
WARNING: Expected: [old-hash]
WARNING: Actual: [new-hash]
```

This indicates:
1. The class file has been modified since the last hash update
2. The SecureClassImporter needs updated hash values
3. Follow this workflow to update the hashes

### Security Review Process
Before updating hashes:
1. **Code Review**: Ensure all class changes are reviewed and approved
2. **Security Check**: Verify no malicious code was introduced
3. **Functionality Test**: Confirm classes still work as expected
4. **Hash Update**: Only then update the hash values

### Audit Trail
Maintain records of:
- When hashes were updated
- What class changes triggered the update
- Who approved the changes
- Test results confirming functionality

## Troubleshooting

### Common Issues

**Issue**: Hash generator fails to run
```powershell
# Solution: Check file permissions and PowerShell execution policy
Get-ExecutionPolicy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Issue**: SecureClassImporter still shows old hashes
```powershell
# Solution: Verify you updated the correct hash entry
Get-Content .\Private\SecureClassImporter.ps1 | Select-String "ExpectedHash.*YOUR_CLASS_NAME" -Context 2
```

**Issue**: Test scripts fail after hash update
```powershell
# Solution: Verify hash format and check for typos
.\Tools\Generate-ClassHashes.ps1 -OutputFormat PowerShell | Select-String "YOUR_CLASS_NAME" -Context 5
```

## Best Practices

1. **Always test after updating hashes**
2. **Keep old hash values in comments during development**
3. **Generate JSON backups of hash values for audit purposes**
4. **Update hashes immediately after class changes**
5. **Document the reason for each hash update**

---
*Workflow documented: 2025-07-02*
*For use with: Find-UnknownSID Secure Class Loading System*
