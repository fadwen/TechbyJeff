#Requires -Version 5.1

# CaOutcome PowerShell Module
# Turns a Conditional Access What If response into the effective outcome of the sign-in it
# describes, reports what changes when the tenant's report-only policies are promoted, runs
# that over a matrix of personas, and diffs a run against a committed baseline

$ModuleRoot = $PSScriptRoot
Write-Verbose "Initializing CaOutcome module from: $ModuleRoot"

# Import Private functions
$privateFunctions = Get-ChildItem -Path "$ModuleRoot\Private\*.ps1" -ErrorAction SilentlyContinue
foreach ($function in $privateFunctions) {
    Write-Verbose "Loading private function: $($function.Name)"
    . $function.FullName
}

# Import Public functions
$publicFunctions = Get-ChildItem -Path "$ModuleRoot\Public\*.ps1" -ErrorAction SilentlyContinue
foreach ($function in $publicFunctions) {
    Write-Verbose "Loading public function: $($function.Name)"
    . $function.FullName
}

# The policy states that make up each world. Current is what the tenant enforces right now;
# Projected is what it would enforce if every report-only policy were switched on. Disabled
# policies are in neither, and the What If API returns them with the rest.
$script:CurrentStates = @('enabled')
$script:ProjectedStates = @('enabled', 'enabledForReportingButNotEnforced')

# Export public functions
Export-ModuleMember -Function @(
    'ConvertTo-CaOutcome',
    'Expand-CaScenario',
    'Invoke-CaScenarioMatrix',
    'Export-CaBaseline',
    'Compare-CaBaseline'
)

# Module cleanup on removal
$ExecutionContext.SessionState.Module.OnRemove = {
    Write-Verbose "Cleaning up CaOutcome module"
    Remove-Variable -Name CurrentStates -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name ProjectedStates -Scope Script -ErrorAction SilentlyContinue
}
