#Requires -Version 5.1

class ScriptConfiguration {
    [string[]]$WellKnownSIDPatterns
    [string[]]$ProtectedSIDs
    [string[]]$CriticalObjectPatterns
    [int]$BatchSize
    [int]$MemoryCheckInterval
    [bool]$EnableDetailedLogging
    [string]$LogLevel
    [string]$LogFilePath
    [bool]$EnableLogFileRotation
    [int]$MaxLogFileSizeMB

    ScriptConfiguration() {
        $this.InitializeDefaults()
    }

    [void]InitializeDefaults() {
        $this.WellKnownSIDPatterns = @(
            '^S-1-1-0$',          # Everyone
            '^S-1-5-11$',         # Authenticated Users
            '^S-1-5-32-',         # Built-in groups
            '^S-1-3-[0-4]$',      # Creator Owner/Group
            '^S-1-5-18$',         # Local System
            '^S-1-5-19$',         # Local Service
            '^S-1-5-20$',         # Network Service
            '^S-1-5-6$',          # Service
            '^S-1-16-',           # Integrity levels
            '^S-1-15-2-\d+$',     # App packages
            '^S-1-5-80-\d+$',     # NT Service
            '^S-1-5-90-\d+$',     # Windows Manager
            '^S-1-5-96-\d+$',     # Font drivers
            '^S-1-5-84-\d+$'      # User-mode drivers
        )

        $this.ProtectedSIDs = @(
            'S-1-5-32-544',    # Administrators
            'S-1-5-32-545',    # Users
            'S-1-5-32-546',    # Guests
            'S-1-5-18',        # Local System
            'S-1-5-19',        # Local Service
            'S-1-5-20'         # Network Service
        )

        $this.CriticalObjectPatterns = @(
            '*CN=Domain Admins*',
            '*CN=Enterprise Admins*',
            '*CN=Schema Admins*',
            '*CN=BUILTIN*',
            '*CN=Users,DC=*',
            '*CN=Computers,DC=*'
        )

        $this.BatchSize = 100
        $this.MemoryCheckInterval = 50
        $this.EnableDetailedLogging = $false
        $this.LogLevel = 'Information'
        $this.LogFilePath = $null
        $this.EnableLogFileRotation = $true
        $this.MaxLogFileSizeMB = 10
    }

    static [ScriptConfiguration]LoadFromFile([string]$configPath) {
        if (-not (Test-Path $configPath)) {
            throw "Configuration file not found: $configPath"
        }

        try {
            $configData = Get-Content $configPath -Raw | ConvertFrom-Json
            $config = [ScriptConfiguration]::new()

            # Validation with proper error handling
            if ($configData.WellKnownSIDPatterns) {
                # Validate SID patterns
                foreach ($pattern in $configData.WellKnownSIDPatterns) {
                    try {
                        $null = [regex]::new($pattern)
                    }
                    catch {
                        throw "Invalid regex pattern in WellKnownSIDPatterns: $pattern"
                    }
                }
                $config.WellKnownSIDPatterns = $configData.WellKnownSIDPatterns
            }

            if ($configData.ProtectedSIDs) {
                # Validate SID formats
                foreach ($sid in $configData.ProtectedSIDs) {
                    if (-not ($sid -match '^S-1-\d+(-\d+)*$')) {
                        throw "Invalid SID format in ProtectedSIDs: $sid"
                    }
                }
                $config.ProtectedSIDs = $configData.ProtectedSIDs
            }

            if ($configData.BatchSize) {
                if ($configData.BatchSize -lt 1 -or $configData.BatchSize -gt 1000) {
                    throw "BatchSize must be between 1 and 1000, got: $($configData.BatchSize)"
                }
                $config.BatchSize = $configData.BatchSize
            }

            if ($configData.MemoryCheckInterval) {
                if ($configData.MemoryCheckInterval -lt 1 -or $configData.MemoryCheckInterval -gt 100) {
                    throw "MemoryCheckInterval must be between 1 and 100, got: $($configData.MemoryCheckInterval)"
                }
                $config.MemoryCheckInterval = $configData.MemoryCheckInterval
            }

            if ($null -ne $configData.EnableDetailedLogging) { $config.EnableDetailedLogging = $configData.EnableDetailedLogging }
            if ($configData.LogLevel) { $config.LogLevel = $configData.LogLevel }
            if ($configData.LogFilePath) { $config.LogFilePath = $configData.LogFilePath }
            if ($null -ne $configData.EnableLogFileRotation) { $config.EnableLogFileRotation = $configData.EnableLogFileRotation }
            if ($configData.MaxLogFileSizeMB) { $config.MaxLogFileSizeMB = $configData.MaxLogFileSizeMB }

            return $config

        } catch {
            throw "Failed to load configuration from $configPath : $($_.Exception.Message)"
        }
    }

    [bool] ValidateConfiguration() {
        try {
            Write-Verbose "Starting configuration validation"

            # Validate SID patterns with detailed error reporting
            foreach ($pattern in $this.WellKnownSIDPatterns) {
                try {
                    $null = [regex]::new($pattern)
                    Write-Verbose "Validated SID pattern: $pattern"
                } catch {
                    Write-Error "Invalid regex pattern in WellKnownSIDPatterns: $pattern - $($_.Exception.Message)"
                    return $false
                }
            }

            # Validate protected SIDs format and accessibility
            foreach ($sid in $this.ProtectedSIDs) {
                if (-not ($sid -match '^S-1-\d+(-\d+)*$')) {
                    Write-Error "Invalid protected SID format: $sid"
                    return $false
                }

                # Additional validation: Ensure it's not a malformed well-known SID
                try {
                    $null = [System.Security.Principal.SecurityIdentifier]::new($sid)
                    Write-Verbose "Validated protected SID: $sid"
                } catch {
                    Write-Error "Protected SID failed .NET validation: $sid - $($_.Exception.Message)"
                    return $false
                }
            }

            # Validate critical object patterns for proper wildcard usage
            foreach ($pattern in $this.CriticalObjectPatterns) {
                if ([string]::IsNullOrWhiteSpace($pattern)) {
                    Write-Error "Empty critical object pattern detected"
                    return $false
                }

                # Ensure patterns have reasonable structure
                if ($pattern.Length -lt 3 -or $pattern.Length -gt 500) {
                    Write-Error "Critical object pattern has invalid length: $pattern"
                    return $false
                }

                Write-Verbose "Validated critical object pattern: $pattern"
            }

            # Validate numeric ranges with business logic
            if ($this.BatchSize -lt 1 -or $this.BatchSize -gt 1000) {
                Write-Error "BatchSize out of valid range (1-1000): $($this.BatchSize)"
                return $false
            }

            if ($this.MemoryCheckInterval -lt 1 -or $this.MemoryCheckInterval -gt 1000) {
                Write-Error "MemoryCheckInterval out of valid range (1-1000): $($this.MemoryCheckInterval)"
                return $false
            }

            # Validate log level against known values
            $validLogLevels = @('Critical', 'Error', 'Warning', 'Information', 'Debug', 'Verbose')
            if ($this.LogLevel -notin $validLogLevels) {
                Write-Error "Invalid LogLevel specified: $($this.LogLevel). Valid values: $($validLogLevels -join ', ')"
                return $false
            }

            Write-Verbose "Configuration validation completed successfully"
            return $true

        } catch {
            Write-Error "Configuration validation failed: $($_.Exception.Message)"
            return $false
        }
    }
}