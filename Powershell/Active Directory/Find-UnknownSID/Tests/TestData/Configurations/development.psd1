# Test Environment Configuration - Development

@{
    # Environment Settings
    Environment = @{
        Name = 'Development'
        Description = 'Development environment for Find-UnknownSID testing'
        ContactEmail = 'dev-team@contoso.com'
        MaintenanceWindow = 'Daily 02:00-04:00 UTC'
    }

    # Active Directory Configuration
    ActiveDirectory = @{
        DomainController = 'DC01.dev.contoso.local'
        Domain = 'dev.contoso.local'
        BaseDN = 'DC=dev,DC=contoso,DC=local'
        TestOU = 'OU=Testing,OU=Development,DC=dev,DC=contoso,DC=local'
        ServiceAccount = @{
            Username = 'svc-findunknownsid-dev'
            Description = 'Service account for Find-UnknownSID development testing'
            RequiredPermissions = @(
                'Read all properties of all objects in domain'
                'Read permissions on all objects in domain'
                'Read deleted objects container'
            )
        }
        TestData = @{
            CreateTestObjects = $true
            TestUserCount = 10
            TestGroupCount = 5
            TestOUCount = 3
            OrphanedSIDCount = 8
        }
    }

    # Database Configuration  
    Database = @{
        ConnectionString = 'Server=SQL-DEV-01.dev.contoso.local;Database=FindUnknownSID_Dev;Integrated Security=true;Connection Timeout=30;'
        TestDatabase = 'FindUnknownSID_DevTest'
        BackupLocation = '\\fileserver\backups\dev\findunknownsid'
        LogRetentionDays = 7
        PerformanceLogging = $true
        Tables = @{
            AuditLog = 'dbo.AuditLog_Dev'
            SIDMapping = 'dbo.SIDMapping_Dev'
            ProcessingHistory = 'dbo.ProcessingHistory_Dev'
            PerformanceMetrics = 'dbo.PerformanceMetrics_Dev'
        }
    }

    # Logging Configuration
    Logging = @{
        Level = 'Debug'
        Path = 'C:\Logs\FindUnknownSID\Development'
        MaxFileSizeMB = 10
        MaxLogFiles = 20
        EnableVerbose = $true
        EnableDebug = $true
        Destinations = @('File', 'EventLog', 'Console')
        EventLog = @{
            LogName = 'Application'
            Source = 'FindUnknownSID-Dev'
        }
        StructuredLogging = @{
            Enabled = $true
            Format = 'JSON'
            IncludeCallStack = $true
        }
    }

    # Performance Configuration
    Performance = @{
        BatchSize = 100
        MaxConcurrentJobs = 2
        QueryTimeout = 30
        MemoryLimitMB = 512
        EnablePerformanceCounters = $true
        Thresholds = @{
            MaxExecutionTimeMinutes = 10
            MaxMemoryUsageMB = 256
            MaxTempFilesMB = 100
            WarningThresholdPercent = 75
        }
        Optimization = @{
            EnableCaching = $true
            CacheExpirationMinutes = 30
            EnableCompression = $false
            ParallelProcessing = $false
        }
    }

    # Security Configuration
    Security = @{
        RequireSecureConnection = $false
        EncryptSensitiveData = $true
        AuditAllOperations = $true
        RequireAdminApproval = $false
        Compliance = @{
            EnableSOXCompliance = $false
            EnableGDPRCompliance = $true
            DataRetentionDays = 90
            RequireDataClassification = $false
        }
        Authentication = @{
            RequireKerberos = $true
            AllowNTLM = $true
            RequireMFA = $false
        }
        Permissions = @{
            MinimumPrivilegeLevel = 'ReadOnly'
            AllowElevation = $true
            RequireJustification = $true
        }
    }

    # Testing Configuration
    Testing = @{
        EnableMockMode = $true
        MockDataPath = '.\Tests\TestData'
        SimulateErrors = $true
        TestCoverage = @{
            TargetPercent = 80
            IncludePaths = @('Public\*.ps1', 'Private\*.ps1', 'Classes\*.ps1')
            ExcludePaths = @('Tests\*', 'Build\*')
        }
        PerformanceTesting = @{
            LargeDatasetSize = 10000
            StressTestDuration = '00:05:00'
            MaxMemoryUsage = '256MB'
            ConcurrentUsers = 5
        }
        SecurityTesting = @{
            EnableVulnerabilityScans = $true
            TestMaliciousInputs = $true
            ValidateInputSanitization = $true
            TestPrivilegeEscalation = $true
        }
    }

    # Integration Configuration
    Integration = @{
        MicrosoftGraph = @{
            TenantId = '12345678-1234-1234-1234-123456789012'
            ClientId = '87654321-4321-4321-4321-210987654321'
            Environment = 'Development'
            Scopes = @('Directory.Read.All', 'User.Read.All', 'Group.Read.All')
            MockResponses = $true
        }
        SIEM = @{
            Enabled = $false
            Endpoint = 'https://siem-dev.contoso.local'
            APIKey = 'dev-api-key-placeholder'
            EventTypes = @('SIDFound', 'SIDRemoved', 'ErrorOccurred')
        }
        Monitoring = @{
            Enabled = $true
            Endpoint = 'https://monitoring-dev.contoso.local'
            MetricsInterval = '00:01:00'
            HealthCheckInterval = '00:05:00'
        }
    }

    # Email Configuration
    Email = @{
        SMTPServer = 'smtp-dev.contoso.local'
        Port = 587
        UseSSL = $true
        FromAddress = 'findunknownsid-dev@contoso.com'
        Recipients = @{
            Administrators = @('dev-admin@contoso.com')
            SecurityTeam = @('security-dev@contoso.com')
            Operations = @('ops-dev@contoso.com')
        }
        Templates = @{
            DailyReport = 'DailyReport_Dev.html'
            ErrorAlert = 'ErrorAlert_Dev.html'
            CompletionSummary = 'CompletionSummary_Dev.html'
        }
    }

    # Backup and Recovery Configuration
    BackupRecovery = @{
        BackupEnabled = $true
        BackupLocation = '\\fileserver\backups\dev\findunknownsid'
        BackupSchedule = 'Daily at 23:00'
        RetentionDays = 30
        VerifyBackups = $true
        AutomaticRestore = $false
        DisasterRecovery = @{
            RPO_Minutes = 60
            RTO_Minutes = 120
            AlternateLocation = '\\dr-fileserver\backups\dev\findunknownsid'
        }
    }

    # Feature Flags
    Features = @{
        EnableAdvancedLogging = $true
        EnablePerformanceOptimization = $true
        EnableExperimentalFeatures = $true
        EnableBetaAPI = $true
        EnableDebugMode = $true
        EnableUIEnhancements = $true
        EnableAutomaticCleanup = $false
        EnableRealTimeMonitoring = $true
    }

    # Resource Limits
    ResourceLimits = @{
        MaxProcessingTime = '01:00:00'
        MaxMemoryUsage = '1GB'
        MaxTempStorage = '500MB'
        MaxConcurrentConnections = 10
        MaxLogFileSize = '50MB'
        MaxReportSize = '10MB'
    }

    # Troubleshooting Configuration
    Troubleshooting = @{
        EnableDetailedErrorMessages = $true
        IncludeStackTrace = $true
        EnableRemoteDebugging = $true
        DiagnosticsLevel = 'Verbose'
        AutoCollectDiagnostics = $true
        DiagnosticsRetentionDays = 14
        SupportContact = 'dev-support@contoso.com'
    }
}
