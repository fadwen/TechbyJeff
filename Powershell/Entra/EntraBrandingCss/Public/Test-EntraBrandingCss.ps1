function Test-EntraBrandingCss {
    <#
    .EXTERNALHELP EntraBrandingCss-Help.xml
    .SYNOPSIS
        Finds retired CSS properties in Entra ID company branding, from files or a tenant
    #>

    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType('EntraBrandingCss.Result')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Tenant',
        Justification = 'The switch selects the parameter set; the set name is what the body reads.')]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory, Position = 0, ValueFromPipeline,
            ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [SupportsWildcards()]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path,

        [Parameter(ParameterSetName = 'Tenant', Mandatory)]
        [switch]$Tenant,

        [Parameter(ParameterSetName = 'Tenant')]
        [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
        [string]$OrganizationId,

        [Parameter(ParameterSetName = 'Tenant')]
        [switch]$IncludeTheme,

        [Parameter(ParameterSetName = 'Tenant')]
        [scriptblock]$RequestHandler
    )

    begin {
        $correlationId = [guid]::NewGuid()
        $mode = $PSCmdlet.ParameterSetName
        Write-Verbose "Starting $($MyInvocation.MyCommand.Name) ($mode) - CorrelationId: $correlationId"
    }

    process {
        if ($PSCmdlet.ParameterSetName -ne 'Path') { return }

        foreach ($item in $Path) {
            # Ignore rather than a try/catch or SilentlyContinue: either of those would put
            # Resolve-Path's own error in the caller's -ErrorVariable beside the one written here
            $resolved = @(Resolve-Path -Path $item -ErrorAction Ignore)
            if ($resolved.Count -eq 0) {
                Write-Error "Path not found: $item - CorrelationId: $correlationId"
                continue
            }

            foreach ($entry in $resolved) {
                $fullPath = $entry.ProviderPath
                if (Test-Path -LiteralPath $fullPath -PathType Container) {
                    Write-Error ("$fullPath is a directory; pass the .css files in it - " +
                        "CorrelationId: $correlationId")
                    continue
                }

                $css = $null
                try {
                    # ReadAllText honors a byte order mark and defaults to UTF-8 without one, on
                    # every PowerShell version. Get-Content on 5.1 would read BOM-less UTF-8 as ANSI.
                    $css = [System.IO.File]::ReadAllText($fullPath)
                } catch {
                    Write-Error ("Could not read $fullPath : $($_.Exception.Message) - " +
                        "CorrelationId: $correlationId")
                    continue
                }

                Invoke-CssScan -Css $css -Source $fullPath -SourceType File -Name (Split-Path -Leaf $fullPath)
            }
        }
    }

    end {
        if ($PSCmdlet.ParameterSetName -eq 'Tenant') {
            $sourceSplat = @{ RequestHandler = $RequestHandler }
            if ($OrganizationId) { $sourceSplat.OrganizationId = $OrganizationId }

            try {
                $sources = @(Get-EntraBrandingSource @sourceSplat)
                if ($IncludeTheme) {
                    $themeOrganizationId = $OrganizationId
                    if (-not $themeOrganizationId -and $sources.Count -gt 0) {
                        $themeOrganizationId = $sources[0].OrganizationId
                    }
                    if ($themeOrganizationId) {
                        $sources += @(Get-EntraBrandingThemeSource -OrganizationId $themeOrganizationId `
                            -RequestHandler $RequestHandler)
                    } else {
                        Write-Warning 'No organization id was discovered, so branding themes were not read.'
                    }
                }
            } catch {
                Write-Error ("Reading tenant branding failed: $($_.Exception.Message) - " +
                    "CorrelationId: $correlationId") -ErrorAction Stop
                return
            }

            foreach ($source in $sources) {
                if ($source.Error) {
                    Write-Error "Could not read $($source.Path): $($source.Error) - CorrelationId: $correlationId"
                    [PSCustomObject]@{
                        PSTypeName           = 'EntraBrandingCss.Result'
                        Source               = $source.Path
                        SourceType           = $source.Kind
                        Name                 = $source.Name
                        Status               = 'Error'
                        HasCustomCss         = $null
                        RetiredCount         = 0
                        ReviewCount          = 0
                        DeclarationCount     = 0
                        Length               = 0
                        CustomCssRelativeUrl = $source.CustomCssRelativeUrl
                        Findings             = @()
                        Error                = $source.Error
                    }
                    continue
                }

                Invoke-CssScan -Css $source.Css -Source $source.Path -SourceType $source.Kind -Name $source.Name `
                    -CustomCssRelativeUrl $source.CustomCssRelativeUrl
            }
        }

        Write-Verbose "Completed $($MyInvocation.MyCommand.Name) - CorrelationId: $correlationId"
    }
}
