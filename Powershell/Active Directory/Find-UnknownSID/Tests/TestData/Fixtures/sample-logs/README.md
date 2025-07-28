# Sample Log Files for Testing Log Analysis and Processing
# 
# This directory contains various log file formats and scenarios for testing
# log parsing, analysis, and troubleshooting features in the Find-UnknownSID module.

Log File Inventory:
==================

1. **find-unknownsid-success.log**
   - Successful execution log
   - Contains normal operation entries
   - Used for positive testing scenarios

2. **find-unknownsid-errors.log**
   - Error and exception log
   - Contains various error scenarios
   - Used for error handling validation

3. **find-unknownsid-performance.log**
   - Performance metrics and timing data
   - Contains execution time measurements
   - Used for performance analysis testing

4. **security-events.log**
   - Security-related log entries
   - Contains audit trail and security events
   - Used for security compliance testing

5. **debug-verbose.log**
   - Detailed debug information
   - Contains verbose execution details
   - Used for troubleshooting scenario testing

6. **corrupted-log.log**
   - Intentionally corrupted log file
   - Contains malformed entries
   - Used for error handling and resilience testing

7. **large-log-100mb.log**
   - Large log file for performance testing
   - Contains 100MB+ of log data
   - Used for memory and performance testing

8. **json-structured.log**
   - JSON-formatted structured logs
   - Contains machine-readable log entries
   - Used for structured logging testing

9. **csv-format.log**
   - CSV-formatted log entries
   - Contains comma-separated log data
   - Used for data export and analysis testing

10. **empty.log**
    - Empty log file
    - Used for edge case testing
    - Validates empty file handling

Log Entry Formats:
=================

**Standard Format:**
```
[2024-01-15 10:30:00.123] [INFO] [Find-UnknownSID] Starting SID analysis process
[2024-01-15 10:30:01.456] [DEBUG] [SecurityDescriptor] Processing object: CN=TestObject,OU=Test,DC=contoso,DC=com
[2024-01-15 10:30:02.789] [WARN] [SIDResolver] Unknown SID found: S-1-5-21-9999999999-9999999999-9999999999-1001
[2024-01-15 10:30:03.012] [ERROR] [DatabaseConnection] Failed to connect to database: Connection timeout
```

**JSON Structured Format:**
```json
{"timestamp":"2024-01-15T10:30:00.123Z","level":"INFO","component":"Find-UnknownSID","message":"Starting SID analysis process","correlationId":"12345678-1234-1234-1234-123456789012"}
{"timestamp":"2024-01-15T10:30:01.456Z","level":"DEBUG","component":"SecurityDescriptor","message":"Processing object","objectPath":"CN=TestObject,OU=Test,DC=contoso,DC=com","correlationId":"12345678-1234-1234-1234-123456789012"}
{"timestamp":"2024-01-15T10:30:02.789Z","level":"WARN","component":"SIDResolver","message":"Unknown SID found","sid":"S-1-5-21-9999999999-9999999999-9999999999-1001","riskLevel":"High","correlationId":"12345678-1234-1234-1234-123456789012"}
```

**CSV Format:**
```csv
Timestamp,Level,Component,Message,Details,CorrelationId
2024-01-15 10:30:00.123,INFO,Find-UnknownSID,Starting SID analysis process,,12345678-1234-1234-1234-123456789012
2024-01-15 10:30:01.456,DEBUG,SecurityDescriptor,Processing object,CN=TestObject,12345678-1234-1234-1234-123456789012
2024-01-15 10:30:02.789,WARN,SIDResolver,Unknown SID found,S-1-5-21-9999999999-9999999999-9999999999-1001,12345678-1234-1234-1234-123456789012
```

Test Scenarios:
===============

**Log Parsing Testing:**
- Parse different log formats (text, JSON, CSV)
- Extract timestamp and severity information
- Handle malformed log entries
- Process large log files efficiently

**Error Analysis Testing:**
- Identify error patterns in logs
- Extract stack traces and error details
- Correlate errors across log entries
- Generate error reports from log data

**Performance Analysis Testing:**
- Extract timing information from logs
- Calculate performance metrics
- Identify performance bottlenecks
- Generate performance reports

**Security Event Testing:**
- Parse security-related log entries
- Identify security violations
- Track user activity from logs
- Generate security reports

**Correlation Testing:**
- Track operations across log entries using correlation IDs
- Build execution timelines from logs
- Identify related log entries
- Trace request flows through system

Sample Log Entries:
==================

**Successful Operation:**
```
[2024-01-15 10:30:00.123] [INFO] [Find-UnknownSID] Starting SID analysis for domain: contoso.com
[2024-01-15 10:30:00.234] [INFO] [ADConnector] Connected to domain controller: DC01.contoso.com
[2024-01-15 10:30:00.345] [INFO] [SecurityScanner] Beginning security descriptor scan
[2024-01-15 10:30:01.456] [DEBUG] [SecurityDescriptor] Processing: CN=Users,DC=contoso,DC=com
[2024-01-15 10:30:01.567] [DEBUG] [SIDAnalyzer] Analyzing 15 SIDs in security descriptor
[2024-01-15 10:30:01.678] [INFO] [SIDResolver] 12 SIDs resolved successfully
[2024-01-15 10:30:01.789] [WARN] [SIDResolver] 3 unknown SIDs found
[2024-01-15 10:30:01.890] [INFO] [Find-UnknownSID] Analysis completed successfully. Found 3 orphaned SIDs.
```

**Error Scenario:**
```
[2024-01-15 10:30:00.123] [INFO] [Find-UnknownSID] Starting SID analysis for domain: contoso.com
[2024-01-15 10:30:00.234] [ERROR] [ADConnector] Failed to connect to domain controller: DC01.contoso.com
[2024-01-15 10:30:00.235] [ERROR] [ADConnector] Error details: The server is not operational
[2024-01-15 10:30:00.236] [INFO] [ADConnector] Attempting connection to backup DC: DC02.contoso.com
[2024-01-15 10:30:00.345] [INFO] [ADConnector] Connected to backup domain controller: DC02.contoso.com
[2024-01-15 10:30:00.456] [INFO] [SecurityScanner] Beginning security descriptor scan with backup DC
```

**Performance Data:**
```
[2024-01-15 10:30:00.123] [PERF] [SecurityScanner] Scan started - Objects to process: 15,432
[2024-01-15 10:30:15.456] [PERF] [SecurityScanner] Progress: 5,000 objects processed (32.4%) - Elapsed: 00:00:15.333
[2024-01-15 10:30:30.789] [PERF] [SecurityScanner] Progress: 10,000 objects processed (64.8%) - Elapsed: 00:00:30.666
[2024-01-15 10:30:45.012] [PERF] [SecurityScanner] Progress: 15,000 objects processed (97.2%) - Elapsed: 00:00:44.889
[2024-01-15 10:30:47.234] [PERF] [SecurityScanner] Scan completed - Total objects: 15,432 - Total time: 00:00:47.111
[2024-01-15 10:30:47.235] [PERF] [SIDAnalyzer] SID analysis started - Total SIDs: 48,567
[2024-01-15 10:30:52.345] [PERF] [SIDAnalyzer] SID analysis completed - Resolved: 47,123 - Unknown: 1,444 - Time: 00:00:05.110
```

Usage in Tests:
==============

```powershell
# Parse log file
$logFile = Join-Path $TestDataPath "Fixtures\sample-logs\find-unknownsid-success.log"
$logEntries = Get-LogEntries -FilePath $logFile

# Analyze errors
$errorLog = Join-Path $TestDataPath "Fixtures\sample-logs\find-unknownsid-errors.log"
$errors = Get-ErrorsFromLog -FilePath $errorLog

# Performance analysis
$perfLog = Join-Path $TestDataPath "Fixtures\sample-logs\find-unknownsid-performance.log"
$metrics = Get-PerformanceMetrics -FilePath $perfLog

# Test log parsing with corrupted data
$corruptedLog = Join-Path $TestDataPath "Fixtures\sample-logs\corrupted-log.log"
{ Parse-LogFile -FilePath $corruptedLog } | Should -Not -Throw
```

Generation Commands:
===================

```powershell
# Generate sample success log
@"
[2024-01-15 10:30:00.123] [INFO] [Find-UnknownSID] Starting SID analysis process
[2024-01-15 10:30:01.456] [DEBUG] [SecurityDescriptor] Processing object: CN=TestObject,OU=Test,DC=contoso,DC=com
[2024-01-15 10:30:02.789] [INFO] [Find-UnknownSID] Analysis completed successfully
"@ | Out-File "find-unknownsid-success.log"

# Generate large log file
1..100000 | ForEach-Object {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [INFO] [TestComponent] Log entry $_ with sample content"
} | Out-File "large-log-100mb.log"

# Generate corrupted log
@"
[2024-01-15 10:30:00.123] [INFO] [Find-UnknownSID] Starting SID analysis process
[2024-01-15 10:30:01.456] [INVALID LOG ENTRY WITH MISSING TIMESTAMP
[2024-01-15 10:30:02.789] [INFO] [Find-UnknownSID] Analysis completed successfully
CORRUPTED ENTRY WITHOUT PROPER FORMAT
"@ | Out-File "corrupted-log.log"
```

Maintenance Notes:
=================
- Regenerate large log files if they become corrupted
- Update sample log entries to reflect current log format
- Add new log scenarios as testing requirements evolve
- Clean up generated log files to manage disk space
- Keep log formats consistent with actual application output
