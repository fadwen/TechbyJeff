#Requires -Module Pester

# Import test bootstrapper first
$testBootstrapper = Join-Path (Split-Path -Parent $PSScriptRoot) "Infrastructure\TestBootstrapper.ps1"
if (Test-Path $testBootstrapper) {
. $testBootstrapper
}
# Import FileSystem module functions for testing
$FileSystemModulePath = Join-Path $PSScriptRoot '..\..\Private\FileSystem'
Get-ChildItem -Path $FileSystemModulePath -Filter '*.ps1' | ForEach-Object {
    . $_.FullName
}

#Requires -Module Pester

    # Import test bootstrapper first
    $testBootstrapper = Join-Path (Split-Path -Parent $PSScriptRoot) "Infrastructure\TestBootstrapper.ps1"
    if (Test-Path $testBootstrapper) {
        . $testBootstrapper
    }

    # Import FileSystem module functions for testing
    $FileSystemModulePath = Join-Path $PSScriptRoot '..\..\Private\FileSystem'
    Get-ChildItem -Path $FileSystemModulePath -Filter '*.ps1' | ForEach-Object {
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
    Mock New-Item { return @{ FullName = 'MockPath' } }
    Mock Get-Item { return @{ FullName = 'MockPath'; Attributes = 'Directory' } }
    Mock Get-ChildItem { return @() }
    Mock Remove-Item { }
    Mock Out-File { }
    Mock Get-Content { return @() }

    # Mock ACL operations
    Mock Get-Acl { return @{ Access = @(); Owner = 'BUILTIN\Administrators' } }
    Mock Set-Acl { }

    # Mock logging function
    Mock Write-StructuredLog { }

    # Mock security operations
    Mock [System.Security.Principal.WindowsIdentity]::GetCurrent {
        return @{ Name = 'DOMAIN\TestUser'; Groups = @(@{ Value = 'S-1-5-32-544' }) }
    }


Describe "Get-SafeFileName" -Tag "Unit", "FileSystem", "Security" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
    }

    Context "Parameter Validation" {
        It "Should require FileName parameter" {
            { Get-SafeFileName } | Should Throw "*FileName*"
        }

        It "Should accept string input" {
            { Get-SafeFileName -FileName "test.txt" } | Should Not Throw
        }

        It "Should accept correlation ID parameter" {
            { Get-SafeFileName -FileName "test.txt" -CorrelationId $script:TestCorrelationId } | Should Not Throw
        }

        It "Should validate input is not null or empty" {
            { Get-SafeFileName -FileName "" } | Should Throw "*FileName*"
            { Get-SafeFileName -FileName $null } | Should Throw "*FileName*"
        }
    }

    Context "Core Functionality" {
        It "Should return safe filename for valid input" {
            $result = Get-SafeFileName -FileName "ValidFileName.txt"

            $result | Should Be "ValidFileName.txt"
        }

        It "Should sanitize invalid characters" {
            $unsafeFileName = "test<>file|name.txt"
            $result = Get-SafeFileName -FileName $unsafeFileName

            $result | Should Not Match "[<>|]"
            $result | Should Match "^[a-zA-Z0-9\-_\.]+$"
        }

        It "Should remove path traversal attempts" {
            $maliciousFileName = "..\..\..\..\windows\system32\test.txt"
            $result = Get-SafeFileName -FileName $maliciousFileName

            $result | Should Not Match "\.\."
            $result | Should Not Match "\\"
        }

        It "Should handle reserved Windows filenames" {
            $reservedNames = @("CON", "PRN", "AUX", "NUL", "COM1", "LPT1")

            foreach ($reservedName in $reservedNames) {
                $result = Get-SafeFileName -FileName "$reservedName.txt"

                $result | Should Not Be "$reservedName.txt"
                $result | Should Match "^[^_]*_.*\.txt$"  # Should be modified
            }
        }

        It "Should truncate extremely long filenames" {
            $longFileName = "a" * 300 + ".txt"
            $result = Get-SafeFileName -FileName $longFileName

            $result.Length | Should BeLessThan 255
            $result | Should Match "\.txt$"  # Should preserve extension
        }

        It "Should preserve file extensions when possible" {
            $testCases = @(
                @{ Input = "test.doc"; Expected = "\.doc$" }
                @{ Input = "file.xlsx"; Expected = "\.xlsx$" }
                @{ Input = "image.png"; Expected = "\.png$" }
                @{ Input = "script.ps1"; Expected = "\.ps1$" }
            )

            foreach ($testCase in $testCases) {
                $result = Get-SafeFileName -FileName $testCase.Input
                $result | Should Match $testCase.Expected
            }
        }

        It "Should handle multiple periods in filename" {
            $fileName = "test.backup.file.txt"
            $result = Get-SafeFileName -FileName $fileName

            $result | Should Match "\.txt$"
            $result | Should Not Match "\.\."
        }

        It "Should handle Unicode characters appropriately" {
            $unicodeFileName = "tst-fil-am.txt"
            $result = Get-SafeFileName -FileName $unicodeFileName

            $result | Should Not BeNullOrEmpty
            $result | Should Match "\.txt$"
        }
    }

    Context "Security Validation" {
        It "Should prevent null byte injection" {
            $maliciousFileName = "test`0.txt"
            $result = Get-SafeFileName -FileName $maliciousFileName

            $result | Should Not Match "`0"
        }

        It "Should prevent command injection attempts" {
            $maliciousFileName = "test & del *.* & .txt"
            $result = Get-SafeFileName -FileName $maliciousFileName

            $result | Should Not Match "&"
            $result | Should Not Match "del"
            $result | Should Not Match "\*"
        }

        It "Should handle double extension attacks" {
            $maliciousFileName = "document.pdf.exe"
            $result = Get-SafeFileName -FileName $maliciousFileName

            # Should sanitize or block dangerous extensions
            $result | Should Not Match "\.exe$"
        }

        It "Should prevent leading and trailing spaces" {
            $fileName = "  test file  .txt  "
            $result = Get-SafeFileName -FileName $fileName

            $result | Should Not Match "^\s"
            $result | Should Not Match "\s$"
        }

        It "Should prevent leading periods (hidden files)" {
            $fileName = ".hiddenfile.txt"
            $result = Get-SafeFileName -FileName $fileName

            $result | Should Not Match "^\."
        }

        It "Should validate against dangerous file extensions" {
            $dangerousExtensions = @(".exe", ".bat", ".cmd", ".com", ".scr", ".vbs", ".js")

            foreach ($ext in $dangerousExtensions) {
                $fileName = "test$ext"
                $result = Get-SafeFileName -FileName $fileName -BlockDangerousExtensions

                $result | Should Not Match [regex]::Escape($ext) + "$"
            }
        }
    }

    Context "Error Handling" {
        It "Should handle extremely long input gracefully" {
            $veryLongInput = "a" * 10000

            { Get-SafeFileName -FileName $veryLongInput } | Should Not Throw
        }

        It "Should handle input with only invalid characters" {
            $invalidInput = "<>|?*"
            $result = Get-SafeFileName -FileName $invalidInput

            $result | Should Not BeNullOrEmpty
            $result | Should Match "^[a-zA-Z0-9\-_\.]+$"
        }

        It "Should provide fallback filename when input is unsalvageable" {
            $impossibleInput = "....????***"
            $result = Get-SafeFileName -FileName $impossibleInput

            $result | Should Not BeNullOrEmpty
            $result | Should Match "^file_\d{14}$"  # Should generate timestamp-based fallback
        }
    }

    Context "Performance" {
        It "Should process filenames quickly" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            1..100 | ForEach-Object {
                Get-SafeFileName -FileName "test_file_$_.txt"
            }

            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000
        }

        It "Should handle batch processing efficiently" {
            $fileNames = 1..50 | ForEach-Object { "test_file_$_.txt" }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $results = $fileNames | ForEach-Object { Get-SafeFileName -FileName $_ }
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 2000
            $results | Should -HaveCount 50
        }
    }

    Context "Audit and Compliance" {
        It "Should log filename sanitization with correlation ID" {
            Mock Write-StructuredLog { }

            Get-SafeFileName -FileName "test<>file.txt" -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*filename sanitization*" }
        }

        It "Should log security violations" {
            Mock Write-StructuredLog { }

            Get-SafeFileName -FileName "..\..\malicious.exe"

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*security*" -and $Message -like "*path traversal*" }
        }

        It "Should track sanitization metrics" {
            Mock Write-StructuredLog { }

            Get-SafeFileName -FileName "test|file.txt"

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*characters sanitized*" }
        }
    }


Describe "Initialize-LogDirectory" -Tag "Unit", "FileSystem", "Logging" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestLogPath = Join-Path $TestDrive 'logs'
    }

    Context "Parameter Validation" {
        It "Should require LogPath parameter" {
            { Initialize-LogDirectory } | Should Throw "*LogPath*"
        }

        It "Should accept valid path string" {
            { Initialize-LogDirectory -LogPath $script:TestLogPath } | Should Not Throw
        }

        It "Should accept correlation ID parameter" {
            { Initialize-LogDirectory -LogPath $script:TestLogPath -CorrelationId $script:TestCorrelationId } | Should Not Throw
        }

        It "Should validate path format" {
            { Initialize-LogDirectory -LogPath "invalid<>path" } | Should Throw "*LogPath*"
        }
    }

    Context "Core Functionality" {
        It "Should create log directory if it doesn't exist" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $script:TestLogPath }
            Mock New-Item { return @{ FullName = $script:TestLogPath } }

            $result = Initialize-LogDirectory -LogPath $script:TestLogPath

            $result | Should Not BeNullOrEmpty
            $result.LogDirectory | Should Be $script:TestLogPath
            $result.Created | Should Be $true
            Should Invoke New-Item -Exactly 1 -Scope It
        }

        It "Should use existing directory if it exists" {
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $script:TestLogPath }
            Mock Get-Item { return @{ FullName = $script:TestLogPath; Attributes = 'Directory' } }

            $result = Initialize-LogDirectory -LogPath $script:TestLogPath

            $result.LogDirectory | Should Be $script:TestLogPath
            $result.Created | Should Be $false
            Should Invoke New-Item -Exactly 0 -Scope It
        }

        It "Should create nested directory structure" {
            $nestedPath = Join-Path $script:TestLogPath 'nested\deep\structure'
            Mock Test-Path { return $false }
            Mock New-Item { return @{ FullName = $nestedPath } }

            $result = Initialize-LogDirectory -LogPath $nestedPath

            Should Invoke New-Item -ParameterFilter { $ItemType -eq 'Directory' -and $Force -eq $true }
        }

        It "Should set appropriate permissions on log directory" {
            Mock Test-Path { return $false }
            Mock New-Item { return @{ FullName = $script:TestLogPath } }
            Mock Get-Acl { return @{ Access = @(); Owner = 'BUILTIN\Administrators' } }
            Mock Set-Acl { }

            $result = Initialize-LogDirectory -LogPath $script:TestLogPath -SetPermissions

            Should Invoke Set-Acl -Exactly 1 -Scope It
            $result.PermissionsSet | Should Be $true
        }

        It "Should create subdirectories for different log types" {
            Mock Test-Path { return $false }
            Mock New-Item { return @{ FullName = $script:TestLogPath } }

            $result = Initialize-LogDirectory -LogPath $script:TestLogPath -CreateSubdirectories

            $result.Subdirectories | Should Not BeNullOrEmpty
            $result.Subdirectories | Should Contain "Error"
            $result.Subdirectories | Should Contain "Warning"
            $result.Subdirectories | Should Contain "Information"
        }

        It "Should validate directory accessibility" {
            Mock Test-Path { return $true }
            Mock Get-Item { return @{ FullName = $script:TestLogPath; Attributes = 'Directory' } }
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $script:TestLogPath -and $PathType -eq 'Container' }

            $result = Initialize-LogDirectory -LogPath $script:TestLogPath -ValidateAccess

            $result.AccessValidated | Should Be $true
        }

        It "Should handle UNC paths correctly" {
            $uncPath = "\\server\share\logs"
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $uncPath }
            Mock New-Item { return @{ FullName = $uncPath } }

            $result = Initialize-LogDirectory -LogPath $uncPath

            $result.LogDirectory | Should Be $uncPath
            Should Invoke New-Item -ParameterFilter { $Path -eq $uncPath }
        }
    }

    Context "Error Handling" {
        It "Should handle insufficient permissions gracefully" {
            Mock Test-Path { return $false }
            Mock New-Item { throw "Access is denied" }

            { Initialize-LogDirectory -LogPath $script:TestLogPath } | Should Throw "*Access is denied*"
        }

        It "Should handle disk space issues" {
            Mock Test-Path { return $false }
            Mock New-Item { throw "There is not enough space on the disk" }

            { Initialize-LogDirectory -LogPath $script:TestLogPath } | Should Throw "*not enough space*"
        }

        It "Should handle network path unavailability" {
            $networkPath = "\\unreachable\server\logs"
            Mock Test-Path { throw "The network path was not found" }

            { Initialize-LogDirectory -LogPath $networkPath } | Should Throw "*network path*"
        }

        It "Should handle existing file with same name" {
            Mock Test-Path { return $true }
            Mock Get-Item { return @{ FullName = $script:TestLogPath; Attributes = 'Archive' } }  # File, not directory

            { Initialize-LogDirectory -LogPath $script:TestLogPath } | Should Throw "*exists as file*"
        }

        It "Should handle corrupted file system" {
            Mock Test-Path { return $false }
            Mock New-Item { throw "The file or directory is corrupted and unreadable" }

            { Initialize-LogDirectory -LogPath $script:TestLogPath } | Should Throw "*corrupted*"
        }
    }

    Context "Security Validation" {
        It "Should validate path traversal attempts" {
            $maliciousPath = "C:\Windows\System32\..\..\..\..\logs"

            { Initialize-LogDirectory -LogPath $maliciousPath } | Should Throw "*path traversal*"
        }

        It "Should prevent creation in system directories" {
            $systemPath = "C:\Windows\System32\logs"

            { Initialize-LogDirectory -LogPath $systemPath } | Should Throw "*system directory*"
        }

        It "Should validate user has appropriate permissions" {
            Mock Test-Path { return $false }
            Mock New-Item { throw "Access is denied" }

            { Initialize-LogDirectory -LogPath "C:\Program Files\RestrictedLogs" } | Should Throw "*Access is denied*"
        }

        It "Should set secure permissions when requested" {
            Mock Test-Path { return $false }
            Mock New-Item { return @{ FullName = $script:TestLogPath } }
            Mock Get-Acl { return @{ Access = @(); Owner = 'BUILTIN\Administrators' } }
            Mock Set-Acl { }

            $result = Initialize-LogDirectory -LogPath $script:TestLogPath -SetSecurePermissions

            Should Invoke Set-Acl -ParameterFilter { $AclObject.Access | Where-Object { $_.IdentityReference -eq 'BUILTIN\Administrators' } }
        }
    }

    Context "Performance and Scalability" {
        It "Should complete initialization quickly" {
            Mock Test-Path { return $false }
            Mock New-Item { return @{ FullName = $script:TestLogPath } }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Initialize-LogDirectory -LogPath $script:TestLogPath
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000
        }

        It "Should handle multiple concurrent initializations" {
            Mock Test-Path { return $false }
            Mock New-Item { return @{ FullName = $script:TestLogPath } }

            $jobs = 1..5 | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($LogPath)
                    Initialize-LogDirectory -LogPath "$LogPath$_"
                } -ArgumentList $script:TestLogPath
            }

            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job

            $results | Should -HaveCount 5
        }
    }

    Context "Audit and Compliance" {
        It "Should log directory creation with correlation ID" {
            Mock Write-StructuredLog { }
            Mock Test-Path { return $false }
            Mock New-Item { return @{ FullName = $script:TestLogPath } }

            Initialize-LogDirectory -LogPath $script:TestLogPath -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*directory created*" }
        }

        It "Should log security context" {
            Mock Write-StructuredLog { }
            Mock Test-Path { return $false }
            Mock New-Item { return @{ FullName = $script:TestLogPath } }

            Initialize-LogDirectory -LogPath $script:TestLogPath

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*$env:USERNAME*" }
        }

        It "Should track directory usage metrics" {
            Mock Write-StructuredLog { }
            Mock Test-Path { return $false }
            Mock New-Item { return @{ FullName = $script:TestLogPath } }
            Mock Get-ChildItem { return @() }

            Initialize-LogDirectory -LogPath $script:TestLogPath -TrackUsage

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*directory size*" -or $Message -like "*file count*" }
        }
    }


Describe "Test-DirectoryAccess" -Tag "Unit", "FileSystem", "Access" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestDirectoryPath = Join-Path $TestDrive 'testdir'
    }

    Context "Parameter Validation" {
        It "Should require DirectoryPath parameter" {
            { Test-DirectoryAccess } | Should Throw "*DirectoryPath*"
        }

        It "Should accept valid directory path" {
            { Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath } | Should Not Throw
        }

        It "Should validate directory exists" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $script:TestDirectoryPath }

            { Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath } | Should Throw "*DirectoryPath*"
        }

        It "Should accept access type parameter" {
            { Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read' } | Should Not Throw
        }

        It "Should validate access type values" {
            { Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'InvalidType' } | Should Throw "*AccessType*"
        }
    }

    Context "Core Functionality" {
        It "Should test read access successfully" {
            Mock Get-ChildItem { return @() }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read'

            $result | Should Not BeNullOrEmpty
            $result.HasAccess | Should Be $true
            $result.AccessType | Should Be 'Read'
            Should Invoke Get-ChildItem -Exactly 1 -Scope It
        }

        It "Should test write access successfully" {
            $testFile = Join-Path $script:TestDirectoryPath 'write_test.tmp'
            Mock Out-File { }
            Mock Remove-Item { }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Write'

            $result.HasAccess | Should Be $true
            $result.AccessType | Should Be 'Write'
            Should Invoke Out-File -Exactly 1 -Scope It
            Should Invoke Remove-Item -Exactly 1 -Scope It
        }

        It "Should test create access successfully" {
            $testDir = Join-Path $script:TestDirectoryPath 'create_test'
            Mock New-Item { return @{ FullName = $testDir } }
            Mock Remove-Item { }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Create'

            $result.HasAccess | Should Be $true
            $result.AccessType | Should Be 'Create'
            Should Invoke New-Item -Exactly 1 -Scope It
        }

        It "Should test delete access successfully" {
            $testFile = Join-Path $script:TestDirectoryPath 'delete_test.tmp'
            Mock Out-File { }
            Mock Remove-Item { }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Delete'

            $result.HasAccess | Should Be $true
            $result.AccessType | Should Be 'Delete'
        }

        It "Should test execute access successfully" {
            Mock Get-ChildItem { return @() }
            Mock Set-Location { }
            Mock Pop-Location { }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Execute'

            $result.HasAccess | Should Be $true
            $result.AccessType | Should Be 'Execute'
        }

        It "Should test multiple access types" {
            Mock Get-ChildItem { return @() }
            Mock Out-File { }
            Mock Remove-Item { }
            Mock New-Item { return @{ FullName = 'test' } }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType @('Read', 'Write', 'Create')

            $result | Should -HaveCount 3
            $result | ForEach-Object { $_.HasAccess | Should Be $true }
        }

        It "Should include detailed access information" {
            Mock Get-Acl {
                return @{
                    Owner = 'BUILTIN\Administrators'
                    Access = @(
                        @{ IdentityReference = $env:USERNAME; FileSystemRights = 'FullControl'; AccessControlType = 'Allow' }
                    )
                }
            }
            Mock Get-ChildItem { return @() }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read' -Detailed

            $result.HasAccess | Should Be $true
            $result.Owner | Should Be 'BUILTIN\Administrators'
            $result.UserRights | Should Not BeNullOrEmpty
        }
    }

    Context "Error Handling" {
        It "Should detect read access denial" {
            Mock Get-ChildItem { throw "Access is denied" }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read'

            $result.HasAccess | Should Be $false
            $result.Error | Should Match "*Access is denied*"
        }

        It "Should detect write access denial" {
            Mock Out-File { throw "Access is denied" }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Write'

            $result.HasAccess | Should Be $false
            $result.Error | Should Match "*Access is denied*"
        }

        It "Should handle network connectivity issues" {
            $networkPath = "\\server\share\directory"
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $networkPath }
            Mock Get-ChildItem { throw "The network path was not found" }

            $result = Test-DirectoryAccess -DirectoryPath $networkPath -AccessType 'Read'

            $result.HasAccess | Should Be $false
            $result.Error | Should Match "*network path*"
        }

        It "Should handle disk space issues for write tests" {
            Mock Out-File { throw "There is not enough space on the disk" }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Write'

            $result.HasAccess | Should Be $false
            $result.Error | Should Match "*not enough space*"
        }

        It "Should handle corrupted directory" {
            Mock Get-ChildItem { throw "The file or directory is corrupted and unreadable" }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read'

            $result.HasAccess | Should Be $false
            $result.Error | Should Match "*corrupted*"
        }
    }

    Context "Security Validation" {
        It "Should validate user identity in access test" {
            Mock Get-Acl {
                return @{
                    Access = @(
                        @{ IdentityReference = $env:USERNAME; FileSystemRights = 'Read'; AccessControlType = 'Allow' }
                    )
                }
            }
            Mock Get-ChildItem { return @() }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read' -ValidateUser

            $result.HasAccess | Should Be $true
            $result.UserValidated | Should Be $true
        }

        It "Should detect privilege escalation attempts" {
            Mock Get-Acl {
                return @{
                    Access = @(
                        @{ IdentityReference = 'BUILTIN\Administrators'; FileSystemRights = 'FullControl'; AccessControlType = 'Allow' }
                    )
                }
            }
            Mock [System.Security.Principal.WindowsIdentity]::GetCurrent {
                return @{ Name = 'DOMAIN\RegularUser'; Groups = @() }  # Non-admin user
            }
            Mock Get-ChildItem { return @() }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read' -CheckPrivileges

            $result.PrivilegeEscalation | Should Be $false
        }

        It "Should validate against suspicious access patterns" {
            Mock Get-ChildItem { return @() }

            $result = Test-DirectoryAccess -DirectoryPath "C:\Windows\System32" -AccessType 'Write' -SecurityCheck

            $result.SecurityRisk | Should Be $true
            $result.RiskReason | Should Match "*system directory*"
        }
    }

    Context "Performance and Scalability" {
        It "Should complete access tests quickly" {
            Mock Get-ChildItem { return @() }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read'
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 500
        }

        It "Should handle multiple concurrent access tests" {
            Mock Get-ChildItem { return @() }

            $jobs = 1..5 | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($DirectoryPath)
                    Test-DirectoryAccess -DirectoryPath $DirectoryPath -AccessType 'Read'
                } -ArgumentList $script:TestDirectoryPath
            }

            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job

            $results | Should -HaveCount 5
            $results | ForEach-Object { $_.HasAccess | Should Be $true }
        }

        It "Should efficiently test large directories" {
            $largeFileSet = 1..1000 | ForEach-Object {
                @{ Name = "file$_.txt"; FullName = "$script:TestDirectoryPath\file$_.txt" }
            }
            Mock Get-ChildItem { return $largeFileSet }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read'
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 2000
            $result.HasAccess | Should Be $true
        }
    }

    Context "Audit and Compliance" {
        It "Should log access tests with correlation ID" {
            Mock Write-StructuredLog { }
            Mock Get-ChildItem { return @() }

            Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read' -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*access test*" }
        }

        It "Should log security context and user information" {
            Mock Write-StructuredLog { }
            Mock Get-ChildItem { return @() }

            Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read'

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*$env:USERNAME*" -and $Message -like "*access test*" }
        }

        It "Should track access patterns for compliance" {
            Mock Write-StructuredLog { }
            Mock Get-ChildItem { return @() }

            Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read' -TrackCompliance

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*compliance*" -and $Message -like "*access pattern*" }
        }

        It "Should log failed access attempts for security monitoring" {
            Mock Write-StructuredLog { }
            Mock Get-ChildItem { throw "Access is denied" }

            Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read'

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*access denied*" -and $Level -eq "WARNING" }
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
Mock New-Item { return @{ FullName = 'MockPath' } }
Mock Get-Item { return @{ FullName = 'MockPath'; Attributes = 'Directory' } }
Mock Get-ChildItem { return @() }
Mock Remove-Item { }
Mock Out-File { }
Mock Get-Content { return @() }
# Mock ACL operations
Mock Get-Acl { return @{ Access = @(); Owner = 'BUILTIN\Administrators' } }
Mock Set-Acl { }
# Mock logging function
Mock Write-StructuredLog { }
# Mock security operations
Mock [System.Security.Principal.WindowsIdentity]::GetCurrent {
return @{ Name = 'DOMAIN\TestUser'; Groups = @(@{ Value = 'S-1-5-32-544' }) }



Describe "Get-SafeFileName" -Tag "Unit", "FileSystem", "Security" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
    }

    Context "Parameter Validation" {
        It "Should require FileName parameter" {
            { Get-SafeFileName } | Should Throw "*FileName*"
        }

        It "Should accept string input" {
            { Get-SafeFileName -FileName "test.txt" } | Should Not Throw
        }

        It "Should accept correlation ID parameter" {
            { Get-SafeFileName -FileName "test.txt" -CorrelationId $script:TestCorrelationId } | Should Not Throw
        }

        It "Should validate input is not null or empty" {
            { Get-SafeFileName -FileName "" } | Should Throw "*FileName*"
            { Get-SafeFileName -FileName $null } | Should Throw "*FileName*"
        }
    }

    Context "Core Functionality" {
        It "Should return safe filename for valid input" {
            $result = Get-SafeFileName -FileName "ValidFileName.txt"

            $result | Should Be "ValidFileName.txt"
        }

        It "Should sanitize invalid characters" {
            $unsafeFileName = "test<>file|name.txt"
            $result = Get-SafeFileName -FileName $unsafeFileName

            $result | Should Not Match "[<>|]"
            $result | Should Match "^[a-zA-Z0-9\-_\.]+$"
        }

        It "Should remove path traversal attempts" {
            $maliciousFileName = "..\..\..\..\windows\system32\test.txt"
            $result = Get-SafeFileName -FileName $maliciousFileName

            $result | Should Not Match "\.\."
            $result | Should Not Match "\\"
        }

        It "Should handle reserved Windows filenames" {
            $reservedNames = @("CON", "PRN", "AUX", "NUL", "COM1", "LPT1")

            foreach ($reservedName in $reservedNames) {
                $result = Get-SafeFileName -FileName "$reservedName.txt"

                $result | Should Not Be "$reservedName.txt"
                $result | Should Match "^[^_]*_.*\.txt$"  # Should be modified
            }
        }

        It "Should truncate extremely long filenames" {
            $longFileName = "a" * 300 + ".txt"
            $result = Get-SafeFileName -FileName $longFileName

            $result.Length | Should BeLessThan 255
            $result | Should Match "\.txt$"  # Should preserve extension
        }

        It "Should preserve file extensions when possible" {
            $testCases = @(
                @{ Input = "test.doc"; Expected = "\.doc$" }
                @{ Input = "file.xlsx"; Expected = "\.xlsx$" }
                @{ Input = "image.png"; Expected = "\.png$" }
                @{ Input = "script.ps1"; Expected = "\.ps1$" }
            )

            foreach ($testCase in $testCases) {
                $result = Get-SafeFileName -FileName $testCase.Input
                $result | Should Match $testCase.Expected
            }
        }

        It "Should handle multiple periods in filename" {
            $fileName = "test.backup.file.txt"
            $result = Get-SafeFileName -FileName $fileName

            $result | Should Match "\.txt$"
            $result | Should Not Match "\.\."
        }

        It "Should handle Unicode characters appropriately" {
            $unicodeFileName = "tst-fil-am.txt"
            $result = Get-SafeFileName -FileName $unicodeFileName

            $result | Should Not BeNullOrEmpty
            $result | Should Match "\.txt$"
        }
    }

    Context "Security Validation" {
        It "Should prevent null byte injection" {
            $maliciousFileName = "test`0.txt"
            $result = Get-SafeFileName -FileName $maliciousFileName

            $result | Should Not Match "`0"
        }

        It "Should prevent command injection attempts" {
            $maliciousFileName = "test & del *.* & .txt"
            $result = Get-SafeFileName -FileName $maliciousFileName

            $result | Should Not Match "&"
            $result | Should Not Match "del"
            $result | Should Not Match "\*"
        }

        It "Should handle double extension attacks" {
            $maliciousFileName = "document.pdf.exe"
            $result = Get-SafeFileName -FileName $maliciousFileName

            # Should sanitize or block dangerous extensions
            $result | Should Not Match "\.exe$"
        }

        It "Should prevent leading and trailing spaces" {
            $fileName = "  test file  .txt  "
            $result = Get-SafeFileName -FileName $fileName

            $result | Should Not Match "^\s"
            $result | Should Not Match "\s$"
        }

        It "Should prevent leading periods (hidden files)" {
            $fileName = ".hiddenfile.txt"
            $result = Get-SafeFileName -FileName $fileName

            $result | Should Not Match "^\."
        }

        It "Should validate against dangerous file extensions" {
            $dangerousExtensions = @(".exe", ".bat", ".cmd", ".com", ".scr", ".vbs", ".js")

            foreach ($ext in $dangerousExtensions) {
                $fileName = "test$ext"
                $result = Get-SafeFileName -FileName $fileName -BlockDangerousExtensions

                $result | Should Not Match [regex]::Escape($ext) + "$"
            }
        }
    }

    Context "Error Handling" {
        It "Should handle extremely long input gracefully" {
            $veryLongInput = "a" * 10000

            { Get-SafeFileName -FileName $veryLongInput } | Should Not Throw
        }

        It "Should handle input with only invalid characters" {
            $invalidInput = "<>|?*"
            $result = Get-SafeFileName -FileName $invalidInput

            $result | Should Not BeNullOrEmpty
            $result | Should Match "^[a-zA-Z0-9\-_\.]+$"
        }

        It "Should provide fallback filename when input is unsalvageable" {
            $impossibleInput = "....????***"
            $result = Get-SafeFileName -FileName $impossibleInput

            $result | Should Not BeNullOrEmpty
            $result | Should Match "^file_\d{14}$"  # Should generate timestamp-based fallback
        }
    }

    Context "Performance" {
        It "Should process filenames quickly" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            1..100 | ForEach-Object {
                Get-SafeFileName -FileName "test_file_$_.txt"
            }

            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000
        }

        It "Should handle batch processing efficiently" {
            $fileNames = 1..50 | ForEach-Object { "test_file_$_.txt" }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $results = $fileNames | ForEach-Object { Get-SafeFileName -FileName $_ }
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 2000
            $results | Should -HaveCount 50
        }
    }

    Context "Audit and Compliance" {
        It "Should log filename sanitization with correlation ID" {
            Mock Write-StructuredLog { }

            Get-SafeFileName -FileName "test<>file.txt" -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*filename sanitization*" }
        }

        It "Should log security violations" {
            Mock Write-StructuredLog { }

            Get-SafeFileName -FileName "..\..\malicious.exe"

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*security*" -and $Message -like "*path traversal*" }
        }

        It "Should track sanitization metrics" {
            Mock Write-StructuredLog { }

            Get-SafeFileName -FileName "test|file.txt"

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*characters sanitized*" }
        }
    }


Describe "Initialize-LogDirectory" -Tag "Unit", "FileSystem", "Logging" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestLogPath = Join-Path $TestDrive 'logs'
    }

    Context "Parameter Validation" {
        It "Should require LogPath parameter" {
            { Initialize-LogDirectory } | Should Throw "*LogPath*"
        }

        It "Should accept valid path string" {
            { Initialize-LogDirectory -LogPath $script:TestLogPath } | Should Not Throw
        }

        It "Should accept correlation ID parameter" {
            { Initialize-LogDirectory -LogPath $script:TestLogPath -CorrelationId $script:TestCorrelationId } | Should Not Throw
        }

        It "Should validate path format" {
            { Initialize-LogDirectory -LogPath "invalid<>path" } | Should Throw "*LogPath*"
        }
    }

    Context "Core Functionality" {
        It "Should create log directory if it doesn't exist" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $script:TestLogPath }
            Mock New-Item { return @{ FullName = $script:TestLogPath } }

            $result = Initialize-LogDirectory -LogPath $script:TestLogPath

            $result | Should Not BeNullOrEmpty
            $result.LogDirectory | Should Be $script:TestLogPath
            $result.Created | Should Be $true
            Should Invoke New-Item -Exactly 1 -Scope It
        }

        It "Should use existing directory if it exists" {
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $script:TestLogPath }
            Mock Get-Item { return @{ FullName = $script:TestLogPath; Attributes = 'Directory' } }

            $result = Initialize-LogDirectory -LogPath $script:TestLogPath

            $result.LogDirectory | Should Be $script:TestLogPath
            $result.Created | Should Be $false
            Should Invoke New-Item -Exactly 0 -Scope It
        }

        It "Should create nested directory structure" {
            $nestedPath = Join-Path $script:TestLogPath 'nested\deep\structure'
            Mock Test-Path { return $false }
            Mock New-Item { return @{ FullName = $nestedPath } }

            $result = Initialize-LogDirectory -LogPath $nestedPath

            Should Invoke New-Item -ParameterFilter { $ItemType -eq 'Directory' -and $Force -eq $true }
        }

        It "Should set appropriate permissions on log directory" {
            Mock Test-Path { return $false }
            Mock New-Item { return @{ FullName = $script:TestLogPath } }
            Mock Get-Acl { return @{ Access = @(); Owner = 'BUILTIN\Administrators' } }
            Mock Set-Acl { }

            $result = Initialize-LogDirectory -LogPath $script:TestLogPath -SetPermissions

            Should Invoke Set-Acl -Exactly 1 -Scope It
            $result.PermissionsSet | Should Be $true
        }

        It "Should create subdirectories for different log types" {
            Mock Test-Path { return $false }
            Mock New-Item { return @{ FullName = $script:TestLogPath } }

            $result = Initialize-LogDirectory -LogPath $script:TestLogPath -CreateSubdirectories

            $result.Subdirectories | Should Not BeNullOrEmpty
            $result.Subdirectories | Should Contain "Error"
            $result.Subdirectories | Should Contain "Warning"
            $result.Subdirectories | Should Contain "Information"
        }

        It "Should validate directory accessibility" {
            Mock Test-Path { return $true }
            Mock Get-Item { return @{ FullName = $script:TestLogPath; Attributes = 'Directory' } }
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $script:TestLogPath -and $PathType -eq 'Container' }

            $result = Initialize-LogDirectory -LogPath $script:TestLogPath -ValidateAccess

            $result.AccessValidated | Should Be $true
        }

        It "Should handle UNC paths correctly" {
            $uncPath = "\\server\share\logs"
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $uncPath }
            Mock New-Item { return @{ FullName = $uncPath } }

            $result = Initialize-LogDirectory -LogPath $uncPath

            $result.LogDirectory | Should Be $uncPath
            Should Invoke New-Item -ParameterFilter { $Path -eq $uncPath }
        }
    }

    Context "Error Handling" {
        It "Should handle insufficient permissions gracefully" {
            Mock Test-Path { return $false }
            Mock New-Item { throw "Access is denied" }

            { Initialize-LogDirectory -LogPath $script:TestLogPath } | Should Throw "*Access is denied*"
        }

        It "Should handle disk space issues" {
            Mock Test-Path { return $false }
            Mock New-Item { throw "There is not enough space on the disk" }

            { Initialize-LogDirectory -LogPath $script:TestLogPath } | Should Throw "*not enough space*"
        }

        It "Should handle network path unavailability" {
            $networkPath = "\\unreachable\server\logs"
            Mock Test-Path { throw "The network path was not found" }

            { Initialize-LogDirectory -LogPath $networkPath } | Should Throw "*network path*"
        }

        It "Should handle existing file with same name" {
            Mock Test-Path { return $true }
            Mock Get-Item { return @{ FullName = $script:TestLogPath; Attributes = 'Archive' } }  # File, not directory

            { Initialize-LogDirectory -LogPath $script:TestLogPath } | Should Throw "*exists as file*"
        }

        It "Should handle corrupted file system" {
            Mock Test-Path { return $false }
            Mock New-Item { throw "The file or directory is corrupted and unreadable" }

            { Initialize-LogDirectory -LogPath $script:TestLogPath } | Should Throw "*corrupted*"
        }
    }

    Context "Security Validation" {
        It "Should validate path traversal attempts" {
            $maliciousPath = "C:\Windows\System32\..\..\..\..\logs"

            { Initialize-LogDirectory -LogPath $maliciousPath } | Should Throw "*path traversal*"
        }

        It "Should prevent creation in system directories" {
            $systemPath = "C:\Windows\System32\logs"

            { Initialize-LogDirectory -LogPath $systemPath } | Should Throw "*system directory*"
        }

        It "Should validate user has appropriate permissions" {
            Mock Test-Path { return $false }
            Mock New-Item { throw "Access is denied" }

            { Initialize-LogDirectory -LogPath "C:\Program Files\RestrictedLogs" } | Should Throw "*Access is denied*"
        }

        It "Should set secure permissions when requested" {
            Mock Test-Path { return $false }
            Mock New-Item { return @{ FullName = $script:TestLogPath } }
            Mock Get-Acl { return @{ Access = @(); Owner = 'BUILTIN\Administrators' } }
            Mock Set-Acl { }

            $result = Initialize-LogDirectory -LogPath $script:TestLogPath -SetSecurePermissions

            Should Invoke Set-Acl -ParameterFilter { $AclObject.Access | Where-Object { $_.IdentityReference -eq 'BUILTIN\Administrators' } }
        }
    }

    Context "Performance and Scalability" {
        It "Should complete initialization quickly" {
            Mock Test-Path { return $false }
            Mock New-Item { return @{ FullName = $script:TestLogPath } }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Initialize-LogDirectory -LogPath $script:TestLogPath
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000
        }

        It "Should handle multiple concurrent initializations" {
            Mock Test-Path { return $false }
            Mock New-Item { return @{ FullName = $script:TestLogPath } }

            $jobs = 1..5 | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($LogPath)
                    Initialize-LogDirectory -LogPath "$LogPath$_"
                } -ArgumentList $script:TestLogPath
            }

            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job

            $results | Should -HaveCount 5
        }
    }

    Context "Audit and Compliance" {
        It "Should log directory creation with correlation ID" {
            Mock Write-StructuredLog { }
            Mock Test-Path { return $false }
            Mock New-Item { return @{ FullName = $script:TestLogPath } }

            Initialize-LogDirectory -LogPath $script:TestLogPath -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*directory created*" }
        }

        It "Should log security context" {
            Mock Write-StructuredLog { }
            Mock Test-Path { return $false }
            Mock New-Item { return @{ FullName = $script:TestLogPath } }

            Initialize-LogDirectory -LogPath $script:TestLogPath

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*$env:USERNAME*" }
        }

        It "Should track directory usage metrics" {
            Mock Write-StructuredLog { }
            Mock Test-Path { return $false }
            Mock New-Item { return @{ FullName = $script:TestLogPath } }
            Mock Get-ChildItem { return @() }

            Initialize-LogDirectory -LogPath $script:TestLogPath -TrackUsage

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*directory size*" -or $Message -like "*file count*" }
        }
    }


Describe "Test-DirectoryAccess" -Tag "Unit", "FileSystem", "Access" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestDirectoryPath = Join-Path $TestDrive 'testdir'
    }

    Context "Parameter Validation" {
        It "Should require DirectoryPath parameter" {
            { Test-DirectoryAccess } | Should Throw "*DirectoryPath*"
        }

        It "Should accept valid directory path" {
            { Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath } | Should Not Throw
        }

        It "Should validate directory exists" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $script:TestDirectoryPath }

            { Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath } | Should Throw "*DirectoryPath*"
        }

        It "Should accept access type parameter" {
            { Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read' } | Should Not Throw
        }

        It "Should validate access type values" {
            { Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'InvalidType' } | Should Throw "*AccessType*"
        }
    }

    Context "Core Functionality" {
        It "Should test read access successfully" {
            Mock Get-ChildItem { return @() }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read'

            $result | Should Not BeNullOrEmpty
            $result.HasAccess | Should Be $true
            $result.AccessType | Should Be 'Read'
            Should Invoke Get-ChildItem -Exactly 1 -Scope It
        }

        It "Should test write access successfully" {
            $testFile = Join-Path $script:TestDirectoryPath 'write_test.tmp'
            Mock Out-File { }
            Mock Remove-Item { }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Write'

            $result.HasAccess | Should Be $true
            $result.AccessType | Should Be 'Write'
            Should Invoke Out-File -Exactly 1 -Scope It
            Should Invoke Remove-Item -Exactly 1 -Scope It
        }

        It "Should test create access successfully" {
            $testDir = Join-Path $script:TestDirectoryPath 'create_test'
            Mock New-Item { return @{ FullName = $testDir } }
            Mock Remove-Item { }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Create'

            $result.HasAccess | Should Be $true
            $result.AccessType | Should Be 'Create'
            Should Invoke New-Item -Exactly 1 -Scope It
        }

        It "Should test delete access successfully" {
            $testFile = Join-Path $script:TestDirectoryPath 'delete_test.tmp'
            Mock Out-File { }
            Mock Remove-Item { }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Delete'

            $result.HasAccess | Should Be $true
            $result.AccessType | Should Be 'Delete'
        }

        It "Should test execute access successfully" {
            Mock Get-ChildItem { return @() }
            Mock Set-Location { }
            Mock Pop-Location { }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Execute'

            $result.HasAccess | Should Be $true
            $result.AccessType | Should Be 'Execute'
        }

        It "Should test multiple access types" {
            Mock Get-ChildItem { return @() }
            Mock Out-File { }
            Mock Remove-Item { }
            Mock New-Item { return @{ FullName = 'test' } }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType @('Read', 'Write', 'Create')

            $result | Should -HaveCount 3
            $result | ForEach-Object { $_.HasAccess | Should Be $true }
        }

        It "Should include detailed access information" {
            Mock Get-Acl {
                return @{
                    Owner = 'BUILTIN\Administrators'
                    Access = @(
                        @{ IdentityReference = $env:USERNAME; FileSystemRights = 'FullControl'; AccessControlType = 'Allow' }
                    )
                }
            }
            Mock Get-ChildItem { return @() }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read' -Detailed

            $result.HasAccess | Should Be $true
            $result.Owner | Should Be 'BUILTIN\Administrators'
            $result.UserRights | Should Not BeNullOrEmpty
        }
    }

    Context "Error Handling" {
        It "Should detect read access denial" {
            Mock Get-ChildItem { throw "Access is denied" }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read'

            $result.HasAccess | Should Be $false
            $result.Error | Should Match "*Access is denied*"
        }

        It "Should detect write access denial" {
            Mock Out-File { throw "Access is denied" }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Write'

            $result.HasAccess | Should Be $false
            $result.Error | Should Match "*Access is denied*"
        }

        It "Should handle network connectivity issues" {
            $networkPath = "\\server\share\directory"
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $networkPath }
            Mock Get-ChildItem { throw "The network path was not found" }

            $result = Test-DirectoryAccess -DirectoryPath $networkPath -AccessType 'Read'

            $result.HasAccess | Should Be $false
            $result.Error | Should Match "*network path*"
        }

        It "Should handle disk space issues for write tests" {
            Mock Out-File { throw "There is not enough space on the disk" }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Write'

            $result.HasAccess | Should Be $false
            $result.Error | Should Match "*not enough space*"
        }

        It "Should handle corrupted directory" {
            Mock Get-ChildItem { throw "The file or directory is corrupted and unreadable" }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read'

            $result.HasAccess | Should Be $false
            $result.Error | Should Match "*corrupted*"
        }
    }

    Context "Security Validation" {
        It "Should validate user identity in access test" {
            Mock Get-Acl {
                return @{
                    Access = @(
                        @{ IdentityReference = $env:USERNAME; FileSystemRights = 'Read'; AccessControlType = 'Allow' }
                    )
                }
            }
            Mock Get-ChildItem { return @() }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read' -ValidateUser

            $result.HasAccess | Should Be $true
            $result.UserValidated | Should Be $true
        }

        It "Should detect privilege escalation attempts" {
            Mock Get-Acl {
                return @{
                    Access = @(
                        @{ IdentityReference = 'BUILTIN\Administrators'; FileSystemRights = 'FullControl'; AccessControlType = 'Allow' }
                    )
                }
            }
            Mock [System.Security.Principal.WindowsIdentity]::GetCurrent {
                return @{ Name = 'DOMAIN\RegularUser'; Groups = @() }  # Non-admin user
            }
            Mock Get-ChildItem { return @() }

            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read' -CheckPrivileges

            $result.PrivilegeEscalation | Should Be $false
        }

        It "Should validate against suspicious access patterns" {
            Mock Get-ChildItem { return @() }

            $result = Test-DirectoryAccess -DirectoryPath "C:\Windows\System32" -AccessType 'Write' -SecurityCheck

            $result.SecurityRisk | Should Be $true
            $result.RiskReason | Should Match "*system directory*"
        }
    }

    Context "Performance and Scalability" {
        It "Should complete access tests quickly" {
            Mock Get-ChildItem { return @() }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read'
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 500
        }

        It "Should handle multiple concurrent access tests" {
            Mock Get-ChildItem { return @() }

            $jobs = 1..5 | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($DirectoryPath)
                    Test-DirectoryAccess -DirectoryPath $DirectoryPath -AccessType 'Read'
                } -ArgumentList $script:TestDirectoryPath
            }

            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job

            $results | Should -HaveCount 5
            $results | ForEach-Object { $_.HasAccess | Should Be $true }
        }

        It "Should efficiently test large directories" {
            $largeFileSet = 1..1000 | ForEach-Object {
                @{ Name = "file$_.txt"; FullName = "$script:TestDirectoryPath\file$_.txt" }
            }
            Mock Get-ChildItem { return $largeFileSet }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read'
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 2000
            $result.HasAccess | Should Be $true
        }
    }

    Context "Audit and Compliance" {
        It "Should log access tests with correlation ID" {
            Mock Write-StructuredLog { }
            Mock Get-ChildItem { return @() }

            Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read' -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*access test*" }
        }

        It "Should log security context and user information" {
            Mock Write-StructuredLog { }
            Mock Get-ChildItem { return @() }

            Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read'

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*$env:USERNAME*" -and $Message -like "*access test*" }
        }

        It "Should track access patterns for compliance" {
            Mock Write-StructuredLog { }
            Mock Get-ChildItem { return @() }

            Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read' -TrackCompliance

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*compliance*" -and $Message -like "*access pattern*" }
        }

        It "Should log failed access attempts for security monitoring" {
            Mock Write-StructuredLog { }
            Mock Get-ChildItem { throw "Access is denied" }

            Test-DirectoryAccess -DirectoryPath $script:TestDirectoryPath -AccessType 'Read'

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*access denied*" -and $Level -eq "WARNING" }
        }
    }
}







