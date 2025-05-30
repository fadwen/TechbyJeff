# Comprehensive analysis of a large script
Invoke-ScriptAnalyzer -Path "C:\Scripts\LargeScript.ps1" -Recurse

# Focus on specific rule categories
Invoke-ScriptAnalyzer -Path "C:\Scripts\LargeScript.ps1" -Settings PSGallery

# Automatically fix formatting and style issues
Invoke-ScriptAnalyzer -Path "C:\Scripts\LargeScript.ps1" -Fix

# Find unused variables with a single command
Invoke-ScriptAnalyzer -Path "C:\Scripts\LargeScript.ps1" -IncludeRule PSUseDeclaredVarsMoreThanAssignments

# Check for other code quality issues
Invoke-ScriptAnalyzer -Path "C:\Scripts\LargeScript.ps1" -IncludeRule PSAvoidUsingWriteHost,PSAvoidGlobalVars
