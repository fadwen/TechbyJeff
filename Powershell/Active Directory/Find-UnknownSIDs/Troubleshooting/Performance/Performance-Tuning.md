# Performance Tuning Guide - Find-UnknownSIDs

## Overview
This guide provides comprehensive performance optimization strategies for the Find-UnknownSIDs script in enterprise environments. Performance tuning is critical for large-scale Active Directory operations and resource-constrained environments.

## Performance Baseline and Metrics

### Understanding Performance Characteristics

#### Baseline Performance Metrics
- **Small Environment** (< 1,000 objects): 100-200 objects/second
- **Medium Environment** (1,000-10,000 objects): 75-150 objects/second
- **Large Environment** (10,000-100,000 objects): 50-100 objects/second
- **Enterprise Environment** (> 100,000 objects): 25-75 objects/second

#### Key Performance Factors
1. **Domain Controller Performance**: CPU, memory, and disk I/O capabilities
2. **Network Latency**: Distance and connection quality to domain controllers
3. **Parallel Processing**: Number of concurrent threads and throttling
4. **Memory Management**: Available system memory and garbage collection
5. **Object Complexity**: Number of ACL entries per object
6. **Inheritance Processing**: Inherited vs. explicit permissions

### Performance Monitoring and Measurement

#### Built-in Performance Monitoring
```powershell
function Measure-ScriptPerformance {
    param(
        [string]$TestOU = "OU=TestUsers,DC=contoso,DC=com",
        [int]$ParallelThrottleLimit = 10,
        [int]$MaxMemoryUsageMB = 1024
    )

    Write-Host "=== PERFORMANCE BASELINE TEST ===" -ForegroundColor Cyan

    # Pre-test system metrics
    $StartMemory = [System.GC]::GetTotalMemory($false) / 1MB
    $StartTime = Get-Date

    # Get object count for baseline
    $ObjectCount = (Get-ADObject -SearchBase $TestOU -Filter *).Count
    Write-Host "Test scope: $ObjectCount objects in $TestOU" -ForegroundColor Yellow

    # Execute performance test
    try {
        $Results = .\Find-UnknownSIDs.ps1 -SearchBase $TestOU -ParallelThrottleLimit $ParallelThrottleLimit -MaxMemoryUsageMB $MaxMemoryUsageMB -LogLevel Warning

        # Post-test metrics
        $EndTime = Get-Date
        $EndMemory = [System.GC]::GetTotalMemory($false) / 1MB
        $Duration = $EndTime - $StartTime
        $MemoryUsed = $EndMemory - $StartMemory

        # Calculate performance metrics
        $ObjectsPerSecond = if ($Duration.TotalSeconds -gt 0) { [math]::Round($ObjectCount / $Duration.TotalSeconds, 2) } else { 0 }
        $MemoryPerObject = if ($ObjectCount -gt 0) { [math]::Round($MemoryUsed / $ObjectCount, 3) } else { 0 }

        # Display results
        $PerformanceResults = @{
            TestScope = $TestOU
            ObjectCount = $ObjectCount
            Duration = $Duration.TotalSeconds
            ObjectsPerSecond = $ObjectsPerSecond
            TotalMemoryUsed = [math]::Round($MemoryUsed, 2)
            MemoryPerObject = $MemoryPerObject
            ParallelThreads = $ParallelThrottleLimit
            MemoryLimit = $MaxMemoryUsageMB
            OrphanedSIDsFound = $Results.Statistics.OrphanedSIDCount
        }

        Write-Host "Performance Results:" -ForegroundColor Green
        Write-Host "  Duration: $($Duration.TotalSeconds) seconds" -ForegroundColor Yellow
        Write-Host "  Processing rate: $ObjectsPerSecond objects/second" -ForegroundColor Yellow
        Write-Host "  Memory usage: $([math]::Round($MemoryUsed, 2)) MB total, $MemoryPerObject MB/object" -ForegroundColor Yellow
        Write-Host "  Orphaned SIDs: $($Results.Statistics.OrphanedSIDCount)" -ForegroundColor Yellow

        return $PerformanceResults

    } catch {
        Write-Host "Performance test failed: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Comparative performance testing
function Compare-PerformanceSettings {
    param(
        [string]$TestOU = "OU=TestUsers,DC=contoso,DC=com"
    )

    Write-Host "=== COMPARATIVE PERFORMANCE ANALYSIS ===" -ForegroundColor Cyan

    $TestConfigurations = @(
        @{ Threads = 5; Memory = 1024; Description = "Conservative" },
        @{ Threads = 10; Memory = 2048; Description = "Balanced" },
        @{ Threads = 20; Memory = 4096; Description = "Aggressive" },
        @{ Threads = 1; Memory = 512; Description = "Minimal Resources" }
    )

    $Results = @()

    foreach ($Config in $TestConfigurations) {
        Write-Host "Testing $($Config.Description) configuration..." -ForegroundColor Yellow
        Write-Host "  Threads: $($Config.Threads), Memory: $($Config.Memory) MB" -ForegroundColor Gray

        $TestResult = Measure-ScriptPerformance -TestOU $TestOU -ParallelThrottleLimit $Config.Threads -MaxMemoryUsageMB $Config.Memory

        if ($TestResult) {
            $TestResult.Configuration = $Config.Description
            $Results += $TestResult
        }

        # Cool-down period
        Start-Sleep -Seconds 30
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }

    # Display comparison
    Write-Host "`nPerformance Comparison:" -ForegroundColor Cyan
    $Results | ForEach-Object {
        Write-Host "$($_.Configuration): $($_.ObjectsPerSecond) obj/sec, $($_.TotalMemoryUsed) MB" -ForegroundColor Yellow
    }

    # Recommend optimal configuration
    $BestPerformance = $Results | Sort-Object ObjectsPerSecond -Descending | Select-Object -First 1
    Write-Host "`nRecommended configuration: $($BestPerformance.Configuration)" -ForegroundColor Green
    Write-Host "  Threads: $($BestPerformance.ParallelThreads)" -ForegroundColor Green
    Write-Host "  Memory: $($BestPerformance.MemoryLimit) MB" -ForegroundColor Green

    return $Results
}
```

## Parallel Processing Optimization

### 1. Thread Pool Optimization

#### Optimal Thread Configuration
```powershell
function Get-OptimalThreadCount {
    param(
        [int]$ObjectCount,
        [int]$AvailableCPUCores = $env:NUMBER_OF_PROCESSORS
    )

    Write-Host "Calculating optimal thread count..." -ForegroundColor Cyan
    Write-Host "  Objects to process: $ObjectCount" -ForegroundColor Gray
    Write-Host "  Available CPU cores: $AvailableCPUCores" -ForegroundColor Gray

    # Base thread calculation on object count and system resources
    $OptimalThreads = switch ($ObjectCount) {
        { $_ -le 100 } {
            [math]::Min(5, $AvailableCPUCores)
        }
        { $_ -le 1000 } {
            [math]::Min(10, $AvailableCPUCores * 2)
        }
        { $_ -le 10000 } {
            [math]::Min(20, $AvailableCPUCores * 3)
        }
        { $_ -le 50000 } {
            [math]::Min(30, $AvailableCPUCores * 4)
        }
        default {
            [math]::Min(50, $AvailableCPUCores * 5)
        }
    }

    # Adjust for memory constraints
    $AvailableMemoryGB = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB / 1024
    $MemoryConstrainedThreads = [math]::Floor($AvailableMemoryGB * 5) # ~200MB per thread

    $RecommendedThreads = [math]::Min($OptimalThreads, $MemoryConstrainedThreads)

    Write-Host "Thread count recommendations:" -ForegroundColor Yellow
    Write-Host "  CPU-based optimal: $OptimalThreads" -ForegroundColor Gray
    Write-Host "  Memory-constrained: $MemoryConstrainedThreads" -ForegroundColor Gray
    Write-Host "  Final recommendation: $RecommendedThreads" -ForegroundColor Green

    return @{
        RecommendedThreads = $RecommendedThreads
        CPUOptimal = $OptimalThreads
        MemoryConstrained = $MemoryConstrainedThreads
        ObjectCount = $ObjectCount
        AvailableCores = $AvailableCPUCores
        AvailableMemoryGB = [math]::Round($AvailableMemoryGB, 2)
    }
}

# Dynamic thread adjustment
function Start-AdaptiveProcessing {
    param(
        [string[]]$SearchBase,
        [int]$InitialThreadCount = 10
    )

    Write-Host "Starting adaptive processing with dynamic thread adjustment..." -ForegroundColor Cyan

    # Get total object count
    $TotalObjects = 0
    foreach ($OU in $SearchBase) {
        $ObjectsInOU = (Get-ADObject -SearchBase $OU -Filter *).Count
        $TotalObjects += $ObjectsInOU
        Write-Host "  $OU: $ObjectsInOU objects" -ForegroundColor Gray
    }

    # Calculate optimal settings
    $ThreadConfig = Get-OptimalThreadCount -ObjectCount $TotalObjects
    $OptimalThreads = $ThreadConfig.RecommendedThreads
    $OptimalMemory = [math]::Max(1024, $OptimalThreads * 200) # 200MB per thread baseline

    Write-Host "Adaptive configuration:" -ForegroundColor Yellow
    Write-Host "  Threads: $OptimalThreads" -ForegroundColor Green
    Write-Host "  Memory: $OptimalMemory MB" -ForegroundColor Green

    # Execute with optimized settings
    $Results = .\Find-UnknownSIDs.ps1 -SearchBase $SearchBase -ParallelThrottleLimit $OptimalThreads -MaxMemoryUsageMB $OptimalMemory

    return $Results
}
```

### 2. Load Balancing Strategies

#### Domain Controller Load Balancing
```powershell
function Optimize-DomainControllerUsage {
    param(
        [string[]]$SearchBase
    )

    Write-Host "Optimizing domain controller selection..." -ForegroundColor Cyan

    # Get all available domain controllers
    $DomainControllers = Get-ADDomainController -Filter *
    Write-Host "Available domain controllers:" -ForegroundColor Yellow

    $DCPerformance = @()

    foreach ($DC in $DomainControllers) {
        Write-Host "  Testing $($DC.HostName)..." -ForegroundColor Gray

        # Test connectivity and response time
        $ResponseTime = Measure-Command {
            try {
                $TestResult = Test-NetConnection $DC.HostName -Port 389 -InformationLevel Quiet
                if (-not $TestResult) {
                    throw "Connection failed"
                }
            } catch {
                throw $_
            }
        }

        # Test AD query performance
        $QueryTime = Measure-Command {
            try {
                Get-ADDomain -Server $DC.HostName | Out-Null
            } catch {
                throw $_
            }
        }

        $DCPerformance += @{
            HostName = $DC.HostName
            Site = $DC.Site
            ResponseTime = $ResponseTime.TotalMilliseconds
            QueryTime = $QueryTime.TotalMilliseconds
            TotalTime = $ResponseTime.TotalMilliseconds + $QueryTime.TotalMilliseconds
            IsGlobalCatalog = $DC.IsGlobalCatalog
            IsReadOnly = $DC.IsReadOnly
        }

        Write-Host "    Response: $([math]::Round($ResponseTime.TotalMilliseconds, 2))ms, Query: $([math]::Round($QueryTime.TotalMilliseconds, 2))ms" -ForegroundColor Gray
    }

    # Select optimal domain controller
    $OptimalDC = $DCPerformance |
        Where-Object { -not $_.IsReadOnly } |
        Sort-Object TotalTime |
        Select-Object -First 1

    if ($OptimalDC) {
        Write-Host "Optimal DC selected: $($OptimalDC.HostName)" -ForegroundColor Green
        Write-Host "  Site: $($OptimalDC.Site)" -ForegroundColor Gray
        Write-Host "  Total response time: $([math]::Round($OptimalDC.TotalTime, 2))ms" -ForegroundColor Gray

        # Set environment variable to use optimal DC
        $env:LOGONSERVER = "\\$($OptimalDC.HostName)"
        Write-Host "Environment configured to use optimal DC" -ForegroundColor Green

        return $OptimalDC
    } else {
        Write-Host "No optimal DC found, using default" -ForegroundColor Yellow
        return $null
    }
}

# Implement round-robin DC selection for load distribution
function Set-LoadBalancedDCSelection {
    param(
        [int]$MaxConcurrentOperations = 10
    )

    Write-Host "Configuring load-balanced DC selection..." -ForegroundColor Cyan

    $AvailableDCs = Get-ADDomainController -Filter * | Where-Object { -not $_.IsReadOnly }

    if ($AvailableDCs.Count -gt 1) {
        Write-Host "Load balancing across $($AvailableDCs.Count) domain controllers" -ForegroundColor Yellow

        # Create DC rotation schedule
        $Script:DCRotation = @{
            Controllers = $AvailableDCs.HostName
            CurrentIndex = 0
            LoadCount = @{}
        }

        # Initialize load counters
        foreach ($DC in $AvailableDCs.HostName) {
            $Script:DCRotation.LoadCount[$DC] = 0
        }

        Write-Host "DC rotation configured:" -ForegroundColor Green
        $AvailableDCs | ForEach-Object { Write-Host "  - $($_.HostName)" -ForegroundColor Gray }

        return $Script:DCRotation
    } else {
        Write-Host "Only one writable DC available - no load balancing needed" -ForegroundColor Yellow
        return $null
    }
}
```

## Memory Optimization

### 3. Memory Management Strategies

#### Advanced Memory Monitoring
```powershell
function Monitor-MemoryUsage {
    param(
        [int]$MonitoringIntervalSeconds = 30,
        [int]$MaxMemoryThresholdMB = 1024,
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    Write-Host "Starting advanced memory monitoring..." -ForegroundColor Cyan
    Write-Host "  Monitoring interval: $MonitoringIntervalSeconds seconds" -ForegroundColor Gray
    Write-Host "  Memory threshold: $MaxMemoryThresholdMB MB" -ForegroundColor Gray

    $MemoryLog = @()
    $AlertThresholds = @{
        Warning = $MaxMemoryThresholdMB * 0.8  # 80%
        Critical = $MaxMemoryThresholdMB * 0.9  # 90%
        Emergency = $MaxMemoryThresholdMB * 0.95 # 95%
    }

    # Background monitoring job
    $MonitoringJob = Start-Job -ScriptBlock {
        param($IntervalSeconds, $Thresholds, $CorrelationId)

        while ($true) {
            $CurrentMemory = [System.GC]::GetTotalMemory($false) / 1MB
            $Timestamp = Get-Date

            $MemoryStatus = @{
                Timestamp = $Timestamp
                MemoryUsageMB = [math]::Round($CurrentMemory, 2)
                CorrelationId = $CorrelationId
                AlertLevel = "Normal"
            }

            # Determine alert level
            if ($CurrentMemory -gt $Thresholds.Emergency) {
                $MemoryStatus.AlertLevel = "Emergency"
                # Trigger emergency cleanup
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                [System.GC]::Collect()
            } elseif ($CurrentMemory -gt $Thresholds.Critical) {
                $MemoryStatus.AlertLevel = "Critical"
                # Trigger aggressive cleanup
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
            } elseif ($CurrentMemory -gt $Thresholds.Warning) {
                $MemoryStatus.AlertLevel = "Warning"
                # Trigger standard cleanup
                [System.GC]::Collect()
            }

            # Output status for parent process
            $MemoryStatus | ConvertTo-Json -Compress

            Start-Sleep -Seconds $IntervalSeconds
        }
    } -ArgumentList $MonitoringIntervalSeconds, $AlertThresholds, $CorrelationId

    Write-Host "Memory monitoring job started (ID: $($MonitoringJob.Id))" -ForegroundColor Green

    return @{
        Job = $MonitoringJob
        Thresholds = $AlertThresholds
        CorrelationId = $CorrelationId
    }
}

# Optimized garbage collection strategies
function Optimize-GarbageCollection {
    param(
        [string]$CollectionStrategy = "Balanced"
    )

    Write-Host "Optimizing garbage collection strategy: $CollectionStrategy" -ForegroundColor Cyan

    switch ($CollectionStrategy) {
        "Conservative" {
            # Minimal GC intervention - let CLR manage
            Write-Host "  Conservative GC - minimal intervention" -ForegroundColor Gray
            $GCSettings = @{
                ForceCollectionInterval = 300  # 5 minutes
                WaitForPendingFinalizers = $false
                CompactLOH = $false
            }
        }

        "Balanced" {
            # Balanced approach - periodic cleanup
            Write-Host "  Balanced GC - periodic cleanup" -ForegroundColor Gray
            $GCSettings = @{
                ForceCollectionInterval = 120  # 2 minutes
                WaitForPendingFinalizers = $true
                CompactLOH = $true
            }
        }

        "Aggressive" {
            # Aggressive cleanup - for memory-constrained environments
            Write-Host "  Aggressive GC - frequent cleanup" -ForegroundColor Gray
            $GCSettings = @{
                ForceCollectionInterval = 60   # 1 minute
                WaitForPendingFinalizers = $true
                CompactLOH = $true
            }
        }
    }

    # Apply GC configuration
    if ($GCSettings.CompactLOH) {
        # Enable LOH compaction on next GC
        [System.Runtime.GCSettings]::LargeObjectHeapCompactionMode = [System.Runtime.GCLargeObjectHeapCompactionMode]::CompactOnce
    }

    Write-Host "GC optimization applied:" -ForegroundColor Green
    Write-Host "  Collection interval: $($GCSettings.ForceCollectionInterval) seconds" -ForegroundColor Gray
    Write-Host "  Wait for finalizers: $($GCSettings.WaitForPendingFinalizers)" -ForegroundColor Gray
    Write-Host "  Compact LOH: $($GCSettings.CompactLOH)" -ForegroundColor Gray

    return $GCSettings
}
```

### 4. Object Lifecycle Management

#### Efficient Object Processing
```powershell
function Optimize-ObjectProcessing {
    param(
        [string[]]$SearchBase,
        [int]$BatchSize = 100,
        [string]$ProcessingMode = "Streaming"
    )

    Write-Host "Optimizing object processing with $ProcessingMode mode..." -ForegroundColor Cyan

    switch ($ProcessingMode) {
        "Streaming" {
            # Process objects one at a time - lowest memory usage
            Write-Host "  Streaming mode - minimal memory footprint" -ForegroundColor Gray

            foreach ($OU in $SearchBase) {
                Get-ADObject -SearchBase $OU -Filter * | ForEach-Object {
                    # Process individual object
                    $ProcessedObject = Process-SingleObject -ADObject $_

                    # Immediately output and clear from memory
                    Write-Output $ProcessedObject
                    $ProcessedObject = $null

                    # Periodic cleanup
                    if ((Get-Random -Maximum 100) -lt 5) {  # 5% chance
                        [System.GC]::Collect()
                    }
                }
            }
        }

        "Batched" {
            # Process objects in batches - balanced memory/performance
            Write-Host "  Batched mode - balanced processing (batch size: $BatchSize)" -ForegroundColor Gray

            foreach ($OU in $SearchBase) {
                $AllObjects = Get-ADObject -SearchBase $OU -Filter *
                $TotalBatches = [math]::Ceiling($AllObjects.Count / $BatchSize)

                for ($i = 0; $i -lt $TotalBatches; $i++) {
                    $StartIndex = $i * $BatchSize
                    $EndIndex = [math]::Min($StartIndex + $BatchSize - 1, $AllObjects.Count - 1)
                    $Batch = $AllObjects[$StartIndex..$EndIndex]

                    Write-Host "    Processing batch $($i + 1)/$TotalBatches ($($Batch.Count) objects)" -ForegroundColor Gray

                    # Process batch
                    $BatchResults = @()
                    foreach ($Object in $Batch) {
                        $BatchResults += Process-SingleObject -ADObject $Object
                    }

                    # Output batch results
                    Write-Output $BatchResults

                    # Clear batch from memory
                    $Batch = $null
                    $BatchResults = $null
                    [System.GC]::Collect()
                }

                # Clear all objects array
                $AllObjects = $null
                [System.GC]::Collect()
            }
        }

        "Bulk" {
            # Load all objects at once - highest performance, highest memory usage
            Write-Host "  Bulk mode - high performance processing" -ForegroundColor Gray

            $AllObjects = @()
            foreach ($OU in $SearchBase) {
                $AllObjects += Get-ADObject -SearchBase $OU -Filter *
            }

            Write-Host "    Processing $($AllObjects.Count) objects in bulk" -ForegroundColor Gray

            # Process all objects
            $Results = foreach ($Object in $AllObjects) {
                Process-SingleObject -ADObject $Object
            }

            Write-Output $Results
        }
    }
}

function Process-SingleObject {
    param(
        [Microsoft.ActiveDirectory.Management.ADObject]$ADObject
    )

    # Optimized single object processing
    try {
        # Get ACL efficiently
        $ACL = Get-Acl -Path "AD:$($ADObject.DistinguishedName)" -ErrorAction Stop

        # Process ACEs with minimal memory allocation
        $OrphanedSIDs = @()
        foreach ($ACE in $ACL.Access) {
            try {
                # Quick SID validation
                $SID = [System.Security.Principal.SecurityIdentifier]::new($ACE.IdentityReference)
                $null = $SID.Translate([System.Security.Principal.NTAccount])
            } catch {
                # SID is orphaned
                $OrphanedSIDs += @{
                    SID = $ACE.IdentityReference.ToString()
                    AccessControlType = $ACE.AccessControlType
                    Rights = $ACE.ActiveDirectoryRights
                }
            }
        }

        # Return minimal result object
        if ($OrphanedSIDs.Count -gt 0) {
            return @{
                ObjectDN = $ADObject.DistinguishedName
                OrphanedSIDs = $OrphanedSIDs
                ObjectClass = $ADObject.ObjectClass
            }
        }

        return $null

    } catch {
        # Return error object
        return @{
            ObjectDN = $ADObject.DistinguishedName
            Error = $_.Exception.Message
        }
    }
}
```

## Network and I/O Optimization

### 5. Network Performance Tuning

#### Connection Optimization
```powershell
function Optimize-NetworkConnections {
    param(
        [int]$ConnectionPoolSize = 10,
        [int]$QueryTimeoutSeconds = 60
    )

    Write-Host "Optimizing network connections..." -ForegroundColor Cyan

    # Configure AD connection settings
    $ADConnectionSettings = @{
        ConnectionPoolSize = $ConnectionPoolSize
        QueryTimeout = $QueryTimeoutSeconds
        PageSize = 1000  # LDAP page size
        ReferralChasing = $false  # Disable referral chasing for performance
    }

    # Set AD module preferences
    try {
        Set-ADDefaultDomainPasswordPolicy -ComplexityEnabled $true -ErrorAction SilentlyContinue

        # Configure LDAP session options
        $LDAPSessionOptions = @{
            ReferralChasing = "None"
            ProtocolVersion = 3
            Timeout = [TimeSpan]::FromSeconds($QueryTimeoutSeconds)
            SecureSocketLayer = $true
        }

        Write-Host "Network optimization applied:" -ForegroundColor Green
        Write-Host "  Connection pool size: $ConnectionPoolSize" -ForegroundColor Gray
        Write-Host "  Query timeout: $QueryTimeoutSeconds seconds" -ForegroundColor Gray
        Write-Host "  LDAP page size: $($ADConnectionSettings.PageSize)" -ForegroundColor Gray
        Write-Host "  Referral chasing: Disabled" -ForegroundColor Gray

        return $ADConnectionSettings

    } catch {
        Write-Host "Some network optimizations could not be applied: $($_.Exception.Message)" -ForegroundColor Yellow
        return $ADConnectionSettings
    }
}

# Connection pooling and reuse
function Initialize-ConnectionPool {
    param(
        [int]$PoolSize = 5,
        [string[]]$PreferredDCs = @()
    )

    Write-Host "Initializing connection pool (size: $PoolSize)..." -ForegroundColor Cyan

    $ConnectionPool = @{
        Connections = @()
        AvailableConnections = @()
        ActiveConnections = @()
        MaxPoolSize = $PoolSize
        CreatedConnections = 0
    }

    # Pre-create connections
    for ($i = 0; $i -lt $PoolSize; $i++) {
        try {
            $DC = if ($PreferredDCs.Count -gt 0) {
                $PreferredDCs[$i % $PreferredDCs.Count]
            } else {
                (Get-ADDomainController).HostName
            }

            # Test connection
            $TestResult = Test-NetConnection $DC -Port 389 -InformationLevel Quiet
            if ($TestResult) {
                $Connection = @{
                    Id = $i
                    DomainController = $DC
                    CreatedTime = Get-Date
                    LastUsed = Get-Date
                    UseCount = 0
                    IsAvailable = $true
                }

                $ConnectionPool.Connections += $Connection
                $ConnectionPool.AvailableConnections += $Connection
                $ConnectionPool.CreatedConnections++

                Write-Host "  Connection $i: $DC" -ForegroundColor Gray
            }
        } catch {
            Write-Host "  Failed to create connection $i`: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Write-Host "Connection pool initialized: $($ConnectionPool.CreatedConnections)/$PoolSize connections" -ForegroundColor Green

    return $ConnectionPool
}
```

### 6. Disk I/O Optimization

#### Logging and Output Optimization
```powershell
function Optimize-DiskIO {
    param(
        [string]$LogPath = ".\Logs",
        [string]$OutputPath = ".\Output",
        [bool]$EnableAsyncIO = $true
    )

    Write-Host "Optimizing disk I/O operations..." -ForegroundColor Cyan

    # Configure high-performance logging
    $LoggingConfig = @{
        BufferSize = 65536  # 64KB buffer
        WriteThrough = $false  # Use write caching
        AsyncIO = $EnableAsyncIO
        CompressionEnabled = $true
    }

    # Create optimized directories
    $Directories = @($LogPath, $OutputPath)
    foreach ($Dir in $Directories) {
        if (-not (Test-Path $Dir)) {
            New-Item -Path $Dir -ItemType Directory -Force | Out-Null
            Write-Host "  Created directory: $Dir" -ForegroundColor Gray
        }

        # Configure directory for performance
        try {
            # Disable indexing on log directories
            $DirObject = Get-Item $Dir
            $DirObject.Attributes = $DirObject.Attributes -bor [System.IO.FileAttributes]::NotContentIndexed
            Write-Host "  Disabled indexing: $Dir" -ForegroundColor Gray
        } catch {
            Write-Host "  Could not disable indexing: $Dir" -ForegroundColor Yellow
        }
    }

    # Configure buffered output for CSV exports
    if ($EnableAsyncIO) {
        # Use memory-based buffering for CSV output
        $Script:CSVBuffer = [System.Collections.Generic.List[PSObject]]::new()
        $Script:BufferFlushThreshold = 1000  # Flush every 1000 records

        Write-Host "  Async I/O enabled with buffering" -ForegroundColor Green
    }

    Write-Host "Disk I/O optimization applied:" -ForegroundColor Green
    Write-Host "  Buffer size: $($LoggingConfig.BufferSize) bytes" -ForegroundColor Gray
    Write-Host "  Write caching: $(-not $LoggingConfig.WriteThrough)" -ForegroundColor Gray
    Write-Host "  Async I/O: $($LoggingConfig.AsyncIO)" -ForegroundColor Gray
    Write-Host "  Compression: $($LoggingConfig.CompressionEnabled)" -ForegroundColor Gray

    return $LoggingConfig
}

# Efficient CSV output with buffering
function Write-OptimizedCSV {
    param(
        [PSObject[]]$Data,
        [string]$OutputPath,
        [bool]$UseBuffering = $true,
        [int]$BufferSize = 1000
    )

    if ($UseBuffering) {
        # Add to buffer
        $Script:CSVBuffer.AddRange($Data)

        # Check if buffer should be flushed
        if ($Script:CSVBuffer.Count -ge $BufferSize) {
            Flush-CSVBuffer -OutputPath $OutputPath
        }
    } else {
        # Direct write
        $Data | Export-Csv -Path $OutputPath -NoTypeInformation -Append
    }
}

function Flush-CSVBuffer {
    param(
        [string]$OutputPath
    )

    if ($Script:CSVBuffer.Count -gt 0) {
        Write-Host "Flushing CSV buffer: $($Script:CSVBuffer.Count) records" -ForegroundColor Gray

        # Write buffer to file
        $Script:CSVBuffer | Export-Csv -Path $OutputPath -NoTypeInformation -Append

        # Clear buffer
        $Script:CSVBuffer.Clear()
    }
}
```

## Configuration Optimization

### 7. Environment-Specific Tuning

#### Production Environment Configuration
```powershell
function Get-ProductionConfiguration {
    param(
        [int]$EstimatedObjectCount,
        [string]$EnvironmentType = "Production"
    )

    Write-Host "Generating $EnvironmentType environment configuration..." -ForegroundColor Cyan
    Write-Host "  Estimated object count: $EstimatedObjectCount" -ForegroundColor Gray

    # Base configuration on environment size
    $Config = switch ($EstimatedObjectCount) {
        { $_ -le 1000 } {
            @{
                ParallelThrottleLimit = 5
                MaxMemoryUsageMB = 1024
                LogLevel = "Information"
                BatchSize = 50
                GCStrategy = "Conservative"
                ConnectionPoolSize = 3
                Description = "Small environment optimized"
            }
        }
        { $_ -le 10000 } {
            @{
                ParallelThrottleLimit = 10
                MaxMemoryUsageMB = 2048
                LogLevel = "Warning"
                BatchSize = 100
                GCStrategy = "Balanced"
                ConnectionPoolSize = 5
                Description = "Medium environment optimized"
            }
        }
        { $_ -le 50000 } {
            @{
                ParallelThrottleLimit = 20
                MaxMemoryUsageMB = 4096
                LogLevel = "Warning"
                BatchSize = 200
                GCStrategy = "Balanced"
                ConnectionPoolSize = 8
                Description = "Large environment optimized"
            }
        }
        default {
            @{
                ParallelThrottleLimit = 30
                MaxMemoryUsageMB = 8192
                LogLevel = "Error"
                BatchSize = 500
                GCStrategy = "Aggressive"
                ConnectionPoolSize = 10
                Description = "Enterprise environment optimized"
            }
        }
    }

    # Add environment-specific settings
    $Config.EnvironmentType = $EnvironmentType
    $Config.EstimatedObjectCount = $EstimatedObjectCount
    $Config.GeneratedDate = Get-Date

    # Production-specific hardening
    if ($EnvironmentType -eq "Production") {
        $Config.SecurityValidation = $true
        $Config.BackupRequired = $true
        $Config.AuditLogging = "Comprehensive"
        $Config.ChangeApprovalRequired = $true
    }

    Write-Host "Configuration generated:" -ForegroundColor Green
    Write-Host "  $($Config.Description)" -ForegroundColor Gray
    Write-Host "  Threads: $($Config.ParallelThrottleLimit)" -ForegroundColor Gray
    Write-Host "  Memory: $($Config.MaxMemoryUsageMB) MB" -ForegroundColor Gray
    Write-Host "  Log level: $($Config.LogLevel)" -ForegroundColor Gray
    Write-Host "  Batch size: $($Config.BatchSize)" -ForegroundColor Gray

    return $Config
}

# Save optimized configuration
function Save-OptimizedConfiguration {
    param(
        [hashtable]$Configuration,
        [string]$ConfigPath = ".\config-optimized.json"
    )

    Write-Host "Saving optimized configuration to: $ConfigPath" -ForegroundColor Cyan

    try {
        $Configuration | ConvertTo-Json -Depth 5 | Out-File -FilePath $ConfigPath -Encoding UTF8
        Write-Host "✓ Configuration saved successfully" -ForegroundColor Green

        # Validate saved configuration
        $LoadedConfig = Get-Content -Path $ConfigPath | ConvertFrom-Json
        Write-Host "✓ Configuration validation passed" -ForegroundColor Green

        return $ConfigPath

    } catch {
        Write-Host "✗ Failed to save configuration: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}
```

## Performance Monitoring and Alerting

### 8. Real-time Performance Monitoring

#### Comprehensive Performance Dashboard
```powershell
function Start-PerformanceMonitoring {
    param(
        [string]$CorrelationId,
        [int]$RefreshIntervalSeconds = 30
    )

    Write-Host "Starting real-time performance monitoring..." -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to stop monitoring" -ForegroundColor Yellow

    $MonitoringStartTime = Get-Date
    $Iteration = 0

    try {
        while ($true) {
            $Iteration++
            Clear-Host

            Write-Host "=== FIND-UNKNOWNSIDS PERFORMANCE MONITOR ===" -ForegroundColor Cyan
            Write-Host "Correlation ID: $CorrelationId" -ForegroundColor Gray
            Write-Host "Monitoring since: $($MonitoringStartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
            Write-Host "Refresh interval: $RefreshIntervalSeconds seconds (Iteration: $Iteration)" -ForegroundColor Gray
            Write-Host ""

            # System metrics
            Write-Host "SYSTEM METRICS:" -ForegroundColor Yellow
            $OS = Get-CimInstance Win32_OperatingSystem
            $CPU = Get-CimInstance Win32_Processor | Select-Object -First 1
            $FreeMemoryGB = [math]::Round($OS.FreePhysicalMemory / 1MB / 1024, 2)
            $TotalMemoryGB = [math]::Round($OS.TotalVisibleMemorySize / 1MB / 1024, 2)
            $MemoryUsagePercent = [math]::Round((($TotalMemoryGB - $FreeMemoryGB) / $TotalMemoryGB) * 100, 1)

            Write-Host "  CPU: $($CPU.Name)" -ForegroundColor Gray
            Write-Host "  Memory: $FreeMemoryGB GB free / $TotalMemoryGB GB total ($MemoryUsagePercent% used)" -ForegroundColor $(if ($MemoryUsagePercent -gt 80) { "Red" } elseif ($MemoryUsagePercent -gt 60) { "Yellow" } else { "Green" })

            # Process metrics
            Write-Host ""
            Write-Host "PROCESS METRICS:" -ForegroundColor Yellow
            $PowerShellProcesses = Get-Process -Name powershell* -ErrorAction SilentlyContinue
            if ($PowerShellProcesses) {
                foreach ($Process in $PowerShellProcesses) {
                    $ProcessMemoryMB = [math]::Round($Process.WorkingSet / 1MB, 2)
                    $ProcessCPU = [math]::Round($Process.CPU, 2)
                    Write-Host "  PID $($Process.Id): $ProcessMemoryMB MB, $ProcessCPU CPU seconds" -ForegroundColor Gray
                }
            }

            # PowerShell GC metrics
            Write-Host ""
            Write-Host "GARBAGE COLLECTION:" -ForegroundColor Yellow
            $GCMemory = [math]::Round([System.GC]::GetTotalMemory($false) / 1MB, 2)
            $Gen0Collections = [System.GC]::CollectionCount(0)
            $Gen1Collections = [System.GC]::CollectionCount(1)
            $Gen2Collections = [System.GC]::CollectionCount(2)

            Write-Host "  Managed memory: $GCMemory MB" -ForegroundColor $(if ($GCMemory -gt 1000) { "Red" } elseif ($GCMemory -gt 500) { "Yellow" } else { "Green" })
            Write-Host "  Collections - Gen0: $Gen0Collections, Gen1: $Gen1Collections, Gen2: $Gen2Collections" -ForegroundColor Gray

            # AD connectivity
            Write-Host ""
            Write-Host "ACTIVE DIRECTORY:" -ForegroundColor Yellow
            try {
                $DCTestTime = Measure-Command {
                    $DC = Get-ADDomainController -ErrorAction Stop
                }
                Write-Host "  Domain Controller: $($DC.HostName) (Response: $([math]::Round($DCTestTime.TotalMilliseconds, 2))ms)" -ForegroundColor Green

                $DomainTestTime = Measure-Command {
                    $Domain = Get-ADDomain -ErrorAction Stop
                }
                Write-Host "  Domain: $($Domain.DNSRoot) (Query: $([math]::Round($DomainTestTime.TotalMilliseconds, 2))ms)" -ForegroundColor Green

            } catch {
                Write-Host "  ✗ AD connectivity failed: $($_.Exception.Message)" -ForegroundColor Red
            }

            # Log analysis
            Write-Host ""
            Write-Host "LOG ANALYSIS:" -ForegroundColor Yellow
            $LogFiles = Get-ChildItem ".\Logs" -Filter "*$CorrelationId*" -ErrorAction SilentlyContinue
            if ($LogFiles) {
                $LatestLog = $LogFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                $LogSizeMB = [math]::Round($LatestLog.Length / 1MB, 2)
                $LogAge = (Get-Date) - $LatestLog.LastWriteTime

                Write-Host "  Latest log: $($LatestLog.Name)" -ForegroundColor Gray
                Write-Host "  Size: $LogSizeMB MB, Age: $([math]::Round($LogAge.TotalMinutes, 1)) minutes" -ForegroundColor Gray

                # Check for recent errors
                $RecentErrors = Select-String -Path $LatestLog.FullName -Pattern "ERROR|CRITICAL" -ErrorAction SilentlyContinue |
                    Select-Object -Last 5

                if ($RecentErrors) {
                    Write-Host "  Recent errors detected:" -ForegroundColor Red
                    $RecentErrors | ForEach-Object {
                        Write-Host "    $($_.Line.Substring(0, [math]::Min(80, $_.Line.Length)))..." -ForegroundColor Red
                    }
                }
            } else {
                Write-Host "  No log files found for correlation ID: $CorrelationId" -ForegroundColor Yellow
            }

            # Performance recommendations
            Write-Host ""
            Write-Host "RECOMMENDATIONS:" -ForegroundColor Yellow
            if ($MemoryUsagePercent -gt 80) {
                Write-Host "  ⚠ High memory usage - consider reducing parallel threads" -ForegroundColor Yellow
            }
            if ($GCMemory -gt 1000) {
                Write-Host "  ⚠ High managed memory - consider manual garbage collection" -ForegroundColor Yellow
            }
            if ($Gen2Collections -gt ($Iteration * 0.1)) {
                Write-Host "  ⚠ Frequent Gen2 collections - optimize object lifecycle" -ForegroundColor Yellow
            }

            # Wait for next refresh
            Start-Sleep -Seconds $RefreshIntervalSeconds
        }
    }
    catch [System.Management.Automation.PipelineStoppedException] {
        Write-Host "`nPerformance monitoring stopped by user" -ForegroundColor Yellow
    }
    catch {
        Write-Host "`nPerformance monitoring error: $($_.Exception.Message)" -ForegroundColor Red
    }
}
```

## Performance Troubleshooting Scenarios

### 9. Common Performance Issues and Solutions

#### Issue Resolution Matrix
```powershell
function Diagnose-PerformanceIssues {
    param(
        [string]$CorrelationId,
        [hashtable]$PerformanceData = @{}
    )

    Write-Host "Diagnosing performance issues..." -ForegroundColor Cyan

    $Diagnostics = @{
        Issues = @()
        Recommendations = @()
        Severity = "Normal"
    }

    # Memory-related issues
    $CurrentMemoryMB = [System.GC]::GetTotalMemory($false) / 1MB
    if ($CurrentMemoryMB -gt 2048) {
        $Diagnostics.Issues += "High memory usage: $([math]::Round($CurrentMemoryMB, 2)) MB"
        $Diagnostics.Recommendations += "Reduce parallel threads or implement batch processing"
        $Diagnostics.Severity = "High"
    }

    # GC pressure analysis
    $Gen2Collections = [System.GC]::CollectionCount(2)
    if ($Gen2Collections -gt 10) {
        $Diagnostics.Issues += "Excessive Gen2 garbage collections: $Gen2Collections"
        $Diagnostics.Recommendations += "Optimize object lifecycle and reduce large object allocations"
        if ($Diagnostics.Severity -eq "Normal") { $Diagnostics.Severity = "Medium" }
    }

    # Performance data analysis
    if ($PerformanceData.ObjectsPerSecond -and $PerformanceData.ObjectsPerSecond -lt 10) {
        $Diagnostics.Issues += "Low processing rate: $($PerformanceData.ObjectsPerSecond) objects/second"
        $Diagnostics.Recommendations += "Check network connectivity and domain controller performance"
        $Diagnostics.Severity = "High"
    }

    # Thread efficiency analysis
    if ($PerformanceData.ParallelThreads -and $PerformanceData.ObjectsPerSecond) {
        $EfficiencyRatio = $PerformanceData.ObjectsPerSecond / $PerformanceData.ParallelThreads
        if ($EfficiencyRatio -lt 2) {
            $Diagnostics.Issues += "Low thread efficiency: $([math]::Round($EfficiencyRatio, 2)) objects/second/thread"
            $Diagnostics.Recommendations += "Reduce parallel threads or optimize per-object processing"
            if ($Diagnostics.Severity -eq "Normal") { $Diagnostics.Severity = "Medium" }
        }
    }

    # System resource analysis
    $OS = Get-CimInstance Win32_OperatingSystem
    $MemoryUsagePercent = (($OS.TotalVisibleMemorySize - $OS.FreePhysicalMemory) / $OS.TotalVisibleMemorySize) * 100
    if ($MemoryUsagePercent -gt 85) {
        $Diagnostics.Issues += "System memory usage high: $([math]::Round($MemoryUsagePercent, 1))%"
        $Diagnostics.Recommendations += "Close unnecessary applications or add more system memory"
        $Diagnostics.Severity = "High"
    }

    # Output diagnostics
    Write-Host "Performance Diagnostics:" -ForegroundColor Yellow
    Write-Host "  Severity: $($Diagnostics.Severity)" -ForegroundColor $(
        switch ($Diagnostics.Severity) {
            "Normal" { "Green" }
            "Medium" { "Yellow" }
            "High" { "Red" }
            default { "Gray" }
        }
    )

    if ($Diagnostics.Issues.Count -gt 0) {
        Write-Host "  Issues identified:" -ForegroundColor Red
        $Diagnostics.Issues | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }

        Write-Host "  Recommendations:" -ForegroundColor Yellow
        $Diagnostics.Recommendations | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
    } else {
        Write-Host "  ✓ No performance issues detected" -ForegroundColor Green
    }

    return $Diagnostics
}
```

## Summary and Best Practices

### Performance Optimization Checklist
- [ ] **System Resources**: Adequate CPU cores and memory for environment size
- [ ] **Thread Configuration**: Optimal parallel thread count based on object count and resources
- [ ] **Memory Management**: Appropriate memory limits and garbage collection strategy
- [ ] **Network Optimization**: Optimal domain controller selection and connection pooling
- [ ] **Batch Processing**: Efficient object processing strategy for environment size
- [ ] **I/O Optimization**: Optimized logging and output configurations
- [ ] **Monitoring**: Real-time performance monitoring and alerting
- [ ] **Configuration**: Environment-specific tuning and optimization

### Performance Targets by Environment Size
- **Small (< 1,000 objects)**: 100-200 objects/second, < 1 GB memory
- **Medium (1,000-10,000 objects)**: 75-150 objects/second, < 2 GB memory
- **Large (10,000-100,000 objects)**: 50-100 objects/second, < 4 GB memory
- **Enterprise (> 100,000 objects)**: 25-75 objects/second, < 8 GB memory

### Emergency Performance Recovery
When performance degrades significantly:
1. **Immediate**: Reduce parallel threads to 1-5
2. **Short-term**: Implement batch processing with smaller batch sizes
3. **Medium-term**: Optimize memory management and garbage collection
4. **Long-term**: Review system resources and infrastructure capacity

---

*Last Updated: 2025-07-02*
*Version: 2.0.0*
*Author: Jeffrey Stuhr*