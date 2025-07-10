# Enhanced Class Loading Implementation for Find-UnknownSID

This document provides implementation options for enhancing the current class loading approach in Find-UnknownSID.ps1.

## Option 1: Minimal Enhancement (Recommended)

Replace the current class loading section in Find-UnknownSID.ps1 with this enhanced version:

```powershell
# Enhanced class loading with basic security controls
Write-StatusMessage "Loading class definitions..." -Color Cyan

$classesPath = Join-Path $PSScriptRoot "Classes"
$classFiles = @(
    'ScriptConfiguration.ps1',
    'MemoryManager.ps1',
    'ProcessingStatistics.ps1',
    'OrphanedSIDResult.ps1',
    'SIDAnalysisResult.ps1',
    'SecurityValidationResult.ps1',
    'RemovalOperationResult.ps1',
    'RestoreOperationResult.ps1'
)

# Validate Classes directory exists
if (-not (Test-Path $classesPath -PathType Container)) {
    Write-Error "❌ Classes directory not found: $classesPath"
    throw "Critical initialization failure: Classes directory missing"
}

$resolvedClassesPath = Resolve-Path -Path $classesPath

foreach ($classFile in $classFiles) {
    $classPath = Join-Path $classesPath $classFile

    try {
        # Basic security checks
        if (-not (Test-Path $classPath -PathType Leaf)) {
            throw "Required class file not found: $classFile"
        }

        # Path traversal protection
        $resolvedClassPath = Resolve-Path -Path $classPath
        if (-not $resolvedClassPath.Path.StartsWith($resolvedClassesPath.Path)) {
            throw "Security violation: Class file outside expected directory: $classFile"
        }

        # Load the class
        . $resolvedClassPath.Path
        Write-Verbose "✅ Imported class: $classFile"

        # Log successful import
        if (Get-Command Write-ScriptLog -ErrorAction SilentlyContinue) {
            Write-ScriptLog "Successfully imported class: $classFile" -Level Debug -Component 'ClassLoader' -CorrelationId $CorrelationId
        }
    }
    catch {
        $errorMessage = "❌ Failed to import class $classFile : $($_.Exception.Message)"
        Write-Error $errorMessage

        # Log failure
        if (Get-Command Write-ScriptLog -ErrorAction SilentlyContinue) {
            Write-ScriptLog $errorMessage -Level Error -Component 'ClassLoader' -CorrelationId $CorrelationId
        }

        throw "Critical class import failure: $classFile"
    }
}

Write-StatusMessage "✅ All classes loaded successfully" -Color Green
```

## Option 2: Full Secure Implementation

If you want maximum security, replace the class loading section with:

```powershell
# Import secure class loader
. (Join-Path $PSScriptRoot "Private\SecureClassImporter.ps1")

# Use secure class loading
try {
    $classLoadResult = Import-ProjectClassesSecure -ClassesPath (Join-Path $PSScriptRoot "Classes") -CorrelationId $CorrelationId -ValidateIntegrity:$false

    if ($classLoadResult.Success) {
        Write-StatusMessage "✅ All $($classLoadResult.LoadedCount) classes loaded securely" -Color Green

        # Optional: Test class instantiation
        $testResult = Test-ClassLoadingIntegrity -CorrelationId $CorrelationId
        if ($testResult.Success) {
            Write-Verbose "All classes tested successfully for instantiation"
        } else {
            Write-Warning "Some classes failed instantiation testing"
        }
    } else {
        throw "Secure class loading failed: $($classLoadResult.FailedCount) classes failed"
    }
}
catch {
    Write-Error "❌ Secure class loading failed: $($_.Exception.Message)"
    throw "Critical initialization failure"
}
```

## Option 3: Hybrid Approach with Dynamic Discovery (Use with Caution)

⚠️ **Only use if you absolutely need dynamic capabilities and understand the security risks:**

```powershell
# Hybrid approach: Core classes hardcoded, optional dynamic discovery
function Import-ProjectClassesHybrid {
    param(
        [string]$ClassesPath,
        [string]$CorrelationId,
        [switch]$AllowDynamicDiscovery = $false
    )

    # Always load core classes first (hardcoded for security)
    $coreClasses = @(
        'ScriptConfiguration.ps1',
        'MemoryManager.ps1',
        'ProcessingStatistics.ps1'
    )

    Write-StatusMessage "Loading core classes..." -Color Cyan
    foreach ($coreClass in $coreClasses) {
        $classPath = Join-Path $ClassesPath $coreClass
        if (Test-Path $classPath) {
            . $classPath
            Write-Verbose "Core class loaded: $coreClass"
        } else {
            throw "Critical core class missing: $coreClass"
        }
    }

    # Load remaining hardcoded classes
    $additionalClasses = @(
        'OrphanedSIDResult.ps1',
        'SIDAnalysisResult.ps1',
        'SecurityValidationResult.ps1',
        'RemovalOperationResult.ps1',
        'RestoreOperationResult.ps1'
    )

    foreach ($additionalClass in $additionalClasses) {
        $classPath = Join-Path $ClassesPath $additionalClass
        if (Test-Path $classPath) {
            . $classPath
            Write-Verbose "Additional class loaded: $additionalClass"
        }
    }

    # Optional dynamic discovery (disabled by default)
    if ($AllowDynamicDiscovery) {
        Write-Warning "Dynamic class discovery enabled - ensure Classes directory contains only trusted files"

        $allKnownClasses = $coreClasses + $additionalClasses
        $dynamicFiles = Get-ChildItem -Path $ClassesPath -Filter "*.ps1" |
            Where-Object { $_.Name -notin $allKnownClasses } |
            Where-Object { $_.Name -match '^[A-Za-z][A-Za-z0-9]*\.ps1$' }

        foreach ($file in $dynamicFiles) {
            Write-Warning "Loading dynamic class file: $($file.Name)"
            try {
                . $file.FullName
                Write-Verbose "Dynamic class loaded: $($file.Name)"
            }
            catch {
                Write-Warning "Failed to load dynamic class $($file.Name): $($_.Exception.Message)"
            }
        }
    }
}

# Usage (dynamic discovery disabled by default)
Import-ProjectClassesHybrid -ClassesPath (Join-Path $PSScriptRoot "Classes") -CorrelationId $CorrelationId
```

## Recommended Implementation Path

1. **Start with Option 1** - Minimal enhancement that adds basic security without major changes
2. **Consider Option 2** - If you want enterprise-grade security controls
3. **Avoid Option 3** - Unless you have specific requirements for dynamic discovery

## Security Considerations Summary

- **Hardcoded approach (current)**: ✅ Most secure, recommended for production
- **Enhanced hardcoded (Option 1)**: ✅ Secure with additional protections
- **Full secure implementation (Option 2)**: ✅ Maximum security with enterprise features
- **Hybrid with dynamic (Option 3)**: ⚠️ Use only with extreme caution and proper controls

## File Integrity Monitoring (Optional)

For high-security environments, consider implementing file integrity monitoring:

```powershell
# Generate checksums for all class files
$classFiles = Get-ChildItem ".\Classes\*.ps1"
foreach ($file in $classFiles) {
    $hash = Get-FileHash $file.FullName -Algorithm SHA256
    Write-Output "$($file.Name): $($hash.Hash)"
}
```

Store these hashes in a secure location and verify them before loading classes in production environments.
