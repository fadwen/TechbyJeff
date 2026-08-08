#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }

<#
    Invoke-WebRequest is mocked throughout, so nothing here reaches a network.

    Two of these are regression tests for defects found while building the module.

    1. The failure message swallowed the inner exception and inlined its stack trace.

       "New-Object System.Exception($a + $b, $inner)" does not call the (message, inner)
       constructor. PowerShell binds the whole parenthesised list as ONE array argument, joins
       it to a string, and matches Exception(string) - so the message came out with twenty
       lines of System.Net internals appended and InnerException was never set. The symptom is
       cosmetic until you try to inspect the inner exception and find there isn't one.

    2. Pagination could loop forever.

       Okta will return a Link rel="next" pointing at the page you just fetched. Without a
       comparison against the current URL, -Paginate spins on it until the agent count runs
       out.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-OktaTestRequest' -Tag 'Unit', 'Private' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            $script:Connection = @{
                OrgUrl              = 'https://dev-123456.okta.com'
                AuthorizationHeader = 'SSWS test'
            }
        }
    }

    Context 'Request construction' {

        It 'sends the body as UTF-8 bytes so accented data survives' {
            # Handing Invoke-WebRequest a string lets Windows PowerShell pick the encoding,
            # and it picks one that turns every accented character into a question mark.
            InModuleScope OktaTestEnvironment {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ Content = '{}'; Headers = @{}; RawContentStream = $null }
                }

                $accented = [string][char]0x5A + [string][char]0xFC + 'rich'
                $null = Invoke-OktaTestRequest -Method POST -Path '/api/v1/groups' `
                    -Connection $script:Connection -Body @{ name = $accented }

                Should-Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                    $Body -is [byte[]] -and
                    ([System.Text.Encoding]::UTF8.GetString($Body)).Contains($accented)
                }
            }
        }

        It 'appends and URL-encodes query parameters' {
            InModuleScope OktaTestEnvironment {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ Content = '{}'; Headers = @{}; RawContentStream = $null }
                }

                $null = Invoke-OktaTestRequest -Method GET -Path '/api/v1/users' `
                    -Connection $script:Connection -Query @{ filter = 'status eq "ACTIVE"' }

                # AbsoluteUri, not ToString(). Invoke-WebRequest types -Uri as [uri], and
                # Uri.ToString() UNESCAPES the string it returns, so interpolating the object
                # hands back the decoded form and the assertion tests nothing.
                Should-Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                    $Uri.AbsoluteUri.EndsWith('?filter=status%20eq%20%22ACTIVE%22')
                }
            }
        }

        It 'omits the Authorization header when the connection carries none' {
            # The token endpoint rejects a request that presents both a client assertion and an
            # Authorization header.
            InModuleScope OktaTestEnvironment {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ Content = '{}'; Headers = @{}; RawContentStream = $null }
                }

                $null = Invoke-OktaTestRequest -Method POST -Path '/oauth2/v1/token' `
                    -Connection @{ OrgUrl = 'https://dev-123456.okta.com'; AuthorizationHeader = $null } `
                    -Body 'grant_type=client_credentials' `
                    -ContentType 'application/x-www-form-urlencoded'

                Should-Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                    -not $Headers.ContainsKey('Authorization')
                }
            }
        }

        It 'decodes the response from the raw bytes rather than the parsed content' {
            # Okta sends application/json with no charset, and Windows PowerShell then decodes
            # it as Latin-1. Reading RawContentStream is what keeps accents intact.
            InModuleScope OktaTestEnvironment {
                $accented = 'Ni' + [string][char]0xF1 + 'o'
                $json = '{"name":"' + $accented + '"}'
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

                Mock Invoke-WebRequest {
                    [PSCustomObject]@{
                        # Deliberately wrong, to prove it is not the source that is used.
                        Content          = '{"name":"mojibake"}'
                        Headers          = @{}
                        RawContentStream = [System.IO.MemoryStream]::new($bytes)
                    }
                }

                $result = Invoke-OktaTestRequest -Method GET -Path '/api/v1/groups/x' `
                    -Connection $script:Connection

                $result.name | Should-Be $accented
            }
        }
    }

    Context 'Error reporting' {

        It 'surfaces the Okta errorSummary rather than the generic HTTP message' {
            InModuleScope OktaTestEnvironment {
                Mock Invoke-WebRequest {
                    $response = [PSCustomObject]@{ StatusCode = 400 }
                    $exception = New-Object System.Exception('The remote server returned an error.')
                    $record = New-Object System.Management.Automation.ErrorRecord(
                        $exception, 'BadRequest', 'InvalidOperation', $null)
                    $record.ErrorDetails = New-Object System.Management.Automation.ErrorDetails(
                        '{"errorCode":"E0000001","errorSummary":"Api validation failed","errorCauses":' +
                        '[{"errorSummary":"login: An object with this field already exists"}]}')
                    $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response
                    throw $record
                }

                $thrown = $null
                try {
                    $null = Invoke-OktaTestRequest -Method POST -Path '/api/v1/users' `
                        -Connection $script:Connection -Body @{ x = 1 } -MaxRetry 1
                }
                catch { $thrown = $_ }

                $thrown.Exception.Message | Should-MatchString 'An object with this field already exists'
            }
        }

        It 'keeps the failure message to one line and preserves the inner exception' {
            # The regression. A concatenation inside New-Object's argument list is bound as one
            # array, so the message absorbed the inner exception's whole ToString and
            # InnerException was left null.
            InModuleScope OktaTestEnvironment {
                Mock Invoke-WebRequest {
                    throw (New-Object System.Exception("Something failed.`nStack line one`nStack line two"))
                }

                $thrown = $null
                try {
                    $null = Invoke-OktaTestRequest -Method GET -Path '/api/v1/users' `
                        -Connection $script:Connection -MaxRetry 1
                }
                catch { $thrown = $_ }

                @($thrown.Exception.Message -split "`n").Count | Should-Be 1
                $thrown.Exception.InnerException | Should-NotBeNull
            }
        }

        It 'does not retry a client error' {
            # Retrying a 400 five times turns one clear failure into five identical ones and
            # multiplies the rate limit cost of a bad request by five.
            InModuleScope OktaTestEnvironment {
                Mock Invoke-WebRequest {
                    $response = [PSCustomObject]@{ StatusCode = 400 }
                    $exception = New-Object System.Exception('Bad request')
                    $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response
                    throw $exception
                }

                try {
                    $null = Invoke-OktaTestRequest -Method GET -Path '/api/v1/users' `
                        -Connection $script:Connection -MaxRetry 5
                }
                catch { $null = $_ }

                Should-Invoke Invoke-WebRequest -Times 1 -Exactly
            }
        }
    }

    Context 'Pagination' {

        It 'follows the Link rel="next" header across pages' {
            InModuleScope OktaTestEnvironment {
                $script:PageCount = 0

                Mock Invoke-WebRequest {
                    $script:PageCount++
                    if ($script:PageCount -eq 1) {
                        return [PSCustomObject]@{
                            Content = '[{"id":"a"}]'
                            Headers = @{ Link = '<https://dev-123456.okta.com/api/v1/users?after=a>; rel="next"' }
                            RawContentStream = $null
                        }
                    }
                    return [PSCustomObject]@{ Content = '[{"id":"b"}]'; Headers = @{}; RawContentStream = $null }
                }

                $result = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/users' `
                    -Connection $script:Connection -Paginate)

                $result.Count | Should-Be 2
                @($result.id) | Should-BeCollection @('a', 'b')
            }
        }

        It 'stops when the next link points at the page it just fetched' {
            # Okta really does do this. Without the guard the loop never ends.
            InModuleScope OktaTestEnvironment {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{
                        Content = '[{"id":"a"}]'
                        Headers = @{ Link = '<https://dev-123456.okta.com/api/v1/users>; rel="next"' }
                        RawContentStream = $null
                    }
                }

                $result = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/users' `
                    -Connection $script:Connection -Paginate)

                $result.Count | Should-Be 1
                Should-Invoke Invoke-WebRequest -Times 1 -Exactly
            }
        }

        It 'returns an empty array rather than null when there is nothing to page' {
            # @() and $null behave differently under .Count on Windows PowerShell, and every
            # caller of this treats the result as a collection.
            InModuleScope OktaTestEnvironment {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ Content = '[]'; Headers = @{}; RawContentStream = $null }
                }

                $result = Invoke-OktaTestRequest -Method GET -Path '/api/v1/users' `
                    -Connection $script:Connection -Paginate

                @($result).Count | Should-Be 0
            }
        }
    }
}
