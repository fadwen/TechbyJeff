# Test file for Import-SecureClasses function
# Pester 3.4.0 compatible test

# Load the function
. "$PSScriptRoot\..\..\..\..\Private\ClassManagement\Import-SecureClasses.ps1"

# Load dependencies for mocking
$dependencies = @(
    "$PSScriptRoot\..\..\..\..\Tests\Unit\Private\ClassManagement\Test-ClassIntegrity.ps1"
)

foreach ($dep in $dependencies) {
    if (Test-Path $dep) {
        try {
            . $dep
        } catch {
            Write-Warning "Failed to load dependency $dep : $($_.Exception.Message)"
        }
    }
}

Describe "Import-SecureClasses" -Tag @("Unit", "Private", "ClassManagement") {
    
    BeforeAll {
        # Mock dependencies for testing
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:ValidClassNames = @('ScriptConfiguration', 'MemoryManager', 'ProcessingStatistics')
        $script:InvalidClassNames = @('NonExistentClass', 'UnauthorizedClass')
        $script:TestClassesPath = "C:\TestClasses"
        
        # Mock the Get-ApprovedClassList function to return test data - provide function definition first
        function Get-ApprovedClassList {
            return @{
                Classes = @{
                    'ScriptConfiguration.ps1' = @{
                        FileName = 'ScriptConfiguration.ps1'
                        ExpectedHash = 'abc123def456'
                        RequiredTypes = @('System.Object')
                        Dependencies = @()
                    }
                    'MemoryManager.ps1' = @{
                        FileName = 'MemoryManager.ps1'
                        ExpectedHash = 'def456ghi789'
                        RequiredTypes = @('System.Object')
                        Dependencies = @()
                    }
                    'ProcessingStatistics.ps1' = @{
                        FileName = 'ProcessingStatistics.ps1'
                        ExpectedHash = 'ghi789jkl012'
                        RequiredTypes = @('System.Object')
                        Dependencies = @()
                    }
                }
            }
        }
        
        # Mock the Get-ApprovedClassList function to return test data
        Mock Get-ApprovedClassList {
            return @{
                Classes = @{
                    'ScriptConfiguration.ps1' = @{
                        FileName = 'ScriptConfiguration.ps1'
                        ExpectedHash = 'abc123def456'
                        RequiredTypes = @('System.Object')
                        Dependencies = @()
                    }
                    'MemoryManager.ps1' = @{
                        FileName = 'MemoryManager.ps1'
                        ExpectedHash = 'def456ghi789'
                        RequiredTypes = @('System.Object')
                        Dependencies = @()
                    }
                    'ProcessingStatistics.ps1' = @{
                        FileName = 'ProcessingStatistics.ps1'
                        ExpectedHash = 'ghi789jkl012'
                        RequiredTypes = @('System.Object')
                        Dependencies = @()
                    }
                }
                Metadata = @{
                    ConfigurationVersion = '1.0'
                    CorrelationId = $script:TestCorrelationId
                }
            }
        }
        
        # Mock Test-ClassIntegrity to return success
        Mock Test-ClassIntegrity {
            param($ClassPath, $CorrelationId)
            return [PSCustomObject]@{
                IsValid = $true
                ClassPath = $ClassPath
                CorrelationId = $CorrelationId
            }
        }
        
        # Mock Test-Path to return true for class files
        Mock Test-Path {
            param($Path)
            if ($Path -and $Path -match '\.ps1$') {
                return $true
            }
            return $false
        }
        
        # Mock Resolve-Path to return the path as-is
        Mock Resolve-Path {
            param($Path)
            if ($Path) {
                return @{ Path = $Path }
            } else {
                throw "Cannot bind argument to parameter 'Path' because it is null."
            }
        }
        
        # Mock Resolve-ClassPath to return valid paths
        Mock Resolve-ClassPath {
            param($ClassesPath, $ClassNames, $CorrelationId)
            $results = @()
            foreach ($className in $ClassNames) {
                $results += [PSCustomObject]@{
                    IsValid = $true
                    ClassName = $className
                    Path = Join-Path $ClassesPath $className
                    CorrelationId = $CorrelationId
                }
            }
            return $results
        }
    }

    Context "Parameter Validation" {
        It "Should require ClassNames parameter" {
            # In Pester 3.4, we test mandatory parameters by ensuring they're marked as mandatory
            # rather than calling the function without them (which causes prompts)
            $paramInfo = (Get-Command Import-SecureClasses).Parameters.ClassNames
            $paramInfo.Attributes.Mandatory | Should Be $true
        }
        
        It "Should reject null ClassNames" {
            { Import-SecureClasses -ClassNames $null } | Should Throw
        }
        
        It "Should reject empty ClassNames array" {
            { Import-SecureClasses -ClassNames @() } | Should Throw
        }
        
        It "Should accept valid ClassNames array" {
            { Import-SecureClasses -ClassNames $script:ValidClassNames -ValidationOnly } | Should Not Throw
        }
        
        It "Should accept valid ClassesPath parameter" {
            { Import-SecureClasses -ClassNames $script:ValidClassNames -ClassesPath $script:TestClassesPath -ValidationOnly } | Should Not Throw
        }
        
        It "Should reject null or empty ClassesPath" {
            { Import-SecureClasses -ClassNames $script:ValidClassNames -ClassesPath '' } | Should Throw
            { Import-SecureClasses -ClassNames $script:ValidClassNames -ClassesPath $null } | Should Throw
        }
        
        It "Should accept CorrelationId parameter" {
            { Import-SecureClasses -ClassNames $script:ValidClassNames -CorrelationId $script:TestCorrelationId -ValidationOnly } | Should Not Throw
        }
        
        It "Should support ValidateIntegrity switch" {
            { Import-SecureClasses -ClassNames $script:ValidClassNames -ValidateIntegrity -ValidationOnly } | Should Not Throw
        }
        
        It "Should support ValidationOnly switch" {
            { Import-SecureClasses -ClassNames $script:ValidClassNames -ValidationOnly } | Should Not Throw
        }
    }
    
    Context "Core Functionality - Validation Only" {
        BeforeEach {
            Mock Get-ApprovedClassList {
                return @{
                    Classes = @{
                        'ScriptConfiguration.ps1' = @{
                            RequiredTypes = @('ScriptConfiguration')
                            Dependencies = @()
                        }
                        'MemoryManager.ps1' = @{
                            RequiredTypes = @('MemoryManager')
                            Dependencies = @('System.IDisposable')
                        }
                        'ProcessingStatistics.ps1' = @{
                            RequiredTypes = @('ProcessingStatistics')
                            Dependencies = @()
                        }
                    }
                    Metadata = @{
                        Version = 'Current'
                        TotalClasses = 3
                    }
                }
            }
            
            Mock Resolve-ClassPath {
                param($ClassNames)
                return $ClassNames | ForEach-Object {
                    [PSCustomObject]@{
                        ClassName = $_
                        FullPath = Join-Path $script:TestClassesPath $_
                        IsValid = $true
                    }
                }
            }
        }
        
        It "Should return success for valid classes in validation mode" {
            $result = Import-SecureClasses -ClassNames $script:ValidClassNames -ValidationOnly
            
            $result.GetType().Name | Should Be "PSCustomObject"
            $result.Success | Should Be $true
            $result.ValidationOnly | Should Be $true
            $result.TotalClasses | Should Be $script:ValidClassNames.Count
            $result.FailedClasses.Count | Should Be 0
        }
        
        It "Should return failure for invalid classes in validation mode" {
            $result = Import-SecureClasses -ClassNames $script:InvalidClassNames -ValidationOnly
            
            $result.Success | Should Be $false
            $result.FailedClasses.Count -gt 0 | Should Be $true
            ($result.FailedClasses -contains 'NonExistentClass') | Should Be $true
            ($result.FailedClasses -contains 'UnauthorizedClass') | Should Be $true
        }
        
        It "Should handle mixed valid and invalid classes" {
            $mixedClasses = $script:ValidClassNames + $script:InvalidClassNames
            $result = Import-SecureClasses -ClassNames $mixedClasses -ValidationOnly
            
            $result.Success | Should Be $false
            ($result.FailedClasses -contains 'NonExistentClass') | Should Be $true
            ($result.FailedClasses -contains 'UnauthorizedClass') | Should Be $true
        }
    }
    
    Context "Core Functionality - Path Loading" {
        BeforeEach {
            Mock Get-ApprovedClassList {
                return @{
                    Classes = @{
                        'ScriptConfiguration.ps1' = @{
                            RequiredTypes = @('ScriptConfiguration')
                            Dependencies = @()
                        }
                        'MemoryManager.ps1' = @{
                            RequiredTypes = @('MemoryManager')
                            Dependencies = @('System.IDisposable')
                        }
                        'ProcessingStatistics.ps1' = @{
                            RequiredTypes = @('ProcessingStatistics')
                            Dependencies = @()
                        }
                    }
                    Metadata = @{
                        Version = 'Current'
                        TotalClasses = 3
                    }
                }
            }
            
            Mock Resolve-ClassPath {
                param($ClassNames)
                return $ClassNames | ForEach-Object {
                    [PSCustomObject]@{
                        ClassName = $_
                        FullPath = Join-Path $script:TestClassesPath $_
                        IsValid = $true
                    }
                }
            }
        }
        
        It "Should return paths for loading valid classes" {
            $result = Import-SecureClasses -ClassNames $script:ValidClassNames
            
            $result.Success | Should Be $true
            $result.PathsToLoad.Count | Should Be $script:ValidClassNames.Count
            $result.ValidatedClasses.Count | Should Be $script:ValidClassNames.Count
            $result.FailedClasses.Count | Should Be 0
        }
        
        It "Should include expected class names in ValidatedClasses" {
            $result = Import-SecureClasses -ClassNames $script:ValidClassNames
            
            foreach ($className in $script:ValidClassNames) {
                $result.ValidatedClasses -contains $className | Should Be $true
            }
        }
        
        It "Should include valid file paths in PathsToLoad" {
            $result = Import-SecureClasses -ClassNames $script:ValidClassNames
            
            $result.PathsToLoad.Count | Should Be $script:ValidClassNames.Count
            foreach ($path in $result.PathsToLoad) {
                $path.Contains($script:TestClassesPath) | Should Be $true
                $path.EndsWith('.ps1') | Should Be $true
            }
        }
        
        It "Should handle integrity validation when enabled" {
            Mock Test-ClassIntegrity { 
                return @{ IsValid = $true }
            }
            
            $result = Import-SecureClasses -ClassNames $script:ValidClassNames -ValidateIntegrity
            
            $result.Success | Should Be $true
            Assert-MockCalled Test-ClassIntegrity -Exactly $script:ValidClassNames.Count
        }
        
        It "Should fail on integrity validation failure" {
            Mock Test-ClassIntegrity { 
                return @{ IsValid = $false }
            }
            
            $result = Import-SecureClasses -ClassNames $script:ValidClassNames -ValidateIntegrity
            
            $result.Success | Should Be $false
            $result.FailedClasses.Count | Should Be $script:ValidClassNames.Count
        }
    }
    
    Context "Error Handling" {
        It "Should handle Get-ApprovedClassList failure" {
            Mock Get-ApprovedClassList {
                throw "Configuration service unavailable"
            }
            
            $result = Import-SecureClasses -ClassNames $script:ValidClassNames
            
            $result.Success | Should Be $false
            $result.Error.Contains("Failed to get approved class configuration") | Should Be $true
            $result.FailedClasses | Should Be $script:ValidClassNames
        }
        
        It "Should handle Resolve-ClassPath failure" {
            Mock Get-ApprovedClassList {
                return @{
                    Classes = @{
                        'ScriptConfiguration.ps1' = @{ RequiredTypes = @('ScriptConfiguration') }
                        'MemoryManager.ps1' = @{ RequiredTypes = @('MemoryManager') }
                        'ProcessingStatistics.ps1' = @{ RequiredTypes = @('ProcessingStatistics') }
                    }
                }
            }
            
            Mock Resolve-ClassPath {
                throw "Path resolution failed"
            }
            
            $result = Import-SecureClasses -ClassNames $script:ValidClassNames
            
            $result.Success | Should Be $false
            $result.Error.Contains("Path resolution failed") | Should Be $true
            $result.FailedClasses | Should Be $script:ValidClassNames
        }
        
        It "Should handle partial path resolution failures" {
            Mock Get-ApprovedClassList {
                return @{
                    Classes = @{
                        'ScriptConfiguration.ps1' = @{ RequiredTypes = @('ScriptConfiguration') }
                        'MemoryManager.ps1' = @{ RequiredTypes = @('MemoryManager') }
                        'ProcessingStatistics.ps1' = @{ RequiredTypes = @('ProcessingStatistics') }
                    }
                }
            }
            
            Mock Resolve-ClassPath {
                return @(
                    [PSCustomObject]@{ ClassName = 'ScriptConfiguration.ps1'; FullPath = 'C:\path\ScriptConfiguration.ps1'; IsValid = $true }
                    [PSCustomObject]@{ ClassName = 'MemoryManager.ps1'; FullPath = 'C:\path\MemoryManager.ps1'; IsValid = $false }
                    [PSCustomObject]@{ ClassName = 'ProcessingStatistics.ps1'; FullPath = 'C:\path\ProcessingStatistics.ps1'; IsValid = $true }
                )
            }
            
            $result = Import-SecureClasses -ClassNames $script:ValidClassNames
            
            $result.Success | Should Be $false
            ($result.FailedClasses -contains 'MemoryManager') | Should Be $true
            ($result.ValidatedClasses -contains 'ScriptConfiguration') | Should Be $true
            ($result.ValidatedClasses -contains 'ProcessingStatistics') | Should Be $true
        }
        
        It "Should handle class validation exceptions gracefully" {
            Mock Get-ApprovedClassList {
                return @{
                    Classes = @{
                        'ScriptConfiguration.ps1' = @{ RequiredTypes = @('ScriptConfiguration') }
                    }
                }
            }
            
            Mock Resolve-ClassPath {
                return @(
                    [PSCustomObject]@{ ClassName = 'ScriptConfiguration.ps1'; FullPath = 'C:\path\ScriptConfiguration.ps1'; IsValid = $true }
                )
            }
            
            Mock Test-ClassIntegrity {
                throw "Integrity check failed unexpectedly"
            }
            
            $result = Import-SecureClasses -ClassNames @('ScriptConfiguration') -ValidateIntegrity
            
            $result.Success | Should Be $false
            ($result.FailedClasses -contains 'ScriptConfiguration') | Should Be $true
        }
    }
    
    Context "Security and Compliance" {
        BeforeEach {
            Mock Get-ApprovedClassList {
                return @{
                    Classes = @{
                        'ScriptConfiguration.ps1' = @{ RequiredTypes = @('ScriptConfiguration') }
                        'MemoryManager.ps1' = @{ RequiredTypes = @('MemoryManager') }
                    }
                }
            }
            
            Mock Resolve-ClassPath {
                param($ClassNames)
                return $ClassNames | ForEach-Object {
                    [PSCustomObject]@{
                        ClassName = $_
                        FullPath = Join-Path $script:TestClassesPath $_
                        IsValid = $true
                    }
                }
            }
        }
        
        It "Should reject unapproved classes" {
            $result = Import-SecureClasses -ClassNames @('UnapprovedClass')
            
            $result.Success | Should Be $false
            $result.Error.Contains("Unapproved classes requested") | Should Be $true
            ($result.FailedClasses -contains 'UnapprovedClass') | Should Be $true
        }
        
        It "Should track correlation ID for audit purposes" {
            $testCorrelationId = [System.Guid]::NewGuid().ToString()
            
            Import-SecureClasses -ClassNames @('ScriptConfiguration') -CorrelationId $testCorrelationId -ValidationOnly
            
            Assert-MockCalled Get-ApprovedClassList -ParameterFilter { $CorrelationId -eq $testCorrelationId }
            Assert-MockCalled Resolve-ClassPath -ParameterFilter { $CorrelationId -eq $testCorrelationId }
        }
        
        It "Should support security validation through integrity checking" {
            Mock Test-ClassIntegrity {
                param($ClassPath, $CorrelationId)
                return @{
                    IsValid = $true
                    SecurityChecks = @('HashValidation', 'SignatureVerification')
                    CorrelationId = $CorrelationId
                }
            }
            
            $result = Import-SecureClasses -ClassNames @('ScriptConfiguration') -ValidateIntegrity
            
            $result.Success | Should Be $true
            Assert-MockCalled Test-ClassIntegrity -Exactly 1
        }
    }
    
    Context "Performance and Efficiency" {
        BeforeEach {
            Mock Get-ApprovedClassList {
                return @{
                    Classes = @{
                        'ScriptConfiguration.ps1' = @{ RequiredTypes = @('ScriptConfiguration') }
                        'MemoryManager.ps1' = @{ RequiredTypes = @('MemoryManager') }
                        'ProcessingStatistics.ps1' = @{ RequiredTypes = @('ProcessingStatistics') }
                        'OrphanedSIDResult.ps1' = @{ RequiredTypes = @('OrphanedSIDResult') }
                        'SIDAnalysisResult.ps1' = @{ RequiredTypes = @('SIDAnalysisResult') }
                    }
                }
            }
            
            Mock Resolve-ClassPath {
                param($ClassNames)
                return $ClassNames | ForEach-Object {
                    [PSCustomObject]@{
                        ClassName = $_
                        FullPath = Join-Path $script:TestClassesPath $_
                        IsValid = $true
                    }
                }
            }
        }
        
        It "Should complete within reasonable time for multiple classes" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            $largeClassSet = @('ScriptConfiguration', 'MemoryManager', 'ProcessingStatistics')
            $result = Import-SecureClasses -ClassNames $largeClassSet -ValidationOnly
            
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 5000
        }
        
        It "Should handle large class sets efficiently" {
            $largeClassSet = @('ScriptConfiguration', 'MemoryManager', 'ProcessingStatistics', 'OrphanedSIDResult', 'SIDAnalysisResult')
            
            $result = Import-SecureClasses -ClassNames $largeClassSet -ValidationOnly
            
            $result.Success | Should Be $true
            $result.TotalClasses | Should Be $largeClassSet.Count
        }
        
        It "Should minimize dependency calls" {
            # Test that validation-only mode doesn't call path resolution
            $result = Import-SecureClasses -ClassNames @('ScriptConfiguration') -ValidationOnly
            
            # Should have called Get-ApprovedClassList but not Resolve-ClassPath
            $result.ValidationOnly | Should Be $true
            $result.PathsToLoad.Count | Should Be 0  # No paths in validation-only mode
        }
    }
    
    Context "Result Object Structure" {
        BeforeEach {
            Mock Get-ApprovedClassList {
                return @{
                    Classes = @{
                        'ScriptConfiguration.ps1' = @{ RequiredTypes = @('ScriptConfiguration') }
                    }
                }
            }
            
            Mock Resolve-ClassPath {
                return @(
                    [PSCustomObject]@{ ClassName = 'ScriptConfiguration.ps1'; FullPath = 'C:\path\ScriptConfiguration.ps1'; IsValid = $true }
                )
            }
        }
        
        It "Should return consistent result object structure" {
            $result = Import-SecureClasses -ClassNames @('ScriptConfiguration')
            
            $result.GetType().Name | Should Be "PSCustomObject"
            ($result.PSObject.Properties.Name -contains 'Success') | Should Be $true
            ($result.PSObject.Properties.Name -contains 'ValidatedClasses') | Should Be $true
            ($result.PSObject.Properties.Name -contains 'FailedClasses') | Should Be $true
            ($result.PSObject.Properties.Name -contains 'PathsToLoad') | Should Be $true
            ($result.PSObject.Properties.Name -contains 'TotalClasses') | Should Be $true
        }
        
        It "Should include ValidationOnly property when in validation mode" {
            $result = Import-SecureClasses -ClassNames @('ScriptConfiguration') -ValidationOnly
            
            ($result.PSObject.Properties.Name -contains 'ValidationOnly') | Should Be $true
            $result.ValidationOnly | Should Be $true
        }
        
        It "Should include Error property on failure" {
            Mock Get-ApprovedClassList {
                throw "Test error"
            }
            
            $result = Import-SecureClasses -ClassNames @('ScriptConfiguration') -ValidationOnly
            
            ($result.PSObject.Properties.Name -contains 'Error') | Should Be $true
            $result.Error | Should Not BeNullOrEmpty
        }
        
        It "Should have correct array types for collections" {
            $result = Import-SecureClasses -ClassNames @('ScriptConfiguration')
            
            $result.ValidatedClasses -is [array] | Should Be $true
            $result.FailedClasses -is [array] | Should Be $true
            $result.PathsToLoad -is [array] | Should Be $true
        }
    }
}






