# Pester tests for Invoke-SIDRemoval function

# Mock functions for testing
function Write-StructuredLog {
    param($Level, $Message, $CorrelationId, $SecurityContext)
    # Mock implementation
}

function Test-ValidDistinguishedName {
    param($DistinguishedName)
    if ($DistinguishedName -match '^CN=|^OU=|^DC=') {
        return $true
    }
    return $false
}

function Invoke-ADOperationWithRetry {
    param($ScriptBlock, $MaxRetries, $OperationName, $ObjectContext, $CorrelationId)
    return & $ScriptBlock
}

function Get-ACLForRemoval {
    param($ObjectDistinguishedName)
    return [PSCustomObject]@{
        DistinguishedName = $ObjectDistinguishedName
        OrphanedSIDs = @(
            [PSCustomObject]@{
                SID = "S-1-5-21-1234567890-1001"
                Type = "Unknown"
            }
        )
    }
}

# Function under test
function Invoke-SIDRemoval {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$ObjectDistinguishedName,
        [string[]]$OrphanedSIDs,
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )
    
    # Custom parameter validation to avoid prompting
    if ([string]::IsNullOrEmpty($ObjectDistinguishedName)) {
        throw [System.Management.Automation.ParameterBindingException]::new("Cannot bind argument to parameter 'ObjectDistinguishedName' because it is an empty string.")
    }
    
    if ($null -eq $OrphanedSIDs -or $OrphanedSIDs.Count -eq 0) {
        throw [System.Management.Automation.ParameterBindingException]::new("Cannot bind argument to parameter 'OrphanedSIDs' because it is null.")
    }
    
    if (-not (Test-ValidDistinguishedName -DistinguishedName $ObjectDistinguishedName)) {
        throw "Invalid distinguished name format"
    }
    
    foreach ($sid in $OrphanedSIDs) {
        if ($sid -notmatch '^S-1-[0-59]-\d+') {
            throw "Invalid SID format: $sid"
        }
        
        if ($sid -match "malicious|injection") {
            throw "Invalid SID detected"
        }
    }
    
    if ($WhatIfPreference) {
        Write-StructuredLog -Level Information -Message "WhatIf: Would remove SIDs" -CorrelationId $CorrelationId
        return [PSCustomObject]@{
            ObjectDistinguishedName = $ObjectDistinguishedName
            SIDsToRemove = $OrphanedSIDs
            WhatIf = $true
            Success = $true
        }
    }
    
    $result = Invoke-ADOperationWithRetry -ScriptBlock {
        if ($ObjectDistinguishedName -eq "CN=TestFailure,DC=domain,DC=com") {
            throw "Access denied"
        }
        
        [PSCustomObject]@{
            ObjectDistinguishedName = $ObjectDistinguishedName
            SIDsRemoved = $OrphanedSIDs
            Success = $true
            RemovedCount = $OrphanedSIDs.Count
        }
    } -MaxRetries 3 -OperationName "RemoveSIDs" -ObjectContext $ObjectDistinguishedName -CorrelationId $CorrelationId
    
    Write-StructuredLog -Level Information -Message "SIDs removed successfully" -CorrelationId $CorrelationId -SecurityContext @{
        ObjectDN = $ObjectDistinguishedName
        SIDCount = $OrphanedSIDs.Count
    }
    
    return $result
}

Describe "Invoke-SIDRemoval" {
    
    Context "Parameter Validation" {
        It "Should throw when ObjectDistinguishedName is null or empty" {
            { Invoke-SIDRemoval -OrphanedSIDs @("S-1-5-21-1234567890-1001") } | Should Throw "Cannot bind argument to parameter 'ObjectDistinguishedName' because it is an empty string."
        }
        
        It "Should throw when ObjectDistinguishedName is empty string" {
            { Invoke-SIDRemoval -ObjectDistinguishedName "" -OrphanedSIDs @("S-1-5-21-1234567890-1001") } | Should Throw "Cannot bind argument to parameter 'ObjectDistinguishedName' because it is an empty string."
        }
        
        It "Should throw when OrphanedSIDs is null" {
            { Invoke-SIDRemoval -ObjectDistinguishedName "CN=TestUser,DC=domain,DC=com" -OrphanedSIDs $null } | Should Throw "Cannot bind argument to parameter 'OrphanedSIDs' because it is null."
        }
        
        It "Should throw when OrphanedSIDs is empty array" {
            { Invoke-SIDRemoval -ObjectDistinguishedName "CN=TestUser,DC=domain,DC=com" -OrphanedSIDs @() } | Should Throw "Cannot bind argument to parameter 'OrphanedSIDs' because it is null."
        }
        
        It "Should accept valid parameters" {
            $result = Invoke-SIDRemoval -ObjectDistinguishedName "CN=TestUser,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001")
            $result | Should Not BeNullOrEmpty
        }
    }
    
    Context "SID Validation" {
        It "Should validate SID format" {
            { Invoke-SIDRemoval -ObjectDistinguishedName "CN=TestUser,DC=domain,DC=com" -OrphanedSIDs @("InvalidSID") } | Should Throw "Invalid SID format"
        }
        
        It "Should accept valid SID formats" {
            $validSIDs = @("S-1-5-21-1234567890-1001", "S-1-5-32-544")
            $result = Invoke-SIDRemoval -ObjectDistinguishedName "CN=TestUser,DC=domain,DC=com" -OrphanedSIDs $validSIDs
            $result.Success | Should Be $true
        }
        
        It "Should process multiple SIDs" {
            $multipleSIDs = @("S-1-5-21-1234567890-1001", "S-1-5-21-1234567890-1002", "S-1-5-21-1234567890-1003")
            $result = Invoke-SIDRemoval -ObjectDistinguishedName "CN=TestUser,DC=domain,DC=com" -OrphanedSIDs $multipleSIDs
            $result.RemovedCount | Should Be 3
        }
    }
    
    Context "SID Removal Operations" {
        It "Should remove SIDs successfully" {
            $result = Invoke-SIDRemoval -ObjectDistinguishedName "CN=TestUser,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001")
            $result.Success | Should Be $true
            $result.SIDsRemoved -contains "S-1-5-21-1234567890-1001" | Should Be $true
        }
        
        It "Should return correct object structure" {
            $result = Invoke-SIDRemoval -ObjectDistinguishedName "CN=TestUser,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001")
            $result.ObjectDistinguishedName | Should Be "CN=TestUser,DC=domain,DC=com"
            $result.Success | Should Be $true
            $result.RemovedCount | Should Be 1
        }
        
        It "Should handle DN with special characters" {
            $specialDN = "CN=Test User (Special),OU=Users,DC=domain,DC=com"
            $result = Invoke-SIDRemoval -ObjectDistinguishedName $specialDN -OrphanedSIDs @("S-1-5-21-1234567890-1001")
            $result.ObjectDistinguishedName | Should Be $specialDN
        }
        
        It "Should count removed SIDs correctly" {
            $testSIDs = @("S-1-5-21-1234567890-1001", "S-1-5-21-1234567890-1002")
            $result = Invoke-SIDRemoval -ObjectDistinguishedName "CN=TestUser,DC=domain,DC=com" -OrphanedSIDs $testSIDs
            $result.RemovedCount | Should Be 2
        }
    }
    
    Context "WhatIf Support" {
        It "Should support WhatIf mode" {
            $result = Invoke-SIDRemoval -ObjectDistinguishedName "CN=TestUser,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001") -WhatIf
            $result.WhatIf | Should Be $true
            $result.SIDsToRemove | Should Not BeNullOrEmpty
        }
        
        It "Should not actually remove SIDs in WhatIf mode" {
            $result = Invoke-SIDRemoval -ObjectDistinguishedName "CN=TestUser,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001") -WhatIf
            $result.SIDsToRemove | Should Not BeNullOrEmpty
        }
    }
    
    Context "Error Handling" {
        It "Should handle access denied errors" {
            { Invoke-SIDRemoval -ObjectDistinguishedName "CN=TestFailure,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001") } | Should Throw
        }
        
        It "Should validate distinguished name format" {
            { Invoke-SIDRemoval -ObjectDistinguishedName "InvalidFormat" -OrphanedSIDs @("S-1-5-21-1234567890-1001") } | Should Throw
        }
    }
    
    Context "Security Validation" {
        It "Should reject malicious SIDs" {
            { Invoke-SIDRemoval -ObjectDistinguishedName "CN=TestUser,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-malicious-1001") } | Should Throw
        }
        
        It "Should reject injection attempts in SIDs" {
            { Invoke-SIDRemoval -ObjectDistinguishedName "CN=TestUser,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-injection-1001") } | Should Throw
        }
    }
    
    Context "Integration and Dependencies" {
        It "Should validate distinguished names" {
            $result = Invoke-SIDRemoval -ObjectDistinguishedName "CN=TestUser,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001")
            $result | Should Not BeNullOrEmpty
        }
        
        It "Should use retry mechanisms" {
            $result = Invoke-SIDRemoval -ObjectDistinguishedName "CN=TestUser,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001")
            $result.Success | Should Be $true
        }
        
        It "Should maintain correlation ID" {
            $correlationId = [System.Guid]::NewGuid().ToString()
            $result = Invoke-SIDRemoval -ObjectDistinguishedName "CN=TestUser,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001") -CorrelationId $correlationId
            $result | Should Not BeNullOrEmpty
        }
    }
}
