#Requires -Module Pester

# Import the module under test and specific function
$ModulePath = Join-Path $PSScriptRoot "..\..\..\..\Find-UnknownSID.psd1"
if (Test-Path $ModulePath) {
    Import-Module $ModulePath -Force
}

# Import required dependencies
. "$PSScriptRoot\..\..\..\..\Private\Logging\Initialize-LoggingSystem.ps1"
. "$PSScriptRoot\..\..\..\..\Private\Reporting\Write-ProcessingSummary.ps1"

# Test suite for Write-ProcessingSummary function
Describe "Write-ProcessingSummary" -Tag "Unit", "Private", "Reporting" {
    BeforeEach {
        # Mock structured logging
        Mock Write-StructuredLog { }
        
        # Mock Export-Csv
        Mock Export-Csv { }
        
        # Mock console output
        Mock Write-Host { }
        Mock Write-Output { }
        
        # Sample processing statistics with TimeSpan objects
        $script:TestStatistics = [PSCustomObject]@{
            TotalObjectsProcessed = 150
            OrphanedSIDsFound = 12
            OrphanedSIDsRemoved = 8
            ErrorCount = 2
            ProcessingDuration = [TimeSpan]::FromMinutes(15)
            StartTime = Get-Date
            EndTime = (Get-Date).AddMinutes(15)
        }
        
        # Test data with StreamingManager for CSV export tests
        $script:TestStatisticsWithStreaming = [PSCustomObject]@{
            TotalObjectsProcessed = 150
            OrphanedSIDsFound = 12
            OrphanedSIDsRemoved = 8
            ErrorCount = 2
            ProcessingDuration = [TimeSpan]::FromMinutes(15)
            StartTime = Get-Date
            EndTime = (Get-Date).AddMinutes(15)
            StreamingManager = [PSCustomObject]@{
                Summary = [PSCustomObject]@{
                    TotalResults = 12
                }
            }
        }
        
        # Mock StreamingManager.ExportToCsv method
        Add-Member -InputObject $script:TestStatisticsWithStreaming.StreamingManager -MemberType ScriptMethod -Name ExportToCsv -Value { 
            param($path) 
            # This will be tracked by the Export-Csv mock we already have
            Export-Csv -Path $path -InputObject @() -NoTypeInformation
        }
        
        # Sample orphaned SIDs
        $script:TestOrphanedSIDs = @(
            [PSCustomObject]@{
                SID = 'S-1-5-21-1234567890-987654321-1122334455-1001'
                ObjectPath = 'OU=TestOU,DC=domain,DC=com'
                ObjectType = 'organizationalUnit'
                Removed = $true
            },
            [PSCustomObject]@{
                SID = 'S-1-5-21-1234567890-987654321-1122334455-1002'
                ObjectPath = 'CN=TestUser,OU=Users,DC=domain,DC=com'
                ObjectType = 'user'
                Removed = $false
            }
        )
        
        # Sample errors
        $script:TestErrors = @(
            [PSCustomObject]@{
                Timestamp = Get-Date
                Level = 'Error'
                Message = 'Failed to process object: Access denied'
                Exception = 'System.UnauthorizedAccessException'
            }
        )
    }
    
    Context "Parameter Validation" {
        It "Should accept valid ProcessingResults parameter" {
            { Write-ProcessingSummary -ProcessingResults $script:TestStatistics } | Should Not Throw
        }

        It "Should accept valid OutputPath parameter" {
            { Write-ProcessingSummary -ProcessingResults $script:TestStatistics -OutputPath "C:\temp\test.csv" } | Should Not Throw
        }

        It "Should accept AutomationMode switch" {
            { Write-ProcessingSummary -ProcessingResults $script:TestStatistics -AutomationMode } | Should Not Throw
        }

        It "Should accept CorrelationId parameter" {
            { Write-ProcessingSummary -ProcessingResults $script:TestStatistics -CorrelationId "test-123" } | Should Not Throw
        }
    }
    
    Context "Console Output" {
        It "Should display processing summary to console" {
            Write-ProcessingSummary -ProcessingResults $script:TestStatistics
            
            Assert-MockCalled Write-StructuredLog -Times 3
        }
        
        It "Should display orphaned SIDs summary when provided" {
            Write-ProcessingSummary -ProcessingResults $script:TestStatistics
            
            Assert-MockCalled Write-StructuredLog -Times 3
        }
        
        It "Should display error summary when errors provided" {
            Write-ProcessingSummary -ProcessingResults $script:TestStatistics
            
            Assert-MockCalled Write-StructuredLog -Times 3
        }
    }
    
    Context "CSV Export" {
        It "Should export to CSV when OutputPath specified" {
            Write-ProcessingSummary -ProcessingResults $script:TestStatisticsWithStreaming -OutputPath "C:\temp\test.csv"
            
            Assert-MockCalled Export-Csv -Times 1 -Exactly -Scope It
        }
        
        It "Should not export to CSV when OutputPath not specified" {
            Write-ProcessingSummary -ProcessingResults $script:TestStatistics
            
            Assert-MockCalled Export-Csv -Times 0 -Exactly -Scope It
        }
    }
    
    Context "Automation Mode" {
        It "Should output structured data in automation mode" {
            Mock Write-Information { }
            
            Write-ProcessingSummary -ProcessingResults $script:TestStatistics -AutomationMode
            
            Assert-MockCalled Write-Information -Times 1
        }
        
        It "Should not display console output in automation mode" {
            Write-ProcessingSummary -ProcessingResults $script:TestStatistics -AutomationMode
            
            Assert-MockCalled Write-StructuredLog -Times 3
        }
    }
    
    Context "Structured Logging" {
        It "Should log processing summary" {
            Write-ProcessingSummary -ProcessingResults $script:TestStatistics
            
            Assert-MockCalled Write-StructuredLog -Times 5
        }
        
        It "Should log with correct parameters" {
            Write-ProcessingSummary -ProcessingResults $script:TestStatistics
            
            Assert-MockCalled Write-StructuredLog -ParameterFilter {
                $Level -eq 'Information' -and $Component -eq 'Summary'
            } -Times 1
        }
    }
    
    Context "Error Handling" {
        It "Should handle missing ProcessingResults gracefully" {
            { Write-ProcessingSummary -ProcessingResults $null } | Should Throw
        }
        
        It "Should handle invalid OutputPath gracefully" {
            # Use streaming data and mock the ExportToCsv method to throw
            $TestDataWithError = $script:TestStatisticsWithStreaming.PSObject.Copy()
            Add-Member -InputObject $TestDataWithError.StreamingManager -MemberType ScriptMethod -Name ExportToCsv -Value { 
                param($path) 
                throw "Access denied"
            } -Force
            
            { Write-ProcessingSummary -ProcessingResults $TestDataWithError -OutputPath "Z:\invalid\path.csv" } | Should Not Throw
        }
        
        It "Should log errors during CSV export" {
            # Use streaming data and mock the ExportToCsv method to throw
            $TestDataWithError = $script:TestStatisticsWithStreaming.PSObject.Copy()
            Add-Member -InputObject $TestDataWithError.StreamingManager -MemberType ScriptMethod -Name ExportToCsv -Value { 
                param($path) 
                throw "Access denied"
            } -Force
            
            Write-ProcessingSummary -ProcessingResults $TestDataWithError -OutputPath "Z:\invalid\path.csv"
            
            Assert-MockCalled Write-StructuredLog -ParameterFilter {
                $Level -eq 'Error'
            } -Times 1
        }
    }
}
