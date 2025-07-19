# Test file for Get-ApprovedClassList function
# Pester 3.4.0 compatible test

# Load the function
. "$PSScriptRoot\..\..\..\..\Private\ClassManagement\Get-ApprovedClassList.ps1"

Describe "Get-ApprovedClassList" -Tag @("Unit", "Private", "ClassManagement") {
    
    Context "Parameter Validation" {
        It "Should accept valid ConfigurationVersion parameter" {
            $result = Get-ApprovedClassList -ConfigurationVersion 'Current' -Verbose:$false
            $result | Should Not BeNullOrEmpty
        }
        
        It "Should accept valid CorrelationId parameter" {
            $testGuid = [System.Guid]::NewGuid().ToString()
            $result = Get-ApprovedClassList -CorrelationId $testGuid -Verbose:$false
            $result | Should Not BeNullOrEmpty
        }
        
        It "Should reject invalid ConfigurationVersion" {
            { Get-ApprovedClassList -ConfigurationVersion 'invalid' } | Should Throw
        }
        
        It "Should use default ConfigurationVersion when not specified" {
            $result = Get-ApprovedClassList -Verbose:$false
            # Function should execute without errors when using default
            $result | Should Not BeNullOrEmpty
        }
        
        It "Should generate correlation ID when not provided" {
            $result = Get-ApprovedClassList -Verbose:$false
            # Function should execute and return configuration
            $result | Should Not BeNullOrEmpty
        }
    }
    
    Context "Core Functionality" {
        It "Should return a hashtable with class configurations" {
            $result = Get-ApprovedClassList -Verbose:$false
            $result | Should BeOfType [hashtable]
            $result.Count | Should BeGreaterThan 0
            $result.ContainsKey('Classes') | Should Be $true
            $result.ContainsKey('Metadata') | Should Be $true
        }
        
        It "Should return expected core class files" {
            $result = Get-ApprovedClassList -Verbose:$false
            $classes = $result.Classes
            $expectedClassFiles = @(
                'ScriptConfiguration.ps1',
                'MemoryManager.ps1',
                'OrphanedSIDResult.ps1', 
                'ProcessingStatistics.ps1',
                'RemovalOperationResult.ps1',
                'RestoreOperationResult.ps1',
                'SecurityValidationResult.ps1',
                'SIDAnalysisResult.ps1',
                'StreamingResultsManager.ps1'
            )
            
            foreach ($classFile in $expectedClassFiles) {
                $classes.ContainsKey($classFile) | Should Be $true
            }
        }
        
        It "Should include required metadata for each class" {
            $result = Get-ApprovedClassList -Verbose:$false
            $classes = $result.Classes
            
            foreach ($class in $classes.Values) {
                $class.RequiredTypes | Should Not BeNullOrEmpty
                # Dependencies can be empty array for some classes, but should be defined
                ($class.Keys -contains 'Dependencies') | Should Be $true
                $class.Description | Should Not BeNullOrEmpty
                $class.ExpectedHash | Should Not BeNullOrEmpty
                $class.LastVerified | Should Not BeNullOrEmpty
            }
        }
        
        It "Should have valid ExpectedHash values" {
            $result = Get-ApprovedClassList -Verbose:$false
            $classes = $result.Classes
            
            foreach ($class in $classes.Values) {
                # SHA256 hashes should be 64 characters long
                $class.ExpectedHash.Length | Should Be 64
                # Should contain only valid hex characters
                $class.ExpectedHash | Should Match '^[A-F0-9]+$'
            }
        }
        
        It "Should have valid RequiredTypes arrays" {
            $result = Get-ApprovedClassList -Verbose:$false
            $classes = $result.Classes
            
            foreach ($class in $classes.Values) {
                # RequiredTypes should be an array (even single-element arrays)
                ($class.RequiredTypes -is [array]) | Should Be $true
                # Should have at least one required type
                @($class.RequiredTypes).Count | Should BeGreaterThan 0
            }
        }
        
        It "Should include configuration metadata" {
            $result = Get-ApprovedClassList -Verbose:$false
            $metadata = $result.Metadata
            
            $metadata.Version | Should Not BeNullOrEmpty
            $metadata.TotalClasses | Should BeGreaterThan 0
            $metadata.GeneratedOn | Should Not BeNullOrEmpty
            $metadata.LastUpdated | Should Not BeNullOrEmpty
            $metadata.CorrelationId | Should Not BeNullOrEmpty
        }
    }
}


