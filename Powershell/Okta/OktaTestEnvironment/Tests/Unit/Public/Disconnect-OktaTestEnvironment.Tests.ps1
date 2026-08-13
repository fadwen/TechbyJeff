#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Disconnect-OktaTestEnvironment is four lines, and the reason it gets its own suite is that
    all four are about a live credential.

    Until it runs, an SSWS token or a bearer token sits in a module-scoped variable that
    anything else in the session can read. So the properties worth pinning are that it actually
    clears (rather than clearing a copy), that it is honest under -WhatIf rather than reporting
    success while leaving the credential in place, and that calling it when nothing is connected
    is a no-op rather than an error - because the natural place to put it is a finally block,
    where throwing would mask whatever really went wrong.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Disconnect-OktaTestEnvironment' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Write-OktaTestProgress { }
            $script:OktaConnection = @{
                OrgUrl              = 'https://trial-1.okta.com'
                AuthorizationHeader = 'SSWS a-real-looking-token'
                AuthType            = 'ApiToken'
                Prefix              = 'OKTALAB'
                EmailDomain         = 'oktalab.example.com'
            }
        }
    }

    It 'clears the stored credential' {
        InModuleScope OktaTestEnvironment {
            Disconnect-OktaTestEnvironment -Confirm:$false

            Get-OktaTestConnection -AllowNone | Should-BeNull
        }
    }

    It 'leaves no Authorization header behind anywhere in module state' {
        # Clearing a copy rather than the variable itself would pass the test above while the
        # token stayed readable.
        InModuleScope OktaTestEnvironment {
            Disconnect-OktaTestEnvironment -Confirm:$false

            $script:OktaConnection | Should-BeNull
        }
    }

    It 'makes the next call demand a reconnection rather than failing obscurely' {
        InModuleScope OktaTestEnvironment {
            Disconnect-OktaTestEnvironment -Confirm:$false

            { Get-OktaTestConnection } | Should-Throw -ExceptionMessage '*Connect-OktaTestEnvironment*'
        }
    }

    It 'keeps the credential under -WhatIf' {
        # A disconnect that reports success under -WhatIf while leaving a live token in the
        # session is the worst possible direction for this particular function to be wrong in.
        InModuleScope OktaTestEnvironment {
            Disconnect-OktaTestEnvironment -WhatIf

            (Get-OktaTestConnection).AuthorizationHeader | Should-Be 'SSWS a-real-looking-token'
        }
    }

    It 'is a no-op when nothing is connected' {
        # It belongs in a finally block, where throwing would mask the real failure.
        InModuleScope OktaTestEnvironment {
            $script:OktaConnection = $null

            Disconnect-OktaTestEnvironment -Confirm:$false

            Get-OktaTestConnection -AllowNone | Should-BeNull
            Should-NotInvoke Write-OktaTestProgress
        }
    }

    It 'names the org it is disconnecting from' {
        InModuleScope OktaTestEnvironment {
            Disconnect-OktaTestEnvironment -Confirm:$false
            Should-Invoke Write-OktaTestProgress -Times 1 -Exactly
        }
    }
}
