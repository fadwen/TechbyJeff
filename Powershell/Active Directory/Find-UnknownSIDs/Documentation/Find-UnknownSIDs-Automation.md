# Find-UnknownSIDs Automation Guide

## Exit Codes

| Code | Name | Description | Action Required |
|------|------|-------------|-----------------|
| 0 | Success | Script completed successfully | None |
| 1 | GeneralFailure | Critical error or general failure | Check logs for details |
| 2 | ModuleImportFailure | Active Directory module not available | Install AD PowerShell module |
| 3 | InvalidParameters | Invalid script parameters | Review parameter values |
| 4 | SecurityValidationBlocked | Security validation prevented operation | Review blocked SIDs |
| 5 | BackupOperationFailed | ACL backup failed | Check backup directory permissions |
| 6 | NoObjectsFound | No AD objects found in search scope | Verify SearchBase parameter |
| 7 | ErrorThresholdExceeded | Too many processing errors | Review error logs |
| 8 | UserCancelled | User cancelled interactive operation | Re-run with -Force in automation |
| 9 | InsufficientPermissions | Insufficient privileges | Run with administrator rights |
| 10 | MemoryManagementFailure | Memory management error | Check system resources |

## Automation Mode Parameters

### Required for Automation
```powershell
# Basic automation run
.\Find-UnknownSIDs.ps1 -AutomationMode -Force

# Removal with automation
.\Find-UnknownSIDs.ps1 -AutomationMode -Force -Remove -WhatIf

# Production removal
.\Find-UnknownSIDs.ps1 -AutomationMode -Force -Remove -BackupPath "C:\Backups"
```

### Error Handling Options
```powershell
# Exit on first critical error
.\Find-UnknownSIDs.ps1 -AutomationMode -ExitOnFirstError

# Set error threshold
.\Find-UnknownSIDs.ps1 -AutomationMode -MaxErrorThreshold 50

# Disable security validation (not recommended)
.\Find-UnknownSIDs.ps1 -AutomationMode -SkipSecurityValidation
```

## CI/CD Integration

### Azure DevOps Pipeline
```yaml
- task: PowerShell@2
  displayName: 'Scan for Orphaned SIDs'
  inputs:
    filePath: 'Scripts/Active Directory/Find-UnknownSIDs.ps1'
    arguments: '-AutomationMode -Force -VerboseOutput'
    failOnStderr: true
  continueOnError: false
```

### GitHub Actions
```yaml
- name: Scan for Orphaned SIDs
  run: |
    powershell -File "Scripts/Active Directory/Find-UnknownSIDs.ps1" -AutomationMode -Force
  shell: pwsh
```

### Jenkins Pipeline
```groovy
stage('AD Security Scan') {
    steps {
        powershell '''
            $result = & "Scripts/Active Directory/Find-UnknownSIDs.ps1" -AutomationMode -Force
            if ($LASTEXITCODE -ne 0) {
                throw "AD scan failed with exit code: $LASTEXITCODE"
            }
        '''
    }
}
```

## Environment Variables

### Automation Detection
Script automatically detects these environments:
- `CI=true` (General CI indicator)
- `TF_BUILD=True` (Azure DevOps)
- `GITHUB_ACTIONS=true` (GitHub Actions)
- `JENKINS_URL` (Jenkins)
- `BUILD_BUILDID` (Azure DevOps legacy)

### Logging Control
- `DETAILED_AUTOMATION_LOGGING=true` - Enable detailed JSON logging

## Output Parsing

### Structured Output Example
```json
{
  "Timestamp": "2024-01-15T10:30:00",
  "CorrelationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "ExitCode": 0,
  "ObjectsProcessed": 1500,
  "OrphanedSIDsFound": 25,
  "SIDsRemoved": 20,
  "ProcessingErrors": 2,
  "CriticalErrors": 0,
  "Duration": "00:05:30",
  "Success": true
}
```

### Log File Analysis
```powershell
# Parse automation logs
$logData = Get-Content "OrphanedDelegations_*.log" | Where-Object { $_ -match "^\d{4}-\d{2}-\d{2}" }
$results = $logData | ConvertFrom-Json -ErrorAction SilentlyContinue
```

## Error Recovery

### Common Automation Failures

1. **Exit Code 2 - Module Import**
   ```powershell
   # Pre-check module availability
   if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
       Install-WindowsFeature -Name RSAT-AD-PowerShell
   }
   ```

2. **Exit Code 9 - Permissions**
   ```powershell
   # Run with elevated privileges
   Start-Process PowerShell -Verb RunAs -ArgumentList "-File script.ps1"
   ```

3. **Exit Code 7 - Error Threshold**
   ```powershell
   # Increase threshold or process in smaller batches
   .\Find-UnknownSIDs.ps1 -MaxErrorThreshold 200 -BatchSize 50
   ```

## Best Practices

### Production Automation
1. Always use `-WhatIf` first in new environments
2. Set appropriate error thresholds based on environment size
3. Monitor memory usage with `-MaxMemoryUsageMB`
4. Use correlation IDs for log correlation
5. Implement proper backup validation

### Security Considerations
1. Never use `-SkipSecurityValidation` in production
2. Review security validation reports before automated removal
3. Implement approval workflows for high-risk operations
4. Monitor for blocked SIDs in automation logs

### Performance Optimization
```powershell
# Large environment optimization
.\Find-UnknownSIDs.ps1 `
    -AutomationMode `
    -BatchSize 50 `
    -MaxMemoryUsageMB 2048 `
    -MaxErrorThreshold 500 `
    -SearchBase "OU=LargeOU,DC=domain,DC=com"
```
