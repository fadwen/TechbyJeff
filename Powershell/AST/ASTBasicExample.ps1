<#
.SYNOPSIS
    Demonstrates basic PowerShell Abstract Syntax Tree (AST) parsing and command extraction.

.DESCRIPTION
    This script provides a simple example of how to use PowerShell's AST parsing capabilities
    to analyze PowerShell code. It demonstrates:

    - Parsing PowerShell code into an Abstract Syntax Tree
    - Finding specific AST node types (CommandAst in this case)
    - Extracting command names from the parsed structure
    - Basic AST traversal techniques

    This serves as an introductory example for developers learning to work with PowerShell's
    AST functionality for code analysis, refactoring tools, or custom linting rules.

.EXAMPLE
    PS> .\ASTBasicExample.ps1

    Runs the example script, which will parse a sample command and display the commands found:
    Found command: Get-Process
    Found command: Where-Object

.EXAMPLE
    PS> # Modify the $code variable in the script to analyze different PowerShell code
    PS> .\ASTBasicExample.ps1

    You can edit the $code variable in this script to experiment with parsing different
    PowerShell commands and see how they are identified by the AST parser.

.NOTES
    Author: Jeffrey Stuhr
    Last Updated: 2025-05-29
    Version: 1.0

    This example uses System.Management.Automation.Language.Parser which is available
    in PowerShell 3.0 and later versions. The AST parsing functionality is the foundation
    for more advanced code analysis tools and PowerShell development utilities.

    For more complex AST operations, see the other scripts in this folder:
    - Show-DependencyMap.ps1 for function dependency analysis
    - Find-UnusedCode.ps1 for identifying unused code elements
#>

# Parse a simple script
$code = 'Get-Process | Where-Object {$_.CPU -gt 100}'
$ast = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$null, [ref]$null)

# Find all command elements
$commands = $ast.FindAll({$args[0] -is [System.Management.Automation.Language.CommandAst]}, $true)

# Display the commands found
$commands | ForEach-Object {
    Write-Host "Found command: $($_.GetCommandName())"
}
