Describe "Security Framework Tests" {
    BeforeAll {
    # Import test bootstrapper first
    $testBootstrapper = Join-Path (Split-Path -Parent $PSScriptRoot) "Infrastructure\TestBootstrapper.ps1"
    if (Test-Path $testBootstrapper) {
        . $testBootstrapper
    }
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
    }

    Context "Basic Security Validation" {
        It "Should load security functions" {
            Get-Command Test-ClassIntegrity -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should validate correlation ID format" {
            $script:TestCorrelationId | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        }
    }
}
