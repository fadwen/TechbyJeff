# Test Environment Configuration - Production

@{
    # Environment Settings
    Environment = @{
        Name = 'Production'
        Description = 'Production environment for Find-UnknownSID'
        ContactEmail = 'prod-ops@contoso.com'
        MaintenanceWindow = 'Sunday 02:00-04:00 UTC'
        ChangeControlRequired = $true
    }

    # Active Directory Configuration
    ActiveDirectory = @{
        DomainController = 'DC01.contoso.com'
        Domain = 'contoso.com'
        BaseDN = 'DC=contoso,DC=com'
        ServiceAccount = @{
            Username = 'svc-findunknownsid-prod'
            Description = 'Service account for Find-UnknownSID production operations'
            RequiredPermissions = @(
                'Read all properties of all objects in domain'
                'Read permissions on all objects in domain'
                'Read deleted objects container'
                'Audit directory service access'
            )
            PasswordRotationDays = 30
        }
        Replication = @{
            PreferredSites = @('MainSite', 'BackupSite')
            ReplicationCheckInterval = '00:15:00'
            MaxReplicationLag = '00:05:00'
        }
    }

    # Database Configuration  
    Database = @{
        ConnectionString = 'Server=SQL-PROD-CLUSTER.contoso.com;Database=FindUnknownSID_Prod;Integrated Security=true;Connection Timeout=60;MultipleActiveResultSets=true;Encrypt=true;TrustServerCertificate=false;'
        BackupLocation = '\\prod-fileserver\backups\production\findunknownsid'
        LogRetentionDays = 365
        PerformanceLogging = $false
        HighAvailability = @{
            AlwaysOnEnabled = $true
            SecondaryReplicas = @('SQL-PROD-02.contoso.com', 'SQL-DR-01.contoso.com')
            BackupPreference = 'SecondaryOnly'
        }
        Security = @{
            EncryptionEnabled = $true
            TDEEnabled = $true
            BackupEncryption = $true
            AuditingEnabled = $true
        }
        Tables = @{
            AuditLog = 'dbo.AuditLog'
            SIDMapping = 'dbo.SIDMapping'
            ProcessingHistory = 'dbo.ProcessingHistory'
            PerformanceMetrics = 'dbo.PerformanceMetrics'
            ComplianceReports = 'dbo.ComplianceReports'
        }
    }

    # Logging Configuration
    Logging = @{
        Level = 'Information'
        Path = 'E:\Logs\FindUnknownSID\Production'
        MaxFileSizeMB = 100
        MaxLogFiles = 365
        EnableVerbose = $false
        EnableDebug = $false
        Destinations = @('File', 'EventLog', 'SIEM')
        EventLog = @{
            LogName = 'Application'
            Source = 'FindUnknownSID'
        }
        StructuredLogging = @{
            Enabled = $true
            Format = 'JSON'
            IncludeCallStack = $false
            SensitiveDataRedaction = $true
        }
        SIEM = @{
            Enabled = $true
            Endpoint = 'https://siem.contoso.com/api/events'
            APIKey = 'prod-siem-api-key'
            SecurityEvents = $true
        }
    }

    # Performance Configuration
    Performance = @{
        BatchSize = 1000
        MaxConcurrentJobs = 8
        QueryTimeout = 120
        MemoryLimitMB = 4096
        EnablePerformanceCounters = $true
        Thresholds = @{
            MaxExecutionTimeMinutes = 120
            MaxMemoryUsageMB = 2048
            MaxTempFilesMB = 1024
            WarningThresholdPercent = 80
            CriticalThresholdPercent = 95
        }
        Optimization = @{
            EnableCaching = $true
            CacheExpirationMinutes = 60
            EnableCompression = $true
            ParallelProcessing = $true
            LoadBalancing = $true
        }
        Monitoring = @{
            RealTimeMetrics = $true
            AlertThresholds = @{
                CPUPercent = 80
                MemoryPercent = 85
                DiskPercent = 90
                ResponseTimeMs = 5000
            }
        }
    }

    # Security Configuration
    Security = @{
        RequireSecureConnection = $true
        EncryptSensitiveData = $true
        AuditAllOperations = $true
        RequireAdminApproval = $true
        Compliance = @{
            EnableSOXCompliance = $true
            EnableGDPRCompliance = $true
            EnableHIPAACompliance = $false
            DataRetentionDays = 2555  # 7 years for SOX
            RequireDataClassification = $true
        }
        Authentication = @{
            RequireKerberos = $true
            AllowNTLM = $false
            RequireMFA = $true
            SessionTimeout = 480  # 8 hours
        }
        Permissions = @{
            MinimumPrivilegeLevel = 'ReadOnly'
            AllowElevation = $false
            RequireJustification = $true
            RequireApprovalWorkflow = $true
        }
        Encryption = @{
            DataAtRest = $true
            DataInTransit = $true
            KeyManagement = 'Azure Key Vault'
            RotationPolicy = 'Annual'
        }
    }

    # Testing Configuration
    Testing = @{
        EnableMockMode = $false
        ProductionValidation = $true
        PreDeploymentTests = $true
        TestCoverage = @{
            RequiredPercent = 95
            CriticalPath = 100
        }
        PerformanceTesting = @{
            BaselineRequired = $true
            RegressionThreshold = 10  # percent
            LoadTestingRequired = $true
        }
        SecurityTesting = @{
            PenetrationTestingRequired = $true
            VulnerabilityScansRequired = $true
            ComplianceValidation = $true
        }
    }

    # Integration Configuration
    Integration = @{
        MicrosoftGraph = @{
            TenantId = '11111111-1111-1111-1111-111111111111'
            ClientId = '22222222-2222-2222-2222-222222222222'
            Environment = 'Production'
            Scopes = @('Directory.Read.All', 'User.Read.All', 'Group.Read.All', 'AuditLog.Read.All')
            RateLimiting = @{
                MaxRequestsPerMinute = 1000
                BackoffStrategy = 'Exponential'
            }
        }
        SIEM = @{
            Enabled = $true
            Endpoint = 'https://siem.contoso.com/api/events'
            APIKey = 'prod-siem-api-key'
            EventTypes = @('SIDFound', 'SIDRemoved', 'ErrorOccurred', 'SecurityViolation', 'ComplianceEvent')
            RealTime = $true
        }
        Monitoring = @{
            Enabled = $true
            Endpoint = 'https://monitoring.contoso.com/api/metrics'
            MetricsInterval = '00:05:00'
            HealthCheckInterval = '00:01:00'
            AlertingEnabled = $true
        }
        ServiceNow = @{
            Enabled = $true
            Endpoint = 'https://contoso.service-now.com/api'
            AutoCreateIncidents = $true
            IncidentCategory = 'Security'
            Priority = 'P2'
        }
    }

    # Email Configuration
    Email = @{
        SMTPServer = 'smtp.contoso.com'
        Port = 587
        UseSSL = $true
        FromAddress = 'findunknownsid@contoso.com'
        Recipients = @{
            Administrators = @('admin@contoso.com', 'backup-admin@contoso.com')
            SecurityTeam = @('security@contoso.com', 'soc@contoso.com')
            Operations = @('operations@contoso.com')
            Management = @('it-management@contoso.com')
            Compliance = @('compliance@contoso.com')
        }
        Templates = @{
            DailyReport = 'DailyReport_Prod.html'
            ErrorAlert = 'ErrorAlert_Prod.html'
            CompletionSummary = 'CompletionSummary_Prod.html'
            SecurityAlert = 'SecurityAlert_Prod.html'
            ComplianceReport = 'ComplianceReport_Prod.html'
        }
        Scheduling = @{
            DailyReports = '06:00'
            WeeklyReports = 'Monday 08:00'
            MonthlyReports = '1st day 09:00'
            QuarterlyReports = '1st day of quarter 10:00'
        }
    }

    # Backup and Recovery Configuration
    BackupRecovery = @{
        BackupEnabled = $true
        BackupLocation = '\\prod-fileserver\backups\production\findunknownsid'
        BackupSchedule = 'Daily at 01:00'
        RetentionDays = 2555  # 7 years
        VerifyBackups = $true
        AutomaticRestore = $false
        OffSiteBackup = $true
        DisasterRecovery = @{
            RPO_Minutes = 15
            RTO_Minutes = 60
            AlternateLocation = '\\dr-fileserver\backups\production\findunknownsid'
            GeoReplication = $true
            TestingSchedule = 'Quarterly'
        }
        Encryption = @{
            BackupEncryption = $true
            KeyManagement = 'Enterprise'
            VerifyEncryption = $true
        }
    }

    # Feature Flags
    Features = @{
        EnableAdvancedLogging = $true
        EnablePerformanceOptimization = $true
        EnableExperimentalFeatures = $false
        EnableBetaAPI = $false
        EnableDebugMode = $false
        EnableUIEnhancements = $true
        EnableAutomaticCleanup = $true
        EnableRealTimeMonitoring = $true
        EnablePredictiveAnalytics = $true
        EnableAIAssistance = $false
    }

    # Resource Limits
    ResourceLimits = @{
        MaxProcessingTime = '04:00:00'
        MaxMemoryUsage = '8GB'
        MaxTempStorage = '10GB'
        MaxConcurrentConnections = 50
        MaxLogFileSize = '500MB'
        MaxReportSize = '100MB'
        MaxBatchSize = 10000
        MaxRetryAttempts = 3
    }

    # Troubleshooting Configuration
    Troubleshooting = @{
        EnableDetailedErrorMessages = $false
        IncludeStackTrace = $false
        EnableRemoteDebugging = $false
        DiagnosticsLevel = 'Error'
        AutoCollectDiagnostics = $true
        DiagnosticsRetentionDays = 90
        SupportContact = 'prod-support@contoso.com'
        EscalationProcedure = @{
            Level1 = 'operations@contoso.com'
            Level2 = 'senior-admin@contoso.com'
            Level3 = 'engineering@contoso.com'
        }
    }

    # Business Continuity
    BusinessContinuity = @{
        MaintenanceWindows = @{
            Regular = 'Sunday 02:00-04:00 UTC'
            Emergency = 'As needed with approval'
            Notification = '72 hours advance notice'
        }
        ChangeManagement = @{
            RequiredApprovals = @('Technical Lead', 'Security Team', 'Operations Manager')
            TestingRequired = $true
            RollbackPlan = $true
            DocumentationRequired = $true
        }
        ServiceLevelAgreements = @{
            Availability = '99.9%'
            ResponseTime = '30 seconds'
            ErrorRate = '<0.1%'
            DataIntegrity = '100%'
        }
    }

    # Compliance and Governance
    Compliance = @{
        Frameworks = @('SOX', 'GDPR', 'ISO27001', 'PCI-DSS')
        AuditSchedule = 'Annual'
        DataClassification = @{
            PublicData = 'Green'
            InternalData = 'Yellow'
            ConfidentialData = 'Orange'
            RestrictedData = 'Red'
        }
        RetentionPolicies = @{
            OperationalLogs = '365 days'
            SecurityLogs = '7 years'
            AuditTrails = '7 years'
            BackupData = '7 years'
        }
    }
}
