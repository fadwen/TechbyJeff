#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The request body, and the retry behaviour around sending it.

    Retry exists because the evaluate endpoint's reference documents no throttling limits, which
    is not the same as there being none, and a matrix run is precisely the traffic shape that
    finds an unpublished one: dozens of POSTs to a single endpoint as fast as they will go.

    Two things are easy to get wrong and are pinned here. Retrying a 403 or a 400 is worse than
    useless - the request will fail identically forever, and the attempts spend the quota that
    the throttle is about to care about. And giving up has to rethrow rather than return
    something empty, because an empty response folds into a perfectly plausible outcome that
    says every policy is inapplicable.

    The status code is read defensively, from several possible property paths and finally from
    the message, because the exception shape depends on who made the call - and this module
    deliberately lets the caller supply the transport.
#>

# A real typed exception carrying a Response, which is the shape the retry logic reads. Declared
# at file scope because a PowerShell class is resolved when the file is parsed, so it has to
# exist before any test body runs.
class CaOutcomeTestHttpException : System.Exception {
    [object]$Response
    CaOutcomeTestHttpException([string]$message, [int]$statusCode, [int]$retryAfter) : base($message) {
        $headers = @{}
        if ($retryAfter -gt 0) { $headers['Retry-After'] = $retryAfter }
        $this.Response = [PSCustomObject]@{ StatusCode = $statusCode; Headers = $headers }
    }
}

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'CaOutcome.psd1') -Force

    function global:New-HttpError {
        param([int]$StatusCode, [int]$RetryAfterSecond, [string]$Message = 'request failed')
        $exception = [PSCustomObject]@{ Message = $Message; Response = $null }
        if ($StatusCode) {
            $headers = @{}
            if ($RetryAfterSecond) { $headers['Retry-After'] = $RetryAfterSecond }
            $exception.Response = [PSCustomObject]@{
                StatusCode = $StatusCode
                Headers    = $headers
            }
        }
        [PSCustomObject]@{ Exception = $exception }
    }
}

AfterAll {
    Remove-Module CaOutcome -Force -ErrorAction SilentlyContinue
    Remove-Item -Path 'function:global:New-HttpError' -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-CaEvaluateBody' -Tag 'Unit', 'Private' {

    It 'builds an applicationContext for a scenario targeting an application' {
        InModuleScope CaOutcome {
            $body = ConvertTo-CaEvaluateBody -Scenario ([PSCustomObject]@{
                Name = 's'; UserId = 'u1'
                ApplicationId = '00000003-0000-0ff1-ce00-000000000000'
                Conditions = @{ devicePlatform = 'windows' }
            })

            $body.signInContext['@odata.type'] | Should-Be '#microsoft.graph.applicationContext'
            $body.signInContext['includeApplications'] |
                Should-BeCollection @('00000003-0000-0ff1-ce00-000000000000')
            $body.signInIdentity['userId'] | Should-Be 'u1'
        }
    }

    It 'builds a userActionContext for a scenario targeting a user action' {
        InModuleScope CaOutcome {
            $body = ConvertTo-CaEvaluateBody -Scenario ([PSCustomObject]@{
                Name = 's'; UserId = 'u1'; UserAction = 'registerSecurityInformation'
            })

            $body.signInContext['@odata.type'] | Should-Be '#microsoft.graph.userActionContext'
            $body.signInContext['userAction'] | Should-Be 'registerSecurityInformation'
        }
    }

    It 'builds an authContext for a scenario targeting an authentication context' {
        InModuleScope CaOutcome {
            $body = ConvertTo-CaEvaluateBody -Scenario ([PSCustomObject]@{
                Name = 's'; UserId = 'u1'; AuthenticationContext = 'c37'
            })

            $body.signInContext['@odata.type'] | Should-Be '#microsoft.graph.authContext'
            $body.signInContext['authenticationContextValue'] | Should-Be 'c37'
        }
    }

    It 'always asks for every policy, not only the applying ones' {
        # The projection is meaningless without the report-only policies that did not apply,
        # so this is pinned rather than exposed
        InModuleScope CaOutcome {
            $body = ConvertTo-CaEvaluateBody -Scenario ([PSCustomObject]@{
                Name = 's'; UserId = 'u1'; ApplicationId = 'app'
            })

            $body.appliedPoliciesOnly | Should-BeFalse
        }
    }

    It 'refuses a scenario that targets nothing' {
        InModuleScope CaOutcome {
            { ConvertTo-CaEvaluateBody -Scenario ([PSCustomObject]@{ Name = 's'; UserId = 'u1' }) } |
                Should-Throw -ExceptionMessage '*no application, user action*'
        }
    }

    It 'refuses a scenario with no user, naming the scenario' {
        # Graph rejects it anyway, but with a message that does not say which row of the
        # matrix produced it
        InModuleScope CaOutcome {
            { ConvertTo-CaEvaluateBody -Scenario ([PSCustomObject]@{
                Name = 'admin/office365/managed'; ApplicationId = 'app' }) } |
                Should-Throw -ExceptionMessage "*admin/office365/managed*"
        }
    }
}

Describe 'Get-CaRetryDirective' -Tag 'Unit', 'Private' {

    It 'retries a throttle' {
        InModuleScope CaOutcome {
            (Get-CaRetryDirective -ErrorRecord (New-HttpError -StatusCode 429)).ShouldRetry |
                Should-BeTrue
        }
    }

    It 'retries the transient server codes' {
        InModuleScope CaOutcome {
            foreach ($code in @(502, 503, 504)) {
                (Get-CaRetryDirective -ErrorRecord (New-HttpError -StatusCode $code)).ShouldRetry |
                    Should-BeTrue
            }
        }
    }

    It 'does not retry a request that will fail identically forever' {
        InModuleScope CaOutcome {
            foreach ($code in @(400, 401, 403, 404)) {
                (Get-CaRetryDirective -ErrorRecord (New-HttpError -StatusCode $code)).ShouldRetry |
                    Should-BeFalse
            }
        }
    }

    It 'honours Retry-After over any backoff of its own' {
        InModuleScope CaOutcome {
            $directive = Get-CaRetryDirective -ErrorRecord (New-HttpError -StatusCode 429 `
                -RetryAfterSecond 17)
            $directive.RetryAfterSecond | Should-Be 17
        }
    }

    It 'reads Retry-After from the HttpClient header shape as well as the raw one' {
        # HttpClient surfaces it as RetryAfter.Delta, older stacks as a Retry-After string.
        # Both are attempted because the transport is the caller's choice, not this module's.
        InModuleScope CaOutcome {
            $httpClientShape = [PSCustomObject]@{
                Exception = [PSCustomObject]@{
                    Message = 'throttled'
                    Response = [PSCustomObject]@{
                        StatusCode = 429
                        Headers = [PSCustomObject]@{
                            RetryAfter = [PSCustomObject]@{
                                Delta = [PSCustomObject]@{ TotalSeconds = 12.4 }
                            }
                        }
                    }
                }
            }

            $directive = Get-CaRetryDirective -ErrorRecord $httpClientShape
            $directive.ShouldRetry | Should-BeTrue
            # Rounded up: waiting less than the server asked is what gets you throttled again
            $directive.RetryAfterSecond | Should-Be 13
        }
    }

    It 'falls back to the message when no status code can be found' {
        InModuleScope CaOutcome {
            $throttled = New-HttpError -Message 'Response status code 429 (Too Many Requests)'
            (Get-CaRetryDirective -ErrorRecord $throttled).ShouldRetry | Should-BeTrue
        }
    }

    It 'does not read every unrecognised failure as transient' {
        InModuleScope CaOutcome {
            $broken = New-HttpError -Message 'The property signInConditions is invalid'
            (Get-CaRetryDirective -ErrorRecord $broken).ShouldRetry | Should-BeFalse
        }
    }
}

Describe 'Invoke-CaEvaluateRequest' -Tag 'Unit', 'Private' {

    It 'returns the handler result when the first attempt succeeds' {
        InModuleScope CaOutcome {
            $handler = { 'response' }
            Invoke-CaEvaluateRequest -Body @{ a = 1 } -RequestHandler $handler | Should-Be 'response'
        }
    }

    It 'retries a throttle and returns the eventual success' {
        InModuleScope CaOutcome {
            $script:calls = 0
            # The handler is called as & $handler $body $uri; a block with no param() simply
            # ignores both arguments
            $handler = {
                $script:calls++
                if ($script:calls -lt 3) { throw 'Response status code 429 (Too Many Requests)' }
                'recovered'
            }

            $result = Invoke-CaEvaluateRequest -Body @{ a = 1 } -RequestHandler $handler `
                -InitialBackoffSecond 0
            $result | Should-Be 'recovered'
            $script:calls | Should-Be 3
        }
    }

    It 'gives up after MaxRetry and rethrows rather than returning nothing' {
        # An empty response folds into a plausible outcome saying every policy is inapplicable,
        # which is a confident wrong answer
        InModuleScope CaOutcome {
            $script:calls = 0
            $handler = {
                $script:calls++
                throw 'Response status code 429 (Too Many Requests)'
            }

            { Invoke-CaEvaluateRequest -Body @{ a = 1 } -RequestHandler $handler `
                -InitialBackoffSecond 0 -MaxRetry 2 } | Should-Throw

            $script:calls | Should-Be 3   # the first attempt plus two retries
        }
    }

    It 'does not retry a request the server has rejected outright' {
        InModuleScope CaOutcome {
            $script:calls = 0
            $handler = {
                $script:calls++
                throw 'The property signInConditions is invalid'
            }

            { Invoke-CaEvaluateRequest -Body @{ a = 1 } -RequestHandler $handler `
                -InitialBackoffSecond 0 } | Should-Throw

            $script:calls | Should-Be 1
        }
    }

    It 'hands the body and the uri to the handler' {
        InModuleScope CaOutcome {
            $handler = { param($Body, $Uri) "$Uri|$($Body.marker)" }
            Invoke-CaEvaluateRequest -Body @{ marker = 'x' } -Uri 'https://example.test/e' `
                -RequestHandler $handler | Should-Be 'https://example.test/e|x'
        }
    }

    It 'says what to do when no handler is given and the Graph SDK is absent' {
        <#
            The default handler is the module's only contact with Microsoft.Graph.Authentication,
            and the SDK is deliberately not a RequiredModule - so this is the path a user hits
            on a bare host. The message has to name the fix, because "command not found" from
            somewhere inside a private function does not.
        #>
        InModuleScope CaOutcome {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Invoke-MgGraphRequest' }

            { Invoke-CaEvaluateRequest -Body @{ a = 1 } } |
                Should-Throw -ExceptionMessage '*Invoke-MgGraphRequest was not found*'
        }
    }

    It 'waits for as long as the server asked before retrying' {
        # Exercises the Retry-After path end to end rather than only Get-CaRetryDirective:
        # the server's number has to reach Start-Sleep, not just be parsed
        InModuleScope CaOutcome {
            $script:attempts = 0
            $handler = {
                $script:attempts++
                if ($script:attempts -eq 1) {
                    throw [CaOutcomeTestHttpException]::new('too many requests', 429, 1)
                }
                'recovered'
            }

            $elapsed = Measure-Command {
                $script:result = Invoke-CaEvaluateRequest -Body @{ a = 1 } -RequestHandler $handler `
                    -InitialBackoffSecond 30
            }

            $script:result | Should-Be 'recovered'
            $script:attempts | Should-Be 2

            # The 30 second backoff was overridden by the server's Retry-After of 1
            $elapsed.TotalSeconds | Should-BeLessThan 20
        }
    }
}
