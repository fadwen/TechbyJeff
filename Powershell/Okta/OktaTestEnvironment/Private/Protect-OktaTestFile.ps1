function Protect-OktaTestFile {
    <#
    .SYNOPSIS
        Restricts a file so only the current user can read it

    .DESCRIPTION
        The credential file holds an unencrypted RSA private key that can mint admin-scoped
        access tokens for the tenant. Writing it with whatever permissions it inherited from
        its parent folder is not good enough, so this replaces the ACL outright.

        On Windows that means a new DACL with inheritance disabled and exactly one entry, for
        the current user. Disabling inheritance is the part that matters: adding an allow ACE
        does nothing if an inherited ACE already grants Everyone read.

        Elsewhere it shells out to chmod 600. A failure is reported as a warning rather than
        an exception, because a key that exists with loose permissions and a loud warning is
        more useful to a lab than an aborted setup that leaves an app registered in Okta with
        no key on disk to match it.

    .PARAMETER Path
        The file to protect

    .OUTPUTS
        Boolean indicating whether permissions were successfully restricted

    .EXAMPLE
        Protect-OktaTestFile -Path $credentialPath

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        Write-Warning "Cannot restrict permissions on '$Path' because it does not exist."
        return $false
    }

    if (-not $PSCmdlet.ShouldProcess($Path, 'Restrict access to the current user only')) {
        return $false
    }

    $onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or
        ($PSVersionTable.PSObject.Properties['Platform'] -and $PSVersionTable.Platform -eq 'Win32NT') -or
        ($env:OS -eq 'Windows_NT')

    try {
        if ($onWindows) {
            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
            $acl = Get-Acl -Path $Path

            # $true, $false: protect the DACL from inheritance and drop the inherited ACEs
            # rather than copying them in. Copying them in would preserve the very entries
            # this is meant to remove.
            $acl.SetAccessRuleProtection($true, $false)
            foreach ($rule in @($acl.Access)) {
                $null = $acl.RemoveAccessRule($rule)
            }

            # A folder has to hand its restriction down to the files created inside it later,
            # or locking the folder buys nothing for the credential that lands in it.
            $isContainer = Test-Path -Path $Path -PathType Container
            $inheritance = if ($isContainer) { 'ContainerInherit, ObjectInherit' } else { 'None' }

            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $identity, 'FullControl', $inheritance, 'None', 'Allow')
            $acl.SetAccessRule($rule)
            $acl.SetOwner($identity)

            Set-Acl -Path $Path -AclObject $acl -ErrorAction Stop
        }
        else {
            # -First 1 is load-bearing. On Debian, Get-Command finds chmod twice - /usr/bin/chmod
            # and /bin/chmod - so .Source is an ARRAY, and invoking it passed the second path as
            # an argument instead of running one command. The file silently kept mode 644 while
            # this function reported success. Found by running on a real Linux host.
            $chmod = @(Get-Command -Name chmod -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1)
            if ($chmod.Count -eq 0) {
                Write-Warning "chmod was not found, so '$Path' keeps its inherited permissions."
                return $false
            }
            $mode = if (Test-Path -Path $Path -PathType Container) { '700' } else { '600' }
            & $chmod[0].Source $mode $Path
            if ($LASTEXITCODE -ne 0) { throw "chmod exited with code $LASTEXITCODE." }
        }

        Write-Verbose "Restricted '$Path' to the current user."
        return $true
    }
    catch {
        Write-Warning ("Could not restrict permissions on '$Path': $($_.Exception.Message). " +
            'The private key is readable by anyone who can read the containing folder.')
        return $false
    }
}
