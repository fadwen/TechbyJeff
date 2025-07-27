#Requires -Version 5.1
#Requires -Module Pester

$ModuleRoot = Resolve-Path "$PSScriptRoot\..\..\.."

# Import the class file
. "$ModuleRoot\Classes\OrphanedSIDResult.ps1"

Describe "OrphanedSIDResult Class Tests" -Tag "Unit", "Classes", "OrphanedSIDResult" {

    Context "Constructor Tests" {
        It "Should create instance with default constructor" {
            $result = [OrphanedSIDResult]::new()
            
            $result | Should Not BeNullOrEmpty
            $result.Timestamp | Should Not BeNullOrEmpty
            $result.CorrelationId | Should Not BeNullOrEmpty
            $result.CorrelationId | Should Match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        }

        It "Should set Timestamp to current time" {
            $beforeCreate = Get-Date
            Start-Sleep -Milliseconds 50  # Small delay to ensure timestamp difference
            $result = [OrphanedSIDResult]::new()
            $afterCreate = Get-Date
            
            $result.Timestamp | Should BeGreaterThan $beforeCreate
            $result.Timestamp | Should BeLessThan $afterCreate.AddMilliseconds(1)
        }

        It "Should generate unique CorrelationId for each instance" {
            $result1 = [OrphanedSIDResult]::new()
            $result2 = [OrphanedSIDResult]::new()
            
            $result1.CorrelationId | Should Not Be $result2.CorrelationId
        }
    }

    Context "Property Tests" {
        BeforeEach {
            $script:testResult = [OrphanedSIDResult]::new()
        }

        It "Should have correct property types" {
            # Set properties to test their types since null properties can't be type-tested
            $script:testResult.ObjectDN = "Test"
            $script:testResult.ObjectClass = "Test"
            $script:testResult.OrphanedSID = "Test"
            $script:testResult.LikelySource = "Test"
            $script:testResult.Confidence = "Test"
            $script:testResult.AnalysisNotes = "Test"
            $script:testResult.ProcessingMethod = "Test"
            $script:testResult.ActionTaken = "Test"
            
            $script:testResult.ObjectDN | Should BeOfType [string]
            $script:testResult.ObjectClass | Should BeOfType [string]
            $script:testResult.OrphanedSID | Should BeOfType [string]
            $script:testResult.LikelySource | Should BeOfType [string]
            $script:testResult.Confidence | Should BeOfType [string]
            $script:testResult.AnalysisNotes | Should BeOfType [string]
            $script:testResult.AccessControlType | Should BeOfType [System.Security.AccessControl.AccessControlType]
            $script:testResult.ActiveDirectoryRights | Should BeOfType [System.DirectoryServices.ActiveDirectoryRights]
            $script:testResult.InheritanceType | Should BeOfType [System.Security.AccessControl.InheritanceFlags]
            $script:testResult.ObjectType | Should BeOfType [System.Guid]
            $script:testResult.InheritedObjectType | Should BeOfType [System.Guid]
            $script:testResult.IsInherited | Should BeOfType [bool]
            $script:testResult.ProcessingMethod | Should BeOfType [string]
            $script:testResult.ActionTaken | Should BeOfType [string]
            $script:testResult.CorrelationId | Should BeOfType [string]
            $script:testResult.Timestamp | Should BeOfType [DateTime]
        }

        It "Should allow setting ObjectDN property" {
            $testDN = "CN=TestUser,OU=Users,DC=example,DC=com"
            $script:testResult.ObjectDN = $testDN
            $script:testResult.ObjectDN | Should Be $testDN
        }

        It "Should allow setting ObjectClass property" {
            $testClass = "user"
            $script:testResult.ObjectClass = $testClass
            $script:testResult.ObjectClass | Should Be $testClass
        }

        It "Should allow setting OrphanedSID property" {
            $testSID = "S-1-5-21-1234567890-987654321-123456789-1001"
            $script:testResult.OrphanedSID = $testSID
            $script:testResult.OrphanedSID | Should Be $testSID
        }

        It "Should allow setting LikelySource property" {
            $testSource = "Former Domain User"
            $script:testResult.LikelySource = $testSource
            $script:testResult.LikelySource | Should Be $testSource
        }

        It "Should allow setting Confidence property" {
            $testConfidence = "High"
            $script:testResult.Confidence = $testConfidence
            $script:testResult.Confidence | Should Be $testConfidence
        }

        It "Should allow setting AnalysisNotes property" {
            $testNotes = "SID not found in current domain or any trusted domains"
            $script:testResult.AnalysisNotes = $testNotes
            $script:testResult.AnalysisNotes | Should Be $testNotes
        }

        It "Should allow setting AccessControlType property" {
            $script:testResult.AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
            $script:testResult.AccessControlType | Should Be ([System.Security.AccessControl.AccessControlType]::Allow)
        }

        It "Should allow setting ActiveDirectoryRights property" {
            $script:testResult.ActiveDirectoryRights = [System.DirectoryServices.ActiveDirectoryRights]::ReadProperty
            $script:testResult.ActiveDirectoryRights | Should Be ([System.DirectoryServices.ActiveDirectoryRights]::ReadProperty)
        }

        It "Should allow setting InheritanceType property" {
            $script:testResult.InheritanceType = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit
            $script:testResult.InheritanceType | Should Be ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit)
        }

        It "Should allow setting ObjectType property" {
            $testGuid = [System.Guid]::NewGuid()
            $script:testResult.ObjectType = $testGuid
            $script:testResult.ObjectType | Should Be $testGuid
        }

        It "Should allow setting InheritedObjectType property" {
            $testGuid = [System.Guid]::NewGuid()
            $script:testResult.InheritedObjectType = $testGuid
            $script:testResult.InheritedObjectType | Should Be $testGuid
        }

        It "Should allow setting IsInherited property" {
            $script:testResult.IsInherited = $true
            $script:testResult.IsInherited | Should Be $true
            
            $script:testResult.IsInherited = $false
            $script:testResult.IsInherited | Should Be $false
        }

        It "Should allow setting ProcessingMethod property" {
            $testMethod = "Automated Scan"
            $script:testResult.ProcessingMethod = $testMethod
            $script:testResult.ProcessingMethod | Should Be $testMethod
        }

        It "Should allow setting ActionTaken property" {
            $testAction = "Removed from ACL"
            $script:testResult.ActionTaken = $testAction
            $script:testResult.ActionTaken | Should Be $testAction
        }
    }

    Context "Property Default Values" {
        BeforeEach {
            $script:testResult = [OrphanedSIDResult]::new()
        }

        It "Should have null or empty default values for string properties" {
            $script:testResult.ObjectDN | Should BeNullOrEmpty
            $script:testResult.ObjectClass | Should BeNullOrEmpty
            $script:testResult.OrphanedSID | Should BeNullOrEmpty
            $script:testResult.LikelySource | Should BeNullOrEmpty
            $script:testResult.Confidence | Should BeNullOrEmpty
            $script:testResult.AnalysisNotes | Should BeNullOrEmpty
            $script:testResult.ProcessingMethod | Should BeNullOrEmpty
            $script:testResult.ActionTaken | Should BeNullOrEmpty
        }

        It "Should have default enum values" {
            # AccessControlType defaults to Allow (0)
            $script:testResult.AccessControlType | Should Be ([System.Security.AccessControl.AccessControlType]::Allow)
            
            # ActiveDirectoryRights defaults to 0
            $script:testResult.ActiveDirectoryRights | Should Be 0
            
            # InheritanceType defaults to None (0)
            $script:testResult.InheritanceType | Should Be ([System.Security.AccessControl.InheritanceFlags]::None)
        }

        It "Should have empty GUID default values" {
            $script:testResult.ObjectType | Should Be ([System.Guid]::Empty)
            $script:testResult.InheritedObjectType | Should Be ([System.Guid]::Empty)
        }

        It "Should have false default for IsInherited" {
            $script:testResult.IsInherited | Should Be $false
        }
    }

    Context "Integration Tests" {
        It "Should create complete OrphanedSIDResult object" {
            $result = [OrphanedSIDResult]::new()
            
            # Set all properties
            $result.ObjectDN = "CN=TestUser,OU=Users,DC=example,DC=com"
            $result.ObjectClass = "user"
            $result.OrphanedSID = "S-1-5-21-1234567890-987654321-123456789-1001"
            $result.LikelySource = "Former Domain User"
            $result.Confidence = "High"
            $result.AnalysisNotes = "SID not found in current domain or any trusted domains"
            $result.AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
            $result.ActiveDirectoryRights = [System.DirectoryServices.ActiveDirectoryRights]::ReadProperty
            $result.InheritanceType = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit
            $result.ObjectType = [System.Guid]::NewGuid()
            $result.InheritedObjectType = [System.Guid]::NewGuid()
            $result.IsInherited = $true
            $result.ProcessingMethod = "Automated Scan"
            $result.ActionTaken = "Removed from ACL"
            
            # Verify all properties are set correctly
            $result.ObjectDN | Should Be "CN=TestUser,OU=Users,DC=example,DC=com"
            $result.ObjectClass | Should Be "user"
            $result.OrphanedSID | Should Be "S-1-5-21-1234567890-987654321-123456789-1001"
            $result.LikelySource | Should Be "Former Domain User"
            $result.Confidence | Should Be "High"
            $result.AnalysisNotes | Should Be "SID not found in current domain or any trusted domains"
            $result.AccessControlType | Should Be ([System.Security.AccessControl.AccessControlType]::Allow)
            $result.ActiveDirectoryRights | Should Be ([System.DirectoryServices.ActiveDirectoryRights]::ReadProperty)
            $result.InheritanceType | Should Be ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit)
            $result.IsInherited | Should Be $true
            $result.ProcessingMethod | Should Be "Automated Scan"
            $result.ActionTaken | Should Be "Removed from ACL"
            
            # Verify constructor-set properties
            $result.Timestamp | Should Not BeNullOrEmpty
            $result.CorrelationId | Should Not BeNullOrEmpty
        }

        It "Should support multiple instances with unique identifiers" {
            $result1 = [OrphanedSIDResult]::new()
            $result2 = [OrphanedSIDResult]::new()
            
            $result1.ObjectDN = "CN=User1,OU=Users,DC=example,DC=com"
            $result2.ObjectDN = "CN=User2,OU=Users,DC=example,DC=com"
            
            $result1.OrphanedSID = "S-1-5-21-1234567890-987654321-123456789-1001"
            $result2.OrphanedSID = "S-1-5-21-1234567890-987654321-123456789-1002"
            
            # Should have different correlation IDs
            $result1.CorrelationId | Should Not Be $result2.CorrelationId
            
            # Should maintain separate properties
            $result1.ObjectDN | Should Not Be $result2.ObjectDN
            $result1.OrphanedSID | Should Not Be $result2.OrphanedSID
        }
    }

    Context "Enum Value Tests" {
        BeforeEach {
            $script:testResult = [OrphanedSIDResult]::new()
        }

        It "Should accept all AccessControlType enum values" {
            $script:testResult.AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
            $script:testResult.AccessControlType | Should Be ([System.Security.AccessControl.AccessControlType]::Allow)
            
            $script:testResult.AccessControlType = [System.Security.AccessControl.AccessControlType]::Deny
            $script:testResult.AccessControlType | Should Be ([System.Security.AccessControl.AccessControlType]::Deny)
        }

        It "Should accept ActiveDirectoryRights enum values" {
            $script:testResult.ActiveDirectoryRights = [System.DirectoryServices.ActiveDirectoryRights]::ReadProperty
            $script:testResult.ActiveDirectoryRights | Should Be ([System.DirectoryServices.ActiveDirectoryRights]::ReadProperty)
            
            $script:testResult.ActiveDirectoryRights = [System.DirectoryServices.ActiveDirectoryRights]::WriteProperty
            $script:testResult.ActiveDirectoryRights | Should Be ([System.DirectoryServices.ActiveDirectoryRights]::WriteProperty)
            
            $script:testResult.ActiveDirectoryRights = [System.DirectoryServices.ActiveDirectoryRights]::GenericAll
            $script:testResult.ActiveDirectoryRights | Should Be ([System.DirectoryServices.ActiveDirectoryRights]::GenericAll)
        }

        It "Should accept InheritanceFlags enum values" {
            $script:testResult.InheritanceType = [System.Security.AccessControl.InheritanceFlags]::None
            $script:testResult.InheritanceType | Should Be ([System.Security.AccessControl.InheritanceFlags]::None)
            
            $script:testResult.InheritanceType = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit
            $script:testResult.InheritanceType | Should Be ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit)
            
            $script:testResult.InheritanceType = [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
            $script:testResult.InheritanceType | Should Be ([System.Security.AccessControl.InheritanceFlags]::ObjectInherit)
        }
    }

    Context "GUID Property Tests" {
        BeforeEach {
            $script:testResult = [OrphanedSIDResult]::new()
        }

        It "Should handle ObjectType GUID properly" {
            $testGuid = [System.Guid]::NewGuid()
            $script:testResult.ObjectType = $testGuid
            $script:testResult.ObjectType | Should Be $testGuid
            $script:testResult.ObjectType | Should BeOfType [System.Guid]
        }

        It "Should handle InheritedObjectType GUID properly" {
            $testGuid = [System.Guid]::NewGuid()
            $script:testResult.InheritedObjectType = $testGuid
            $script:testResult.InheritedObjectType | Should Be $testGuid
            $script:testResult.InheritedObjectType | Should BeOfType [System.Guid]
        }

        It "Should accept empty GUID values" {
            $script:testResult.ObjectType = [System.Guid]::Empty
            $script:testResult.ObjectType | Should Be ([System.Guid]::Empty)
            
            $script:testResult.InheritedObjectType = [System.Guid]::Empty
            $script:testResult.InheritedObjectType | Should Be ([System.Guid]::Empty)
        }
    }

    Context "DateTime Property Tests" {
        It "Should maintain Timestamp accuracy" {
            $beforeCreate = Get-Date
            Start-Sleep -Milliseconds 10
            $result = [OrphanedSIDResult]::new()
            Start-Sleep -Milliseconds 10
            $afterCreate = Get-Date
            
            $result.Timestamp | Should BeGreaterThan $beforeCreate
            $result.Timestamp | Should BeLessThan $afterCreate
        }

        It "Should allow setting custom Timestamp" {
            $result = [OrphanedSIDResult]::new()
            $customTime = Get-Date "2024-01-01 12:00:00"
            
            $result.Timestamp = $customTime
            $result.Timestamp | Should Be $customTime
        }
    }

    Context "String Property Validation" {
        BeforeEach {
            $script:testResult = [OrphanedSIDResult]::new()
        }

        It "Should handle empty and null string values" {
            $script:testResult.ObjectDN = ""
            $script:testResult.ObjectDN | Should Be ""
            
            $script:testResult.ObjectDN = $null
            $script:testResult.ObjectDN | Should BeNullOrEmpty
        }

        It "Should handle long string values" {
            $longString = "A" * 1000
            $script:testResult.AnalysisNotes = $longString
            $script:testResult.AnalysisNotes | Should Be $longString
            $script:testResult.AnalysisNotes.Length | Should Be 1000
        }

        It "Should handle special characters in strings" {
            $specialString = "Test with special chars: !@#$%^&*()[]{}|;:,.<>?~"
            $script:testResult.LikelySource = $specialString
            $script:testResult.LikelySource | Should Be $specialString
        }
    }
}

