# Parse a simple script
$code = 'Get-Process | Where-Object {$_.CPU -gt 100}'
$ast = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$null, [ref]$null)

# Find all command elements
$commands = $ast.FindAll({$args[0] -is [System.Management.Automation.Language.CommandAst]}, $true)

# Display the commands found
$commands | ForEach-Object {
    Write-Host "Found command: $($_.GetCommandName())"
}
