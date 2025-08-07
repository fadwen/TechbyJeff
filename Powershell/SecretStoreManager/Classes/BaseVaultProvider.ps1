# Base vault provider class
class BaseVaultProvider {
    [string]$Name
    [string]$ModuleName
    [bool]$IsAvailable
    [hashtable]$Configuration

    BaseVaultProvider([string]$name, [string]$moduleName) {
        $this.Name = $name
        $this.ModuleName = $moduleName
        $this.IsAvailable = $this.CheckModuleAvailability()
        $this.Configuration = @{}
    }

    [bool] CheckModuleAvailability() {
        return $null -ne (Get-Module -ListAvailable -Name $this.ModuleName)
    }

    [void] InstallModule() {
        if (-not $this.IsAvailable) {
            Install-Module -Name $this.ModuleName -Force -Scope CurrentUser -AllowClobber
            $this.IsAvailable = $this.CheckModuleAvailability()
        }
    }

    # Virtual methods to be overridden by specific providers
    [hashtable] CreateVault([string]$vaultName, [hashtable]$parameters) {
        throw "CreateVault method must be implemented by derived class"
    }

    [hashtable] RemoveVault([string]$vaultName, [bool]$force) {
        throw "RemoveVault method must be implemented by derived class"
    }

    [object] StoreSecret([string]$vaultName, [string]$secretName, [object]$secret, [hashtable]$metadata) {
        throw "StoreSecret method must be implemented by derived class"
    }

    [object] GetSecret([string]$vaultName, [string]$secretName, [bool]$asPlainText) {
        throw "GetSecret method must be implemented by derived class"
    }

    [array] ListSecrets([string]$vaultName) {
        throw "ListSecrets method must be implemented by derived class"
    }
}
