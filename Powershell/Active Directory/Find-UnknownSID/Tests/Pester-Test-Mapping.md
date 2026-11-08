# Find-UnknownSID Pester Test Map

What is under `Tests/`, what each file covers, and how the pieces fit together. How to run the
suite and the latest results are in
[Documentation/Quick-Test-Reference.md](../Documentation/Quick-Test-Reference.md).

## Target

- Windows PowerShell 5.1 and Pester 3.4.0, the version that ships with Windows.
- Pester 3 syntax throughout: `Should Be`, `Should Throw`, `Should Not BeNullOrEmpty`,
  `Assert-MockCalled`, `-TestCases`. Pester 4 and 5 operators (`Should -Be`, `Should -Invoke`)
  are not used and would fail under 3.4.
- Files that need setup use `BeforeAll`/`BeforeEach` blocks, which Pester 3.4 supports, or
  run their setup at the top of the file before the first `Describe`.
- Find-UnknownSID is a script, not a module. Tests load the code they exercise by dot-sourcing
  the `.ps1` files under `Private/` and `Classes/`, or by reading `Find-UnknownSID.ps1` as text
  where the test validates the script's content.
- No Active Directory domain is needed. Every AD cmdlet a test reaches is mocked. On a machine
  without the RSAT `ActiveDirectory` module, `TestHelpers/ADCmdletStubs.ps1` defines the cmdlets
  as global placeholder functions, because Pester 3.4 can only mock a command that exists.

Counts below are `It` blocks per file. One `It` in `Get-SIDAnalysis.Tests.ps1` carries four
`-TestCases`; Pester 3.4 reports it once. The executed total in a run is lower than the sum of
these counts because some `It` blocks are inside helper functions or guarded blocks.

## Layout

```text
Tests/
├── Unit/
│   ├── Classes/          9 files   208 It    one file per class in Classes/
│   ├── Public/           1 file     20 It    Find-UnknownSID.ps1 entry point
│   └── Private/
│       ├── ACL/              3 files    51 It
│       ├── ActiveDirectory/  4 files   132 It
│       ├── Backup/           6 files   412 It
│       ├── ClassManagement/  5 files   110 It
│       ├── Core/             5 files   154 It
│       ├── FileSystem/       3 files   121 It
│       ├── LegacyCore/       8 files   177 It    content checks on Find-UnknownSID.ps1
│       ├── Logging/         12 files   373 It
│       ├── Operations/       2 files    20 It
│       ├── Reporting/        3 files    92 It
│       ├── SID/              6 files   215 It
│       ├── Security/         5 files    92 It
│       ├── System/           5 files    98 It
│       └── Utilities/        3 files   141 It
├── Integration/
│   ├── EndToEnd/             3 files    93 It
│   └── SystemIntegration/    4 files   123 It
├── Performance/
│   ├── Benchmarks/           3 files    62 It
│   └── LoadTests/            4 files   108 It
├── TestData/                 fixtures, configurations, sample data, mock responses
└── TestHelpers/              5 helper scripts
```

94 test files; 2412 `It` blocks in Unit, 216 in Integration, 170 in Performance.

## Unit tests

### Unit/Classes

One file per class in `Classes/`. Each file dot-sources the class file and tests construction,
property validation, and methods.

| Test file | Covers | It |
| --- | --- | --- |
| MemoryManager.Tests.ps1 | `MemoryManager` class | 24 |
| OrphanedSIDResult.Tests.ps1 | `OrphanedSIDResult` class | 35 |
| ProcessingStatistics.Tests.ps1 | `ProcessingStatistics` class | 33 |
| RemovalOperationResult.Tests.ps1 | `RemovalOperationResult` class | 21 |
| RestoreOperationResult.Tests.ps1 | `RestoreOperationResult` class | 24 |
| ScriptConfiguration.Tests.ps1 | `ScriptConfiguration` class (default `BatchSize` is 50) | 20 |
| SecurityValidationResult.Tests.ps1 | `SecurityValidationResult` class | 37 |
| SIDAnalysisResult.Tests.ps1 | `SIDAnalysisResult` class | 11 |
| StreamingResultsManager.Tests.ps1 | `StreamingResultsManager` class | 3 |

### Unit/Public

| Test file | Covers | It |
| --- | --- | --- |
| Find-UnknownSID.Tests.ps1 | `Find-UnknownSID.ps1`: parameter validation, mocked AD functions, error handling, memory safety, input sanitization | 20 |

### Unit/Private/ACL

| Test file | Covers | It |
| --- | --- | --- |
| Get-ACLForRemoval.Tests.ps1 | `Get-ACLForRemoval` | 9 |
| Invoke-SIDRemoval.Tests.ps1 | `Invoke-SIDRemoval` | 21 |
| Set-ModifiedACL.Tests.ps1 | `Set-ModifiedACL` | 21 |

### Unit/Private/ActiveDirectory

| Test file | Covers | It |
| --- | --- | --- |
| Get-ADObjectFromSearchBase.Tests.ps1 | `Get-ADObjectFromSearchBase` | 21 |
| Get-ADObjectsSequential.Tests.ps1 | `Get-ADObjectsSequential` | 25 |
| Invoke-ADOperationWithRetry.Tests.ps1 | `Invoke-ADOperationWithRetry` | 37 |
| Test-ValidDistinguishedName.Tests.ps1 | `Test-ValidDistinguishedName` | 49 |

### Unit/Private/Backup

| Test file | Covers | It |
| --- | --- | --- |
| Find-BackupFile.Tests.ps1 | `Find-BackupFile` | 37 |
| Get-BackupMetadata.Tests.ps1 | `Get-BackupMetadata`; one `It` is marked `-Skip` | 57 |
| Invoke-RestoreWorkflow.Tests.ps1 | `Invoke-RestoreWorkflow`, `Restore-IndividualObject`, `Start-RestoreOperation`, `Complete-RestoreOperation` | 78 |
| New-ACLBackup.Tests.ps1 | `New-ACLBackup` | 64 |
| Restore-ACLOperation.Tests.ps1 | `Set-ObjectACL`, `Get-RestorationTarget`, `Confirm-RestorationSuccess`, `ConvertFrom-BackupToACL` | 87 |
| Test-BackupValidation.Tests.ps1 | `Test-BackupValidation`, `Test-BackupIntegrity`, `Test-BackupFormat`, `Get-BackupMetadata` | 89 |

### Unit/Private/ClassManagement

| Test file | Covers | It |
| --- | --- | --- |
| Get-ApprovedClassList.Tests.ps1 | `Get-ApprovedClassList` | 11 |
| Get-ClassValidationResult.Tests.ps1 | `Get-ClassValidationResult` | 11 |
| Import-SecureClasses.Tests.ps1 | `Import-SecureClasses`; mocks of `Test-ClassIntegrity` return `IntegrityPassed` | 31 |
| Resolve-ClassPath.Tests.ps1 | `Resolve-ClassPath` | 37 |
| Test-ClassInstantiation.Tests.ps1 | `Test-ClassInstantiation` | 20 |

### Unit/Private/Core

| Test file | Covers | It |
| --- | --- | --- |
| Import-LoggingSystem.Tests.ps1 | `Import-LoggingSystem` | 32 |
| Initialize-ScriptExecution.Tests.ps1 | `Initialize-ScriptExecution` | 26 |
| Invoke-MainProcessingLogic.Tests.ps1 | `Invoke-MainProcessingLogic` | 28 |
| Remove-OrphanedSID.Tests.ps1 | `Remove-OrphanedSID` | 34 |
| Start-OrchestrationWorkflow.Tests.ps1 | `Start-OrchestrationWorkflow`; stubs `Write-StructuredLog` so it runs on its own | 34 |

### Unit/Private/FileSystem

| Test file | Covers | It |
| --- | --- | --- |
| Get-SafeFileName.Tests.ps1 | `Get-SafeFileName` | 57 |
| Initialize-LogDirectory.Tests.ps1 | `Initialize-LogDirectory`; the drive-root test reports Inconclusive without elevation | 30 |
| Test-DirectoryAccess.Tests.ps1 | `Test-DirectoryAccess` | 34 |

### Unit/Private/LegacyCore

These eight files predate the one-file-per-function layout. Each reads `Find-UnknownSID.ps1` as
text and asserts that the script contains the functions, classes, parameters, and safeguards it
expects; none of them runs the script. `ACL.Tests.ps1` additionally dot-sources the ACL, logging,
DN-validation and retry functions from `Private/` and calls them with mocked logging.

| Test file | Covers | It |
| --- | --- | --- |
| ACL.Tests.ps1 | ACL function definitions and their integration in the script | 41 |
| ActiveDirectory.Tests.ps1 | AD cmdlet usage and connection handling in the script | 38 |
| Core.Tests.ps1 | Script file presence, syntax, parameters, and core structure | 19 |
| Memory.Tests.ps1 | Memory monitoring and resource-management content | 27 |
| Operations.Tests.ps1 | `Invoke-OperationWithRetry` and `Invoke-RemovalWorkflow` content | 34 |
| Security.Tests.ps1 | Security validation and security class content | 10 |
| SIDValidation.Tests.ps1 | SID validation infrastructure content | 6 |
| SimpleValidation.Tests.ps1 | Basic input validation infrastructure | 2 |

### Unit/Private/Logging

| Test file | Covers | It |
| --- | --- | --- |
| Format-LogMessage.Tests.ps1 | `Format-LogMessage` | 56 |
| Initialize-LoggingConfiguration.Tests.ps1 | `Initialize-LoggingConfiguration`, `Get-LoggingState`, `Test-LogLevel`, `Update-LoggingMetrics`, `Set-LogLevel`, `Get-LogLevel` | 52 |
| Initialize-LoggingSystem.Tests.ps1 | `Initialize-LoggingSystem`, `Get-LoggingState`, `Test-LogLevel` | 37 |
| Protect-LogMessage.Tests.ps1 | `Protect-LogMessage` and its sanitization helpers | 45 |
| Write-ADOperationSecurityLog.Tests.ps1 | `Write-ADOperationSecurityLog` | 25 |
| Write-ClassSecurityEvent.Tests.ps1 | `Write-ClassSecurityEvent` | 43 |
| Write-RemovalSecurityLog.Tests.ps1 | `Write-RemovalSecurityLog` | 8 |
| Write-SecurityLog.Tests.ps1 | `Write-SecurityLog` | 25 |
| Write-SecurityLogEvent.Tests.ps1 | `Write-SecurityLogEvent` | 4 |
| Write-SecurityStructuredLogEntry.Tests.ps1 | `Write-SecurityStructuredLogEntry` | 24 |
| Write-StructuredLog.Tests.ps1 | `Write-StructuredLog` | 51 |
| Write-StructuredLogEntry.Tests.ps1 | `Write-StructuredLogEntry` | 3 |

### Unit/Private/Operations

| Test file | Covers | It |
| --- | --- | --- |
| Invoke-OperationWithRetry.Tests.ps1 | `Invoke-OperationWithRetry` | 5 |
| Invoke-RemovalWorkflow.Tests.ps1 | `Invoke-RemovalWorkflow` | 15 |

### Unit/Private/Reporting

| Test file | Covers | It |
| --- | --- | --- |
| Export-DiagnosticData.Tests.ps1 | `Export-DiagnosticData` | 9 |
| Get-LogFileSummary.Tests.ps1 | `Get-LogFileSummary`, `Get-LogContentAnalysis`, `Get-LogFileHealth`, `Get-LogFileStatistics` | 67 |
| Write-ProcessingSummary.Tests.ps1 | `Write-ProcessingSummary` | 16 |

### Unit/Private/SID

| Test file | Covers | It |
| --- | --- | --- |
| Get-SIDAnalysis.Tests.ps1 | `Get-SIDAnalysis`; one `It` expands to four `-TestCases` of malicious input | 31 |
| New-SIDResult.Tests.ps1 | `New-OrphanedSIDResult`, `Set-ACLMetadata`, `ConvertTo-ResultSummary` | 39 |
| Resolve-SIDIdentity.Tests.ps1 | `Test-AccessRuleForOrphanedSID`, `Resolve-IdentityReference`, `Convert-NTAccountToSID`, `Test-SIDValidityAndType`, `Get-StringFromIdentityReference` | 24 |
| Test-OrphanedSID.Tests.ps1 | `Test-OrphanedSID` | 23 |
| Test-SIDFormat.Tests.ps1 | `Test-SIDFormat`, `Test-WellKnownSID` | 25 |
| Test-SIDSecurity.Tests.ps1 | `Test-SIDSecurity`, `Get-SIDRiskAssessment` | 73 |

`Private/SID/Invoke-SIDProcessing.ps1` (`Find-OrphanedSIDsInObject`, `Get-SIDProcessingStatistics`)
has no dedicated unit test file; it is exercised through the Integration and Performance suites.

### Unit/Private/Security

| Test file | Covers | It |
| --- | --- | --- |
| Get-SecurityDescriptor.Tests.ps1 | `Get-ObjectAccessRule` and the security-descriptor conversion helpers | 16 |
| Invoke-RemovalVerification.Tests.ps1 | `Invoke-RemovalVerification` | 21 |
| Invoke-SecurityValidation.Tests.ps1 | `Invoke-SecurityValidation` | 13 |
| Test-ClassIntegrity.Tests.ps1 | `Test-ClassIntegrity` | 10 |
| Test-PathTraversal.Tests.ps1 | `Test-PathTraversal` | 32 |

### Unit/Private/System

| Test file | Covers | It |
| --- | --- | --- |
| Get-MemoryStatistics.Tests.ps1 | `Get-CurrentMemoryUsage`, `Get-MemoryUsageReport` | 16 |
| Initialize-MemoryManager.Tests.ps1 | `Initialize-MemoryManager` | 23 |
| Invoke-GarbageCollection.Tests.ps1 | `Invoke-GarbageCollection` | 13 |
| Invoke-MemoryMonitoring.Tests.ps1 | `Invoke-MemoryCheck`, `Test-MemoryThreshold` | 27 |
| Invoke-ResourceDisposal.Tests.ps1 | `Invoke-ResourceCleanup`, `Invoke-ResourceDisposal` | 19 |

### Unit/Private/Utilities

| Test file | Covers | It |
| --- | --- | --- |
| Get-StringHash.Tests.ps1 | `Get-StringHash` | 29 |
| Test-BackupIntegrity.Tests.ps1 | `Test-BackupIntegrity` | 60 |
| Validate-BackupSignature.Tests.ps1 | `Validate-BackupSignature` | 52 |

## Integration tests

Workflow tests that load several components together. AD cmdlets are mocked; the three files
marked below dot-source `ADCmdletStubs.ps1` first.

### Integration/EndToEnd

| Test file | Covers | It |
| --- | --- | --- |
| CompleteDiscoveryWorkflow.Tests.ps1 | Discovery run: search, SID analysis, result reporting | 24 |
| CompleteRemovalWorkflow.Tests.ps1 | Removal run: backup, removal, verification (uses AD stubs) | 24 |
| CompleteRestoreWorkflow.Tests.ps1 | Restore run: backup discovery, validation, ACL restoration (uses AD stubs) | 45 |

### Integration/SystemIntegration

| Test file | Covers | It |
| --- | --- | --- |
| ActiveDirectoryIntegration.Tests.ps1 | AD query, retry, and DN validation working together (uses AD stubs) | 30 |
| BackupRestoreIntegration.Tests.ps1 | Backup creation, metadata, validation, and restore together | 26 |
| ClassLoadingIntegration.Tests.ps1 | Class path resolution, integrity checks, secure import, instantiation | 33 |
| LoggingSystemIntegration.Tests.ps1 | Logging initialization, structured and security logging together | 34 |

## Performance tests

Timing and memory regression guards with mocked AD data. All seven files dot-source
`ADCmdletStubs.ps1`. Timing assertions are generous (under one second for the measured
operations) so that they catch regressions without failing on a slow machine.

### Performance/Benchmarks

| Test file | Covers | It |
| --- | --- | --- |
| LargeDatasetProcessing.Tests.ps1 | Processing time and memory for large object sets | 18 |
| MemoryUsageBaseline.Tests.ps1 | Memory baselines for the main operations | 20 |
| ThroughputMeasurement.Tests.ps1 | Objects and SIDs processed per second | 24 |

### Performance/LoadTests

| Test file | Covers | It |
| --- | --- | --- |
| ConcurrentOperations.Tests.ps1 | Behaviour under concurrent operations | 24 |
| MemoryPressure.Tests.ps1 | Behaviour as memory approaches configured thresholds | 24 |
| ResourceCleanup.Tests.ps1 | Disposal and cleanup after large runs | 32 |
| ScalabilityLimits.Tests.ps1 | Scaling with dataset size and batch settings | 28 |

## Test helpers

`Tests/TestHelpers/`. Each is dot-sourced by the test files that need it.

| Helper | Functions | Purpose |
| --- | --- | --- |
| ADCmdletStubs.ps1 | none exported; defines global `Get-ADDomain`, `Get-ADDomainController`, `Get-ADObject`, `Set-ADObject`, `Remove-ADObject`, `Get-ADUser`, `New-ADUser`, `Set-ADUser`, `Get-ADTrust`, `Get-ADRootDSE`, `Test-ADServiceAccount` when the RSAT module is absent | Gives Pester 3.4 a command to mock on machines without RSAT. Each stub throws if a test reaches it unmocked. Defines nothing when the real module is present. Loaded by 13 files: the three EndToEnd and ActiveDirectoryIntegration tests, all seven Performance tests, Restore-ACLOperation, Test-OrphanedSID, and Find-UnknownSID. |
| ADMockFactory.ps1 | `New-ADMocks`, `Get-MockOrphanedSIDs`, `Reset-ADMocks` | Builds a mock AD environment with sample objects and orphaned SIDs. |
| SecurityTestHelpers.ps1 | `Get-MaliciousInputTestCases`, `Test-InputForMaliciousContent`, `New-SecureMockCredential`, `Write-SecurityTestLog`, `Get-TestDataPath`, `Test-ADSecurity`, `Get-MockADEnvironment` | Malicious input patterns (SQL, command, PowerShell, LDAP injection, path traversal), safe credential mocks, and test-data path resolution. |
| BackupTestHelpers.ps1 | `New-TestBackupMetadata`, `New-TestBackupFile`, `Test-BackupPathSecurity`, `New-MaliciousBackupInput`, `Test-BackupFilterValidation`, `New-TestDateRange`, `Assert-BackupResultStructure`; also defines a no-op `Write-StructuredLog` | Builds backup files and metadata for the Backup and Utilities tests. |
| Initialize-TestLogging.ps1 | script, no functions | Dot-sources the logging functions and initializes the logging system against a folder under `$env:TEMP` for tests that need real logging. |

Malicious input is only ever passed to mocked validation. No test executes a malicious string.

## Test data

`Tests/TestData/`.

| Folder | Contents |
| --- | --- |
| Baselines/ | `performance-baselines.psd1`, `security-baselines.json` |
| Configurations/ | `test-config.json` (the standard configuration every test loads), `minimal-config.json`, `enterprise-config.json`, `security-enhanced-config.json`, `performance-testing-config.json`, `development.psd1`, `production.psd1` |
| Fixtures/ | `corrupt-backup-files/`, `performance-datasets/`, `sample-backups/`, `sample-logs/`, `test-certificates/`, `test-files/`; each holds a README describing the fixtures a test creates there at run time |
| MaliciousInputs/ | `attack-patterns.json`, `injection-attempts.json` |
| MockResponses/ | `ad-query-responses.json`, `backup-restore-responses.json`, `database-responses.json`, `graph-api-responses.json`, `log-responses.json` |
| SampleData/ | `mock-ad-objects.json`, `orphaned-sids-large-dataset.json`, `sample-sids.json`, `security-descriptors-complex.json`, `test-acls.json` |

## Conventions for new tests

- One test file per source file, named `<Source>.Tests.ps1`, in the folder that mirrors the
  source folder. A source file that defines several functions gets one test file with one
  `Describe` per function.
- Dot-source the source file and its dependencies at the top of the test file, or stub the
  dependencies (`Write-StructuredLog` is the usual one) so the file runs on its own.
- Mock every AD cmdlet, and dot-source `ADCmdletStubs.ps1` before the first `Mock` when the
  file touches one.
- Pester 3 syntax only. `Should Be`, `Should Throw`, `Assert-MockCalled`. No `Should -Be`.
- Tag the `Describe` with the suite (`Unit`, `Integration`, `Performance`) and the folder.
- Keep timing assertions as regression guards (hundreds of milliseconds of headroom), not as
  benchmarks.

The repository-wide testing standards, written for Pester 6 and newer projects, are in
[ai-powershell-standards](https://github.com/fadwen/ai-powershell-standards). This suite stays on
Pester 3.4 because it must run in-box on Windows PowerShell 5.1.
