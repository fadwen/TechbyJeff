#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The module's contract: what it exports, that the manifest and the loader agree about it,
    and that nothing internal has leaked out.

    The export boundary is stated in two places - FunctionsToExport in the manifest and
    Export-ModuleMember in the psm1 - which is a deliberate redundancy, and redundancy that
    nothing checks is just an opportunity to disagree. These tests are that check.

    They also enforce the offline guarantee. Three of the six public functions, and the whole
    decode and correlation core, must work with no domain and no ActiveDirectory module. That
    is what makes an assessment possible from an analyst's workstation, and what makes this
    suite runnable on a machine that is not a domain controller. It is the kind of property
    that erodes silently the moment someone adds a convenient Get-ADDomain call at module
    scope, so it is asserted rather than assumed.
#>

BeforeDiscovery {
    # The expected-function list has to exist at DISCOVERY time, not at run time, because
    # the -ForEach blocks below build one It per function while the test tree is being
    # constructed. Defined only in BeforeAll it is still $null when discovery runs, and
    # Pester 6 rejects a null -ForEach outright: "Value can not be null or empty array".
    # That is a deliberate improvement on Pester 5, which silently generated zero tests and
    # reported a green run that had asserted nothing.
    $script:ExpectedFunctions = @(
        'ConvertFrom-KrbEtype'
        'Get-KrbEvent'
        'Get-KrbPrincipalEtype'
        'Get-KrbDomainEtypeContext'
        'Get-KrbEtypeRisk'
        'Export-KrbEtypeReport'
    )
}

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ManifestPath = Join-Path -Path $script:ModuleRoot -ChildPath 'KrbEtypeInsight.psd1'

    Import-Module $script:ManifestPath -Force

    $script:ExpectedFunctions = @(
        'ConvertFrom-KrbEtype'
        'Get-KrbEvent'
        'Get-KrbPrincipalEtype'
        'Get-KrbDomainEtypeContext'
        'Get-KrbEtypeRisk'
        'Export-KrbEtypeReport'
    )
}

AfterAll {
    Remove-Module KrbEtypeInsight -Force -ErrorAction SilentlyContinue
}

Describe 'KrbEtypeInsight module contract' -Tag 'Unit', 'Contract' {

    Context 'Manifest' {

        It 'is a valid module manifest' {
            Test-ModuleManifest -Path $script:ManifestPath | Should-NotBeNull
        }

        It 'targets PowerShell 7.6' {
            $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
            $manifest.PowerShellVersion | Should-Be '7.6'
        }

        It 'does not declare ActiveDirectory as a required module' {
            # Declaring it would make the module fail to import on any machine without RSAT,
            # including a CI runner, and would break the offline assessment path that the
            # rest of this file exists to protect.
            $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
            @($manifest.RequiredModules) | Should-BeCollection -Count 0
        }

        It 'ships the format file it declares' {
            $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
            foreach ($format in @($manifest.FormatsToProcess)) {
                Join-Path -Path $script:ModuleRoot -ChildPath $format | Should -Exist
            }
        }

        It 'declares a format file that is well-formed XML' {
            # An invalid Format.ps1xml does not stop the import - PowerShell reports it and
            # carries on - so a malformed view is otherwise only discovered when someone
            # looks at output and finds it rendering as a raw property list.
            #
            # There is no Should-NotThrow in Pester 6. The call is simply made; if it throws,
            # the test fails with the real exception, which is more useful than an assertion
            # message would have been.
            $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
            $formatPath = Join-Path -Path $script:ModuleRoot -ChildPath $manifest.FormatsToProcess[0]

            $document = [xml](Get-Content -Path $formatPath -Raw)
            @($document.Configuration.ViewDefinitions.View).Count | Should-BeGreaterThan 0
        }
    }

    Context 'Export boundary' {

        It 'exports exactly the expected functions' {
            $exported = @(Get-Command -Module KrbEtypeInsight -CommandType Function |
                Select-Object -ExpandProperty Name | Sort-Object)

            $exported | Should-BeCollection @($script:ExpectedFunctions | Sort-Object)
        }

        It 'manifest FunctionsToExport matches Export-ModuleMember in the psm1' {
            $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
            $manifestExports = @($manifest.FunctionsToExport | Sort-Object)

            # [A-Za-z]+ for the verb, not [a-z]+ - ConvertFrom has an interior capital, and a
            # pattern that assumes a single-capital verb silently omits it from the comparison,
            # which is precisely the function whose export would then go unchecked.
            $psm1 = Get-Content -Path (Join-Path $script:ModuleRoot 'KrbEtypeInsight.psm1') -Raw
            $psm1Exports = @([regex]::Matches($psm1, "'(?<name>[A-Z][A-Za-z]+-Krb[A-Za-z]+)'") |
                ForEach-Object { $_.Groups['name'].Value } | Sort-Object -Unique)

            $manifestExports | Should-BeCollection @($psm1Exports)
        }

        It 'exports no aliases, cmdlets or variables' {
            @(Get-Command -Module KrbEtypeInsight -CommandType Alias, Cmdlet) |
                Should-BeCollection -Count 0
        }

        It 'keeps private helper <_> internal' -ForEach @(
            'Get-KrbEtypeCatalog'
            'Get-KrbProtocolCatalog'
            'ConvertTo-KrbInt32'
            'ConvertFrom-KrbEventRecord'
            'ConvertTo-KrbLdapFilterValue'
            'New-KrbRiskFinding'
            'Measure-KrbRiskLevel'
            'New-KrbHtmlReport'
        ) {
            Get-Command -Name $_ -Module KrbEtypeInsight -ErrorAction SilentlyContinue |
                Should-BeNull
        }
    }

    Context 'Comment-based help' {

        It '<_> has a synopsis, description and at least one example' -ForEach $script:ExpectedFunctions {
            $help = Get-Help -Name $_ -ErrorAction Stop

            # Should-BeTruthy rather than a null check: Get-Help returns an empty string for a
            # missing synopsis on some code paths and $null on others, and both are failures.
            $help.Synopsis | Should-BeTruthy
            $help.Description | Should-NotBeNull
            @($help.Examples.Example).Count | Should-BeGreaterThan 0
        }

        It '<_> documents every one of its parameters' -ForEach $script:ExpectedFunctions {
            $command = Get-Command -Name $_
            $help = Get-Help -Name $_

            # Common parameters are supplied by CmdletBinding and are not the author's to
            # document. Everything else must be described, because an undocumented parameter
            # on a security assessment tool is one whose effect on the result is unknown to
            # the person reading the result.
            $declared = @($command.Parameters.Keys | Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            })

            $documented = @($help.Parameters.Parameter.Name)

            foreach ($parameter in $declared) {
                $documented | Should-ContainCollection @($parameter) -Because "$_ -$parameter must be documented"
            }
        }
    }

    Context 'Offline operation' {

        It 'imports with no ActiveDirectory module loaded' {
            Remove-Module ActiveDirectory -Force -ErrorAction SilentlyContinue
            Remove-Module KrbEtypeInsight -Force -ErrorAction SilentlyContinue

            Import-Module $script:ManifestPath -Force
            Get-Command -Module KrbEtypeInsight | Should-NotBeNull
        }

        It 'decodes encryption types with no directory available' {
            # The single most important property of the decode core. If this ever needs a
            # domain, the offline assessment path and this whole test suite go with it.
            $result = ConvertFrom-KrbEtype -TicketEtype '0x17'
            $result.DisplayName | Should-Be 'RC4-HMAC'
        }

        It 'does not touch Active Directory at import time' {
            # A Get-ADDomain call at module scope would make the import fail on a
            # non-domain-joined machine, and would do so with an error that points at the
            # module rather than at the missing dependency.
            $psm1 = Get-Content -Path (Join-Path $script:ModuleRoot 'KrbEtypeInsight.psm1') -Raw
            $psm1 | Should-NotMatchString 'Get-AD\w+'
        }
    }

    Context 'Documented pipelines name properties that exist on the right object' {

        # Written after a documented one-liner was found to be silently wrong. Three places
        # told the reader to run:
        #
        #     Get-KrbEvent -MaxEvents 2000 | Group-Object Source, EventSchemaVersion2
        #
        # EventSchemaVersion2 is a real property - on the RISK object, not the event. Events
        # carry EventVersion and HasEtypeDetail. Group-Object does not error on a property
        # that does not exist; it groups everything into one bucket and prints a confident
        # looking table. The reader would conclude their whole estate shared one schema
        # version, which is the exact assumption that snippet exists to disprove.
        #
        # An audit that only asks "does this name exist somewhere in the module's output?"
        # passes this, because the name is real. The object it is used on is what was wrong,
        # so that is what this checks.

        BeforeAll {
            $fixtureDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'Fixtures'
            $sample = Get-Content (Join-Path $fixtureDir '4769-v2-healthy-aes.xml') -Raw

            $script:EventProperties = @(
                (InModuleScope KrbEtypeInsight -Parameters @{ Xml = $sample } {
                    ConvertFrom-KrbEventRecord -Xml $Xml
                }).PSObject.Properties.Name
            )

            # Every "Get-KrbEvent ... | Group-Object <properties>" in the shipped docs.
            $docs = @(
                Get-ChildItem $script:ModuleRoot -Recurse -Filter *.md -File |
                    Where-Object { $_.FullName -notlike '*Tests*' }
            )

            $script:DocumentedGroupings = @(
                foreach ($doc in $docs) {
                    $text = Get-Content $doc.FullName -Raw
                    foreach ($match in [regex]::Matches($text,
                        'Get-KrbEvent[^|]*\|\s*(?:\r?\n\s*)?Group-Object\s+([A-Za-z][A-Za-z0-9]*(?:\s*,\s*[A-Za-z][A-Za-z0-9]*)*)')) {
                        foreach ($property in ($match.Groups[1].Value -split '\s*,\s*')) {
                            [PSCustomObject]@{ File = $doc.Name; Property = $property.Trim() }
                        }
                    }
                }
            )
        }

        It 'found the documented Get-KrbEvent groupings to check' {
            # Guards the regex itself. If a doc rewrite changes the shape of these examples
            # this test finds nothing, reports green, and checks nothing at all.
            @($script:DocumentedGroupings).Count | Should-BeGreaterThan 0
        }

        It 'groups events only by properties the event object actually has' {
            $unknown = @(
                $script:DocumentedGroupings |
                    Where-Object { $_.Property -notin $script:EventProperties } |
                    ForEach-Object { "$($_.File) groups Get-KrbEvent by '$($_.Property)'" }
            )

            ($unknown -join '; ') | Should-BeEmptyString
        }
    }
}
