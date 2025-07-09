#Requires -Module Pester

# Import test bootstrapper first
$testBootstrapper = Join-Path (Split-Path -Parent $PSScriptRoot) "Infrastructure\TestBootstrapper.ps1"
if (Test-Path $testBootstrapper) {
. $testBootstrapper
}
# Import ClassManagement module functions for testing
$ClassManagementModulePath = Join-Path $PSScriptRoot '..\..\Private\ClassManagement'
Get-ChildItem -Path $ClassManagementModulePath -Filter '*.ps1' | ForEach-Object {
. #Requires -Module Pester


    # Import test bootstrapper first
    $testBootstrapper = Join-Path (Split-Path -Parent $PSScriptRoot) "Infrastructure\TestBootstrapper.ps1"
    if (Test-Path $testBootstrapper) {
        . $testBootstrapper
    }

    # Import ClassManagement module functions for testing
    $ClassManagementModulePath = Join-Path $PSScriptRoot '..\..\Private\ClassManagement'
    Get-ChildItem -Path $ClassManagementModulePath -Filter '*.ps1' | ForEach-Object {
        . $_.FullName
    }

    # Import test helpers if they exist
    $TestHelpersPath = Join-Path $PSScriptRoot '..\TestHelpers\TestHelpers.ps1'
    if (Test-Path $TestHelpersPath) {
        . $TestHelpersPath
    }

    # Mock external dependencies
    Mock Write-Verbose { }
    Mock Write-Information { }
    Mock Write-Warning { }
    Mock Write-Error { }

    # Mock file system operations
    Mock Test-Path { return $true }
    Mock Get-Content { return @() }
    Mock Get-ChildItem { return @() }
    Mock Import-Module { }

    # Mock logging function
    Mock Write-StructuredLog { }

    # Mock security operations
    Mock Get-AuthenticodeSignature { return @{ Status = 'Valid'; SignerCertificate = @{ Subject = 'CN=Test' } } }

Describe "Get-ApprovedClassList" -Tag "Unit", "ClassManagement", "Security" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestClassPath = Join-Path $TestDrive 'Classes'
    }

    Context "Parameter Validation" {
        It "Should accept ClassPath parameter" {
            { Get-ApprovedClassList -ClassPath $script:TestClassPath } | Should Not Throw
        }

        It "Should use default path when not specified" {
            { Get-ApprovedClassList } | Should Not Throw
        }

        It "Should validate class path exists" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $script:TestClassPath }

            { Get-ApprovedClassList -ClassPath $script:TestClassPath } | Should Throw "*ClassPath*"
        }

        It "Should accept correlation ID parameter" {
            { Get-ApprovedClassList -ClassPath $script:TestClassPath -CorrelationId $script:TestCorrelationId } | Should Not Throw
        }
    }

    Context "Core Functionality" {
        It "Should return list of approved classes" {
            $mockClasses = @(
                @{ Name = "OrphanedSIDResult.ps1"; FullName = "$script:TestClassPath\OrphanedSIDResult.ps1" },
                @{ Name = "ProcessingStatistics.ps1"; FullName = "$script:TestClassPath\ProcessingStatistics.ps1" },
                @{ Name = "MemoryManager.ps1"; FullName = "$script:TestClassPath\MemoryManager.ps1" }
            )
            Mock Get-ChildItem { return $mockClasses } -ParameterFilter { $Path -eq $script:TestClassPath }
            Mock Get-AuthenticodeSignature { return @{ Status = 'Valid' } }

            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath

            $result | Should -HaveCount 3
            $result[0].Name | Should Be "OrphanedSIDResult.ps1"
        }

        It "Should filter only PowerShell class files" {
            $mockFiles = @(
                @{ Name = "OrphanedSIDResult.ps1"; FullName = "$script:TestClassPath\OrphanedSIDResult.ps1" },
                @{ Name = "README.md"; FullName = "$script:TestClassPath\README.md" },
                @{ Name = "config.json"; FullName = "$script:TestClassPath\config.json" },
                @{ Name = "ProcessingStatistics.ps1"; FullName = "$script:TestClassPath\ProcessingStatistics.ps1" }
            )
            Mock Get-ChildItem { return $mockFiles }
            Mock Get-AuthenticodeSignature { return @{ Status = 'Valid' } }

            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath

            $result | Should -HaveCount 2
            $result | ForEach-Object { $_.Name | Should Match "\.ps1$" }
        }

        It "Should validate class file signatures" {
            $mockClasses = @(
                @{ Name = "ValidClass.ps1"; FullName = "$script:TestClassPath\ValidClass.ps1" },
                @{ Name = "InvalidClass.ps1"; FullName = "$script:TestClassPath\InvalidClass.ps1" }
            )
            Mock Get-ChildItem { return $mockClasses }
            Mock Get-AuthenticodeSignature {
                param($FilePath)
                if ($FilePath -like "*ValidClass*") {
                    return @{ Status = 'Valid'; SignerCertificate = @{ Subject = 'CN=TrustedPublisher' } }
                } else {
                    return @{ Status = 'NotSigned' }
                }
            }

            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath -RequireSignature

            $result | Should -HaveCount 1
            $result[0].Name | Should Be "ValidClass.ps1"
        }

        It "Should return empty array when no classes found" {
            Mock Get-ChildItem { return @() }

            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath

            $result | Should BeNullOrEmpty
        }

        It "Should include class metadata" {
            $mockClasses = @(
                @{ Name = "TestClass.ps1"; FullName = "$script:TestClassPath\TestClass.ps1"; LastWriteTime = (Get-Date) }
            )
            Mock Get-ChildItem { return $mockClasses }
            Mock Get-AuthenticodeSignature { return @{ Status = 'Valid' } }
            Mock Get-Content { return @("class TestClass {", "    [string]$Name", "}") }

            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath

            $result | Should -HaveCount 1
            $result[0].Name | Should Be "TestClass.ps1"
            $result[0].FullName | Should Be "$script:TestClassPath\TestClass.ps1"
        }
    }

    Context "Error Handling" {
        It "Should handle file access errors" {
            Mock Get-ChildItem { throw "Access is denied" }

            { Get-ApprovedClassList -ClassPath $script:TestClassPath } | Should Throw "*Access is denied*"
        }

        It "Should handle corrupted class files" {
            $mockClasses = @(
                @{ Name = "CorruptedClass.ps1"; FullName = "$script:TestClassPath\CorruptedClass.ps1" }
            )
            Mock Get-ChildItem { return $mockClasses }
            Mock Get-AuthenticodeSignature { throw "File is corrupted" }

            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath -ErrorAction Continue

            $result | Should BeNullOrEmpty
        }

        It "Should handle network path unavailability" {
            Mock Test-Path { throw "The network path was not found" }

            { Get-ApprovedClassList -ClassPath "\\server\share\classes" } | Should Throw "*network path*"
        }
    }

    Context "Performance and Scalability" {
        It "Should handle large class directories efficiently" {
            $largeClassSet = 1..100 | ForEach-Object {
                @{ Name = "Class$_.ps1"; FullName = "$script:TestClassPath\Class$_.ps1"; LastWriteTime = (Get-Date) }
            }
            Mock Get-ChildItem { return $largeClassSet }
            Mock Get-AuthenticodeSignature { return @{ Status = 'Valid' } }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 3000
            $result | Should -HaveCount 100
        }

        It "Should use memory efficiently for large results" {
            $largeClassSet = 1..50 | ForEach-Object {
                @{ Name = "Class$_.ps1"; FullName = "$script:TestClassPath\Class$_.ps1" }
            }
            Mock Get-ChildItem { return $largeClassSet }
            Mock Get-AuthenticodeSignature { return @{ Status = 'Valid' } }

            $memoryBefore = [System.GC]::GetTotalMemory($false)
            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath
            $memoryAfter = [System.GC]::GetTotalMemory($false)

            $memoryIncrease = $memoryAfter -$memoryBefore
            $memoryIncrease | Should BeLessThan 5MB
        }
    }

    Context "Security Validation" {
        It "Should reject unsigned files when signature required" {
            $mockClasses = @(
                @{ Name = "UnsignedClass.ps1"; FullName = "$script:TestClassPath\UnsignedClass.ps1" }
            )
            Mock Get-ChildItem { return $mockClasses }
            Mock Get-AuthenticodeSignature { return @{ Status = 'NotSigned' } }

            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath -RequireSignature

            $result | Should BeNullOrEmpty
        }

        It "Should reject files with invalid signatures" {
            $mockClasses = @(
                @{ Name = "InvalidClass.ps1"; FullName = "$script:TestClassPath\InvalidClass.ps1" }
            )
            Mock Get-ChildItem { return $mockClasses }
            Mock Get-AuthenticodeSignature { return @{ Status = 'UnknownError' } }

            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath -RequireSignature

            $result | Should BeNullOrEmpty
        }

        It "Should validate trusted publishers" {
            $mockClasses = @(
                @{ Name = "TrustedClass.ps1"; FullName = "$script:TestClassPath\TrustedClass.ps1" },
                @{ Name = "UntrustedClass.ps1"; FullName = "$script:TestClassPath\UntrustedClass.ps1" }
            )
            Mock Get-ChildItem { return $mockClasses }
            Mock Get-AuthenticodeSignature {
                param($FilePath)
                if ($FilePath -like "*TrustedClass*") {
                    return @{ Status = 'Valid'; SignerCertificate = @{ Subject = 'CN=TrustedPublisher,O=MyOrg' } }
                } else {
                    return @{ Status = 'Valid'; SignerCertificate = @{ Subject = 'CN=UnknownPublisher' } }
                }
            }

            $trustedPublishers = @('TrustedPublisher')
            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath -RequireSignature -TrustedPublishers $trustedPublishers

            $result | Should -HaveCount 1
            $result[0].Name | Should Be "TrustedClass.ps1"
        }
    }

    Context "Audit and Compliance" {
        It "Should log class discovery operations" {
            Mock Write-StructuredLog { }
            Mock Get-ChildItem { return @() }

            Get-ApprovedClassList -ClassPath $script:TestClassPath -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*class discovery*" }
        }

        It "Should log security validation results" {
            Mock Write-StructuredLog { }
            $mockClasses = @(
                @{ Name = "TestClass.ps1"; FullName = "$script:TestClassPath\TestClass.ps1" }
            )
            Mock Get-ChildItem { return $mockClasses }
            Mock Get-AuthenticodeSignature { return @{ Status = 'NotSigned' } }

            Get-ApprovedClassList -ClassPath $script:TestClassPath -RequireSignature

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*signature validation*" }
        }
    }

Describe "Import-SecureClasses" -Tag "Unit", "ClassManagement", "Import" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestClassList = @(
            @{ Name = "TestClass1.ps1"; FullName = "C:\Classes\TestClass1.ps1" },
            @{ Name = "TestClass2.ps1"; FullName = "C:\Classes\TestClass2.ps1" }
        )
    }

    Context "Parameter Validation" {
        It "Should require ClassList parameter" {
            { Import-SecureClasses } | Should Throw "*ClassList*"
        }

        It "Should accept array of class objects" {
            { Import-SecureClasses -ClassList $script:TestClassList } | Should Not Throw
        }

        It "Should accept validation mode parameter" {
            { Import-SecureClasses -ClassList $script:TestClassList -ValidationMode 'Strict' } | Should Not Throw
        }

        It "Should validate validation mode values" {
            { Import-SecureClasses -ClassList $script:TestClassList -ValidationMode 'InvalidMode' } | Should Throw "*ValidationMode*"
        }
    }

    Context "Core Functionality" {
        It "Should import valid class files successfully" {
            Mock Test-Path { return $true }
            Mock Get-Content { return @("class TestClass {", "    [string]$Name", "}") }
            Mock . { } # Mock dot-sourcing

            $result = Import-SecureClasses -ClassList $script:TestClassList

            $result | Should Not BeNullOrEmpty
            $result.ImportedClasses | Should -HaveCount 2
            $result.FailedClasses | Should BeNullOrEmpty
        }

        It "Should validate class syntax before import" {
            Mock Test-Path { return $true }
            Mock Get-Content {
                param($Path)
                if ($Path -like "*TestClass1*") {
                    return @("class TestClass1 {", "    [string]$Name", "}")  # Valid
                } else {
                    return @("class TestClass2 {", "    invalid syntax", "}")  # Invalid
                }
            }
            Mock . {
                param($Path)
                if ($Path -like "*TestClass2*") {
                    throw "Syntax error"
                }
            }

            $result = Import-SecureClasses -ClassList $script:TestClassList -ValidationMode 'Strict'

            $result.ImportedClasses | Should -HaveCount 1
            $result.FailedClasses | Should -HaveCount 1
            $result.FailedClasses[0].Reason | Should Be "Syntax error"
        }

        It "Should handle empty class list" {
            $result = Import-SecureClasses -ClassList @()

            $result.ImportedClasses | Should BeNullOrEmpty
            $result.FailedClasses | Should BeNullOrEmpty
        }

        It "Should support different validation modes" {
            Mock Test-Path { return $true }
            Mock Get-Content { return @("class TestClass { }") }
            Mock . { throw "Validation error" }

            # Lenient mode should continue on errors
            $result = Import-SecureClasses -ClassList $script:TestClassList -ValidationMode 'Lenient' -ErrorAction Continue

            $result.FailedClasses | Should -HaveCount 2
        }

        It "Should track import timing for performance monitoring" {
            Mock Test-Path { return $true }
            Mock Get-Content { return @("class TestClass { }") }
            Mock . { Start-Sleep -Milliseconds 50 }

            $result = Import-SecureClasses -ClassList $script:TestClassList

            $result.ImportTiming | Should Not BeNullOrEmpty
            $result.ImportTiming.TotalMilliseconds | Should BeGreaterThan 0
        }
    }

    Context "Error Handling" {
        It "Should handle missing class files" {
            Mock Test-Path { return $false }

            $result = Import-SecureClasses -ClassList $script:TestClassList

            $result.FailedClasses | Should -HaveCount 2
            $result.FailedClasses[0].Reason | Should Match "*not found*"
        }

        It "Should handle file access denied errors" {
            Mock Test-Path { return $true }
            Mock Get-Content { throw "Access is denied" }

            $result = Import-SecureClasses -ClassList $script:TestClassList

            $result.FailedClasses | Should -HaveCount 2
            $result.FailedClasses[0].Reason | Should Match "*Access is denied*"
        }

        It "Should handle corrupted class files" {
            Mock Test-Path { return $true }
            Mock Get-Content { return @("corrupted content") }
            Mock . { throw "Unexpected token" }

            $result = Import-SecureClasses -ClassList $script:TestClassList

            $result.FailedClasses | Should -HaveCount 2
            $result.FailedClasses[0].Reason | Should Match "*Unexpected token*"
        }

        It "Should continue processing after individual failures" {
            Mock Test-Path { return $true }
            Mock Get-Content { return @("class TestClass { }") }
            Mock . {
                param($Path)
                if ($Path -like "*TestClass1*") {
                    throw "Error in class 1"
                }
                # TestClass2 should succeed
            }

            $result = Import-SecureClasses -ClassList $script:TestClassList

            $result.ImportedClasses | Should -HaveCount 1
            $result.FailedClasses | Should -HaveCount 1
        }
    }

    Context "Security Validation" {
        It "Should validate class content for security risks" {
            Mock Test-Path { return $true }
            Mock Get-Content {
                return @(
                    "class TestClass {",
                    "    [string]$Name",
                    "    hidden [string]$SecretData = 'password123'",  # Security risk
                    "}"
                )
            }

            $result = Import-SecureClasses -ClassList $script:TestClassList -ValidationMode 'Strict'

            $result.SecurityViolations | Should Not BeNullOrEmpty
            $result.SecurityViolations[0].Risk | Should Match "*hardcoded*"
        }

        It "Should detect potentially dangerous constructs" {
            Mock Test-Path { return $true }
            Mock Get-Content {
                return @(
                    "class TestClass {",
                    "    [void] ExecuteCommand([string]$Command) {",
                    "        Invoke-Expression $Command",  # Dangerous
                    "    }",
                    "}"
                )
            }

            $result = Import-SecureClasses -ClassList $script:TestClassList -ValidationMode 'Strict'

            $result.SecurityViolations | Should Not BeNullOrEmpty
            $result.SecurityViolations[0].Risk | Should Match "*Invoke-Expression*"
        }

        It "Should validate class inheritance security" {
            Mock Test-Path { return $true }
            Mock Get-Content {
                return @(
                    "class TestClass : System.Management.Automation.PSCmdlet {",  # Potentially risky inheritance
                    "    [string]$Name",
                    "}"
                )
            }

            $result = Import-SecureClasses -ClassList $script:TestClassList -ValidationMode 'Strict'

            $result.SecurityViolations | Should Not BeNullOrEmpty
        }
    }

    Context "Performance and Memory Management" {
        It "Should import large class sets efficiently" {
            $largeClassList = 1..50 | ForEach-Object {
                @{ Name = "Class$_.ps1"; FullName = "C:\Classes\Class$_.ps1" }
            }
            Mock Test-Path { return $true }
            Mock Get-Content { return @("class TestClass$args { }") }
            Mock . { }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Import-SecureClasses -ClassList $largeClassList
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 5000
            $result.ImportedClasses | Should -HaveCount 50
        }

        It "Should manage memory efficiently during import" {
            $largeClassList = 1..20 | ForEach-Object {
                @{ Name = "Class$_.ps1"; FullName = "C:\Classes\Class$_.ps1" }
            }
            Mock Test-Path { return $true }
            Mock Get-Content { return @("class TestClass { }") }
            Mock . { }

            $memoryBefore = [System.GC]::GetTotalMemory($false)
            $result = Import-SecureClasses -ClassList $largeClassList
            [System.GC]::Collect()
            $memoryAfter = [System.GC]::GetTotalMemory($false)

            $memoryIncrease = $memoryAfter -$memoryBefore
            $memoryIncrease | Should BeLessThan 2MB
        }
    }

    Context "Audit and Compliance" {
        It "Should log class import operations with correlation ID" {
            Mock Write-StructuredLog { }
            Mock Test-Path { return $true }
            Mock Get-Content { return @("class TestClass { }") }
            Mock . { }

            Import-SecureClasses -ClassList $script:TestClassList -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*class import*" }
        }

        It "Should log security validation results" {
            Mock Write-StructuredLog { }
            Mock Test-Path { return $true }
            Mock Get-Content { return @("class TestClass { }") }
            Mock . { }

            Import-SecureClasses -ClassList $script:TestClassList -ValidationMode 'Strict'

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*security validation*" }
        }

        It "Should include import timing in audit logs" {
            Mock Write-StructuredLog { }
            Mock Test-Path { return $true }
            Mock Get-Content { return @("class TestClass { }") }
            Mock . { }

            Import-SecureClasses -ClassList $script:TestClassList

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*import completed*" -and $Message -like "*milliseconds*" }
        }
    }

Describe "Test-ClassInstantiation" -Tag "Unit", "ClassManagement", "Validation" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestClassName = "OrphanedSIDResult"
    }

    Context "Parameter Validation" {
        It "Should require ClassName parameter" {
            { Test-ClassInstantiation } | Should Throw "*ClassName*"
        }

        It "Should accept string class name" {
            { Test-ClassInstantiation -ClassName $script:TestClassName } | Should Not Throw
        }

        It "Should accept test parameters" {
            $testParams = @{ Name = "Test"; Value = 123 }
            { Test-ClassInstantiation -ClassName $script:TestClassName -TestParameters $testParams } | Should Not Throw
        }
    }

    Context "Core Functionality" {
        It "Should successfully test valid class instantiation" {
            # Mock a simple class for testing
            Add-Type -TypeDefinition @"
public class TestClass {
    public string Name { get; set; }
    public TestClass() { }
    public TestClass(string name) { Name = name; }
}
"@

            $result = Test-ClassInstantiation -ClassName "TestClass"

            $result | Should Not BeNullOrEmpty
            $result.Success | Should Be $true
            $result.Instance | Should Not BeNullOrEmpty
        }

        It "Should test parameterized constructors" {
            # Mock class with parameters
            Add-Type -TypeDefinition @"
public class ParameterizedTestClass {
    public string Name { get; set; }
    public int Value { get; set; }
    public ParameterizedTestClass(string name, int value) {
        Name = name;
        Value = value;
    }
}
"@

            $testParams = @{ name = "TestName"; value = 42 }
            $result = Test-ClassInstantiation -ClassName "ParameterizedTestClass" -TestParameters $testParams

            $result.Success | Should Be $true
            $result.Instance.Name | Should Be "TestName"
            $result.Instance.Value | Should Be 42
        }

        It "Should handle multiple constructor overloads" {
            Add-Type -TypeDefinition @"
public class MultiConstructorClass {
    public string Name { get; set; }
    public int Value { get; set; }
    public MultiConstructorClass() { }
    public MultiConstructorClass(string name) { Name = name; }
    public MultiConstructorClass(string name, int value) { Name = name; Value = value; }
}
"@

            # Test parameterless constructor
            $result1 = Test-ClassInstantiation -ClassName "MultiConstructorClass"
            $result1.Success | Should Be $true

            # Test single parameter constructor
            $result2 = Test-ClassInstantiation -ClassName "MultiConstructorClass" -TestParameters @{ name = "Test" }
            $result2.Success | Should Be $true
            $result2.Instance.Name | Should Be "Test"
        }

        It "Should validate class properties after instantiation" {
            Add-Type -TypeDefinition @"
public class PropertyTestClass {
    public string RequiredProperty { get; set; }
    public int OptionalProperty { get; set; } = 10;
}
"@

            $result = Test-ClassInstantiation -ClassName "PropertyTestClass" Properties

            $result.Success | Should Be $true
            $result.PropertyValidation | Should Not BeNullOrEmpty
            $result.PropertyValidation.OptionalProperty | Should Be 10
        }

        It "Should test class method availability" {
            Add-Type -TypeDefinition @"
public class MethodTestClass {
    public string GetName() { return "TestMethod"; }
    public int Calculate(int a, int b) { return a + b; }
}
"@

            $result = Test-ClassInstantiation -ClassName "MethodTestClass" -TestMethods

            $result.Success | Should Be $true
            $result.MethodTests | Should Not BeNullOrEmpty
            $result.MethodTests.GetName | Should Be $true
            $result.MethodTests.Calculate | Should Be $true
        }
    }

    Context "Error Handling" {
        It "Should handle non-existent class names" {
            $result = Test-ClassInstantiation -ClassName "NonExistentClass"

            $result.Success | Should Be $false
            $result.Error | Should Match "*cannot find type*"
        }

        It "Should handle constructor parameter mismatches" {
            Add-Type -TypeDefinition @"
public class StrictParameterClass {
    public StrictParameterClass(string required) { }
}
"@

            # Try to instantiate without required parameter
            $result = Test-ClassInstantiation -ClassName "StrictParameterClass"

            $result.Success | Should Be $false
            $result.Error | Should Match "*constructor*"
        }

        It "Should handle classes with private constructors" {
            Add-Type -TypeDefinition @"
public class PrivateConstructorClass {
    private PrivateConstructorClass() { }
    public static PrivateConstructorClass Create() { return new PrivateConstructorClass(); }
}
"@

            $result = Test-ClassInstantiation -ClassName "PrivateConstructorClass"

            $result.Success | Should Be $false
            $result.Error | Should Match "*constructor*"
        }

        It "Should handle classes that throw during construction" {
            Add-Type -TypeDefinition @"
public class ThrowingConstructorClass {
    public ThrowingConstructorClass() {
        throw new System.InvalidOperationException("Constructor error");
    }
}
"@

            $result = Test-ClassInstantiation -ClassName "ThrowingConstructorClass"

            $result.Success | Should Be $false
            $result.Error | Should Match "*Constructor error*"
        }
    }

    Context "Performance and Memory Management" {
        It "Should complete instantiation within acceptable time" {
            Add-Type -TypeDefinition @"
public class PerformanceTestClass {
    public PerformanceTestClass() { }
}
"@

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Test-ClassInstantiation -ClassName "PerformanceTestClass"
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 500
            $result.Success | Should Be $true
        }

        It "Should properly dispose of test instances" {
            Add-Type -TypeDefinition @"
public class DisposableTestClass : System.IDisposable {
    public bool IsDisposed { get; private set; }
    public void Dispose() { IsDisposed = true; }
}
"@

            $result = Test-ClassInstantiation -ClassName "DisposableTestClass" -AutoDispose

            $result.Success | Should Be $true
            $result.InstanceDisposed | Should Be $true
        }

        It "Should handle memory-intensive class instantiation" {
            Add-Type -TypeDefinition @"
public class MemoryIntensiveClass {
    private byte[] data = new byte[1024]; // Small test allocation
    public MemoryIntensiveClass() { }
}
"@

            $memoryBefore = [System.GC]::GetTotalMemory($false)
            $result = Test-ClassInstantiation -ClassName "MemoryIntensiveClass"
            [System.GC]::Collect()
            $memoryAfter = [System.GC]::GetTotalMemory($false)

            $result.Success | Should Be $true
            $memoryIncrease = $memoryAfter -$memoryBefore
            $memoryIncrease | Should BeLessThan 10MB  # Reasonable limit
        }
    }

    Context "Audit and Compliance" {
        It "Should log instantiation tests with correlation ID" {
            Mock Write-StructuredLog { }
            Add-Type -TypeDefinition @"
public class AuditTestClass {
    public AuditTestClass() { }
}
"@

            Test-ClassInstantiation -ClassName "AuditTestClass" -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*instantiation test*" }
        }

        It "Should log security-relevant instantiation attempts" {
            Mock Write-StructuredLog { }
            Add-Type -TypeDefinition @"
public class SecuritySensitiveClass {
    public SecuritySensitiveClass() { }
}
"@

            Test-ClassInstantiation -ClassName "SecuritySensitiveClass"

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*security*" -or $Message -like "*instantiation*" }
        }

        It "Should track instantiation performance metrics" {
            Mock Write-StructuredLog { }
            Add-Type -TypeDefinition @"
public class MetricsTestClass {
    public MetricsTestClass() { }
}
"@

            Test-ClassInstantiation -ClassName "MetricsTestClass"

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*performance*" -or $Message -like "*timing*" }
        }
    }
}





.FullName
}
# Import test helpers if they exist
$TestHelpersPath = Join-Path $PSScriptRoot '..\TestHelpers\TestHelpers.ps1'
if (Test-Path $TestHelpersPath) {
. $TestHelpersPath
}
# Mock external dependencies
Mock Write-Verbose { }
Mock Write-Information { }
Mock Write-Warning { }
Mock Write-Error { }
# Mock file system operations
Mock Test-Path { return $true }
Mock Get-Content { return @() }
Mock Get-ChildItem { return @() }
Mock Import-Module { }
# Mock logging function
Mock Write-StructuredLog { }
# Mock security operations
Mock Get-AuthenticodeSignature { return @{ Status = 'Valid'; SignerCertificate = @{ Subject = 'CN=Test' } } }

Describe "Get-ApprovedClassList" -Tag "Unit", "ClassManagement", "Security" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestClassPath = Join-Path $TestDrive 'Classes'
    }

    Context "Parameter Validation" {
        It "Should accept ClassPath parameter" {
            { Get-ApprovedClassList -ClassPath $script:TestClassPath } | Should Not Throw
        }

        It "Should use default path when not specified" {
            { Get-ApprovedClassList } | Should Not Throw
        }

        It "Should validate class path exists" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $script:TestClassPath }

            { Get-ApprovedClassList -ClassPath $script:TestClassPath } | Should Throw "*ClassPath*"
        }

        It "Should accept correlation ID parameter" {
            { Get-ApprovedClassList -ClassPath $script:TestClassPath -CorrelationId $script:TestCorrelationId } | Should Not Throw
        }
    }

    Context "Core Functionality" {
        It "Should return list of approved classes" {
            $mockClasses = @(
                @{ Name = "OrphanedSIDResult.ps1"; FullName = "$script:TestClassPath\OrphanedSIDResult.ps1" },
                @{ Name = "ProcessingStatistics.ps1"; FullName = "$script:TestClassPath\ProcessingStatistics.ps1" },
                @{ Name = "MemoryManager.ps1"; FullName = "$script:TestClassPath\MemoryManager.ps1" }
            )
            Mock Get-ChildItem { return $mockClasses } -ParameterFilter { $Path -eq $script:TestClassPath }
            Mock Get-AuthenticodeSignature { return @{ Status = 'Valid' } }

            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath

            $result | Should -HaveCount 3
            $result[0].Name | Should Be "OrphanedSIDResult.ps1"
        }

        It "Should filter only PowerShell class files" {
            $mockFiles = @(
                @{ Name = "OrphanedSIDResult.ps1"; FullName = "$script:TestClassPath\OrphanedSIDResult.ps1" },
                @{ Name = "README.md"; FullName = "$script:TestClassPath\README.md" },
                @{ Name = "config.json"; FullName = "$script:TestClassPath\config.json" },
                @{ Name = "ProcessingStatistics.ps1"; FullName = "$script:TestClassPath\ProcessingStatistics.ps1" }
            )
            Mock Get-ChildItem { return $mockFiles }
            Mock Get-AuthenticodeSignature { return @{ Status = 'Valid' } }

            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath

            $result | Should -HaveCount 2
            $result | ForEach-Object { $_.Name | Should Match "\.ps1$" }
        }

        It "Should validate class file signatures" {
            $mockClasses = @(
                @{ Name = "ValidClass.ps1"; FullName = "$script:TestClassPath\ValidClass.ps1" },
                @{ Name = "InvalidClass.ps1"; FullName = "$script:TestClassPath\InvalidClass.ps1" }
            )
            Mock Get-ChildItem { return $mockClasses }
            Mock Get-AuthenticodeSignature {
                param($FilePath)
                if ($FilePath -like "*ValidClass*") {
                    return @{ Status = 'Valid'; SignerCertificate = @{ Subject = 'CN=TrustedPublisher' } }
                } else {
                    return @{ Status = 'NotSigned' }
                }
            }

            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath -RequireSignature

            $result | Should -HaveCount 1
            $result[0].Name | Should Be "ValidClass.ps1"
        }

        It "Should return empty array when no classes found" {
            Mock Get-ChildItem { return @() }

            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath

            $result | Should BeNullOrEmpty
        }

        It "Should include class metadata" {
            $mockClasses = @(
                @{ Name = "TestClass.ps1"; FullName = "$script:TestClassPath\TestClass.ps1"; LastWriteTime = (Get-Date) }
            )
            Mock Get-ChildItem { return $mockClasses }
            Mock Get-AuthenticodeSignature { return @{ Status = 'Valid' } }
            Mock Get-Content { return @("class TestClass {", "    [string]$Name", "}") }

            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath

            $result | Should -HaveCount 1
            $result[0].Name | Should Be "TestClass.ps1"
            $result[0].FullName | Should Be "$script:TestClassPath\TestClass.ps1"
        }
    }

    Context "Error Handling" {
        It "Should handle file access errors" {
            Mock Get-ChildItem { throw "Access is denied" }

            { Get-ApprovedClassList -ClassPath $script:TestClassPath } | Should Throw "*Access is denied*"
        }

        It "Should handle corrupted class files" {
            $mockClasses = @(
                @{ Name = "CorruptedClass.ps1"; FullName = "$script:TestClassPath\CorruptedClass.ps1" }
            )
            Mock Get-ChildItem { return $mockClasses }
            Mock Get-AuthenticodeSignature { throw "File is corrupted" }

            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath -ErrorAction Continue

            $result | Should BeNullOrEmpty
        }

        It "Should handle network path unavailability" {
            Mock Test-Path { throw "The network path was not found" }

            { Get-ApprovedClassList -ClassPath "\\server\share\classes" } | Should Throw "*network path*"
        }
    }

    Context "Performance and Scalability" {
        It "Should handle large class directories efficiently" {
            $largeClassSet = 1..100 | ForEach-Object {
                @{ Name = "Class$_.ps1"; FullName = "$script:TestClassPath\Class$_.ps1"; LastWriteTime = (Get-Date) }
            }
            Mock Get-ChildItem { return $largeClassSet }
            Mock Get-AuthenticodeSignature { return @{ Status = 'Valid' } }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 3000
            $result | Should -HaveCount 100
        }

        It "Should use memory efficiently for large results" {
            $largeClassSet = 1..50 | ForEach-Object {
                @{ Name = "Class$_.ps1"; FullName = "$script:TestClassPath\Class$_.ps1" }
            }
            Mock Get-ChildItem { return $largeClassSet }
            Mock Get-AuthenticodeSignature { return @{ Status = 'Valid' } }

            $memoryBefore = [System.GC]::GetTotalMemory($false)
            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath
            $memoryAfter = [System.GC]::GetTotalMemory($false)

            $memoryIncrease = $memoryAfter -$memoryBefore
            $memoryIncrease | Should BeLessThan 5MB
        }
    }

    Context "Security Validation" {
        It "Should reject unsigned files when signature required" {
            $mockClasses = @(
                @{ Name = "UnsignedClass.ps1"; FullName = "$script:TestClassPath\UnsignedClass.ps1" }
            )
            Mock Get-ChildItem { return $mockClasses }
            Mock Get-AuthenticodeSignature { return @{ Status = 'NotSigned' } }

            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath -RequireSignature

            $result | Should BeNullOrEmpty
        }

        It "Should reject files with invalid signatures" {
            $mockClasses = @(
                @{ Name = "InvalidClass.ps1"; FullName = "$script:TestClassPath\InvalidClass.ps1" }
            )
            Mock Get-ChildItem { return $mockClasses }
            Mock Get-AuthenticodeSignature { return @{ Status = 'UnknownError' } }

            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath -RequireSignature

            $result | Should BeNullOrEmpty
        }

        It "Should validate trusted publishers" {
            $mockClasses = @(
                @{ Name = "TrustedClass.ps1"; FullName = "$script:TestClassPath\TrustedClass.ps1" },
                @{ Name = "UntrustedClass.ps1"; FullName = "$script:TestClassPath\UntrustedClass.ps1" }
            )
            Mock Get-ChildItem { return $mockClasses }
            Mock Get-AuthenticodeSignature {
                param($FilePath)
                if ($FilePath -like "*TrustedClass*") {
                    return @{ Status = 'Valid'; SignerCertificate = @{ Subject = 'CN=TrustedPublisher,O=MyOrg' } }
                } else {
                    return @{ Status = 'Valid'; SignerCertificate = @{ Subject = 'CN=UnknownPublisher' } }
                }
            }

            $trustedPublishers = @('TrustedPublisher')
            $result = Get-ApprovedClassList -ClassPath $script:TestClassPath -RequireSignature -TrustedPublishers $trustedPublishers

            $result | Should -HaveCount 1
            $result[0].Name | Should Be "TrustedClass.ps1"
        }
    }

    Context "Audit and Compliance" {
        It "Should log class discovery operations" {
            Mock Write-StructuredLog { }
            Mock Get-ChildItem { return @() }

            Get-ApprovedClassList -ClassPath $script:TestClassPath -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*class discovery*" }
        }

        It "Should log security validation results" {
            Mock Write-StructuredLog { }
            $mockClasses = @(
                @{ Name = "TestClass.ps1"; FullName = "$script:TestClassPath\TestClass.ps1" }
            )
            Mock Get-ChildItem { return $mockClasses }
            Mock Get-AuthenticodeSignature { return @{ Status = 'NotSigned' } }

            Get-ApprovedClassList -ClassPath $script:TestClassPath -RequireSignature

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*signature validation*" }
        }
    }

Describe "Import-SecureClasses" -Tag "Unit", "ClassManagement", "Import" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestClassList = @(
            @{ Name = "TestClass1.ps1"; FullName = "C:\Classes\TestClass1.ps1" },
            @{ Name = "TestClass2.ps1"; FullName = "C:\Classes\TestClass2.ps1" }
        )
    }

    Context "Parameter Validation" {
        It "Should require ClassList parameter" {
            { Import-SecureClasses } | Should Throw "*ClassList*"
        }

        It "Should accept array of class objects" {
            { Import-SecureClasses -ClassList $script:TestClassList } | Should Not Throw
        }

        It "Should accept validation mode parameter" {
            { Import-SecureClasses -ClassList $script:TestClassList -ValidationMode 'Strict' } | Should Not Throw
        }

        It "Should validate validation mode values" {
            { Import-SecureClasses -ClassList $script:TestClassList -ValidationMode 'InvalidMode' } | Should Throw "*ValidationMode*"
        }
    }

    Context "Core Functionality" {
        It "Should import valid class files successfully" {
            Mock Test-Path { return $true }
            Mock Get-Content { return @("class TestClass {", "    [string]$Name", "}") }
            Mock . { } # Mock dot-sourcing

            $result = Import-SecureClasses -ClassList $script:TestClassList

            $result | Should Not BeNullOrEmpty
            $result.ImportedClasses | Should -HaveCount 2
            $result.FailedClasses | Should BeNullOrEmpty
        }

        It "Should validate class syntax before import" {
            Mock Test-Path { return $true }
            Mock Get-Content {
                param($Path)
                if ($Path -like "*TestClass1*") {
                    return @("class TestClass1 {", "    [string]$Name", "}")  # Valid
                } else {
                    return @("class TestClass2 {", "    invalid syntax", "}")  # Invalid
                }
            }
            Mock . {
                param($Path)
                if ($Path -like "*TestClass2*") {
                    throw "Syntax error"
                }
            }

            $result = Import-SecureClasses -ClassList $script:TestClassList -ValidationMode 'Strict'

            $result.ImportedClasses | Should -HaveCount 1
            $result.FailedClasses | Should -HaveCount 1
            $result.FailedClasses[0].Reason | Should Be "Syntax error"
        }

        It "Should handle empty class list" {
            $result = Import-SecureClasses -ClassList @()

            $result.ImportedClasses | Should BeNullOrEmpty
            $result.FailedClasses | Should BeNullOrEmpty
        }

        It "Should support different validation modes" {
            Mock Test-Path { return $true }
            Mock Get-Content { return @("class TestClass { }") }
            Mock . { throw "Validation error" }

            # Lenient mode should continue on errors
            $result = Import-SecureClasses -ClassList $script:TestClassList -ValidationMode 'Lenient' -ErrorAction Continue

            $result.FailedClasses | Should -HaveCount 2
        }

        It "Should track import timing for performance monitoring" {
            Mock Test-Path { return $true }
            Mock Get-Content { return @("class TestClass { }") }
            Mock . { Start-Sleep -Milliseconds 50 }

            $result = Import-SecureClasses -ClassList $script:TestClassList

            $result.ImportTiming | Should Not BeNullOrEmpty
            $result.ImportTiming.TotalMilliseconds | Should BeGreaterThan 0
        }
    }

    Context "Error Handling" {
        It "Should handle missing class files" {
            Mock Test-Path { return $false }

            $result = Import-SecureClasses -ClassList $script:TestClassList

            $result.FailedClasses | Should -HaveCount 2
            $result.FailedClasses[0].Reason | Should Match "*not found*"
        }

        It "Should handle file access denied errors" {
            Mock Test-Path { return $true }
            Mock Get-Content { throw "Access is denied" }

            $result = Import-SecureClasses -ClassList $script:TestClassList

            $result.FailedClasses | Should -HaveCount 2
            $result.FailedClasses[0].Reason | Should Match "*Access is denied*"
        }

        It "Should handle corrupted class files" {
            Mock Test-Path { return $true }
            Mock Get-Content { return @("corrupted content") }
            Mock . { throw "Unexpected token" }

            $result = Import-SecureClasses -ClassList $script:TestClassList

            $result.FailedClasses | Should -HaveCount 2
            $result.FailedClasses[0].Reason | Should Match "*Unexpected token*"
        }

        It "Should continue processing after individual failures" {
            Mock Test-Path { return $true }
            Mock Get-Content { return @("class TestClass { }") }
            Mock . {
                param($Path)
                if ($Path -like "*TestClass1*") {
                    throw "Error in class 1"
                }
                # TestClass2 should succeed
            }

            $result = Import-SecureClasses -ClassList $script:TestClassList

            $result.ImportedClasses | Should -HaveCount 1
            $result.FailedClasses | Should -HaveCount 1
        }
    }

    Context "Security Validation" {
        It "Should validate class content for security risks" {
            Mock Test-Path { return $true }
            Mock Get-Content {
                return @(
                    "class TestClass {",
                    "    [string]$Name",
                    "    hidden [string]$SecretData = 'password123'",  # Security risk
                    "}"
                )
            }

            $result = Import-SecureClasses -ClassList $script:TestClassList -ValidationMode 'Strict'

            $result.SecurityViolations | Should Not BeNullOrEmpty
            $result.SecurityViolations[0].Risk | Should Match "*hardcoded*"
        }

        It "Should detect potentially dangerous constructs" {
            Mock Test-Path { return $true }
            Mock Get-Content {
                return @(
                    "class TestClass {",
                    "    [void] ExecuteCommand([string]$Command) {",
                    "        Invoke-Expression $Command",  # Dangerous
                    "    }",
                    "}"
                )
            }

            $result = Import-SecureClasses -ClassList $script:TestClassList -ValidationMode 'Strict'

            $result.SecurityViolations | Should Not BeNullOrEmpty
            $result.SecurityViolations[0].Risk | Should Match "*Invoke-Expression*"
        }

        It "Should validate class inheritance security" {
            Mock Test-Path { return $true }
            Mock Get-Content {
                return @(
                    "class TestClass : System.Management.Automation.PSCmdlet {",  # Potentially risky inheritance
                    "    [string]$Name",
                    "}"
                )
            }

            $result = Import-SecureClasses -ClassList $script:TestClassList -ValidationMode 'Strict'

            $result.SecurityViolations | Should Not BeNullOrEmpty
        }
    }

    Context "Performance and Memory Management" {
        It "Should import large class sets efficiently" {
            $largeClassList = 1..50 | ForEach-Object {
                @{ Name = "Class$_.ps1"; FullName = "C:\Classes\Class$_.ps1" }
            }
            Mock Test-Path { return $true }
            Mock Get-Content { return @("class TestClass$args { }") }
            Mock . { }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Import-SecureClasses -ClassList $largeClassList
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 5000
            $result.ImportedClasses | Should -HaveCount 50
        }

        It "Should manage memory efficiently during import" {
            $largeClassList = 1..20 | ForEach-Object {
                @{ Name = "Class$_.ps1"; FullName = "C:\Classes\Class$_.ps1" }
            }
            Mock Test-Path { return $true }
            Mock Get-Content { return @("class TestClass { }") }
            Mock . { }

            $memoryBefore = [System.GC]::GetTotalMemory($false)
            $result = Import-SecureClasses -ClassList $largeClassList
            [System.GC]::Collect()
            $memoryAfter = [System.GC]::GetTotalMemory($false)

            $memoryIncrease = $memoryAfter -$memoryBefore
            $memoryIncrease | Should BeLessThan 2MB
        }
    }

    Context "Audit and Compliance" {
        It "Should log class import operations with correlation ID" {
            Mock Write-StructuredLog { }
            Mock Test-Path { return $true }
            Mock Get-Content { return @("class TestClass { }") }
            Mock . { }

            Import-SecureClasses -ClassList $script:TestClassList -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*class import*" }
        }

        It "Should log security validation results" {
            Mock Write-StructuredLog { }
            Mock Test-Path { return $true }
            Mock Get-Content { return @("class TestClass { }") }
            Mock . { }

            Import-SecureClasses -ClassList $script:TestClassList -ValidationMode 'Strict'

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*security validation*" }
        }

        It "Should include import timing in audit logs" {
            Mock Write-StructuredLog { }
            Mock Test-Path { return $true }
            Mock Get-Content { return @("class TestClass { }") }
            Mock . { }

            Import-SecureClasses -ClassList $script:TestClassList

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*import completed*" -and $Message -like "*milliseconds*" }
        }
    }

Describe "Test-ClassInstantiation" -Tag "Unit", "ClassManagement", "Validation" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestClassName = "OrphanedSIDResult"
    }

    Context "Parameter Validation" {
        It "Should require ClassName parameter" {
            { Test-ClassInstantiation } | Should Throw "*ClassName*"
        }

        It "Should accept string class name" {
            { Test-ClassInstantiation -ClassName $script:TestClassName } | Should Not Throw
        }

        It "Should accept test parameters" {
            $testParams = @{ Name = "Test"; Value = 123 }
            { Test-ClassInstantiation -ClassName $script:TestClassName -TestParameters $testParams } | Should Not Throw
        }
    }

    Context "Core Functionality" {
        It "Should successfully test valid class instantiation" {
            # Mock a simple class for testing
            Add-Type -TypeDefinition @"
public class TestClass {
    public string Name { get; set; }
    public TestClass() { }
    public TestClass(string name) { Name = name; }
}
"@

            $result = Test-ClassInstantiation -ClassName "TestClass"

            $result | Should Not BeNullOrEmpty
            $result.Success | Should Be $true
            $result.Instance | Should Not BeNullOrEmpty
        }

        It "Should test parameterized constructors" {
            # Mock class with parameters
            Add-Type -TypeDefinition @"
public class ParameterizedTestClass {
    public string Name { get; set; }
    public int Value { get; set; }
    public ParameterizedTestClass(string name, int value) {
        Name = name;
        Value = value;
    }
}
"@

            $testParams = @{ name = "TestName"; value = 42 }
            $result = Test-ClassInstantiation -ClassName "ParameterizedTestClass" -TestParameters $testParams

            $result.Success | Should Be $true
            $result.Instance.Name | Should Be "TestName"
            $result.Instance.Value | Should Be 42
        }

        It "Should handle multiple constructor overloads" {
            Add-Type -TypeDefinition @"
public class MultiConstructorClass {
    public string Name { get; set; }
    public int Value { get; set; }
    public MultiConstructorClass() { }
    public MultiConstructorClass(string name) { Name = name; }
    public MultiConstructorClass(string name, int value) { Name = name; Value = value; }
}
"@

            # Test parameterless constructor
            $result1 = Test-ClassInstantiation -ClassName "MultiConstructorClass"
            $result1.Success | Should Be $true

            # Test single parameter constructor
            $result2 = Test-ClassInstantiation -ClassName "MultiConstructorClass" -TestParameters @{ name = "Test" }
            $result2.Success | Should Be $true
            $result2.Instance.Name | Should Be "Test"
        }

        It "Should validate class properties after instantiation" {
            Add-Type -TypeDefinition @"
public class PropertyTestClass {
    public string RequiredProperty { get; set; }
    public int OptionalProperty { get; set; } = 10;
}
"@

            $result = Test-ClassInstantiation -ClassName "PropertyTestClass" Properties

            $result.Success | Should Be $true
            $result.PropertyValidation | Should Not BeNullOrEmpty
            $result.PropertyValidation.OptionalProperty | Should Be 10
        }

        It "Should test class method availability" {
            Add-Type -TypeDefinition @"
public class MethodTestClass {
    public string GetName() { return "TestMethod"; }
    public int Calculate(int a, int b) { return a + b; }
}
"@

            $result = Test-ClassInstantiation -ClassName "MethodTestClass" -TestMethods

            $result.Success | Should Be $true
            $result.MethodTests | Should Not BeNullOrEmpty
            $result.MethodTests.GetName | Should Be $true
            $result.MethodTests.Calculate | Should Be $true
        }
    }

    Context "Error Handling" {
        It "Should handle non-existent class names" {
            $result = Test-ClassInstantiation -ClassName "NonExistentClass"

            $result.Success | Should Be $false
            $result.Error | Should Match "*cannot find type*"
        }

        It "Should handle constructor parameter mismatches" {
            Add-Type -TypeDefinition @"
public class StrictParameterClass {
    public StrictParameterClass(string required) { }
}
"@

            # Try to instantiate without required parameter
            $result = Test-ClassInstantiation -ClassName "StrictParameterClass"

            $result.Success | Should Be $false
            $result.Error | Should Match "*constructor*"
        }

        It "Should handle classes with private constructors" {
            Add-Type -TypeDefinition @"
public class PrivateConstructorClass {
    private PrivateConstructorClass() { }
    public static PrivateConstructorClass Create() { return new PrivateConstructorClass(); }
}
"@

            $result = Test-ClassInstantiation -ClassName "PrivateConstructorClass"

            $result.Success | Should Be $false
            $result.Error | Should Match "*constructor*"
        }

        It "Should handle classes that throw during construction" {
            Add-Type -TypeDefinition @"
public class ThrowingConstructorClass {
    public ThrowingConstructorClass() {
        throw new System.InvalidOperationException("Constructor error");
    }
}
"@

            $result = Test-ClassInstantiation -ClassName "ThrowingConstructorClass"

            $result.Success | Should Be $false
            $result.Error | Should Match "*Constructor error*"
        }
    }

    Context "Performance and Memory Management" {
        It "Should complete instantiation within acceptable time" {
            Add-Type -TypeDefinition @"
public class PerformanceTestClass {
    public PerformanceTestClass() { }
}
"@

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Test-ClassInstantiation -ClassName "PerformanceTestClass"
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 500
            $result.Success | Should Be $true
        }

        It "Should properly dispose of test instances" {
            Add-Type -TypeDefinition @"
public class DisposableTestClass : System.IDisposable {
    public bool IsDisposed { get; private set; }
    public void Dispose() { IsDisposed = true; }
}
"@

            $result = Test-ClassInstantiation -ClassName "DisposableTestClass" -AutoDispose

            $result.Success | Should Be $true
            $result.InstanceDisposed | Should Be $true
        }

        It "Should handle memory-intensive class instantiation" {
            Add-Type -TypeDefinition @"
public class MemoryIntensiveClass {
    private byte[] data = new byte[1024]; // Small test allocation
    public MemoryIntensiveClass() { }
}
"@

            $memoryBefore = [System.GC]::GetTotalMemory($false)
            $result = Test-ClassInstantiation -ClassName "MemoryIntensiveClass"
            [System.GC]::Collect()
            $memoryAfter = [System.GC]::GetTotalMemory($false)

            $result.Success | Should Be $true
            $memoryIncrease = $memoryAfter -$memoryBefore
            $memoryIncrease | Should BeLessThan 10MB  # Reasonable limit
        }
    }

    Context "Audit and Compliance" {
        It "Should log instantiation tests with correlation ID" {
            Mock Write-StructuredLog { }
            Add-Type -TypeDefinition @"
public class AuditTestClass {
    public AuditTestClass() { }
}
"@

            Test-ClassInstantiation -ClassName "AuditTestClass" -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*instantiation test*" }
        }

        It "Should log security-relevant instantiation attempts" {
            Mock Write-StructuredLog { }
            Add-Type -TypeDefinition @"
public class SecuritySensitiveClass {
    public SecuritySensitiveClass() { }
}
"@

            Test-ClassInstantiation -ClassName "SecuritySensitiveClass"

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*security*" -or $Message -like "*instantiation*" }
        }

        It "Should track instantiation performance metrics" {
            Mock Write-StructuredLog { }
            Add-Type -TypeDefinition @"
public class MetricsTestClass {
    public MetricsTestClass() { }
}
"@

            Test-ClassInstantiation -ClassName "MetricsTestClass"

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*performance*" -or $Message -like "*timing*" }
        }
    }
}







