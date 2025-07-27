#Requires -Version 5.1
#Requires -Modules Pester

# Calculate path to the Classes directory
$ModuleRoot = "C:\Users\Administrator\TechbyJeff\Powershell\Active Directory\Find-UnknownSID"
$ClassesPath = Join-Path $ModuleRoot "Classes"

# Import the class file
. (Join-Path $ClassesPath "RestoreOperationResult.ps1")

Describe "RestoreOperationResult Class Tests" {
    Context "Constructor Tests" {
        It "Should create instance with default constructor" {
            $result = [RestoreOperationResult]::new()
            
            $result | Should Not BeNullOrEmpty
            $result.GetType().Name | Should Be "RestoreOperationResult"
        }

        It "Should set RestorationDate to current time" {
            $beforeCreate = Get-Date
            Start-Sleep -Milliseconds 10
            $result = [RestoreOperationResult]::new()
            
            $result.RestorationDate | Should BeGreaterThan $beforeCreate
        }

        It "Should generate unique CorrelationId for each instance" {
            $result1 = [RestoreOperationResult]::new()
            $result2 = [RestoreOperationResult]::new()
            
            $result1.CorrelationId | Should Not Be $result2.CorrelationId
        }

        It "Should initialize Success to false" {
            $result = [RestoreOperationResult]::new()
            
            $result.Success | Should Be $false
        }

        It "Should initialize BackupValidation to false" {
            $result = [RestoreOperationResult]::new()
            
            $result.BackupValidation | Should Be $false
        }

        It "Should initialize EntriesRestored to zero" {
            $result = [RestoreOperationResult]::new()
            
            $result.EntriesRestored | Should Be 0
        }

        It "Should initialize WhatIfMode to false" {
            $result = [RestoreOperationResult]::new()
            
            $result.WhatIfMode | Should Be $false
        }

        It "Should initialize ProcessingTime to zero" {
            $result = [RestoreOperationResult]::new()
            
            $result.ProcessingTime | Should Be ([TimeSpan]::Zero)
        }
    }

    Context "Property Tests" {
        BeforeEach {
            $script:testResult = [RestoreOperationResult]::new()
        }

        It "Should have correct property types" {
            # Set properties to non-null values before type checking
            $script:testResult.ObjectDN = "TestDN"
            $script:testResult.BackupFile = "TestFile"
            $script:testResult.ErrorMessage = "TestError"
            
            $script:testResult.ObjectDN.GetType().Name | Should Be "String"
            $script:testResult.CorrelationId.GetType().Name | Should Be "String"
            $script:testResult.BackupFile.GetType().Name | Should Be "String"
            $script:testResult.BackupDate.GetType().Name | Should Be "DateTime"
            $script:testResult.RestorationDate.GetType().Name | Should Be "DateTime"
            $script:testResult.Success.GetType().Name | Should Be "Boolean"
            $script:testResult.ErrorMessage.GetType().Name | Should Be "String"
            $script:testResult.ProcessingTime.GetType().Name | Should Be "TimeSpan"
            $script:testResult.BackupValidation.GetType().Name | Should Be "Boolean"
            $script:testResult.EntriesRestored.GetType().Name | Should Be "Int32"
            $script:testResult.WhatIfMode.GetType().Name | Should Be "Boolean"
        }

        It "Should allow setting ObjectDN property" {
            $testValue = "CN=TestObject,OU=Test,DC=example,DC=com"
            $script:testResult.ObjectDN = $testValue
            
            $script:testResult.ObjectDN | Should Be $testValue
        }

        It "Should allow setting CorrelationId property" {
            $testValue = "12345678-1234-1234-1234-123456789012"
            $script:testResult.CorrelationId = $testValue
            
            $script:testResult.CorrelationId | Should Be $testValue
        }

        It "Should allow setting BackupFile property" {
            $testValue = "C:\Backups\test-backup.xml"
            $script:testResult.BackupFile = $testValue
            
            $script:testResult.BackupFile | Should Be $testValue
        }

        It "Should allow setting BackupDate property" {
            $testValue = Get-Date "2024-01-01 10:00:00"
            $script:testResult.BackupDate = $testValue
            
            $script:testResult.BackupDate | Should Be $testValue
        }

        It "Should allow setting RestorationDate property" {
            $testValue = Get-Date "2024-01-02 12:00:00"
            $script:testResult.RestorationDate = $testValue
            
            $script:testResult.RestorationDate | Should Be $testValue
        }

        It "Should allow setting Success property" {
            $script:testResult.Success = $true
            
            $script:testResult.Success | Should Be $true
        }

        It "Should allow setting ErrorMessage property" {
            $testValue = "Test error message"
            $script:testResult.ErrorMessage = $testValue
            
            $script:testResult.ErrorMessage | Should Be $testValue
        }

        It "Should allow setting ProcessingTime property" {
            $testValue = [TimeSpan]::FromSeconds(30)
            $script:testResult.ProcessingTime = $testValue
            
            $script:testResult.ProcessingTime | Should Be $testValue
        }

        It "Should allow setting BackupValidation property" {
            $script:testResult.BackupValidation = $true
            
            $script:testResult.BackupValidation | Should Be $true
        }

        It "Should allow setting EntriesRestored property" {
            $testValue = 42
            $script:testResult.EntriesRestored = $testValue
            
            $script:testResult.EntriesRestored | Should Be $testValue
        }

        It "Should allow setting WhatIfMode property" {
            $script:testResult.WhatIfMode = $true
            
            $script:testResult.WhatIfMode | Should Be $true
        }
    }

    Context "Integration Tests" {
        It "Should create successful restore operation result" {
            $result = [RestoreOperationResult]::new()
            $result.ObjectDN = "CN=TestUser,OU=Users,DC=test,DC=com"
            $result.BackupFile = "C:\Backups\test.xml"
            $result.BackupDate = Get-Date "2024-01-01"
            $result.Success = $true
            $result.BackupValidation = $true
            $result.EntriesRestored = 5
            $result.ProcessingTime = [TimeSpan]::FromSeconds(10)
            
            $result.Success | Should Be $true
            $result.BackupValidation | Should Be $true
            $result.EntriesRestored | Should Be 5
            $result.ProcessingTime.TotalSeconds | Should Be 10
        }

        It "Should create failed restore operation result" {
            $result = [RestoreOperationResult]::new()
            $result.ObjectDN = "CN=TestUser,OU=Users,DC=test,DC=com"
            $result.Success = $false
            $result.ErrorMessage = "Access denied"
            $result.EntriesRestored = 0
            
            $result.Success | Should Be $false
            $result.ErrorMessage | Should Be "Access denied"
            $result.EntriesRestored | Should Be 0
        }

        It "Should create WhatIf mode operation result" {
            $result = [RestoreOperationResult]::new()
            $result.WhatIfMode = $true
            $result.Success = $true
            $result.EntriesRestored = 0
            
            $result.WhatIfMode | Should Be $true
            $result.Success | Should Be $true
            $result.EntriesRestored | Should Be 0
        }

        It "Should support multiple instances with independent state" {
            $result1 = [RestoreOperationResult]::new()
            $result2 = [RestoreOperationResult]::new()
            
            $result1.Success = $true
            $result1.EntriesRestored = 10
            
            $result2.Success = $false
            $result2.EntriesRestored = 0
            
            $result1.Success | Should Be $true
            $result2.Success | Should Be $false
            $result1.EntriesRestored | Should Be 10
            $result2.EntriesRestored | Should Be 0
            $result1.CorrelationId | Should Not Be $result2.CorrelationId
        }
    }
}
