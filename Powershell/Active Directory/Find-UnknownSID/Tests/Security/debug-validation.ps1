# Debug script for input validation
function Test-InputSanitization {
    param($Input, $ValidationRules, $CorrelationId)
    
    $sanitizationResult = @{
        OriginalInput = $Input
        IsValid = $true
        BlockedPatterns = @()
        SanitizedInput = $Input
        CorrelationId = $CorrelationId
    }
    
    # Check for dangerous patterns
    $dangerousPatterns = @{
        SQLInjection = @("'", "--", "/*", "*/", "xp_", "sp_", "DROP", "DELETE", "INSERT", "UPDATE")
        XSS = @("<script", "javascript:", "onload=", "onerror=", "onclick=", "onmouseover=")
        PathTraversal = @("..", "~/", "%2e%2e", "%252e%252e", "%c0%ae")
        CommandInjection = @(";", "|", "&", "``", "`$", "(", ")", "{", "}", "[", "]")
    }
    
    Write-Host "Input to check: '$Input'"
    
    foreach ($patternType in $dangerousPatterns.Keys) {
        Write-Host "Checking $patternType patterns..."
        foreach ($pattern in $dangerousPatterns[$patternType]) {
            Write-Host "  Checking pattern: '$pattern'"
            if ($Input -match [regex]::Escape($pattern)) {
                Write-Host "    MATCH FOUND!"
                $sanitizationResult.IsValid = $false
                $sanitizationResult.BlockedPatterns += "$patternType`: $pattern"
            }
        }
    }
    
    return [PSCustomObject]$sanitizationResult
}

# Test SQL injection
Write-Host "=== Testing SQL Injection ==="
$result = Test-InputSanitization -Input "'; DROP TABLE Users; --" -CorrelationId "debug"
$result | Format-List

Write-Host "`n=== Testing XSS ==="
$result2 = Test-InputSanitization -Input "<script>alert('xss')</script>" -CorrelationId "debug"
$result2 | Format-List
