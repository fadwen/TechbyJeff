#Requires -Version 5.1

$script:TestPath = $PSScriptRoot
$script:ProjectRoot = Split-Path (Split-Path (Split-Path (Split-Path $TestPath -Parent) -Parent) -Parent) -Parent
$script:FunctionPath = Join-Path $ProjectRoot 'Private\Security\Invoke-SecurityValidation.ps1'

# Dot source the function
. $script:FunctionPath

# Import required dependencies
. (Join-Path $ProjectRoot 'Classes\SecurityValidationResult.ps1')
. (Join-Path $ProjectRoot 'Private\SID\Test-SIDSecurity.ps1')
. (Join-Path $ProjectRoot 'Private\Logging\Write-StructuredLog.ps1')

Describe 'Invoke-SecurityValidation' -Tag 'Unit', 'Private', 'Security' {
    BeforeAll {
        # Mock all external dependencies
        Mock Write-StructuredLog { } -ModuleName $null
    }

    Context 'Parameter Validation' {
        It 'Should accept valid OrphanedSIDs array' {
            $testSIDs = @(
                'S-1-5-21-1234567890-1234567890-1234567890-1001',
                'S-1-5-21-1234567890-1234567890-1234567890-1002'
            )

            Mock Test-SIDSecurity {
                return [PSCustomObject]@{
                    IsValid = $true
                    RiskLevel = 'Low'
                    Issues = @()
                    RequiresElevatedConfirmation = $false
                    BlockedSIDs = @()
                    AllowedSIDs = @($SIDString)
                    ValidatedAt = Get-Date
                    ValidatorVersion = '1.0.0'
                    PSTypeName = 'SecurityValidationResult'
                }
            } -Scope It

            { Invoke-SecurityValidation -OrphanedSIDs $testSIDs } | Should Not Throw
        }

        It 'Should accept ObjectDN parameter' {
            $testSIDs = @(
                'S-1-5-21-1234567890-1234567890-1234567890-1001'
            )

            Mock Test-SIDSecurity {
                return [PSCustomObject]@{
                    IsValid = $true
                    RiskLevel = 'Low'
                    Issues = @()
                    RequiresElevatedConfirmation = $false
                    BlockedSIDs = @()
                    AllowedSIDs = @($SIDString)
                    ValidatedAt = Get-Date
                    ValidatorVersion = '1.0.0'
                    PSTypeName = 'SecurityValidationResult'
                }
            } -Scope It

            { Invoke-SecurityValidation -OrphanedSIDs $testSIDs -ObjectDN 'CN=TestObject,DC=test,DC=com' } | Should Not Throw
        }

        It 'Should throw on null OrphanedSIDs' {
            { Invoke-SecurityValidation -OrphanedSIDs $null } | Should Throw
        }

        It 'Should throw on empty OrphanedSIDs array' {
            { Invoke-SecurityValidation -OrphanedSIDs @() } | Should Throw
        }
    }

    Context 'Security Validation Logic' {
        It 'Should validate regular user SIDs successfully' {
            $testSIDs = @(
                'S-1-5-21-1234567890-1234567890-1234567890-1001'
            )

            Mock Test-SIDSecurity {
                return [PSCustomObject]@{
                    IsValid = $true
                    RiskLevel = 'Low'
                    Issues = @()
                    RequiresElevatedConfirmation = $false
                    BlockedSIDs = @()
                    AllowedSIDs = @($SIDString)
                    ValidatedAt = Get-Date
                    ValidatorVersion = '1.0.0'
                    PSTypeName = 'SecurityValidationResult'
                }
            } -Scope It

            $result = Invoke-SecurityValidation -OrphanedSIDs $testSIDs
            $result | Should Not BeNullOrEmpty
            $result.IsValid | Should Be $true
            $result.RiskLevel | Should Be 'Low'
        }

        It 'Should block protected system SIDs' {
            $testSIDs = @(
                'S-1-5-18'  # Local System
            )

            Mock Test-SIDSecurity {
                return [PSCustomObject]@{
                    IsValid = $false
                    RiskLevel = 'Critical'
                    Issues = @('Protected system SID cannot be removed')
                    RequiresElevatedConfirmation = $true
                    BlockedSIDs = @($SIDString)
                    AllowedSIDs = @()
                    ValidatedAt = Get-Date
                    ValidatorVersion = '1.0.0'
                    PSTypeName = 'SecurityValidationResult'
                }
            } -Scope It

            $result = Invoke-SecurityValidation -OrphanedSIDs $testSIDs
            $result | Should Not BeNullOrEmpty
            $result.IsValid | Should Be $false
            $result.RiskLevel | Should Be 'Critical'
            # Function only sets RequiresElevatedConfirmation for allowed SIDs, not blocked ones
        }

        It 'Should call Test-SIDSecurity with correct parameters' {
            $testSIDs = @(
                'S-1-5-21-1234567890-1234567890-1234567890-1001'
            )
            $objectDN = 'CN=TestObject,DC=test,DC=com'

            Mock Test-SIDSecurity {
                return [PSCustomObject]@{
                    IsValid = $true
                    RiskLevel = 'Low'
                    Issues = @()
                    RequiresElevatedConfirmation = $false
                    BlockedSIDs = @()
                    AllowedSIDs = @($SIDString)
                    ValidatedAt = Get-Date
                    ValidatorVersion = '1.0.0'
                    PSTypeName = 'SecurityValidationResult'
                }
            } -Scope It

            Invoke-SecurityValidation -OrphanedSIDs $testSIDs -ObjectDN $objectDN

            Assert-MockCalled Test-SIDSecurity -Exactly 1 -Scope It -ParameterFilter {
                $SIDString -eq 'S-1-5-21-1234567890-1234567890-1234567890-1001' -and
                $ObjectDN -eq $objectDN
            }
        }
    }

    Context 'Batch Processing' {
        It 'Should process multiple SIDs correctly' {
            $testSIDs = @(
                'S-1-5-21-1234567890-1234567890-1234567890-1001',
                'S-1-5-21-1234567890-1234567890-1234567890-1002',
                'S-1-5-21-1234567890-1234567890-1234567890-1003'
            )

            Mock Test-SIDSecurity {
                return [PSCustomObject]@{
                    IsValid = $true
                    RiskLevel = 'Low'
                    Issues = @()
                    RequiresElevatedConfirmation = $false
                    BlockedSIDs = @()
                    AllowedSIDs = @($SIDString)
                    ValidatedAt = Get-Date
                    ValidatorVersion = '1.0.0'
                    PSTypeName = 'SecurityValidationResult'
                }
            }

            $result = Invoke-SecurityValidation -OrphanedSIDs $testSIDs
            
            # Should call Test-SIDSecurity for each SID
            Assert-MockCalled Test-SIDSecurity -Exactly 3
        }
    }

    Context 'Pipeline Support' {
        It 'Should accept pipeline input' {
            $testSIDs = @(
                'S-1-5-21-1234567890-1234567890-1234567890-1001',
                'S-1-5-21-1234567890-1234567890-1234567890-1002'
            )

            Mock Test-SIDSecurity {
                return [PSCustomObject]@{
                    IsValid = $true
                    RiskLevel = 'Low'
                    Issues = @()
                    RequiresElevatedConfirmation = $false
                    BlockedSIDs = @()
                    AllowedSIDs = @($SIDString)
                    ValidatedAt = Get-Date
                    ValidatorVersion = '1.0.0'
                    PSTypeName = 'SecurityValidationResult'
                }
            }

            $result = $testSIDs | Invoke-SecurityValidation
            $result | Should Not BeNullOrEmpty
        }
    }

    Context 'Error Handling' {
        It 'Should handle validation errors gracefully' {
            $testSIDs = @(
                'S-1-5-ERROR'
            )

            Mock Test-SIDSecurity {
                throw "Simulated validation error for testing"
            } -Scope It

            $result = Invoke-SecurityValidation -OrphanedSIDs $testSIDs
            $result | Should Not BeNullOrEmpty
            $result.IsValid | Should Be $false
            $result.RiskLevel | Should Be 'Critical'
            $result.Issues[0] | Should BeLike "*Simulated validation error*"
        }

        It 'Should handle empty string SID' {
            $testSIDs = @(
                ''
            )

            { Invoke-SecurityValidation -OrphanedSIDs $testSIDs } | Should Throw
        }
    }

    Context 'Logging Integration' {
        It 'Should log security validation events' {
            $testSIDs = @(
                'S-1-5-21-1234567890-1234567890-1234567890-1001'
            )

            Mock Test-SIDSecurity {
                return [PSCustomObject]@{
                    IsValid = $true
                    RiskLevel = 'Low'
                    Issues = @()
                    RequiresElevatedConfirmation = $false
                    BlockedSIDs = @()
                    AllowedSIDs = @($SIDString)
                    ValidatedAt = Get-Date
                    ValidatorVersion = '1.0.0'
                    PSTypeName = 'SecurityValidationResult'
                }
            }

            Invoke-SecurityValidation -OrphanedSIDs $testSIDs

            # Verify structured logging was called
            Assert-MockCalled Write-StructuredLog -Times 1
        }
    }

    Context 'Performance Requirements' {
        It 'Should complete single SID validation within reasonable time' {
            $testSIDs = @(
                'S-1-5-21-1234567890-1234567890-1234567890-1001'
            )

            Mock Test-SIDSecurity {
                Start-Sleep -Milliseconds 5  # Simulate processing time
                return [PSCustomObject]@{
                    IsValid = $true
                    RiskLevel = 'Low'
                    Issues = @()
                    RequiresElevatedConfirmation = $false
                    BlockedSIDs = @()
                    AllowedSIDs = @($SIDString)
                    ValidatedAt = Get-Date
                    ValidatorVersion = '1.0.0'
                    PSTypeName = 'SecurityValidationResult'
                }
            }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Invoke-SecurityValidation -OrphanedSIDs $testSIDs
            $stopwatch.Stop()

            # Should complete within 1 second for single SID
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000
        }
    }
}
