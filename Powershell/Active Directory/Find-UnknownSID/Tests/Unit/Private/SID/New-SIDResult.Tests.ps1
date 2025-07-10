# New-SIDResult.Tests.ps1 - Pester 3.4.x Compatible
# Tests for New-SIDResult private function module (New-OrphanedSIDResult and related functions)

# Create minimal stubs for missing dependencies FIRST
function Write-StructuredLog { param($Message, $Level, $CorrelationId, $Component, $Data) }
function Test-SIDFormat { param($SID) return $SID -match '^S-1-\d+' }

# Load required classes and functions
$ClassPath = Join-Path $PSScriptRoot '..\..\..\..\Classes'
if (Test-Path $ClassPath) {
    Get-ChildItem -Path $ClassPath -Filter '*.ps1' | ForEach-Object { . $_.FullName }
}

# Load SID functions
$SIDPath = Join-Path $PSScriptRoot '..\..\..\..\Private\SID'
if (Test-Path $SIDPath) {
    Get-ChildItem -Path $SIDPath -Filter '*.ps1' | ForEach-Object { . $_.FullName }
}

Describe "New-OrphanedSIDResult Function Tests" {
    
    Context "Function Existence and Core Functionality" {
        It "Should have New-OrphanedSIDResult function available" {
            Get-Command New-OrphanedSIDResult -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }
        
        It "Should accept required parameters and create result object" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testAccessRule = [PSCustomObject]@{
                AccessControlType = 'Allow'
                ActiveDirectoryRights = 'ReadProperty'
                InheritanceFlags = 'None'
                IsInherited = $false
                ObjectType = [System.Guid]::Empty
                InheritedObjectType = [System.Guid]::Empty
            }
            
            { New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule } | Should Not Throw
        }
        
        It "Should return OrphanedSIDResult object" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testAccessRule = [PSCustomObject]@{
                AccessControlType = 'Allow'
                ActiveDirectoryRights = 'ReadProperty'
            }
            
            $result = New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule
            $result | Should Not BeNullOrEmpty
            $result.GetType().Name | Should Be 'OrphanedSIDResult'
        }
        
        It "Should include correlation ID tracking" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow'; ActiveDirectoryRights = 'ReadProperty' }
            $correlationId = [System.Guid]::NewGuid().ToString()
            
            $result = New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule -CorrelationId $correlationId
            $result.CorrelationId | Should Be $correlationId
        }
    }
    
    Context "Parameter Validation and Error Handling" {
        It "Should validate required ObjectDN parameter" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            
            { New-OrphanedSIDResult -ObjectDN $null -OrphanedSID $testSID -AccessRule $testAccessRule } | Should Throw
        }
        
        It "Should validate required OrphanedSID parameter" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            
            { New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $null -AccessRule $testAccessRule } | Should Throw
        }
        
        It "Should validate SID format through Test-SIDFormat function" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $invalidSID = 'INVALID-SID-FORMAT'
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            
            { New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $invalidSID -AccessRule $testAccessRule } | Should Throw
        }
        
        It "Should validate Confidence parameter values" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            
            { New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule -Confidence 'InvalidLevel' } | Should Throw
        }
        
        It "Should accept valid Confidence parameter values" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            
            { New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule -Confidence 'High' } | Should Not Throw
            { New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule -Confidence 'Medium' } | Should Not Throw
            { New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule -Confidence 'Low' } | Should Not Throw
        }
    }
    
    Context "Result Object Properties and Metadata" {
        It "Should populate core object identification properties" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testObjectClass = 'User'
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow'; ActiveDirectoryRights = 'ReadProperty' }
            $likelySource = 'Deleted User'
            $confidence = 'High'
            $notes = 'Test analysis notes'
            
            $result = New-OrphanedSIDResult -ObjectDN $testObjectDN -ObjectClass $testObjectClass -OrphanedSID $testSID -AccessRule $testAccessRule -LikelySource $likelySource -Confidence $confidence -Notes $notes
            
            $result.ObjectDN | Should Be $testObjectDN
            $result.ObjectClass | Should Be $testObjectClass
            $result.OrphanedSID | Should Be $testSID
            $result.LikelySource | Should Be $likelySource
            $result.Confidence | Should Be $confidence
            $result.AnalysisNotes | Should Be $notes
        }
        
        It "Should include processing metadata" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            $processingMethod = 'Enhanced-ACL-Retrieval'
            
            $result = New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule -ProcessingMethod $processingMethod
            
            $result.ProcessingMethod | Should Be $processingMethod
            $result.ActionTaken | Should Be 'Detected'
            $result.Timestamp | Should Not BeNullOrEmpty
            $result.ProcessingContext | Should Not BeNullOrEmpty
        }
        
        It "Should extract ACL metadata from access rule" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testAccessRule = [PSCustomObject]@{
                AccessControlType = 'Allow'
                ActiveDirectoryRights = 'ReadProperty, WriteProperty'
                InheritanceFlags = 'ContainerInherit'
                IsInherited = $true
                ObjectType = [System.Guid]::NewGuid()
                InheritedObjectType = [System.Guid]::NewGuid()
            }
            
            $result = New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule
            
            $result.AccessControlType | Should Be $testAccessRule.AccessControlType
            $result.ActiveDirectoryRights | Should Be $testAccessRule.ActiveDirectoryRights
            $result.InheritanceType | Should Be $testAccessRule.InheritanceFlags
            $result.IsInherited | Should Be $testAccessRule.IsInherited
            $result.ObjectType | Should Be $testAccessRule.ObjectType
            $result.InheritedObjectType | Should Be $testAccessRule.InheritedObjectType
        }
        
        It "Should handle default values for optional parameters" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            
            $result = New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule
            
            $result.ObjectClass | Should Be 'Unknown'
            $result.LikelySource | Should Be 'Unknown'
            $result.Confidence | Should Be 'Medium'
            $result.AnalysisNotes | Should Be ''
            $result.ProcessingMethod | Should Be 'Standard'
        }
    }
    
    Context "ACL Metadata Extraction with Missing Properties" {
        It "Should handle access rule with missing AccessControlType" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testAccessRule = [PSCustomObject]@{
                ActiveDirectoryRights = 'ReadProperty'
                # AccessControlType missing
            }
            
            $result = New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule
            $result.AccessControlType | Should Be 'Allow'
        }
        
        It "Should handle access rule with missing ActiveDirectoryRights" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testAccessRule = [PSCustomObject]@{
                AccessControlType = 'Allow'
                # ActiveDirectoryRights missing
            }
            
            $result = New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule
            $result.ActiveDirectoryRights | Should Be 'GenericRead'
        }
        
        It "Should handle access rule with Rights property instead of ActiveDirectoryRights" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testAccessRule = [PSCustomObject]@{
                AccessControlType = 'Allow'
                Rights = 'GenericAll'  # Alternative property name
            }
            
            $result = New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule
            $result.ActiveDirectoryRights | Should Be 'GenericAll'
        }
        
        It "Should handle access rule with missing inheritance properties" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testAccessRule = [PSCustomObject]@{
                AccessControlType = 'Allow'
                ActiveDirectoryRights = 'ReadProperty'
                # InheritanceFlags and IsInherited missing
            }
            
            $result = New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule
            $result.InheritanceType | Should Be 'None'
            $result.IsInherited | Should Be $false
        }
    }
    
    Context "GUID Property Handling" {
        It "Should handle valid GUID objects" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testGuid = [System.Guid]::NewGuid()
            $testAccessRule = [PSCustomObject]@{
                AccessControlType = 'Allow'
                ObjectType = $testGuid
                InheritedObjectType = $testGuid
            }
            
            $result = New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule
            $result.ObjectType | Should Be $testGuid
            $result.InheritedObjectType | Should Be $testGuid
        }
        
        It "Should handle empty GUID objects" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testAccessRule = [PSCustomObject]@{
                AccessControlType = 'Allow'
                ObjectType = [System.Guid]::Empty
                InheritedObjectType = [System.Guid]::Empty
            }
            
            $result = New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule
            $result.ObjectType | Should Be ([System.Guid]::Empty)
            $result.InheritedObjectType | Should Be ([System.Guid]::Empty)
        }
        
        It "Should handle GUID strings" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testGuidString = '12345678-1234-5678-9abc-123456789012'
            $testAccessRule = [PSCustomObject]@{
                AccessControlType = 'Allow'
                ObjectType = $testGuidString
                InheritedObjectType = $testGuidString
            }
            
            $result = New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule
            $result.ObjectType | Should Be ([System.Guid]::Parse($testGuidString))
        }
        
        It "Should handle null or empty GUID properties" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testAccessRule = [PSCustomObject]@{
                AccessControlType = 'Allow'
                ObjectType = $null
                InheritedObjectType = ''
            }
            
            $result = New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule
            $result.ObjectType | Should Be ([System.Guid]::Empty)
            $result.InheritedObjectType | Should Be ([System.Guid]::Empty)
        }
    }
    
    Context "Processing Context and Enterprise Features" {
        It "Should include comprehensive processing context" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            
            $result = New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule
            
            $result.ProcessingContext | Should Not BeNullOrEmpty
            $result.ProcessingContext.MachineName | Should Be $env:COMPUTERNAME
            $result.ProcessingContext.UserName | Should Be $env:USERNAME
            $result.ProcessingContext.ProcessId | Should Be $PID
            $result.ProcessingContext.PowerShellVersion | Should Not BeNullOrEmpty
            $result.ProcessingContext.ModuleVersion | Should Be '1.0.0'
        }
        
        It "Should trim ObjectDN input" {
            $testObjectDN = '  CN=TestUser,OU=Users,DC=contoso,DC=com  '
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            
            $result = New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule
            $result.ObjectDN | Should Be 'CN=TestUser,OU=Users,DC=contoso,DC=com'
        }
        
        It "Should auto-generate correlation ID when not provided" {
            $testObjectDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            
            $result = New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule
            $result.CorrelationId | Should Not BeNullOrEmpty
            # Should be a valid GUID format
            { [System.Guid]::Parse($result.CorrelationId) } | Should Not Throw
        }
    }
}

Describe "ConvertTo-ResultSummary Export Functionality Tests" {
    
    Context "Export Summary Generation" {
        It "Should have ConvertTo-ResultSummary function available" {
            Get-Command ConvertTo-ResultSummary -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }
        
        It "Should generate summary from collection of results" {
            # Create sample OrphanedSIDResult objects
            $results = @()
            1..5 | ForEach-Object {
                $testObjectDN = "CN=TestUser$_,OU=Users,DC=contoso,DC=com"
                $testSID = "S-1-5-21-1234567890-1234567890-1234567890-100$_"
                $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow'; ActiveDirectoryRights = 'ReadProperty' }
                $results += New-OrphanedSIDResult -ObjectDN $testObjectDN -OrphanedSID $testSID -AccessRule $testAccessRule
            }
            
            $summary = $results | ConvertTo-ResultSummary
            
            $summary | Should Not BeNullOrEmpty
            $summary.TotalOrphanedSIDs | Should Be 5
            $summary.UniqueObjects | Should Be 5
            $summary.UniqueOrphanedSIDs | Should Be 5
        }
        
        It "Should include source category analysis" {
            $results = @()
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            
            # Create results with different sources
            $results += New-OrphanedSIDResult -ObjectDN 'CN=User1,DC=test,DC=com' -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1001' -AccessRule $testAccessRule -LikelySource 'Deleted User'
            $results += New-OrphanedSIDResult -ObjectDN 'CN=User2,DC=test,DC=com' -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1002' -AccessRule $testAccessRule -LikelySource 'Deleted User'
            $results += New-OrphanedSIDResult -ObjectDN 'CN=User3,DC=test,DC=com' -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1003' -AccessRule $testAccessRule -LikelySource 'Moved Account'
            
            $summary = $results | ConvertTo-ResultSummary
            
            $summary.SourceCategories | Should Not BeNullOrEmpty
            $deletedUserCategory = $summary.SourceCategories | Where-Object { $_.Source -eq 'Deleted User' }
            $deletedUserCategory.Count | Should Be 2
            $deletedUserCategory.Percentage | Should Be 66.67
        }
        
        It "Should include confidence distribution analysis" {
            $results = @()
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            
            # Create results with different confidence levels
            $results += New-OrphanedSIDResult -ObjectDN 'CN=User1,DC=test,DC=com' -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1001' -AccessRule $testAccessRule -Confidence 'High'
            $results += New-OrphanedSIDResult -ObjectDN 'CN=User2,DC=test,DC=com' -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1002' -AccessRule $testAccessRule -Confidence 'High'
            $results += New-OrphanedSIDResult -ObjectDN 'CN=User3,DC=test,DC=com' -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1003' -AccessRule $testAccessRule -Confidence 'Medium'
            
            $summary = $results | ConvertTo-ResultSummary
            
            $summary.ConfidenceDistribution | Should Not BeNullOrEmpty
            $highConfidence = $summary.ConfidenceDistribution | Where-Object { $_.Confidence -eq 'High' }
            $highConfidence.Count | Should Be 2
            $highConfidence.Percentage | Should Be 66.67
        }
        
        It "Should include object class analysis" {
            $results = @()
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            
            # Create results with different object classes
            $results += New-OrphanedSIDResult -ObjectDN 'CN=User1,DC=test,DC=com' -ObjectClass 'User' -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1001' -AccessRule $testAccessRule
            $results += New-OrphanedSIDResult -ObjectDN 'CN=Group1,DC=test,DC=com' -ObjectClass 'Group' -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1002' -AccessRule $testAccessRule
            $results += New-OrphanedSIDResult -ObjectDN 'CN=Group2,DC=test,DC=com' -ObjectClass 'Group' -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1003' -AccessRule $testAccessRule
            
            $summary = $results | ConvertTo-ResultSummary
            
            $summary.ObjectClassAnalysis | Should Not BeNullOrEmpty
            $groupClass = $summary.ObjectClassAnalysis | Where-Object { $_.ObjectClass -eq 'Group' }
            $groupClass.Count | Should Be 2
            $groupClass.Percentage | Should Be 66.67
        }
        
        It "Should include processing method statistics" {
            $results = @()
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            
            # Create results with different processing methods
            $results += New-OrphanedSIDResult -ObjectDN 'CN=User1,DC=test,DC=com' -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1001' -AccessRule $testAccessRule -ProcessingMethod 'Enhanced-ACL-Retrieval'
            $results += New-OrphanedSIDResult -ObjectDN 'CN=User2,DC=test,DC=com' -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1002' -AccessRule $testAccessRule -ProcessingMethod 'Standard'
            
            $summary = $results | ConvertTo-ResultSummary
            
            $summary.ProcessingMethods | Should Not BeNullOrEmpty
            $enhancedMethod = $summary.ProcessingMethods | Where-Object { $_.Method -eq 'Enhanced-ACL-Retrieval' }
            $enhancedMethod.Count | Should Be 1
            $enhancedMethod.Percentage | Should Be 50
        }
        
        It "Should include temporal analysis" {
            $results = @()
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            
            $results += New-OrphanedSIDResult -ObjectDN 'CN=User1,DC=test,DC=com' -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1001' -AccessRule $testAccessRule
            Start-Sleep -Milliseconds 100
            $results += New-OrphanedSIDResult -ObjectDN 'CN=User2,DC=test,DC=com' -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1002' -AccessRule $testAccessRule
            
            $summary = $results | ConvertTo-ResultSummary
            
            $summary.ProcessingTimespan | Should Not BeNullOrEmpty
            $summary.ProcessingTimespan.Earliest | Should Not BeNullOrEmpty
            $summary.ProcessingTimespan.Latest | Should Not BeNullOrEmpty
            $summary.ProcessingTimespan.Latest | Should BeGreaterThan $summary.ProcessingTimespan.Earliest
        }
        
        It "Should include access rights analysis" {
            $results = @()
            $testAccessRule1 = [PSCustomObject]@{ AccessControlType = 'Allow'; ActiveDirectoryRights = 'ReadProperty' }
            $testAccessRule2 = [PSCustomObject]@{ AccessControlType = 'Allow'; ActiveDirectoryRights = 'WriteProperty' }
            
            $results += New-OrphanedSIDResult -ObjectDN 'CN=User1,DC=test,DC=com' -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1001' -AccessRule $testAccessRule1
            $results += New-OrphanedSIDResult -ObjectDN 'CN=User2,DC=test,DC=com' -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1002' -AccessRule $testAccessRule1
            $results += New-OrphanedSIDResult -ObjectDN 'CN=User3,DC=test,DC=com' -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1003' -AccessRule $testAccessRule2
            
            $summary = $results | ConvertTo-ResultSummary
            
            $summary.AccessRightsAnalysis | Should Not BeNullOrEmpty
            $readProperty = $summary.AccessRightsAnalysis | Where-Object { $_.Rights -eq 'ReadProperty' }
            $readProperty.Count | Should Be 2
            $readProperty.Percentage | Should Be 66.67
        }
        
        It "Should include comprehensive summary metadata" {
            $results = @()
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            
            $results += New-OrphanedSIDResult -ObjectDN 'CN=User1,DC=test,DC=com' -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1001' -AccessRule $testAccessRule
            
            $correlationId = [System.Guid]::NewGuid().ToString()
            $summary = $results | ConvertTo-ResultSummary -CorrelationId $correlationId
            
            $summary.SummaryMetadata | Should Not BeNullOrEmpty
            $summary.SummaryMetadata.GeneratedAt | Should Not BeNullOrEmpty
            $summary.SummaryMetadata.CorrelationId | Should Be $correlationId
            $summary.SummaryMetadata.GeneratedBy | Should Be $env:USERNAME
            $summary.SummaryMetadata.MachineName | Should Be $env:COMPUTERNAME
        }
    }
    
    Context "Advanced Export and Formatting Features" {
        It "Should handle empty result collections gracefully" {
            $emptyResults = @()
            $summary = $emptyResults | ConvertTo-ResultSummary
            
            $summary.TotalOrphanedSIDs | Should Be 0
            $summary.UniqueObjects | Should Be 0
            $summary.UniqueOrphanedSIDs | Should Be 0
            $summary.SourceCategories | Should BeNullOrEmpty
        }
        
        It "Should sort categories by count in descending order" {
            $results = @()
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            
            # Create more "Deleted User" than "Moved Account"
            1..3 | ForEach-Object {
                $results += New-OrphanedSIDResult -ObjectDN "CN=User$_,DC=test,DC=com" -OrphanedSID "S-1-5-21-1234567890-1234567890-1234567890-100$_" -AccessRule $testAccessRule -LikelySource 'Deleted User'
            }
            $results += New-OrphanedSIDResult -ObjectDN 'CN=User4,DC=test,DC=com' -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1004' -AccessRule $testAccessRule -LikelySource 'Moved Account'
            
            $summary = $results | ConvertTo-ResultSummary
            
            $summary.SourceCategories[0].Source | Should Be 'Deleted User'
            $summary.SourceCategories[0].Count | Should Be 3
            $summary.SourceCategories[1].Source | Should Be 'Moved Account'
            $summary.SourceCategories[1].Count | Should Be 1
        }
        
        It "Should limit access rights analysis to top 10 entries" {
            $results = @()
            
            # Create results with many different access rights (more than 10)
            $validRights = @('CreateChild', 'DeleteChild', 'ListChildren', 'Self', 'ReadProperty', 'WriteProperty', 'DeleteTree', 'ListObject', 'ExtendedRight', 'Delete', 'ReadControl', 'GenericExecute', 'GenericWrite', 'GenericRead', 'WriteDacl')
            1..15 | ForEach-Object {
                $rightIndex = ($_ - 1) % $validRights.Count
                $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow'; ActiveDirectoryRights = $validRights[$rightIndex] }
                $results += New-OrphanedSIDResult -ObjectDN "CN=User$_,DC=test,DC=com" -OrphanedSID "S-1-5-21-1234567890-1234567890-1234567890-100$_" -AccessRule $testAccessRule
            }
            
            $summary = $results | ConvertTo-ResultSummary
            
            $summary.AccessRightsAnalysis.Count | Should BeLessThan 11
        }
        
        It "Should calculate percentages correctly with rounding" {
            $results = @()
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            
            # Create 3 results to test percentage rounding (33.33%)
            1..3 | ForEach-Object {
                $results += New-OrphanedSIDResult -ObjectDN "CN=User$_,DC=test,DC=com" -OrphanedSID "S-1-5-21-1234567890-1234567890-1234567890-100$_" -AccessRule $testAccessRule -LikelySource "Source$_"
            }
            
            $summary = $results | ConvertTo-ResultSummary
            
            # Each source should have 33.33% (rounded to 2 decimal places)
            $summary.SourceCategories | ForEach-Object {
                $_.Percentage | Should Be 33.33
            }
        }
    }
    
    Context "Performance and Reliability" {
        It "Should process large result collections efficiently" {
            $results = @()
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            
            # Create 100 results for performance testing
            $executionTime = Measure-Command {
                1..100 | ForEach-Object {
                    $results += New-OrphanedSIDResult -ObjectDN "CN=User$_,DC=test,DC=com" -OrphanedSID "S-1-5-21-1234567890-1234567890-1234567890-$(1000 + $_)" -AccessRule $testAccessRule
                }
                
                $summary = $results | ConvertTo-ResultSummary
                $summary.TotalOrphanedSIDs | Should Be 100
            }
            
            # Should complete within reasonable time (less than 5 seconds for 100 objects)
            $executionTime.TotalSeconds | Should BeLessThan 5
        }
        
        It "Should handle duplicate SIDs in unique count calculation" {
            $results = @()
            $testAccessRule = [PSCustomObject]@{ AccessControlType = 'Allow' }
            
            # Create results with duplicate SIDs
            $duplicateSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $results += New-OrphanedSIDResult -ObjectDN 'CN=User1,DC=test,DC=com' -OrphanedSID $duplicateSID -AccessRule $testAccessRule
            $results += New-OrphanedSIDResult -ObjectDN 'CN=User2,DC=test,DC=com' -OrphanedSID $duplicateSID -AccessRule $testAccessRule
            $results += New-OrphanedSIDResult -ObjectDN 'CN=User3,DC=test,DC=com' -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1002' -AccessRule $testAccessRule
            
            $summary = $results | ConvertTo-ResultSummary
            
            $summary.TotalOrphanedSIDs | Should Be 3
            $summary.UniqueObjects | Should Be 3
            $summary.UniqueOrphanedSIDs | Should Be 2  # Only 2 unique SIDs
        }
    }
}
