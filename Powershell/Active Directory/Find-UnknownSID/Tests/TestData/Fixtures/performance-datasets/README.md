# Performance Datasets

## Overview
This directory contains large datasets specifically designed for performance testing of the Find-UnknownSID module. These datasets simulate various real-world scenarios with different data volumes and complexity levels.

## File Inventory

### Current Files
*(Directory is currently empty - files will be generated as needed)*

### Expected Files
- `small-domain-dataset.json` - 1,000 objects, 5,000 SIDs
- `medium-domain-dataset.json` - 10,000 objects, 50,000 SIDs
- `large-domain-dataset.json` - 100,000 objects, 500,000 SIDs
- `enterprise-domain-dataset.json` - 1,000,000 objects, 5,000,000 SIDs
- `complex-security-descriptors.json` - Objects with complex ACLs
- `nested-groups-dataset.json` - Deep group membership hierarchies
- `orphaned-sids-volume.json` - Large numbers of orphaned SIDs
- `mixed-object-types.json` - Various AD object types for comprehensive testing

## Usage

### Loading Performance Datasets
```powershell
# Load small dataset for basic performance testing
$smallDataset = Get-Content ".\small-domain-dataset.json" | ConvertFrom-Json

# Load large dataset for stress testing
$largeDataset = Get-Content ".\large-domain-dataset.json" | ConvertFrom-Json

# Use with Find-UnknownSID for performance testing
Measure-Command { Find-UnknownSID -TestData $smallDataset }
```

### Performance Testing Scenarios
```powershell
# Test memory usage with large datasets
$beforeMemory = [System.GC]::GetTotalMemory($true)
$result = Find-UnknownSID -TestData $largeDataset
$afterMemory = [System.GC]::GetTotalMemory($false)
$memoryUsed = ($afterMemory - $beforeMemory) / 1MB

# Test concurrent processing
$jobs = 1..5 | ForEach-Object {
    Start-Job -ScriptBlock {
        param($Dataset)
        Find-UnknownSID -TestData $Dataset
    } -ArgumentList $smallDataset
}
```

### Benchmarking Guidelines
- **Warm-up**: Run 3 iterations before measurement
- **Measurement**: Average of 5 iterations
- **Environment**: Consistent system state
- **Baseline**: Compare against known performance baselines

## File Generation Commands

### Generate Small Dataset (1K objects)
```powershell
$smallDataset = @{
    metadata = @{
        objectCount = 1000
        sidCount = 5000
        generatedAt = Get-Date
        purpose = "Basic performance testing"
    }
    objects = 1..1000 | ForEach-Object {
        @{
            distinguishedName = "CN=Object$_,OU=TestObjects,DC=test,DC=local"
            objectGUID = [System.Guid]::NewGuid().ToString()
            objectSid = "S-1-5-21-1234567890-$_"
            securityDescriptor = "O:BAG:BAD:(A;;CCDCLCSWRPWPDTLOCRRCWDWO;;;BA)(A;;CCDCLCSWRPWPDTLOCRRCWDWO;;;SY)"
            lastModified = (Get-Date).AddDays(-([Random]::new().Next(1, 365)))
        }
    }
}
$smallDataset | ConvertTo-Json -Depth 10 | Out-File "small-domain-dataset.json"
```

### Generate Large Dataset (100K objects)
```powershell
# Warning: This generates a very large file (~500MB)
$largeDataset = @{
    metadata = @{
        objectCount = 100000
        sidCount = 500000
        generatedAt = Get-Date
        purpose = "Stress testing and scalability validation"
        estimatedSize = "500MB"
    }
    objects = 1..100000 | ForEach-Object {
        @{
            distinguishedName = "CN=Object$_,OU=TestObjects,DC=test,DC=local"
            objectGUID = [System.Guid]::NewGuid().ToString()
            objectSid = "S-1-5-21-1234567890-$_"
            securityDescriptor = if ($_ % 10 -eq 0) {
                # Complex security descriptor for every 10th object
                "O:BAG:BAD:(A;;CCDCLCSWRPWPDTLOCRRCWDWO;;;BA)(A;;CCDCLCSWRPWPDTLOCRRCWDWO;;;SY)(A;;CCDCLCSWRPWPDTLOCRRCWDWO;;;WD)"
            } else {
                "O:BAG:BAD:(A;;CCDCLCSWRPWPDTLOCRRCWDWO;;;BA)"
            }
            lastModified = (Get-Date).AddDays(-([Random]::new().Next(1, 365)))
        }
    }
}
$largeDataset | ConvertTo-Json -Depth 10 | Out-File "large-domain-dataset.json"
```

### Generate Complex Security Descriptors Dataset
```powershell
$complexDataset = @{
    metadata = @{
        purpose = "Testing complex ACL processing performance"
        complexity = "High - Multiple ACEs, nested groups, inheritance"
    }
    objects = 1..1000 | ForEach-Object {
        $aceCount = [Random]::new().Next(5, 20)
        $aces = 1..$aceCount | ForEach-Object {
            "(A;;CCDCLCSWRPWPDTLOCRRCWDWO;;;S-1-5-21-1234567890-$([Random]::new().Next(1000, 9999)))"
        }
        @{
            distinguishedName = "CN=ComplexObject$_,OU=TestObjects,DC=test,DC=local"
            objectSid = "S-1-5-21-1234567890-$_"
            securityDescriptor = "O:BAG:BAD:$($aces -join '')"
            aceCount = $aceCount
        }
    }
}
$complexDataset | ConvertTo-Json -Depth 10 | Out-File "complex-security-descriptors.json"
```

## Performance Expectations

### Small Dataset (1K objects)
- **Processing Time**: < 30 seconds
- **Memory Usage**: < 100MB
- **Throughput**: > 50 objects/second

### Medium Dataset (10K objects)
- **Processing Time**: < 5 minutes
- **Memory Usage**: < 500MB
- **Throughput**: > 40 objects/second

### Large Dataset (100K objects)
- **Processing Time**: < 30 minutes
- **Memory Usage**: < 2GB
- **Throughput**: > 60 objects/second

### Enterprise Dataset (1M objects)
- **Processing Time**: < 3 hours
- **Memory Usage**: < 8GB
- **Throughput**: > 100 objects/second

## Cleanup Commands
```powershell
# Remove all generated datasets
Get-ChildItem -Path "." -Filter "*-dataset.json" | Remove-Item -Force

# Remove datasets larger than 100MB
Get-ChildItem -Path "." -Filter "*.json" | Where-Object { $_.Length -gt 100MB } | Remove-Item -Force -Confirm
```

## Best Practices
1. **Start Small**: Begin testing with small datasets
2. **Monitor Resources**: Watch memory and CPU usage during tests
3. **Use Baselines**: Compare results against established baselines
4. **Document Results**: Record performance metrics for trend analysis
5. **Clean Up**: Remove large test files after testing

## Troubleshooting
- **Out of Memory**: Reduce dataset size or increase available memory
- **Slow Performance**: Check for competing processes or disk I/O bottlenecks
- **File Size Issues**: Use streaming or chunked processing for very large datasets
