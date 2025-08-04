#Requires -Module ActiveDirectory
#Requires -Version 5.1


# ADTestEnvironment PowerShell Module
# Comprehensive Active Directory test data generation module

# Module initialization
$ModuleRoot = $PSScriptRoot
Write-Verbose "Initializing ADTestEnvironment module from: $ModuleRoot"

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

# Module variables
$script:ModuleDataPath = Join-Path $ModuleRoot "Data"

# Export public functions
Export-ModuleMember -Function @(
    'New-ADTestEnvironment',
    'New-ADTestOUStructure',
    'New-ADTestUsers',
    'New-ADTestDevices',
    'New-ADTestSecurityGroups', 
    'New-ADTestServiceAccounts',
    'Get-ADTestEnvironmentReport',
    'Remove-ADTestEnvironment'
)

# Module cleanup on removal
$ExecutionContext.SessionState.Module.OnRemove = {
    Write-Verbose "Cleaning up ADTestEnvironment module"
    Remove-Variable -Name ModuleDataPath -Scope Script -ErrorAction SilentlyContinue
}
