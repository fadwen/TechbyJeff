# SID Analysis Troubleshooting Guide

## Overview

This guide provides troubleshooting information for the `Get-SIDAnalysis.ps1` module, which handles comprehensive SID analysis and categorization.

## Common Issues

### 1. Analysis Result Accuracy Issues

**Symptoms:**
- Incorrect SID categorization (e.g., local SIDs marked as foreign)
- Wrong risk level assignments
- Inaccurate confidence levels in analysis results

**Causes:**
- Missing or incorrect CurrentDomainSID parameter
- Corrupted SID data affecting RID parsing
- Configuration issues with domain context

**Solutions:**

```powershell
# Verify domain SID parameter
$currentDomain = Get-ADDomain
$domainSID = $currentDomain.DomainSID.Value
Write-Output "Current Domain SID: $domainSID"

# Test analysis with proper domain context
$testSID = "S-1-5-21-1234567890-1234567890-1234567890-1001"
$analysis = Get-SIDAnalysis -SIDString $testSID -CurrentDomainSID $domainSID

Write-Output "Analysis Result:"
Write-Output "  Source: $($analysis.LikelySource)"
Write-Output "  Confidence: $($analysis.Confidence)"
Write-Output "  Risk: $($analysis.RiskLevel)"
Write-Output "  Context: $($analysis.DomainContext)"
```

**Validation Steps:**
```powershell
# Validate SID components manually
$sidParts = $testSID.Split('-')
$domainPart = ($sidParts[0..($sidParts.Length-2)] -join '-')
$rid = [int]$sidParts[-1]

Write-Output "Domain Part: $domainPart"
Write-Output "RID: $rid"
Write-Output "Matches Current Domain: $($domainPart -eq $domainSID)"
```

### 2. RID Range Analysis Issues

**Symptoms:**
- Incorrect object type identification
- Wrong categorization of built-in accounts
- Unexpected risk levels for standard accounts

**Causes:**
- Custom RID ranges in the environment
- Domain migration artifacts
- Bulk import/sync operations affecting RID patterns

**Solutions:**

```powershell
# Test RID categorization logic
$testRIDs = @(500, 501, 502, 1001, 5001, 15001, 150001)
$baseDomainSID = "S-1-5-21-1234567890-1234567890-1234567890"

foreach ($rid in $testRIDs) {
    $testSID = "$baseDomainSID-$rid"
    $analysis = Get-SIDAnalysis -SIDString $testSID -CurrentDomainSID $baseDomainSID

    Write-Output "RID $rid - Source: $($analysis.LikelySource), Risk: $($analysis.RiskLevel)"
}
```

**Custom RID Range Handling:**
```powershell
# For environments with custom RID ranges, consider configuration extensions
# Add custom analysis logic for specific RID patterns
if ($script:Config -and $script:Config.CustomRIDRanges) {
    foreach ($range in $script:Config.CustomRIDRanges) {
        if ($rid -ge $range.Start -and $rid -le $range.End) {
            # Apply custom categorization
            Write-Output "Custom RID range detected: $($range.Description)"
        }
    }
}
```

### 3. Foreign Domain Analysis Issues

**Symptoms:**
- All external SIDs marked as high risk
- Inability to distinguish legitimate trust relationships
- False positives for cross-domain access

**Causes:**
- Missing trust relationship information
- Outdated domain context data
- Complex multi-domain environments

**Solutions:**

```powershell
# Verify trust relationships
$trusts = Get-ADTrust -Filter *
Write-Output "Configured Trusts:"
foreach ($trust in $trusts) {
    Write-Output "  Domain: $($trust.Target), Type: $($trust.TrustType), Direction: $($trust.Direction)"
}

# Test foreign domain SID analysis
$foreignSID = "S-1-5-21-9876543210-9876543210-9876543210-1001"
$analysis = Get-SIDAnalysis -SIDString $foreignSID -CurrentDomainSID $domainSID

Write-Output "Foreign SID Analysis:"
Write-Output "  Source: $($analysis.LikelySource)"
Write-Output "  Notes: $($analysis.Notes)"
```

**Enhanced Foreign Domain Handling:**
```powershell
# Consider implementing trust-aware analysis
if ($script:Config -and $script:Config.TrustedDomains) {
    $sidDomainPart = ($SIDString.Split('-')[0..($SIDString.Split('-').Length-2)] -join '-')

    if ($sidDomainPart -in $script:Config.TrustedDomains) {
        # Reduce risk level for trusted domains
        $analysis.RiskLevel = "Medium"
        $analysis.Notes += " (From trusted domain)"
    }
}
```

### 4. Performance Issues

**Symptoms:**
- Slow analysis of large SID batches
- High memory usage during bulk operations
- Timeouts in pipeline processing

**Causes:**
- Inefficient SID parsing algorithms
- Excessive logging in production
- Large RID range calculations

**Solutions:**

```powershell
# Performance testing
$testSIDs = @()
for ($i = 1000; $i -lt 2000; $i++) {
    $testSIDs += "S-1-5-21-1234567890-1234567890-1234567890-$i"
}

# Measure analysis performance
Measure-Command {
    $results = $testSIDs | Get-SIDAnalysis -CurrentDomainSID $domainSID
}

# Test memory usage
$before = Get-Process -Id $PID | Select-Object WorkingSet64
$results = $testSIDs | Get-SIDAnalysis -CurrentDomainSID $domainSID
$after = Get-Process -Id $PID | Select-Object WorkingSet64

$memoryIncrease = ($after.WorkingSet64 - $before.WorkingSet64) / 1MB
Write-Output "Memory increase: $($memoryIncrease) MB"
```

**Optimization Strategies:**
```powershell
# Batch processing for better performance
$batchSize = 50
for ($i = 0; $i -lt $allSIDs.Count; $i += $batchSize) {
    $batch = $allSIDs[$i..([Math]::Min($i + $batchSize - 1, $allSIDs.Count - 1))]
    $batchResults = $batch | Get-SIDAnalysis -CurrentDomainSID $domainSID
    $allResults += $batchResults
}
```

## Configuration Issues

### 1. Missing Domain Context

**Problem:** Analysis results show "Unknown Domain" for valid domain SIDs

**Solution:**
```powershell
# Ensure CurrentDomainSID is properly obtained
try {
    $domain = Get-ADDomain -Current LocalComputer
    $domainSID = $domain.DomainSID.Value
    Write-Output "Successfully obtained domain SID: $domainSID"
} catch {
    Write-Warning "Failed to get domain SID: $($_.Exception.Message)"
    # Fallback method using WMI
    $wmiDomain = Get-WmiObject -Class Win32_ComputerSystem
    Write-Output "Computer Domain: $($wmiDomain.Domain)"
}
```

### 2. Invalid SID Analysis Results

**Problem:** Analysis returns "Invalid" for legitimate SIDs

**Solution:**
```powershell
# Debug SID validation chain
$problematicSID = "S-1-5-21-1234567890-1234567890-1234567890-1001"

# Test format validation first
$formatValid = Test-SIDFormat -SID $problematicSID
Write-Output "Format Valid: $formatValid"

if ($formatValid) {
    # Test well-known status
    $isWellKnown = Test-WellKnownSID -SID $problematicSID
    Write-Output "Well-Known: $isWellKnown"

    # Proceed with analysis
    $analysis = Get-SIDAnalysis -SIDString $problematicSID -CurrentDomainSID $domainSID
    Write-Output "Analysis Source: $($analysis.LikelySource)"
}
```

## Error Messages

### "Invalid SID format - does not match standard SID structure"

**Meaning:** The SID string failed format validation

**Resolution:**
1. Verify SID string integrity using Test-SIDFormat
2. Check for data corruption in SID source
3. Validate SID encoding and character set

### "Invalid SID structure - insufficient components"

**Meaning:** SID has fewer than 4 components when split by '-'

**Resolution:**
1. Check SID string for truncation
2. Verify complete SID data retrieval
3. Investigate data source integrity

### "Invalid RID format - must be numeric"

**Meaning:** The last component of the SID is not a valid number

**Resolution:**
1. Check for non-numeric characters in RID
2. Verify SID data integrity
3. Investigate data parsing issues

### "Error during analysis: [Exception details]"

**Meaning:** Unexpected error during the analysis process

**Resolution:**
1. Check correlation ID in logs for detailed context
2. Verify all module dependencies are loaded
3. Check for system resource constraints

## Logging and Diagnostics

### Enable Detailed Analysis Logging

```powershell
# Enable comprehensive logging
$VerbosePreference = 'Continue'
$DebugPreference = 'Continue'

# Test with detailed logging
$correlationId = [System.Guid]::NewGuid().ToString()
Get-SIDAnalysis -SIDString $testSID -CurrentDomainSID $domainSID -CorrelationId $correlationId -Verbose
```

### Correlation ID Tracking

```powershell
# Use correlation IDs for end-to-end analysis tracking
$correlationId = [System.Guid]::NewGuid().ToString()

# Track through validation and analysis
Test-SIDFormat -SID $testSID -CorrelationId $correlationId
$analysis = Get-SIDAnalysis -SIDString $testSID -CurrentDomainSID $domainSID -CorrelationId $correlationId

# Search logs for this correlation ID to trace the complete analysis flow
```

### Analysis Result Validation

```powershell
# Validate analysis result object
$analysis = Get-SIDAnalysis -SIDString $testSID -CurrentDomainSID $domainSID

# Check result completeness
$requiredProperties = @('SID', 'LikelySource', 'Confidence', 'Notes', 'RiskLevel', 'AnalyzedAt', 'DomainContext')
foreach ($property in $requiredProperties) {
    if (-not $analysis.$property) {
        Write-Warning "Missing property: $property"
    }
}
```

## Best Practices

### 1. Domain Context Management

Always provide domain context for accurate analysis:

```powershell
# Best practice: Always obtain and use current domain SID
$domainSID = (Get-ADDomain).DomainSID.Value
$results = $sidList | Get-SIDAnalysis -CurrentDomainSID $domainSID
```

### 2. Error Handling

Implement proper error handling for analysis operations:

```powershell
try {
    $analysis = Get-SIDAnalysis -SIDString $sidString -CurrentDomainSID $domainSID -CorrelationId $correlationId

    if ($analysis.LikelySource -eq "Analysis Error") {
        Write-Error "Analysis failed for SID: $sidString"
        continue
    }

    # Process valid analysis result
} catch {
    Write-Error "Failed to analyze SID $sidString : $($_.Exception.Message)"
    continue
}
```

### 3. Result Interpretation

Properly interpret analysis confidence and risk levels:

```powershell
# Risk-based decision making
switch ($analysis.RiskLevel) {
    'Low' {
        # Safe to process or remove
        Write-Output "Low risk SID: $($analysis.SID)"
    }
    'Medium' {
        # Requires review
        Write-Warning "Medium risk SID requires review: $($analysis.SID)"
    }
    'High' {
        # Do not process automatically
        Write-Error "High risk SID - manual review required: $($analysis.SID)"
    }
}
```

## Contact Information

For additional support:
- **Author:** Jeffrey Stuhr
- **Blog:** https://www.techbyjeff.net
- **LinkedIn:** https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

For urgent issues, check the main troubleshooting directory:
- `.\Troubleshooting\Common\` - General issues
- `.\Troubleshooting\Security\` - Security-specific problems
- `.\Troubleshooting\Performance\` - Performance optimization
