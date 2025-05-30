function Find-UnusedCode {
    param(
        [Parameter(ParameterSetName = 'File')]
        [string]$ScriptPath,

        [Parameter(ParameterSetName = 'String')]
        [string]$ScriptContent,

        [switch]$AnalyzeSelf
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

        Write-Host "Analyzing: $sourceName" -ForegroundColor Cyan
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

        # Find all variable assignments
        $variableAssignments = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst]
        }, $true)

        Write-Host "Found $($variableAssignments.Count) variable assignments" -ForegroundColor Gray

        # Find all variable references
        $variableReferences = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true)

        Write-Host "Found $($variableReferences.Count) variable references" -ForegroundColor Gray

        # Find all function definitions
        $functionDefinitions = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true)

        Write-Host "Found $($functionDefinitions.Count) function definitions" -ForegroundColor Gray

        # Find all function calls (commands)
        $functionCalls = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.CommandAst]
        }, $true)

        Write-Host "Found $($functionCalls.Count) command calls" -ForegroundColor Gray

        $results = @{
            UnusedVariables = @()
            UnusedFunctions = @()
            Statistics = @{}
            SourceName = $sourceName
            ParseErrors = $errors
        }

        # Analyze variables
        $assignedVariables = @()
        foreach ($assignment in $variableAssignments) {
            if ($assignment.Left -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $varName = $assignment.Left.VariablePath.UserPath
                $assignedVariables += @{
                    Name = $varName
                    Line = $assignment.Extent.StartLineNumber
                    Position = $assignment.Extent.StartOffset
                }
            }
        }

        Write-Host "Debug - Assigned variables:" -ForegroundColor Magenta
        foreach ($var in $assignedVariables) {
            Write-Host "  $($var.Name) (Line $($var.Line))" -ForegroundColor Magenta
        }

        $referencedVariables = @()
        foreach ($reference in $variableReferences) {
            $varName = $reference.VariablePath.UserPath
            $referencedVariables += $varName
        }

        $uniqueReferencedVars = $referencedVariables | Select-Object -Unique
        Write-Host "Debug - Referenced variables:" -ForegroundColor Magenta
        foreach ($var in $uniqueReferencedVars) {
            Write-Host "  $var" -ForegroundColor Magenta
        }

        # Find unused variables
        $unusedVars = @()
        foreach ($assignedVar in $assignedVariables) {
            $varName = $assignedVar.Name
            # Exclude automatic variables, parameters, and commonly used variables
            $excludedVars = @('_', 'args', 'input', 'PSItem', 'this', 'matches', 'lastexitcode',
                             'error', 'warning', 'information', 'verbose', 'debug', 'progress',
                             'whatifpreference', 'confirmpreference', 'erroractionpreference')

            if ($varName -notin $excludedVars -and $varName -notin $referencedVariables) {
                $unusedVars += $assignedVar
            }
        }

        $results.UnusedVariables = $unusedVars

        # Analyze functions
        $definedFunctions = @()
        foreach ($funcDef in $functionDefinitions) {
            $definedFunctions += @{
                Name = $funcDef.Name
                Line = $funcDef.Extent.StartLineNumber
                Position = $funcDef.Extent.StartOffset
            }
        }

        $calledFunctions = @()
        foreach ($call in $functionCalls) {
            $commandName = $call.GetCommandName()
            if ($commandName) {
                $calledFunctions += $commandName
            }
        }

        # Find unused functions
        $unusedFuncs = @()
        foreach ($definedFunc in $definedFunctions) {
            if ($definedFunc.Name -notin $calledFunctions) {
                $unusedFuncs += $definedFunc
            }
        }

        $results.UnusedFunctions = $unusedFuncs

        # Generate statistics
        $results.Statistics = @{
            TotalLines = ($content -split "`n").Count
            TotalVariables = $assignedVariables.Count
            TotalFunctions = $definedFunctions.Count
            UnusedVariableCount = $unusedVars.Count
            UnusedFunctionCount = $unusedFuncs.Count
            ReferencedVariables = ($referencedVariables | Select-Object -Unique).Count
            CalledFunctions = ($calledFunctions | Select-Object -Unique).Count
            ParseErrors = $errors.Count
        }

        return $results
    }
    catch {
        Write-Host "Error analyzing script: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Show-UnusedCodeReport {
    param([object]$Analysis)

    if (-not $Analysis) {
        Write-Host "No analysis data provided." -ForegroundColor Red
        return
    }

    $separator = "=" * 60
    Write-Host "`n$separator" -ForegroundColor Cyan
    Write-Host "Script Analysis Results: $($Analysis.SourceName)" -ForegroundColor Green
    Write-Host "$separator" -ForegroundColor Cyan

    # Statistics
    Write-Host "`nStatistics:" -ForegroundColor Yellow
    Write-Host "  Total Lines: " -NoNewline -ForegroundColor Gray
    Write-Host "$($Analysis.Statistics.TotalLines)" -ForegroundColor White

    Write-Host "  Variables: " -NoNewline -ForegroundColor Gray
    Write-Host "$($Analysis.Statistics.UnusedVariableCount)" -ForegroundColor Red -NoNewline
    Write-Host " unused / " -ForegroundColor Gray -NoNewline
    Write-Host "$($Analysis.Statistics.TotalVariables)" -ForegroundColor Green -NoNewline
    Write-Host " total" -ForegroundColor Gray

    Write-Host "  Functions: " -NoNewline -ForegroundColor Gray
    Write-Host "$($Analysis.Statistics.UnusedFunctionCount)" -ForegroundColor Red -NoNewline
    Write-Host " unused / " -ForegroundColor Gray -NoNewline
    Write-Host "$($Analysis.Statistics.TotalFunctions)" -ForegroundColor Green -NoNewline
    Write-Host " total" -ForegroundColor Gray

    if ($Analysis.Statistics.ParseErrors -gt 0) {
        Write-Host "  Parse Errors: " -NoNewline -ForegroundColor Gray
        Write-Host "$($Analysis.Statistics.ParseErrors)" -ForegroundColor Red
    }

    # Unused Variables
    if ($Analysis.UnusedVariables.Count -gt 0) {
        Write-Host "`nUnused Variables:" -ForegroundColor Yellow
        foreach ($var in $Analysis.UnusedVariables) {
            Write-Host "  - " -NoNewline -ForegroundColor Gray
            Write-Host "`$$($var.Name)" -ForegroundColor Red -NoNewline
            Write-Host " (Line $($var.Line))" -ForegroundColor Gray
        }
    } else {
        Write-Host "`nUnused Variables: " -NoNewline -ForegroundColor Yellow
        Write-Host "None found ✓" -ForegroundColor Green
    }

    # Unused Functions
    if ($Analysis.UnusedFunctions.Count -gt 0) {
        Write-Host "`nUnused Functions:" -ForegroundColor Yellow
        foreach ($func in $Analysis.UnusedFunctions) {
            Write-Host "  - " -NoNewline -ForegroundColor Gray
            Write-Host "$($func.Name)" -ForegroundColor Red -NoNewline
            Write-Host " (Line $($func.Line))" -ForegroundColor Gray
        }
    } else {
        Write-Host "`nUnused Functions: " -NoNewline -ForegroundColor Yellow
        Write-Host "None found ✓" -ForegroundColor Green
    }

    Write-Host "`n$separator" -ForegroundColor Cyan
}

# Example usage with sample code
$sampleScript = @'
# Sample PowerShell script for testing
function Get-UserInfo {
    param($Username)
    return Get-ADUser $Username
}

function Send-Email {
    param($To, $Subject, $Body)
    Send-MailMessage -To $To -Subject $Subject -Body $Body
}

function Process-Data {
    # This function is never called
    param($Data)
    return $Data | Sort-Object
}

# Variables
$usedVariable = "Hello World"
$unusedVariable = "This is never used"
$anotherUnused = 42

# Usage
Write-Host $usedVariable
$userInfo = Get-UserInfo -Username "john.doe"
Send-Email -To "test@example.com" -Subject "Test" -Body $usedVariable
'@

Write-Host "Testing with sample script content:" -ForegroundColor Cyan
$analysis = Find-UnusedCode -ScriptContent $sampleScript
Show-UnusedCodeReport -Analysis $analysis

$dashSeparator = "-" * 60
Write-Host "`n$dashSeparator" -ForegroundColor Gray
Write-Host "To analyze a specific file, use:" -ForegroundColor Yellow
Write-Host '  $analysis = Find-UnusedCode -ScriptPath "C:\Path\To\Your\Script.ps1"' -ForegroundColor White
Write-Host '  Show-UnusedCodeReport -Analysis $analysis' -ForegroundColor White

Write-Host "`nTo analyze the current script file, use:" -ForegroundColor Yellow
Write-Host '  $analysis = Find-UnusedCode -AnalyzeSelf' -ForegroundColor White
Write-Host '  Show-UnusedCodeReport -Analysis $analysis' -ForegroundColor White