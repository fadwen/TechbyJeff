# CompanyRules.psm1 - Custom PSScriptAnalyzer Rules for Company Standards

function Measure-CompanyStandards {
    <#
    .SYNOPSIS
        Validates PowerShell code against company-specific standards.

    .DESCRIPTION
        This custom PSScriptAnalyzer rule checks for:
        - Function naming conventions (must start with approved verbs + "Company")
        - Variable naming standards (PascalCase for parameters, camelCase for local vars)
        - Mandatory comment-based help for public functions

    .PARAMETER ScriptBlockAst
        The AST (Abstract Syntax Tree) of the script to analyze.

    .OUTPUTS
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
        Returns diagnostic records for any violations found.
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