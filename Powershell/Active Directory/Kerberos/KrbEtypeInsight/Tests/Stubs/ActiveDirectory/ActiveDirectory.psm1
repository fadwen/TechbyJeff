# GENERATED FILE - do not edit by hand. See Tests/Stubs/README.md.
#
# A stand-in for RSAT, so Pester can mock commands that would otherwise not exist on
# a host without it. Every function is empty: it exists only to reproduce the real
# binding surface, so a call the real cmdlet would reject fails here too. Parameter
# types are carried over wherever the type ships with PowerShell itself.
#
# The suppressions below are the point of the file, not an oversight. The parameters
# are deliberately unused, and a body-less function has nothing to guard.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Stub parameters reproduce real cmdlet binding surfaces.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
    Justification = 'Stubs have no body to guard; the attribute mirrors the real cmdlet.')]
param()

function Get-ADDomain {
    [CmdletBinding()]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        $Current,
        $Identity,
        [System.String]$Server
    )
}

function Get-ADDomainController {
    [CmdletBinding()]
    param(
        $AuthType,
        [System.Management.Automation.SwitchParameter]$AvoidSelf,
        [System.Management.Automation.PSCredential]$Credential,
        [System.Management.Automation.SwitchParameter]$Discover,
        [System.String]$DomainName,
        [System.String]$Filter,
        [System.Management.Automation.SwitchParameter]$ForceDiscover,
        $Identity,
        $MinimumDirectoryServiceVersion,
        [System.Management.Automation.SwitchParameter]$NextClosestSite,
        [System.String]$Server,
        $Service,
        [System.String]$SiteName,
        [System.Management.Automation.SwitchParameter]$Writable
    )
}

function Get-ADForest {
    [CmdletBinding()]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        $Current,
        $Identity,
        [System.String]$Server
    )
}

function Get-ADObject {
    [CmdletBinding()]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Filter,
        $Identity,
        [System.Management.Automation.SwitchParameter]$IncludeDeletedObjects,
        [System.String]$LDAPFilter,
        [System.String]$Partition,
        [System.String[]]$Properties,
        [System.Int32]$ResultPageSize,
        [System.Nullable[System.Int32]]$ResultSetSize,
        [System.String]$SearchBase,
        $SearchScope,
        [System.String]$Server
    )
}

function Get-ADTrust {
    [CmdletBinding()]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Filter,
        $Identity,
        $InputObject,
        [System.String]$LDAPFilter,
        [System.String[]]$Properties,
        [System.String]$Server
    )
}

function Get-ADUser {
    [CmdletBinding()]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Filter,
        $Identity,
        [System.String]$LDAPFilter,
        [System.String]$Partition,
        [System.String[]]$Properties,
        [System.Int32]$ResultPageSize,
        [System.Nullable[System.Int32]]$ResultSetSize,
        [System.String]$SearchBase,
        $SearchScope,
        [System.String]$Server
    )
}

Export-ModuleMember -Function @(
    'Get-ADDomain',
    'Get-ADDomainController',
    'Get-ADForest',
    'Get-ADObject',
    'Get-ADTrust',
    'Get-ADUser'
)
