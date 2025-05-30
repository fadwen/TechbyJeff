# PowerShell Abstract Syntax Tree (AST) Analysis Tools

## Table of Contents
- [Overview & Purpose](#overview--purpose)
- [Prerequisites](#prerequisites)
- [Script Collection](#script-collection)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage Examples](#usage-examples)
- [Custom Rule Development](#custom-rule-development)
- [Troubleshooting](#troubleshooting)
- [References](#references)

## Overview & Purpose

This collection provides comprehensive PowerShell code analysis tools using Abstract Syntax Tree (AST) parsing capabilities. The tools help developers maintain code quality, identify dependencies, find unused code, enforce coding standards, and perform advanced code analysis.

### Key Features
- **Dependency Analysis**: Map function relationships and identify critical components
- **Code Quality**: Find unused variables and functions for cleanup
- **Custom Rules**: Enforce organization-specific coding standards with PSScriptAnalyzer
- **AST Utilities**: Parse and analyze PowerShell code structure
- **Brace Matching**: Find matching braces in complex code blocks

## Prerequisites

### Software Dependencies
- **PowerShell 5.0 or higher** (required for AST parsing)
- **PSScriptAnalyzer module** (optional, for custom rule integration)
- **Windows PowerShell or PowerShell Core**

### Required Permissions
- Read access to PowerShell script files
- Write access for CSV export functionality
- Module import permissions

### Installation Commands
```powershell
# Install PSScriptAnalyzer (optional but recommended)
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser

# Verify PowerShell version
$PSVersionTable.PSVersion
```

## Script Collection

### Core Analysis Tools

| Script | Purpose | Key Features |
|--------|---------|--------------|
| `Show-DependencyMap.ps1` | Function dependency analysis | Maps function relationships, identifies critical functions, exports to CSV |
| `Find-UnusedCode.ps1` | Unused code detection | Finds unused variables and functions, detailed reporting |
| `Find-MatchingBrace.ps1` | Brace matching utility | Locates matching braces using AST parsing |
| `ASTBasicExample.ps1` | AST parsing introduction | Basic example of AST parsing and command extraction |

### Custom Rule Framework

| Script | Purpose | Key Features |
|--------|---------|--------------|
| `CompanyRules.psm1` | Custom PSScriptAnalyzer rules | Enforces naming conventions, requires help documentation |
| `Test-CompanyRules.ps1` | Rule testing framework | Tests custom rules with sample violations |
| `Debug-CompanyRules.ps1` | Rule debugging utility | Comprehensive debugging for custom rule development |
| `badcode.ps1` | Test case with violations | Sample code for testing custom rules |

### Reference Materials

| File | Purpose |
|------|---------|
| `PSScriptAnalyzerExamples.md` | PSScriptAnalyzer usage examples |

## Installation

### Quick Start
1. **Clone or download** the scripts to your local machine
2. **Navigate** to the AST folder in PowerShell
3. **Import modules** as needed:
   ```powershell
   # Import custom rules module
   Import-Module .\CompanyRules.psm1

   # Install PSScriptAnalyzer if not already installed
   Install-Module PSScriptAnalyzer -Scope CurrentUser
   ```

### Folder Structure
```
AST/
├── Show-DependencyMap.ps1      # Dependency analysis
├── Find-UnusedCode.ps1         # Unused code detection
├── Find-MatchingBrace.ps1      # Brace matching
├── ASTBasicExample.ps1         # Basic AST example
├── CompanyRules.psm1           # Custom PSScriptAnalyzer rules
├── Test-CompanyRules.ps1       # Rule testing
├── Debug-CompanyRules.ps1      # Rule debugging
├── badcode.ps1                 # Test cases
├── PSScriptAnalyzerExamples.md # Usage examples
└── README.md                   # This file
```

## Configuration

### Custom Rule Settings
The `CompanyRules.psm1` module enforces these standards:

<details>
<summary>Function Naming Conventions</summary>

- Functions must use approved PowerShell verbs
- Must follow pattern: `Verb-Company*`
- Approved verbs: Get, Set, New, Remove, Test, Start, Stop, Restart, Add, Clear, Copy, Move, Update, Import, Export

</details>

<details>
<summary>Variable Naming Standards</summary>

- **Parameters**: PascalCase (e.g., `$UserName`, `$FilePath`)
- **Local Variables**: camelCase (e.g., `$userName`, `$filePath`)
- Excludes PowerShell automatic variables

</details>

<details>
<summary>Documentation Requirements</summary>

- Public functions must include comment-based help
- Must contain `.SYNOPSIS` section
- Applies to functions matching pattern: `(Get|Set|New|Remove)-Company*`

</details>

## Usage Examples

### Dependency Analysis
```powershell
# Analyze a specific script file
$analysis = Show-DependencyMap -ScriptPath "C:\Scripts\MyScript.ps1"
Show-DependencyReport -Analysis $analysis

# Export results to CSV
Show-DependencyReport -Analysis $analysis -ExportPath "C:\Reports\Dependencies.csv"

# Analyze script content from a variable
$analysis = Show-DependencyMap -ScriptContent $scriptVariable
Show-DependencyReport -Analysis $analysis
```

### Unused Code Detection
```powershell
# Find unused code in a script
$analysis = Find-UnusedCode -ScriptPath "C:\Scripts\MyScript.ps1"
Show-UnusedCodeReport -Analysis $analysis

# Analyze the current script itself
$analysis = Find-UnusedCode -AnalyzeSelf
Show-UnusedCodeReport -Analysis $analysis
```

### Custom Rule Validation
```powershell
# Test custom rules with PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path "MyScript.ps1" -CustomRulePath ".\CompanyRules.psm1"

# Run the built-in test suite
.\Test-CompanyRules.ps1

# Debug custom rule functionality
.\Debug-CompanyRules.ps1
```

### Brace Matching
```powershell
# Find matching brace for a specific position
$code = 'Get-Process | Where-Object { $_.CPU -gt 100 }'
$result = Find-MatchingBrace -Code $code -Position 31

# Display brace positions in code
Find-BracePositions -Code $code
```

### Basic AST Parsing
```powershell
# Run the basic example
.\ASTBasicExample.ps1

# Parse your own code
$code = 'Get-Service | Where-Object {$_.Status -eq "Running"}'
$ast = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$null, [ref]$null)
$commands = $ast.FindAll({$args[0] -is [System.Management.Automation.Language.CommandAst]}, $true)
```

## Custom Rule Development

### Creating New Rules
1. **Add rule logic** to `Measure-CompanyStandards` function in `CompanyRules.psm1`
2. **Return diagnostic records** using this pattern:
   ```powershell
   $results += [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]::new(
       "Violation message",
       $nodeExtent,
       'RuleName',
       [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticSeverity]::Warning,
       $null
   )
   ```
3. **Test the rule** using `Test-CompanyRules.ps1`
4. **Debug issues** with `Debug-CompanyRules.ps1`

### Rule Severity Levels
- **Error**: Critical violations that break functionality
- **Warning**: Important violations that should be addressed
- **Information**: Style or convention violations

## Troubleshooting

### Common Issues

<details>
<summary>Parse Errors in Scripts</summary>

**Problem**: AST parsing fails with syntax errors

**Solution**:
- Check PowerShell syntax in the target script
- Verify file encoding (UTF-8 recommended)
- Look for unmatched braces or quotes

```powershell
# Check for parse errors
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$null, [ref]$errors)
if ($errors) { $errors | Format-List }
```

</details>

<details>
<summary>Custom Rules Not Working</summary>

**Problem**: PSScriptAnalyzer doesn't detect custom rule violations

**Solution**:
1. Verify module import: `Import-Module .\CompanyRules.psm1 -Force`
2. Check function export: `Get-Command Measure-CompanyStandards`
3. Run debug script: `.\Debug-CompanyRules.ps1`
4. Verify rule syntax and diagnostic record creation

</details>

<details>
<summary>Permission Denied Errors</summary>

**Problem**: Cannot read script files or write export files

**Solution**:
- Check file permissions
- Run PowerShell as administrator if needed
- Verify file paths are correct
- Ensure destination folders exist for exports

</details>

<details>
<summary>False Positives in Unused Code</summary>

**Problem**: Variables or functions marked as unused when they are actually used

**Solution**:
- Check for dynamic variable usage (string evaluation)
- Verify scope boundaries (function vs script scope)
- Review excluded variable list in `Find-UnusedCode.ps1`
- Consider splatting or indirect references

</details>

### Performance Considerations
- Large scripts may take longer to analyze
- Consider breaking very large scripts into smaller modules
- CSV exports are faster than console output for large result sets

## References

### PowerShell AST Documentation
- [PowerShell AST Classes](https://docs.microsoft.com/en-us/dotnet/api/system.management.automation.language)
- [Abstract Syntax Tree in PowerShell](https://devblogs.microsoft.com/powershell/powershell-internals-abstract-syntax-tree/)

### PSScriptAnalyzer Resources
- [PSScriptAnalyzer GitHub](https://github.com/PowerShell/PSScriptAnalyzer)
- [Creating Custom Rules](https://github.com/PowerShell/PSScriptAnalyzer/blob/master/docs/markdown/Invoke-ScriptAnalyzer.md)
- [Built-in Rules Reference](https://github.com/PowerShell/PSScriptAnalyzer/tree/master/RuleDocumentation)

### PowerShell Best Practices
- [PowerShell Practice and Style Guide](https://poshcode.gitbook.io/powershell-practice-and-style/)
- [PowerShell Gallery Guidelines](https://docs.microsoft.com/en-us/powershell/scripting/gallery/concepts/publishing-guidelines)

---

**Author**: Jeffrey Stuhr
**Last Updated**: 2025-05-29
**Version**: 1.0
**License**: MIT
