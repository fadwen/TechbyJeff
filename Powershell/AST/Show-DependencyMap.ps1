function Show-DependencyMap {
    param(
        [Parameter(ParameterSetName = 'File')]
        [string]$ScriptPath,

        [Parameter(ParameterSetName = 'String')]
        [string]$ScriptContent,

        [switch]$AnalyzeSelf,
        [string]$ExportPath = $null
    )

    try {
        # Determine what to analyze
        if ($AnalyzeSelf) {
            $content = $MyInvocation.ScriptName | Get-Content -Raw -ErrorAction Stop
            $sourceName = "Current Script"
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'File') {
            if (-not (Test-Path $ScriptPath)) {
                Write-Host "Error: File '$ScriptPath' does not exist." -ForegroundColor Red
                return $null
            }
            $content = Get-Content -Path $ScriptPath -Raw -ErrorAction Stop
            $sourceName = Split-Path $ScriptPath -Leaf
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'String') {
            $content = $ScriptContent
            $sourceName = "Provided Script Content"
        }
        else {
            Write-Host "Error: Must specify either -ScriptPath, -ScriptContent, or -AnalyzeSelf" -ForegroundColor Red
            return $null
        }

        if ([string]::IsNullOrWhiteSpace($content)) {
            Write-Host "Error: Script content is empty or null." -ForegroundColor Red
            return $null
        }

        Write-Host "Analyzing dependencies in: $sourceName" -ForegroundColor Cyan
        Write-Host "Content length: $($content.Length) characters" -ForegroundColor Gray

        # Parse the content
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$errors)

        if ($errors.Count -gt 0) {
            Write-Host "Warning: Found $($errors.Count) parse errors:" -ForegroundColor Yellow
            foreach ($error in $errors) {
                Write-Host "  - Line $($error.Extent.StartLineNumber): $($error.Message)" -ForegroundColor Yellow
            }
        }

        # Find all function definitions with their content
        $functions = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true)

        Write-Host "Found $($functions.Count) function definitions" -ForegroundColor Gray

        $dependencyMap = @{}
        $reverseDependencyMap = @{}

        foreach ($function in $functions) {
            $functionName = $function.Name
            $functionBody = $function.Body.ToString()

            Write-Host "Analyzing function: $functionName" -ForegroundColor Gray

            # Find all commands called within this function
            $commandsInFunction = $function.FindAll({
                $args[0] -is [System.Management.Automation.Language.CommandAst]
            }, $true)

            $dependencies = @()
            foreach ($command in $commandsInFunction) {
                $commandName = $command.GetCommandName()
                # Check if this command is a function defined in our script
                if ($commandName -in $functions.Name) {
                    $dependencies += $commandName
                    Write-Host "  - Calls: $commandName" -ForegroundColor DarkGray
                }
            }

            $dependencyMap[$functionName] = $dependencies | Select-Object -Unique

            # Build reverse dependency map
            foreach ($dependency in ($dependencies | Select-Object -Unique)) {
                if (-not $reverseDependencyMap.ContainsKey($dependency)) {
                    $reverseDependencyMap[$dependency] = @()
                }
                $reverseDependencyMap[$dependency] += $functionName
            }
        }

        # Calculate dependency metrics
        $analysis = @{
            DependencyMap = $dependencyMap
            ReverseDependencyMap = $reverseDependencyMap
            CriticalFunctions = @()
            IsolatedFunctions = @()
            Statistics = @{}
            SourceName = $sourceName
            ParseErrors = $errors
        }

        # Identify critical functions (used by many others)
        $analysis.CriticalFunctions = $reverseDependencyMap.Keys | Where-Object {
            $reverseDependencyMap[$_].Count -ge 2  # Lowered threshold for demo
        } | Sort-Object { $reverseDependencyMap[$_].Count } -Descending

        # Identify isolated functions (no dependencies and not used by others)
        $analysis.IsolatedFunctions = $dependencyMap.Keys | Where-Object {
            $dependencyMap[$_].Count -eq 0 -and
            (-not $reverseDependencyMap.ContainsKey($_) -or $reverseDependencyMap[$_].Count -eq 0)
        }

        $avgDependencies = if ($dependencyMap.Count -gt 0) {
            ($dependencyMap.Values | ForEach-Object { $_.Count } | Measure-Object -Average).Average
        } else { 0 }

        $analysis.Statistics = @{
            TotalFunctions = $functions.Count
            CriticalFunctionCount = $analysis.CriticalFunctions.Count
            IsolatedFunctionCount = $analysis.IsolatedFunctions.Count
            AverageDependencies = $avgDependencies
        }

        return $analysis
    }
    catch {
        Write-Host "Error analyzing dependencies: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Show-DependencyReport {
    param($Analysis, [string]$ExportPath = $null)

    if (-not $Analysis) {
        Write-Host "No analysis data provided." -ForegroundColor Red
        return
    }

    $separator = "=" * 50
    Write-Host "`n$separator" -ForegroundColor Cyan
    Write-Host "Function Dependency Analysis: $($Analysis.SourceName)" -ForegroundColor Green
    Write-Host "$separator" -ForegroundColor Cyan

    Write-Host "`nStatistics:" -ForegroundColor Yellow
    Write-Host "  Total Functions: " -NoNewline -ForegroundColor Gray
    Write-Host "$($Analysis.Statistics.TotalFunctions)" -ForegroundColor White

    Write-Host "  Critical Functions: " -NoNewline -ForegroundColor Gray
    Write-Host "$($Analysis.Statistics.CriticalFunctionCount)" -ForegroundColor Yellow

    Write-Host "  Isolated Functions: " -NoNewline -ForegroundColor Gray
    Write-Host "$($Analysis.Statistics.IsolatedFunctionCount)" -ForegroundColor Cyan

    Write-Host "  Average Dependencies: " -NoNewline -ForegroundColor Gray
    Write-Host "$([Math]::Round($Analysis.Statistics.AverageDependencies, 2))" -ForegroundColor White

    # Show dependency map
    if ($Analysis.DependencyMap.Count -gt 0) {
        Write-Host "`nFunction Dependencies:" -ForegroundColor Yellow
        foreach ($func in $Analysis.DependencyMap.GetEnumerator() | Sort-Object Key) {
            if ($func.Value.Count -gt 0) {
                Write-Host "  $($func.Key) depends on:" -ForegroundColor White
                foreach ($dep in $func.Value) {
                    Write-Host "    - $dep" -ForegroundColor Gray
                }
            } else {
                Write-Host "  $($func.Key)" -ForegroundColor White -NoNewline
                Write-Host " (no internal dependencies)" -ForegroundColor DarkGray
            }
        }
    }

    if ($Analysis.CriticalFunctions.Count -gt 0) {
        Write-Host "`nCritical Functions (High Impact if Changed):" -ForegroundColor Red
        foreach ($func in $Analysis.CriticalFunctions) {
            $usageCount = $Analysis.ReverseDependencyMap[$func].Count
            Write-Host "  $func " -ForegroundColor Yellow -NoNewline
            Write-Host "(used by $usageCount functions)" -ForegroundColor Gray
            foreach ($user in $Analysis.ReverseDependencyMap[$func]) {
                Write-Host "    - $user" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "`nCritical Functions: " -NoNewline -ForegroundColor Red
        Write-Host "None found" -ForegroundColor Green
    }

    if ($Analysis.IsolatedFunctions.Count -gt 0) {
        Write-Host "`nIsolated Functions (Safe to Remove/Modify):" -ForegroundColor Green
        foreach ($func in $Analysis.IsolatedFunctions) {
            Write-Host "  - $func" -ForegroundColor Cyan
        }
    } else {
        Write-Host "`nIsolated Functions: " -NoNewline -ForegroundColor Green
        Write-Host "None found" -ForegroundColor Yellow
    }

    # Show functions with most dependencies (potential complexity issues)
    $complexFunctions = $Analysis.DependencyMap.GetEnumerator() |
        Where-Object { $_.Value.Count -gt 3 } |  # Lowered threshold for demo
        Sort-Object { $_.Value.Count } -Descending

    if ($complexFunctions.Count -gt 0) {
        Write-Host "`nComplex Functions (Many Dependencies):" -ForegroundColor Magenta
        foreach ($func in $complexFunctions) {
            Write-Host "  $($func.Key) " -ForegroundColor Yellow -NoNewline
            Write-Host "depends on $($func.Value.Count) functions" -ForegroundColor Gray
        }
    } else {
        Write-Host "`nComplex Functions: " -NoNewline -ForegroundColor Magenta
        Write-Host "None found" -ForegroundColor Green
    }

    # Export to CSV if requested
    if ($ExportPath) {
        try {
            $exportData = $Analysis.DependencyMap.GetEnumerator() | ForEach-Object {
                [PSCustomObject]@{
                    Function = $_.Key
                    DependsOn = ($_.Value -join '; ')
                    DependencyCount = $_.Value.Count
                    UsedBy = if ($Analysis.ReverseDependencyMap[$_.Key]) {
                        ($Analysis.ReverseDependencyMap[$_.Key] -join '; ')
                    } else { 'None' }
                    UsageCount = if ($Analysis.ReverseDependencyMap[$_.Key]) {
                        $Analysis.ReverseDependencyMap[$_.Key].Count
                    } else { 0 }
                }
            }

            $exportData | Export-Csv -Path $ExportPath -NoTypeInformation
            Write-Host "`nDetailed report exported to: " -ForegroundColor Green -NoNewline
            Write-Host "$ExportPath" -ForegroundColor Cyan
        }
        catch {
            Write-Host "`nError exporting to CSV: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "`n$separator" -ForegroundColor Cyan
}

# Sample script for testing
$sampleScript = @'
# Sample PowerShell script with function dependencies

function Get-DatabaseConnection {
    param($ConnectionString)
    # Base utility function
    return "Connection to $ConnectionString"
}

function Get-UserData {
    param($UserId)
    $connection = Get-DatabaseConnection -ConnectionString "UserDB"
    return "User data for $UserId from $connection"
}

function Get-OrderData {
    param($OrderId)
    $connection = Get-DatabaseConnection -ConnectionString "OrderDB"
    return "Order data for $OrderId from $connection"
}

function Generate-UserReport {
    param($UserId)
    $userData = Get-UserData -UserId $UserId
    $orderData = Get-OrderData -OrderId "123"
    return "Report: $userData, $orderData"
}

function Send-EmailNotification {
    param($Message)
    # Isolated function - no dependencies
    return "Email sent: $Message"
}

function Process-ComplexWorkflow {
    param($UserId, $OrderId)
    $userData = Get-UserData -UserId $UserId
    $orderData = Get-OrderData -OrderId $OrderId
    $report = Generate-UserReport -UserId $UserId
    return "Workflow complete: $userData, $orderData, $report"
}

function Unused-HelperFunction {
    # This function is not called by anyone
    return "I'm lonely"
}
'@

Write-Host "Testing with sample script content:" -ForegroundColor Cyan
$dependencyAnalysis = Show-DependencyMap -ScriptContent $sampleScript
Show-DependencyReport -Analysis $dependencyAnalysis

$dashSeparator = "-" * 60
Write-Host "`n$dashSeparator" -ForegroundColor Gray
Write-Host "Usage Examples:" -ForegroundColor Yellow

Write-Host "`nTo analyze a specific file:" -ForegroundColor Yellow
Write-Host '  $analysis = Show-DependencyMap -ScriptPath "C:\Path\To\Your\Script.ps1"' -ForegroundColor White
Write-Host '  Show-DependencyReport -Analysis $analysis' -ForegroundColor White

Write-Host "`nTo export results to CSV:" -ForegroundColor Yellow
Write-Host '  Show-DependencyReport -Analysis $analysis -ExportPath "C:\Reports\Dependencies.csv"' -ForegroundColor White

Write-Host "`nTo analyze the current script:" -ForegroundColor Yellow
Write-Host '  $analysis = Show-DependencyMap -AnalyzeSelf' -ForegroundColor White
Write-Host '  Show-DependencyReport -Analysis $analysis' -ForegroundColor White