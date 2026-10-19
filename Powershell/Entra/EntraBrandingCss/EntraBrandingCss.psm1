#Requires -Version 5.1

# EntraBrandingCss PowerShell Module
# Parses company branding custom CSS into declarations and reports the ones that use a property
# Microsoft Entra ID is retiring. Reads a .css file, or a tenant through Microsoft Graph. Never
# writes to a tenant.

$ModuleRoot = $PSScriptRoot
Write-Verbose "Initializing EntraBrandingCss module from: $ModuleRoot"

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

# The property catalog is read from Data/RetiredProperties.psd1 on first use and cached here.
$script:PropertyCatalog = $null

Export-ModuleMember -Function @(
    'Test-EntraBrandingCss',
    'Get-EntraBrandingCssProperty'
)

$ExecutionContext.SessionState.Module.OnRemove = {
    Write-Verbose "Cleaning up EntraBrandingCss module"
    Remove-Variable -Name PropertyCatalog -Scope Script -ErrorAction SilentlyContinue
}
