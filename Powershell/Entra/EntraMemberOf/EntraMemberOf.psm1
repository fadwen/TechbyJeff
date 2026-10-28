#Requires -Version 7.4

# EntraMemberOf PowerShell Module
# Finds every use of the memberOf rule operator in dynamic membership groups, dynamic
# administrative units and entitlement management auto-assignment policies, from rule text, an
# exported file, or a tenant through Microsoft Graph. Parses rules rather than searching text.
# Never writes to a tenant.

$ModuleRoot = $PSScriptRoot
Write-Verbose "Initializing EntraMemberOf module from: $ModuleRoot"

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

# Data/MemberOfRules.psd1 is read on first use and cached here.
$script:RuleCatalog = $null

Export-ModuleMember -Function @(
    'Test-EntraMemberOfRule'
)

$ExecutionContext.SessionState.Module.OnRemove = {
    Write-Verbose "Cleaning up EntraMemberOf module"
    Remove-Variable -Name RuleCatalog -Scope Script -ErrorAction SilentlyContinue
}
