#Requires -Version 5.1

# OktaTestEnvironment PowerShell Module
# Seeds and tears down an Okta test tenant within the Integrator Free Plan's ten user licence

$ModuleRoot = $PSScriptRoot
Write-Verbose "Initializing OktaTestEnvironment module from: $ModuleRoot"

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

# The domain baked into the shipped CSV URLs. New-OktaTestApp rewrites it to the connection's
# EmailDomain, because that URL is the only teardown marker every Okta app type preserves.
$script:DefaultSeedDomain = 'oktalab.example.com'

# The active connection, set by Connect-OktaTestEnvironment. Module scoped rather than global
# so that removing the module takes the credential with it.
$script:OktaConnection = $null

# Export public functions
Export-ModuleMember -Function @(
    'Connect-OktaTestEnvironment',
    'Disconnect-OktaTestEnvironment',
    'New-OktaTestEnvironment',
    'New-OktaTestProfileAttribute',
    'New-OktaTestUser',
    'New-OktaTestGroup',
    'New-OktaTestGroupRule',
    'New-OktaTestApp',
    'New-OktaTestUserType',
    'New-OktaTestNetworkZone',
    'New-OktaTestPolicy',
    'New-OktaTestLinkedObject',
    'New-OktaTestTrustedOrigin',
    'New-OktaTestEventHook',
    'New-OktaTestServiceApp',
    'Get-OktaTestAccessToken',
    'Get-OktaTestAppCredential',
    'Get-OktaTestEnvironmentReport',
    'Remove-OktaTestEnvironment'
)

# Module cleanup on removal
$ExecutionContext.SessionState.Module.OnRemove = {
    Write-Verbose "Cleaning up OktaTestEnvironment module"
    Remove-Variable -Name OktaConnection -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name ModuleDataPath -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name DefaultSeedDomain -Scope Script -ErrorAction SilentlyContinue
}
