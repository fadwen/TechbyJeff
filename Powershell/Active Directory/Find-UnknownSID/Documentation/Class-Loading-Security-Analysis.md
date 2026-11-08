# Class Loading: Security Design and Current Implementation

## Summary

Find-UnknownSID loads its PowerShell classes from `Classes/*.ps1` through an allow list rather than
by enumerating the folder. Only class names present in a hardcoded table are resolved and
dot-sourced, so a file dropped into `Classes/` is never executed. The table also records a SHA256
hash per file, but no code computes or compares file hashes, so tampering with an approved file is
not detected at load time. This document describes the implementation as it is and the reasoning
behind the allow-list approach.

## Current Implementation

### Load Sequence

`Find-UnknownSID.ps1` performs class loading in its `begin` block:

1. It dot-sources the class management functions from `Private/ClassManagement/` using a fixed
   list: `Get-ApprovedClassList.ps1`, `Resolve-ClassPath.ps1`, `Test-ClassInstantiation.ps1`,
   `Get-ClassValidationResult.ps1`, `Import-SecureClasses.ps1`. A missing file is a fatal error.
2. It loads the logging system (`Private/Core/Import-LoggingSystem.ps1`).
3. It calls `Import-SecureClasses -ClassNames @(...)` with the nine class names the script needs:
   `MemoryManager`, `OrphanedSIDResult`, `ProcessingStatistics`, `RemovalOperationResult`,
   `RestoreOperationResult`, `ScriptConfiguration`, `SecurityValidationResult`,
   `SIDAnalysisResult`, `StreamingResultsManager`.
4. If the result's `Success` is `$false` it throws `Critical class import failure`. Otherwise it
   dot-sources each path in the result's `PathsToLoad`, at script scope, so the class types are
   visible to every function loaded afterwards.

### Get-ApprovedClassList

`Private/ClassManagement/Get-ApprovedClassList.ps1` returns a hashtable whose `Classes` entry maps
each approved file name to its metadata:

```powershell
'ScriptConfiguration.ps1' = @{
    RequiredTypes = @('ScriptConfiguration')
    Dependencies  = @()
    Description   = 'Core script configuration and validation functionality'
    ExpectedHash  = 'A371D70846A44F38360F26915418A3384E9D2C9216803719AB32FA46677E991C'
    LastVerified  = '2025-07-05'
    SecurityLevel = 'Standard'
    LoadOrder     = 1
}
```

The table is literal code: adding a class means editing this file, which puts the change into
version control and code review. It lists the same nine classes the main script requests.
`Tools/Generate-ClassHashes.ps1` recomputes the `ExpectedHash` values from the files on disk and
rewrites them into this file.

### Import-SecureClasses

`Private/ClassManagement/Import-SecureClasses.ps1` takes `-ClassNames <string[]>`, an optional
`-ClassesPath` (default `.\Classes`), and the switches `-ValidateIntegrity` and `-ValidationOnly`.
It:

1. Fetches the approved table and rejects the call with `Unapproved classes requested` if any
   requested name is not a key in it. No path is returned for an unapproved name.
2. Calls `Resolve-ClassPath`, which resolves `<ClassesPath>\<Name>.ps1`, confirms the file exists
   and can be opened, and marks it valid. Missing or unreadable files go into `FailedClasses`.
3. With `-ValidateIntegrity`, calls `Test-ClassIntegrity -Class <name>` for each resolved file.
4. Returns `Success`, `ValidatedClasses`, `FailedClasses`, `PathsToLoad` and `TotalClasses`.

The main script does not pass `-ValidateIntegrity`.

### What Is Not Verified

- **File hashes.** `ExpectedHash` is stored in the approved table and refreshed by
  `Tools/Generate-ClassHashes.ps1`, but nothing reads it back: there is no `Get-FileHash` or
  `ComputeHash` call anywhere in `Private/ClassManagement/` or `Private/Security/`, and the main
  script never compares a hash. A modified `Classes/*.ps1` with an approved name loads normally.
- **Test-ClassIntegrity** (`Private/Security/Test-ClassIntegrity.ps1`) validates class *names*
  only (non-empty, string shape). It does not open the file, and it is only called when
  `-ValidateIntegrity` is passed, which the script does not do.
- **Path containment.** `Resolve-ClassPath` resolves the path and checks accessibility but does
  not verify that the resolved file lies under `-ClassesPath`, so a reparse point inside
  `Classes/` would be followed.

The effective protection is therefore the allow list: an attacker who can write to `Classes/`
must overwrite an approved file rather than add a new one, and the file-system permissions on that
folder are what prevent it.

## Why an Allow List Rather Than Directory Enumeration

### Risks of Enumerating the Folder

Loading with `Get-ChildItem -Path $classesPath -Filter *.ps1 | ForEach-Object { . $_.FullName }`
executes every script in the folder with the privileges of the running account, which for this
script is usually an account that can modify Active Directory ACLs.

- **Code injection via the file system.** Anyone who can create a file in `Classes/` runs
  arbitrary code the next time the script starts. A dot-sourced file need not define a class at
  all.
- **Supply chain.** A build or sync step that copies an extra file into `Classes/` changes the
  script's behaviour without any change to the script.
- **Privilege escalation.** A low-privilege process that can write to the folder gains the
  privileges of the scheduled task or administrator who runs the script.
- **Reparse points.** A junction or symbolic link inside the folder pulls in files from elsewhere.

### What the Allow List Gives

- **Explicit control.** Only the nine named files are candidates; a tenth file is ignored.
- **Review and traceability.** Adding a class requires a change to `Get-ApprovedClassList.ps1` and
  to the `$requiredClasses` array in the main script, both of which are tracked in git.
- **Deterministic failure.** A missing approved file fails the run at startup rather than
  producing a partially-loaded script.

### What It Does Not Give

It does not protect an approved file's contents. Closing that gap requires the hash comparison
described above, code signing with `Get-AuthenticodeSignature`, or restrictive ACLs on the
`Classes/` folder. Of these, only folder ACLs are available today without a code change, and they
should be applied wherever the script is deployed.

## Operational Controls

### File System Permissions

Restrict write access to the deployment folder, and `Classes/` in particular, to the accounts that
deploy the script. The account that runs the script needs read access only.

### Change Monitoring

A file-system watcher or a periodic hash comparison against `Get-ApprovedClassList.ps1` detects
changes that the loader itself does not:

```powershell
# Run from the Find-UnknownSID folder
. .\Private\ClassManagement\Get-ApprovedClassList.ps1
$approved = (Get-ApprovedClassList).Classes
foreach ($name in $approved.Keys) {
    $actual = (Get-FileHash -Path ".\Classes\$name" -Algorithm SHA256).Hash
    if ($actual -ne $approved[$name].ExpectedHash) {
        Write-Warning "Hash mismatch for $name"
    }
}
```

Run `Tools/Generate-ClassHashes.ps1` after any intentional change to a class file so the recorded
hashes match the deployed files; otherwise the comparison above reports every edited file.

### Code Signing

Signing the `.ps1` files and running under an execution policy of `AllSigned` makes PowerShell
refuse to dot-source a modified file. This is enforced by PowerShell, not by the script, and it
covers `Private/` and the main script as well as `Classes/`.

## Conclusion

Class loading in Find-UnknownSID is allow-list based and refuses unknown files, which removes the
largest risk of directory enumeration. Integrity of the approved files is recorded but not enforced
by the loader; it depends on folder permissions and, where used, code signing.
