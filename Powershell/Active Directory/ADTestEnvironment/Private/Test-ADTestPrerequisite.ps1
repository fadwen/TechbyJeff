function Test-ADTestPrerequisite {
    [CmdletBinding()]
    [OutputType([bool])]
    <#
    .SYNOPSIS
        Tests prerequisites for AD test data operations

    .DESCRIPTION
        Verifies that required modules are available, domain connectivity exists,
        and data files are present

    .PARAMETER CheckDataFiles
        Also verify that required CSV data files exist

    .OUTPUTS
        Boolean indicating if all prerequisites are met

    .EXAMPLE
        if (-not (Test-ADTestPrerequisite)) {
            throw "Prerequisites not met"
        }

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-03
    #>

    [CmdletBinding()]
    param(
        [switch]$CheckDataFiles
    )

    $issues = @()

    # Check AD module
    try {
        Import-Module ActiveDirectory -ErrorAction Stop -Verbose:$false
        Write-Verbose "Active Directory module loaded successfully"
    } catch {
        $issues += "Active Directory PowerShell module not available: $($_.Exception.Message)"
    }

    # Check domain connectivity
    try {
        $domain = Get-ADTestDomain
        Write-Verbose "Domain connectivity verified: $($domain.DNSName)"
    } catch {
        $issues += "Domain connectivity failed: $($_.Exception.Message)"
    }

    # Check data files if requested
    if ($CheckDataFiles) {
        try {
            $dataPath = Get-ADTestDataPath
            $requiredFiles = @("ADUsers.csv", "ADDevices.csv", "ADSecurityGroups.csv")

            foreach ($file in $requiredFiles) {
                $filePath = Join-Path $dataPath $file
                if (-not (Test-Path $filePath)) {
                    $issues += "Required data file missing: $filePath"
                }
            }
        } catch {
            $issues += "Data path validation failed: $($_.Exception.Message)"
        }
    }

    if ($issues.Count -gt 0) {
        foreach ($issue in $issues) {
            Write-Error $issue
        }
        return $false
    }

    return $true
}
