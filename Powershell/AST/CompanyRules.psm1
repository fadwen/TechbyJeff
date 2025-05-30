<#
.SYNOPSIS
    Custom PSScriptAnalyzer module for enforcing company-specific PowerShell coding standards.

.DESCRIPTION
    This PowerShell module contains custom PSScriptAnalyzer rules that enforce company-specific
    coding standards and best practices. The module validates PowerShell code against:

    - Function naming conventions requiring approved verbs with "Company" suffix
    - Variable naming standards (PascalCase for parameters, camelCase for local variables)
    - Mandatory comment-based help for public functions
    - Code quality and consistency standards

    The rules are designed to integrate with PSScriptAnalyzer and can be used in CI/CD
    pipelines, development environments, and code review processes to maintain consistent
    code quality across the organization.

.NOTES
    Author: Jeffrey Stuhr
    Last Updated: 2025-05-29
    Version: 1.0

    Usage: Import this module and run PSScriptAnalyzer with custom rules:
    Import-Module .\CompanyRules.psm1
    Invoke-ScriptAnalyzer -Path script.ps1 -CustomRulePath .\CompanyRules.psm1

    The module exports the Measure-CompanyStandards function which implements all rules.
#>

# CompanyRules.psm1 - Custom PSScriptAnalyzer Rules for Company Standards

function Measure-CompanyStandards {
    <#
    .SYNOPSIS
        Custom PSScriptAnalyzer rule that validates PowerShell code against company standards.

    .DESCRIPTION
        This function implements a comprehensive set of company-specific coding standards
        for PowerShell development. It analyzes the Abstract Syntax Tree (AST) of PowerShell
        code to validate:

        1. Function naming conventions - Functions must start with approved PowerShell verbs
           followed by "-Company" (e.g., Get-CompanyUser, Set-CompanyConfig)
        2. Comment-based help requirements - Public functions must include .SYNOPSIS
        3. Parameter naming standards - Parameters must use PascalCase naming
        4. Variable naming conventions - Local variables should use camelCase

        The function returns diagnostic records that integrate with PSScriptAnalyzer
        reporting and can be used in automated code quality checks.

    .PARAMETER ScriptBlockAst
        The Abstract Syntax Tree (AST) of the PowerShell script to analyze.
        This parameter is automatically provided by PSScriptAnalyzer when the rule is invoked.

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]
        Returns an array of diagnostic records for any coding standard violations found.
        Each record includes the violation description, location, severity, and rule name.

    .EXAMPLE
        PS> Invoke-ScriptAnalyzer -Path "MyScript.ps1" -CustomRulePath ".\CompanyRules.psm1"

        Runs PSScriptAnalyzer with this custom rule against MyScript.ps1.

    .EXAMPLE
        PS> $ast = [System.Management.Automation.Language.Parser]::ParseFile("script.ps1", [ref]$null, [ref]$null)
        PS> Measure-CompanyStandards -ScriptBlockAst $ast

        Directly invokes the rule against a parsed AST for testing purposes.

    .NOTES
        Author: Jeffrey Stuhr
        Last Updated: 2025-05-29
        Version: 1.0

        Approved verbs for function naming: Get, Set, New, Remove, Test, Start, Stop,
        Restart, Add, Clear, Copy, Move, Update, Import, Export

        This rule integrates with PSScriptAnalyzer and follows the standard diagnostic
        record format for consistent reporting across different analysis tools.
    #>

    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )

    process {
        $results = @()

        try {
            # Rule 1: Function Naming Convention
            $functions = $ScriptBlockAst.FindAll({
                $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true)

            foreach ($function in $functions) {
                # Check naming convention: Must start with approved verb + "Company"
                $approvedVerbs = @('Get', 'Set', 'New', 'Remove', 'Test', 'Start', 'Stop', 'Restart', 'Add', 'Clear', 'Copy', 'Move', 'Update', 'Import', 'Export')
                $verbPattern = ($approvedVerbs -join '|')
                $expectedPattern = "^($verbPattern)-Company"

                if ($function.Name -notmatch $expectedPattern) {
                    $results += [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]::new(
                        "Function '$($function.Name)' doesn't follow company naming convention. Expected format: ApprovedVerb-Company*",
                        $function.Extent,
                        'CompanyNamingConvention',
                        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticSeverity]::Warning,
                        $null
                    )
                }

                # Rule 2: Check for comment-based help in public functions
                if ($function.Name -match '^(Get|Set|New|Remove)-Company') {
                    $functionText = $function.Extent.Text
                    if ($functionText -notmatch '\.SYNOPSIS') {
                        $results += [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]::new(
                            "Public function '$($function.Name)' is missing comment-based help with .SYNOPSIS",
                            $function.Extent,
                            'CompanyPublicFunctionHelp',
                            [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticSeverity]::Information,
                            $null
                        )
                    }
                }
            }

            # Rule 3: Parameter Naming Convention (PascalCase)
            $parameters = $ScriptBlockAst.FindAll({
                $args[0] -is [System.Management.Automation.Language.ParameterAst]
            }, $true)

            foreach ($parameter in $parameters) {
                $paramName = $parameter.Name.VariablePath.UserPath

                # Skip common PowerShell automatic parameters
                $skipParams = @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable')

                if ($paramName -notin $skipParams -and $paramName -cnotmatch '^[A-Z][a-zA-Z0-9]*$') {
                    $results += [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]::new(
                        "Parameter '$paramName' should use PascalCase naming convention",
                        $parameter.Extent,
                        'CompanyParameterNaming',
                        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticSeverity]::Information,
                        $null
                    )
                }
            }

            # Rule 4: Variable Assignment Conventions (camelCase for local variables)
            $assignments = $ScriptBlockAst.FindAll({
                $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst]
            }, $true)

            foreach ($assignment in $assignments) {
                if ($assignment.Left -is [System.Management.Automation.Language.VariableExpressionAst]) {
                    $varName = $assignment.Left.VariablePath.UserPath

                    # Skip special PowerShell variables and short variables
                    $skipVars = @('_', 'PSItem', 'args', 'input', 'matches', 'error', 'lastexitcode')

                    if ($varName -notin $skipVars -and $varName.Length -gt 2 -and $varName -cnotmatch '^[a-z][a-zA-Z0-9]*$') {
                        $results += [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]::new(
                            "Local variable '$varName' should use camelCase naming convention",
                            $assignment.Left.Extent,
                            'CompanyVariableNaming',
                            [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticSeverity]::Information,
                            $null
                        )
                    }
                }
            }

        }
        catch {
            Write-Error "Error in Measure-CompanyStandards: $($_.Exception.Message)"
        }

        return $results
    }
}

# REQUIRED: Export the rule function for PSScriptAnalyzer to discover it
Export-ModuleMember -Function Measure-CompanyStandards