@{
    RootModule        = 'KrbEtypeInsight.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'ba1a8c68-0d77-4a64-b01b-e68d1bbdc810'
    Author            = 'Jeffrey Stuhr'
    CompanyName       = 'EntraVantage LLC'
    Copyright         = '(c) 2026 EntraVantage LLC. Licensed under the GNU General Public License v3.0.'

    Description       = @'
Predicts which accounts, services and clients a Kerberos encryption type hardening change
will break, before the change is made. Collects events 4768, 4769 and 4771 from domain
controllers or archived logs, decodes ticket encryption types and msDS-SupportedEncryptionTypes
bitmasks, correlates observed behaviour against directory configuration and domain baseline,
and emits a per-principal risk assessment naming the specific clients that will stop working.
'@

    # 7.6 is the current LTS. The module uses no 7.5 or 7.6 exclusive cmdlet, but the target
    # is declared rather than reached down to 7.4, which loses support on 10-Nov-2026.
    PowerShellVersion = '7.6'
    CompatiblePSEditions = @('Core')

    # ActiveDirectory is intentionally absent. See the note at the top of KrbEtypeInsight.psm1:
    # the decode and correlation core runs offline against .evtx fixtures with no domain
    # present, and requiring RSAT here would make the module unimportable on a CI runner for
    # the benefit of functions that already import it on demand and report a clear error.
    RequiredModules   = @()

    FunctionsToExport = @(
        'ConvertFrom-KrbEtype'
        'Get-KrbEvent'
        'Get-KrbPrincipalEtype'
        'Get-KrbDomainEtypeContext'
        'Get-KrbEtypeRisk'
        'Export-KrbEtypeReport'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    FormatsToProcess  = @('KrbEtypeInsight.Format.ps1xml')

    PrivateData       = @{
        PSData = @{
            Tags = @(
                'ActiveDirectory', 'Kerberos', 'Security', 'RC4', 'AES',
                'Hardening', 'Audit', 'EventLog', 'Windows'
            )
            LicenseUri   = 'https://www.gnu.org/licenses/gpl-3.0.html'
            ProjectUri   = 'https://github.com/fadwen/TechbyJeff'
            IconUri      = ''
            ReleaseNotes = @'
1.0.0 - Initial release. Licensed under the GNU General Public License v3.0.

See CHANGELOG.md for the defects found and fixed during pre-release validation against a
live domain, and for known limitations.

- ConvertFrom-KrbEtype decodes both Kerberos numbering systems: RFC 3961 ticket encryption
  type numbers and MS-KILE msDS-SupportedEncryptionTypes bit flags, plus the client
  advertised encryption type name list from version 2 events.
- Get-KrbEvent collects 4768, 4769 and 4771 from live domain controllers or archived .evtx
  files, handling the version 0, 1 and 2 audit schemas.
- Get-KrbPrincipalEtype reads per-account configuration including the userAccountControl
  overrides that supersede the encryption type attribute.
- Get-KrbDomainEtypeContext establishes the baseline: functional level, per-controller
  DefaultDomainSupportedEncTypes including disagreement between controllers, krbtgt, and
  trust encryption types.
- Get-KrbEtypeRisk correlates all of the above into per-principal risk objects that name the
  specific clients a change will break.
- Export-KrbEtypeReport writes self-contained HTML, per-finding CSV, or full-fidelity JSON.
'@
            RequireLicenseAcceptance = $false
        }
    }

    HelpInfoURI       = ''
}
