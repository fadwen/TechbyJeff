# Result Validation Issues - Troubleshooting Guide

## Overview
This guide addresses issues related to validating SID analysis result objects, ensuring data integrity, and maintaining result quality standards throughout the processing pipeline.

## Common Issues

### 1. Result Structure Validation

#### Issue: Missing Required Properties
**Symptoms:**
- Result objects missing critical properties like SID, ObjectPath, or Timestamp
- Property access errors during downstream processing
- Incomplete audit trails due to missing data

**Root Causes:**
- Incomplete object initialization
- Property assignment failures during creation
- Memory corruption affecting object structure

**Resolution Steps:**
1. **Implement Comprehensive Property Validation:**
   ```powershell
   function Test-OrphanedSIDResultStructure {
       param([PSCustomObject]$Result)

       $requiredProperties = @(
           'SID',
           'ObjectPath',
           'Timestamp',
           'CorrelationId',
           'ProcessingTime',
           'PSTypeName'
       )

       $missingProperties = @()
       foreach ($property in $requiredProperties) {
           if (-not ($Result.PSObject.Properties.Name -contains $property)) {
               $missingProperties += $property
           }
       }

       if ($missingProperties.Count -gt 0) {
           Write-Error "Missing required properties: $($missingProperties -join ', ')"
           return $false
       }

       return $true
   }
   ```

2. **Validate Property Types:**
   ```powershell
   function Test-PropertyTypes {
       param([PSCustomObject]$Result)

       $validationRules = @{
           'SID' = [string]
           'ObjectPath' = [string]
           'Timestamp' = [DateTime]
           'CorrelationId' = [string]
           'ProcessingTime' = [TimeSpan]
       }

       foreach ($property in $validationRules.Keys) {
           $expectedType = $validationRules[$property]
           $actualValue = $Result.$property

           if ($null -ne $actualValue -and $actualValue.GetType() -ne $expectedType) {
               Write-Warning "Property '$property' has incorrect type. Expected: $expectedType, Actual: $($actualValue.GetType())"
               return $false
           }
       }

       return $true
   }
   ```

3. **Check for Property Completeness:**
   ```powershell
   function Test-PropertyCompleteness {
       param([PSCustomObject]$Result)

       # Check for null or empty required string properties
       $stringProperties = @('SID', 'ObjectPath', 'CorrelationId')
       foreach ($property in $stringProperties) {
           $value = $Result.$property
           if ([string]::IsNullOrWhiteSpace($value)) {
               Write-Error "Property '$property' is null, empty, or whitespace"
               return $false
           }
       }

       # Check for valid timestamp
       if ($Result.Timestamp -eq [DateTime]::MinValue -or $Result.Timestamp -eq [DateTime]::MaxValue) {
           Write-Error "Invalid timestamp value: $($Result.Timestamp)"
           return $false
       }

       # Check for reasonable processing time
       if ($Result.ProcessingTime.TotalDays -gt 1) {
           Write-Warning "Unusually long processing time: $($Result.ProcessingTime)"
       }

       return $true
   }
   ```

#### Issue: Invalid PSTypeName
**Symptoms:**
- Result objects don't have the correct PSTypeName
- Type-based filtering and formatting doesn't work
- Objects appear as generic PSCustomObject

**Root Causes:**
- PSTypeName not set during object creation
- Type name overwritten by subsequent operations
- Incorrect type name format

**Resolution Steps:**
1. **Validate PSTypeName Setting:**
   ```powershell
   function Test-PSTypeName {
       param([PSCustomObject]$Result)

       $expectedTypeName = 'OrphanedSIDResult'

       if ($Result.PSTypeName -ne $expectedTypeName) {
           Write-Error "Incorrect PSTypeName. Expected: '$expectedTypeName', Actual: '$($Result.PSTypeName)'"
           return $false
       }

       return $true
   }
   ```

2. **Repair PSTypeName if Needed:**
   ```powershell
   function Repair-PSTypeName {
       param([PSCustomObject]$Result)

       if ($Result.PSTypeName -ne 'OrphanedSIDResult') {
           Write-Warning "Repairing PSTypeName for result object"
           $Result.PSTypeName = 'OrphanedSIDResult'
       }
   }
   ```

### 2. Data Quality Validation

#### Issue: Invalid SID Format
**Symptoms:**
- SID property contains malformed SID strings
- SID translation failures during processing
- Security validation errors

**Root Causes:**
- Corrupted SID data from source systems
- Encoding issues during SID transmission
- Manual SID manipulation introducing errors

**Resolution Steps:**
1. **Implement SID Format Validation:**
   ```powershell
   function Test-SIDFormat {
       param([string]$SID)

       # Standard SID format: S-R-I-S-S...
       $sidPattern = '^S-\d+-\d+(-\d+)*$'

       if ($SID -notmatch $sidPattern) {
           Write-Error "Invalid SID format: $SID"
           return $false
       }

       # Additional validation using .NET SecurityIdentifier
       try {
           $securityIdentifier = [System.Security.Principal.SecurityIdentifier]::new($SID)
           return $true
       }
       catch {
           Write-Error "SID validation failed: $($_.Exception.Message)"
           return $false
       }
   }
   ```

2. **Validate SID Components:**
   ```powershell
   function Test-SIDComponents {
       param([string]$SID)

       $parts = $SID.Split('-')

       # Must start with 'S'
       if ($parts[0] -ne 'S') {
           Write-Error "SID must start with 'S': $SID"
           return $false
       }

       # Must have at least 4 parts (S-R-I-S)
       if ($parts.Length -lt 4) {
           Write-Error "SID has insufficient components: $SID"
           return $false
       }

       # All numeric parts must be valid numbers
       for ($i = 1; $i -lt $parts.Length; $i++) {
           $numericValue = 0
           if (-not [int]::TryParse($parts[$i], [ref]$numericValue)) {
               Write-Error "SID contains non-numeric component: $($parts[$i])"
               return $false
           }
       }

       return $true
   }
   ```

#### Issue: Invalid Distinguished Name (ObjectPath)
**Symptoms:**
- ObjectPath property contains malformed DN strings
- LDAP query failures when using ObjectPath
- Active Directory operation errors

**Root Causes:**
- Incomplete DN construction
- Invalid characters in DN components
- Missing or corrupted DN attributes

**Resolution Steps:**
1. **Validate Distinguished Name Format:**
   ```powershell
   function Test-DistinguishedNameFormat {
       param([string]$DistinguishedName)

       # Basic DN format validation
       if ([string]::IsNullOrWhiteSpace($DistinguishedName)) {
           Write-Error "Distinguished Name cannot be empty"
           return $false
       }

       # Must contain at least one component with '='
       if ($DistinguishedName -notmatch '=') {
           Write-Error "Invalid DN format - missing attribute assignments: $DistinguishedName"
           return $false
       }

       # Validate common DN patterns
       $validDNPattern = '^(CN|OU|DC|O|C|STREET|L|ST)=.+(,(CN|OU|DC|O|C|STREET|L|ST)=.+)*$'
       if ($DistinguishedName -notmatch $validDNPattern) {
           Write-Warning "DN format may be non-standard: $DistinguishedName"
       }

       return $true
   }
   ```

2. **Test DN Accessibility:**
   ```powershell
   function Test-DistinguishedNameAccess {
       param([string]$DistinguishedName)

       try {
           # Attempt to retrieve object information
           $adObject = Get-ADObject -Identity $DistinguishedName -Properties objectClass -ErrorAction Stop
           Write-Verbose "DN accessible: $($adObject.objectClass)"
           return $true
       }
       catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
           Write-Verbose "Object not found (expected for some scenarios): $DistinguishedName"
           return $true  # Object not existing is valid for orphaned SID scenarios
       }
       catch {
           Write-Error "DN access test failed: $($_.Exception.Message)"
           return $false
       }
   }
   ```

### 3. Consistency Validation

#### Issue: Inconsistent Timestamp Formats
**Symptoms:**
- Timestamps in different formats across result objects
- Timezone inconsistencies
- Timestamp parsing errors in downstream systems

**Root Causes:**
- Mixed use of local time vs UTC
- Different timestamp generation methods
- System timezone changes during processing

**Resolution Steps:**
1. **Validate Timestamp Consistency:**
   ```powershell
   function Test-TimestampConsistency {
       param([PSCustomObject[]]$Results)

       $timestampIssues = @()

       foreach ($result in $Results) {
           # Check for UTC timestamps
           if ($result.Timestamp.Kind -ne [DateTimeKind]::Utc) {
               $timestampIssues += "Non-UTC timestamp in result: $($result.CorrelationId)"
           }

           # Check for reasonable timestamp values
           $now = [DateTime]::UtcNow
           $dayAgo = $now.AddDays(-1)
           $hourAhead = $now.AddHours(1)

           if ($result.Timestamp -lt $dayAgo -or $result.Timestamp -gt $hourAhead) {
               $timestampIssues += "Timestamp outside reasonable range: $($result.Timestamp) for $($result.CorrelationId)"
           }
       }

       if ($timestampIssues.Count -gt 0) {
           Write-Warning "Timestamp consistency issues found:"
           $timestampIssues | ForEach-Object { Write-Warning "  $_" }
           return $false
       }

       return $true
   }
   ```

2. **Normalize Timestamps:**
   ```powershell
   function Repair-TimestampConsistency {
       param([PSCustomObject[]]$Results)

       foreach ($result in $Results) {
           if ($result.Timestamp.Kind -ne [DateTimeKind]::Utc) {
               Write-Warning "Converting timestamp to UTC for result: $($result.CorrelationId)"
               $result.Timestamp = $result.Timestamp.ToUniversalTime()
           }
       }
   }
   ```

#### Issue: Correlation ID Duplicates
**Symptoms:**
- Multiple result objects sharing the same correlation ID
- Difficulty tracing individual processing operations
- Audit trail confusion

**Root Causes:**
- Correlation ID not regenerated for each result
- Threading issues with shared correlation ID variables
- Cloning operations copying correlation IDs

**Resolution Steps:**
1. **Detect Correlation ID Duplicates:**
   ```powershell
   function Test-CorrelationIdUniqueness {
       param([PSCustomObject[]]$Results)

       $correlationIds = $Results | ForEach-Object { $_.CorrelationId }
       $uniqueIds = $correlationIds | Select-Object -Unique

       if ($correlationIds.Count -ne $uniqueIds.Count) {
           Write-Error "Duplicate correlation IDs detected"

           # Find and report duplicates
           $duplicates = $correlationIds | Group-Object | Where-Object Count -gt 1
           foreach ($duplicate in $duplicates) {
               Write-Error "Correlation ID '$($duplicate.Name)' appears $($duplicate.Count) times"
           }

           return $false
       }

       return $true
   }
   ```

2. **Repair Duplicate Correlation IDs:**
   ```powershell
   function Repair-DuplicateCorrelationIds {
       param([PSCustomObject[]]$Results)

       $seenIds = @{}

       foreach ($result in $Results) {
           if ($seenIds.ContainsKey($result.CorrelationId)) {
               Write-Warning "Regenerating duplicate correlation ID: $($result.CorrelationId)"
               $result.CorrelationId = [System.Guid]::NewGuid().ToString()
           }
           else {
               $seenIds[$result.CorrelationId] = $true
           }
       }
   }
   ```

## Validation Commands

### Comprehensive Result Validation
```powershell
# Complete result validation function
function Test-OrphanedSIDResult {
    param([PSCustomObject]$Result)

    $validationResults = @{
        StructureValid = Test-OrphanedSIDResultStructure -Result $Result
        TypesValid = Test-PropertyTypes -Result $Result
        DataComplete = Test-PropertyCompleteness -Result $Result
        TypeNameValid = Test-PSTypeName -Result $Result
        SIDValid = Test-SIDFormat -SID $Result.SID
        ObjectPathValid = Test-DistinguishedNameFormat -DistinguishedName $Result.ObjectPath
    }

    $allValid = $validationResults.Values | ForEach-Object { $_ } | Where-Object { $_ -eq $false } | Measure-Object | Select-Object -ExpandProperty Count

    if ($allValid -eq 0) {
        Write-Verbose "Result validation passed for: $($Result.CorrelationId)"
        return $true
    }
    else {
        Write-Error "Result validation failed for: $($Result.CorrelationId)"
        $validationResults.GetEnumerator() | Where-Object { $_.Value -eq $false } | ForEach-Object {
            Write-Error "  $($_.Key): Failed"
        }
        return $false
    }
}
```

### Batch Result Validation
```powershell
# Validate multiple results
function Test-ResultCollection {
    param([PSCustomObject[]]$Results)

    $validationSummary = @{
        TotalResults = $Results.Count
        ValidResults = 0
        InvalidResults = 0
        ValidationErrors = @()
    }

    foreach ($result in $Results) {
        try {
            if (Test-OrphanedSIDResult -Result $result) {
                $validationSummary.ValidResults++
            }
            else {
                $validationSummary.InvalidResults++
            }
        }
        catch {
            $validationSummary.InvalidResults++
            $validationSummary.ValidationErrors += "Result $($result.CorrelationId): $($_.Exception.Message)"
        }
    }

    # Test collection-level consistency
    if (-not (Test-TimestampConsistency -Results $Results)) {
        $validationSummary.ValidationErrors += "Timestamp consistency issues detected"
    }

    if (-not (Test-CorrelationIdUniqueness -Results $Results)) {
        $validationSummary.ValidationErrors += "Correlation ID uniqueness issues detected"
    }

    return $validationSummary
}
```

## Best Practices

### 1. Structure Validation
- Validate all required properties are present before using results
- Implement type checking for critical properties
- Use consistent property naming conventions
- Validate PSTypeName for proper object identification

### 2. Data Quality
- Implement format validation for all structured data (SIDs, DNs)
- Use .NET types for validation when available
- Sanitize input data before creating results
- Implement data range checking for numeric values

### 3. Consistency Checks
- Validate timestamp consistency across result collections
- Ensure correlation ID uniqueness within processing batches
- Check for logical consistency between related properties
- Implement cross-validation between results

### 4. Performance Considerations
- Use efficient validation algorithms for large result sets
- Implement parallel validation for independent checks
- Cache validation results to avoid repeated checks
- Provide summary validation reports for collections

## Related Documentation
- [Result Creation Issues](./Result-Creation-Issues.md)
- [Metadata Population Issues](./Metadata-Population-Issues.md)
- [SID Processing Orchestration Issues](./SID-Processing-Orchestration-Issues.md)
- [Security Descriptor Issues](../Security/Security-Descriptor-Issues.md)

## Support Information
- **Module**: New-SIDResult.ps1
- **Functions**: Test-OrphanedSIDResult, Test-ResultCollection
- **Last Updated**: $(Get-Date -Format 'yyyy-MM-dd')
- **Correlation ID**: Include in all support requests for faster resolution
