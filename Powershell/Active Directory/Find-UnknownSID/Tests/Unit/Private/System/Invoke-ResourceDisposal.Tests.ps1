#Requires -Version 5.1

<#
.SYNOPSIS
    Pester 3.4 tests for the Private/System/Invoke-ResourceDisposal.ps1 functions

.DESCRIPTION
    Covers the two disposal functions the main script relies on during its end block:
    - Invoke-ResourceCleanup: disposes the MemoryManager and any additional IDisposable resources
    - Invoke-ResourceDisposal: disposes an arbitrary set of resources and reports counts

    Disposal must run even under -WhatIf; only the logging around it honours ShouldProcess.
    These tests use a small IDisposable test double so no real resources are touched.

.NOTES
    PowerShell Version: 5.1+ (Windows PowerShell)
    Pester Version: 3.4.x

    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
#>

$projectRoot = Join-Path $PSScriptRoot '..\..\..\..'

# The MemoryManager class is a typed parameter of Invoke-ResourceCleanup, so it must be defined
# before that file is parsed.
. (Join-Path $projectRoot 'Classes\MemoryManager.ps1')
. (Join-Path $projectRoot 'Private\System\Invoke-ResourceDisposal.ps1')

if (-not (Get-Command Write-StructuredLog -ErrorAction SilentlyContinue)) {
    # Stub so the function under test can be mocked. The parameter names are what the
    # -ParameterFilter blocks below bind to, so they are declared even though unused here.
    function Write-StructuredLog {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
        param($Message, $Level, $Component, $CorrelationId, $Data)
    }
}

# IDisposable test double. Records whether Dispose ran and can be told to fail.
class DisposableProbe : System.IDisposable {
    [bool]$Disposed = $false
    [bool]$ThrowOnDispose = $false

    [void] Dispose() {
        if ($this.ThrowOnDispose) {
            throw 'Dispose failed on purpose'
        }
        $this.Disposed = $true
    }
}

Describe 'Invoke-ResourceCleanup' -Tag 'Unit', 'System' {

    BeforeEach {
        Mock Write-StructuredLog { }
        $script:probe = [DisposableProbe]::new()
    }

    Context 'Additional resources' {
        It 'Disposes every IDisposable passed in AdditionalResources' {
            $second = [DisposableProbe]::new()

            Invoke-ResourceCleanup -AdditionalResources @($script:probe, $second) -CorrelationId 'test-cleanup-1'

            $script:probe.Disposed | Should Be $true
            $second.Disposed | Should Be $true
        }

        It 'Continues disposing when one resource throws' {
            $failing = [DisposableProbe]::new()
            $failing.ThrowOnDispose = $true

            { Invoke-ResourceCleanup -AdditionalResources @($failing, $script:probe) } | Should Not Throw

            $script:probe.Disposed | Should Be $true
        }

        It 'Logs a warning for the resource that failed to dispose' {
            $failing = [DisposableProbe]::new()
            $failing.ThrowOnDispose = $true

            Invoke-ResourceCleanup -AdditionalResources @($failing)

            Assert-MockCalled Write-StructuredLog -Times 1 -Exactly -Scope It -ParameterFilter {
                $Level -eq 'Warning' -and $Message -like 'Failed to dispose additional resource:*'
            }
        }

        It 'Accepts a null AdditionalResources value' {
            { Invoke-ResourceCleanup -AdditionalResources $null } | Should Not Throw
        }
    }

    Context 'Memory manager' {
        It 'Disposes a MemoryManager that has not been disposed' {
            $manager = [MemoryManager]::new(512, 25)

            Invoke-ResourceCleanup -MemoryManager $manager

            $manager.Disposed | Should Be $true
        }

        It 'Does not dispose a MemoryManager twice' {
            $manager = [MemoryManager]::new(512, 25)
            $manager.Dispose()

            { Invoke-ResourceCleanup -MemoryManager $manager } | Should Not Throw

            Assert-MockCalled Write-StructuredLog -Times 0 -Exactly -Scope It -ParameterFilter {
                $Message -eq 'Memory manager disposed successfully'
            }
        }

        It 'Accepts a null MemoryManager' {
            { Invoke-ResourceCleanup -MemoryManager $null } | Should Not Throw
        }
    }

    Context 'WhatIf behaviour' {
        It 'Still disposes resources under -WhatIf' {
            Invoke-ResourceCleanup -AdditionalResources @($script:probe) -WhatIf

            $script:probe.Disposed | Should Be $true
        }

        It 'Logs the WhatIf simulation message instead of the start message under -WhatIf' {
            Invoke-ResourceCleanup -AdditionalResources @($script:probe) -WhatIf

            Assert-MockCalled Write-StructuredLog -Times 1 -Exactly -Scope It -ParameterFilter {
                $Message -like 'WhatIf simulation:*'
            }
            Assert-MockCalled Write-StructuredLog -Times 0 -Exactly -Scope It -ParameterFilter {
                $Message -eq 'Starting resource cleanup and disposal...'
            }
        }
    }

    Context 'Correlation tracking' {
        It 'Passes the supplied CorrelationId to every log entry' {
            Invoke-ResourceCleanup -AdditionalResources @($script:probe) -CorrelationId 'corr-123'

            Assert-MockCalled Write-StructuredLog -Times 0 -Exactly -Scope It -ParameterFilter {
                $CorrelationId -ne 'corr-123'
            }
        }

        It 'Generates a CorrelationId when given whitespace' {
            { Invoke-ResourceCleanup -AdditionalResources @($script:probe) -CorrelationId '   ' } | Should Not Throw

            Assert-MockCalled Write-StructuredLog -Times 0 -Exactly -Scope It -ParameterFilter {
                [string]::IsNullOrWhiteSpace($CorrelationId)
            }
        }
    }
}

Describe 'Invoke-ResourceDisposal' -Tag 'Unit', 'System' {

    BeforeEach {
        Mock Write-StructuredLog { }
    }

    Context 'Disposal counts' {
        It 'Disposes IDisposable resources and counts them' {
            $first = [DisposableProbe]::new()
            $second = [DisposableProbe]::new()

            $result = Invoke-ResourceDisposal -Resources @($first, $second)

            $first.Disposed | Should Be $true
            $second.Disposed | Should Be $true
            $result.TotalResources | Should Be 2
            $result.DisposedCount | Should Be 2
            $result.FailedCount | Should Be 0
            $result.SkippedCount | Should Be 0
        }

        It 'Skips null entries and non-disposable objects' {
            $probe = [DisposableProbe]::new()

            $result = Invoke-ResourceDisposal -Resources @($null, 'just a string', $probe)

            $result.DisposedCount | Should Be 1
            $result.SkippedCount | Should Be 2
        }

        It 'Returns zero counts for an empty collection' {
            $result = Invoke-ResourceDisposal -Resources @()

            $result.TotalResources | Should Be 0
            $result.DisposedCount | Should Be 0
        }
    }

    Context 'Failure handling' {
        It 'Rethrows the first disposal failure without -Force' {
            $failing = [DisposableProbe]::new()
            $failing.ThrowOnDispose = $true

            { Invoke-ResourceDisposal -Resources @($failing) } | Should Throw 'Dispose failed on purpose'
        }

        It 'Continues past a failure and records it with -Force' {
            $failing = [DisposableProbe]::new()
            $failing.ThrowOnDispose = $true
            $probe = [DisposableProbe]::new()

            $result = Invoke-ResourceDisposal -Resources @($failing, $probe) -Force

            $probe.Disposed | Should Be $true
            $result.FailedCount | Should Be 1
            $result.DisposedCount | Should Be 1
            $result.Errors.Count | Should Be 1
            $result.Errors[0] | Should Be 'Dispose failed on purpose'
        }

        It 'Logs the failure at Warning level' {
            $failing = [DisposableProbe]::new()
            $failing.ThrowOnDispose = $true

            Invoke-ResourceDisposal -Resources @($failing) -Force | Out-Null

            Assert-MockCalled Write-StructuredLog -Times 1 -Exactly -Scope It -ParameterFilter {
                $Level -eq 'Warning' -and $Message -like 'Failed to dispose resource DisposableProbe:*'
            }
        }
    }

    Context 'WhatIf behaviour' {
        It 'Still disposes resources under -WhatIf' {
            $probe = [DisposableProbe]::new()

            $result = Invoke-ResourceDisposal -Resources @($probe) -WhatIf

            $probe.Disposed | Should Be $true
            $result.DisposedCount | Should Be 1
        }

        It 'Suppresses informational logging under -WhatIf' {
            $probe = [DisposableProbe]::new()

            Invoke-ResourceDisposal -Resources @($probe) -WhatIf | Out-Null

            Assert-MockCalled Write-StructuredLog -Times 0 -Exactly -Scope It -ParameterFilter {
                $Level -eq 'Information'
            }
        }
    }
}
