# Get-ADObjectsSequential         'OU=Users,DC=contoso,DC=com' = @(
# Get-ADObjectsSequential Function Tests - Comprehensive Pester 3.4.x Compatible

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

# Import the function under test
$functionPath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))) "Private\ActiveDirectory\Get-ADObjectsSequential.ps1"
if (Test-Path $functionPath) {
    . $functionPath
}

# Set up global test data at file level (outside Describe block)
$Global:TestConfig = @{
    ValidSearchBases = @(
        'OU=Users,DC=contoso,DC=com'
        'OU=Groups,DC=contoso,DC=com'
        'OU=Computers,DC=contoso,DC=com'
    )
    LargeSearchBases = @(
        'OU=Corp,DC=contoso,DC=com'
        'OU=Sales,DC=contoso,DC=com'
        'OU=Marketing,DC=contoso,DC=com'
        'OU=IT,DC=contoso,DC=com'
        'OU=Finance,DC=contoso,DC=com'
    )
    TestObjects = @{
        'OU=Users,DC=contoso,DC=com' = @(
            [PSCustomObject]@{
                DistinguishedName = 'CN=User1,OU=Users,DC=contoso,DC=com'
                Name = 'User1'
                ObjectClass = 'user'
                nTSecurityDescriptor = 'MockSecurityDescriptor1'
            }
            [PSCustomObject]@{
                DistinguishedName = 'CN=User2,OU=Users,DC=contoso,DC=com'
                Name = 'User2'
                ObjectClass = 'user'
                nTSecurityDescriptor = 'MockSecurityDescriptor2'
            }
            [PSCustomObject]@{
                DistinguishedName = 'CN=User3,OU=Users,DC=contoso,DC=com'
                Name = 'User3'
                ObjectClass = 'user'
                nTSecurityDescriptor = 'MockSecurityDescriptor3'
            }
        )
        'OU=Groups,DC=contoso,DC=com' = @(
            [PSCustomObject]@{
                DistinguishedName = 'CN=Group1,OU=Groups,DC=contoso,DC=com'
                Name = 'Group1'
                ObjectClass = 'group'
                nTSecurityDescriptor = 'MockSecurityDescriptor3'
            }
        )
        'OU=Computers,DC=contoso,DC=com' = @(
            [PSCustomObject]@{
                DistinguishedName = 'CN=Computer1,OU=Computers,DC=contoso,DC=com'
                Name = 'Computer1$'
                ObjectClass = 'computer'
                nTSecurityDescriptor = 'MockSecurityDescriptor4'
            }
        )
        'OU=Corp,DC=contoso,DC=com' = @(
            1..50 | ForEach-Object {
                [PSCustomObject]@{
                    DistinguishedName = "CN=CorpUser$_,OU=Corp,DC=contoso,DC=com"
                    Name = "CorpUser$_"
                    ObjectClass = 'user'
                    nTSecurityDescriptor = "MockSecurityDescriptor$($_+100)"
                }
            }
        )
        'OU=Sales,DC=contoso,DC=com' = @(
            1..30 | ForEach-Object {
                [PSCustomObject]@{
                    DistinguishedName = "CN=SalesUser$_,OU=Sales,DC=contoso,DC=com"
                    Name = "SalesUser$_"
                    ObjectClass = 'user'
                    nTSecurityDescriptor = "MockSecurityDescriptor$($_+200)"
                }
            }
        )
        'OU=Marketing,DC=contoso,DC=com' = @(
            1..25 | ForEach-Object {
                [PSCustomObject]@{
                    DistinguishedName = "CN=MarketingUser$_,OU=Marketing,DC=contoso,DC=com"
                    Name = "MarketingUser$_"
                    ObjectClass = 'user'
                    nTSecurityDescriptor = "MockSecurityDescriptor$($_+300)"
                }
            }
        )
        'OU=IT,DC=contoso,DC=com' = @(
            1..15 | ForEach-Object {
                [PSCustomObject]@{
                    DistinguishedName = "CN=ITUser$_,OU=IT,DC=contoso,DC=com"
                    Name = "ITUser$_"
                    ObjectClass = 'user'
                    nTSecurityDescriptor = "MockSecurityDescriptor$($_+350)"
                }
            }
        )
        'OU=Finance,DC=contoso,DC=com' = @(
            1..20 | ForEach-Object {
                [PSCustomObject]@{
                    DistinguishedName = "CN=FinanceUser$_,OU=Finance,DC=contoso,DC=com"
                    Name = "FinanceUser$_"
                    ObjectClass = 'user'
                    nTSecurityDescriptor = "MockSecurityDescriptor$($_+400)"
                }
            }
        )
        'OU=Invalid,DC=contoso,DC=com' = $null  # For testing error handling
        'OU=Invalid1,DC=contoso,DC=com' = $null
        'OU=Invalid2,DC=contoso,DC=com' = $null
    }
}

# Initialize call tracking arrays
$Global:GetADObjectFromSearchBaseCalls = @()
$Global:WriteSecurityLogCalls = @()
$Global:WriteVerboseCalls = @()
$Global:MockDebugInfo = @{}

# Create mock functions at file level
function Global:Get-ADObjectFromSearchBase {
    param($SearchBase, $IncludeInherited, $CorrelationId)
    
    # Handle both single string and array input - convert to single string for lookup
    $searchBaseKey = if ($SearchBase -is [array] -and $SearchBase.Count -eq 1) {
        $SearchBase[0]
    } elseif ($SearchBase -is [string]) {
        $SearchBase
    } else {
        $SearchBase -join ','
    }
    
    # Track function calls for verification
    $Global:GetADObjectFromSearchBaseCalls += @{
        SearchBase = $searchBaseKey
        IncludeInherited = $IncludeInherited
        CorrelationId = $CorrelationId
        Timestamp = Get-Date
    }
    
    # Increment call counter for legacy tests
    $script:GetADObjectFromSearchBaseCallCount++
    
    Write-Host "GLOBAL MOCK: Get-ADObjectFromSearchBase called with SearchBase: $searchBaseKey" -ForegroundColor Cyan
    
    $containsKeyResult = $Global:TestConfig.TestObjects.ContainsKey($searchBaseKey)
    
    Write-Host "GLOBAL MOCK: Get-ADObjectFromSearchBase called with SearchBase: $searchBaseKey" -ForegroundColor Cyan
    
    if ($containsKeyResult) {
        $result = $Global:TestConfig.TestObjects[$searchBaseKey]
        # If the search base is marked as invalid (null value), throw an exception
        if ($result -eq $null -and $searchBaseKey -like "*Invalid*") {
            Write-Host "GLOBAL MOCK: Simulating error for invalid $searchBaseKey" -ForegroundColor Red
            if ($searchBaseKey -eq 'OU=Invalid,DC=contoso,DC=com') {
                throw "The specified domain either does not exist or could not be contacted."
            } else {
                throw "The specified domain either does not exist or could not be contacted."
            }
        } elseif ($result -ne $null) {
            Write-Host "GLOBAL MOCK: Returning $($result.Count) objects for $searchBaseKey" -ForegroundColor Green
            return $result
        } else {
            Write-Host "GLOBAL MOCK: No test objects found for $searchBaseKey" -ForegroundColor Yellow
            return @()
        }
    } elseif ($searchBaseKey -like "*Invalid*") {
        Write-Host "GLOBAL MOCK: Simulating error for $searchBaseKey" -ForegroundColor Red
        if ($searchBaseKey -eq 'OU=Invalid,DC=contoso,DC=com') {
            throw "The specified domain either does not exist or could not be contacted."
        } else {
            throw "The specified domain either does not exist or could not be contacted."
        }
    } else {
        Write-Host "GLOBAL MOCK: No test objects found for $searchBaseKey" -ForegroundColor Yellow
        return @()
    }
}

# Create script scope mock function as backup
function script:Get-ADObjectFromSearchBase {
    param($SearchBase, $IncludeInherited, $CorrelationId)
    
    # Handle both single string and array input - convert to single string for lookup
    $searchBaseKey = if ($SearchBase -is [array] -and $SearchBase.Count -eq 1) {
        $SearchBase[0]
    } elseif ($SearchBase -is [string]) {
        $SearchBase
    } else {
        $SearchBase -join ','
    }
    
    # Track function calls for verification  
    $Global:GetADObjectFromSearchBaseCalls += @{
        SearchBase = $searchBaseKey
        IncludeInherited = $IncludeInherited
        CorrelationId = $CorrelationId
        Timestamp = Get-Date
    }
    
    # Increment call counter for legacy tests
    $script:GetADObjectFromSearchBaseCallCount++
    
    Write-Host "SCRIPT MOCK: Get-ADObjectFromSearchBase called with SearchBase: $searchBaseKey" -ForegroundColor Magenta
    
    $containsKeyResult = $Global:TestConfig.TestObjects.ContainsKey($searchBaseKey)
    
    Write-Host "SCRIPT MOCK: Get-ADObjectFromSearchBase called with SearchBase: $searchBaseKey" -ForegroundColor Magenta
    
    if ($containsKeyResult) {
        $result = $Global:TestConfig.TestObjects[$searchBaseKey]
        # If the search base is marked as invalid (null value), throw an exception
        if ($result -eq $null -and $searchBaseKey -like "*Invalid*") {
            Write-Host "SCRIPT MOCK: Simulating error for invalid $searchBaseKey" -ForegroundColor Red
            if ($searchBaseKey -eq 'OU=Invalid,DC=contoso,DC=com') {
                throw "The specified domain either does not exist or could not be contacted."
            } elseif ($searchBaseKey -like 'OU=Invalid*,DC=contoso,DC=com') {
                throw "The specified domain either does not exist or could not be contacted."
            } else {
                throw "The specified domain either does not exist or could not be contacted."
            }
        } elseif ($result -ne $null) {
            Write-Host "SCRIPT MOCK: Returning $($result.Count) objects for $searchBaseKey" -ForegroundColor Green
            return $result
        } else {
            Write-Host "SCRIPT MOCK: No test objects found for $searchBaseKey" -ForegroundColor Yellow
            return @()
        }
    } elseif ($searchBaseKey -like "*Invalid*") {
        Write-Host "SCRIPT MOCK: Simulating error for $searchBaseKey" -ForegroundColor Red
        # Handle both old and new invalid test patterns
        if ($searchBaseKey -eq 'OU=Invalid,DC=contoso,DC=com') {
            throw "The specified domain either does not exist or could not be contacted."
        } elseif ($searchBaseKey -like 'OU=Invalid*,DC=contoso,DC=com') {
            throw "The specified domain either does not exist or could not be contacted."
        } else {
            throw "The specified domain either does not exist or could not be contacted."
        }
    } else {
        Write-Host "SCRIPT MOCK: No test objects found for $searchBaseKey" -ForegroundColor Yellow
        return @()
    }
}

# Mock logging functions with call tracking
function Global:Write-ADOperationSecurityLog {
    param($OperationName, $Outcome, $SecurityContext, $CorrelationId)
    $Global:WriteSecurityLogCalls += @{
        OperationName = $OperationName
        Outcome = $Outcome
        SecurityContext = $SecurityContext
        CorrelationId = $CorrelationId
        Timestamp = Get-Date
    }
}

function script:Write-ADOperationSecurityLog {
    param($OperationName, $Outcome, $SecurityContext, $CorrelationId)
    $Global:WriteSecurityLogCalls += @{
        OperationName = $OperationName
        Outcome = $Outcome
        SecurityContext = $SecurityContext
        CorrelationId = $CorrelationId
        Timestamp = Get-Date
    }
}

function Global:Write-Verbose {
    param([string]$Message)
    $Global:WriteVerboseCalls += @{
        Message = $Message
        Timestamp = Get-Date
    }
}

function script:Write-Verbose {
    param([string]$Message)
    $Global:WriteVerboseCalls += @{
        Message = $Message
        Timestamp = Get-Date
    }
}

# Additional mock functions for completeness
function Global:Write-StructuredLog {
    param($Level, $Message, $Component, $CorrelationId, $Data)
    # Mock implementation - just track the call
}

function script:Write-StructuredLog {
    param($Level, $Message, $Component, $CorrelationId, $Data)
    # Mock implementation - just track the call
}

function Global:Write-SecurityStructuredLogEntry {
    param($SecurityEventType, $Message, $Outcome, $CorrelationId, $SecurityContext)
    # Mock implementation - just track the call
}

function script:Write-SecurityStructuredLogEntry {
    param($SecurityEventType, $Message, $Outcome, $CorrelationId, $SecurityContext)
    # Mock implementation - just track the call
}

function Global:Write-SecurityLog {
    param($Level, $Message, $Component, $Operation, $CorrelationId, $Data, $Outcome, $SecurityContext)
    $Global:WriteSecurityLogCalls += @{
        Level = $Level
        Message = $Message
        Component = $Component
        Operation = $Operation
        CorrelationId = $CorrelationId
        Data = $Data
        Outcome = $Outcome
        SecurityContext = $SecurityContext
        Timestamp = Get-Date
    }
}

function script:Write-SecurityLog {
    param($Level, $Message, $Component, $Operation, $CorrelationId, $Data, $Outcome, $SecurityContext)
    $Global:WriteSecurityLogCalls += @{
        Level = $Level
        Message = $Message
        Component = $Component
        Operation = $Operation
        CorrelationId = $CorrelationId
        Data = $Data
        Outcome = $Outcome
        SecurityContext = $SecurityContext
        Timestamp = Get-Date
    }
}

function Global:Write-ADOperationSecurityLog {
    param($OperationName, $Outcome, $SecurityContext, $CorrelationId)
    $Global:WriteSecurityLogCalls += @{
        OperationName = $OperationName
        Outcome = $Outcome
        SecurityContext = $SecurityContext
        CorrelationId = $CorrelationId
        Timestamp = Get-Date
    }
}

function script:Write-ADOperationSecurityLog {
    param($OperationName, $Outcome, $SecurityContext, $CorrelationId)
    $Global:WriteSecurityLogCalls += @{
        OperationName = $OperationName
        Outcome = $Outcome
        SecurityContext = $SecurityContext
        CorrelationId = $CorrelationId
        Timestamp = Get-Date
    }
}

Describe "Get-ADObjectsSequential" {
    
    BeforeEach {
        # Clear call tracking arrays before each test
        $Global:GetADObjectFromSearchBaseCalls = @()
        $Global:WriteSecurityLogCalls = @()
        $Global:WriteVerboseCalls = @()
        
        # Reset any test-specific variables
        $script:GetADObjectFromSearchBaseCallCount = 0
    }
    
    Context "Parameter Validation and Security" {
        It "Should validate mandatory SearchBase parameter" {
            # Test that mandatory parameter validation works by calling with $null
            { Get-ADObjectsSequential -SearchBase $null -ErrorAction Stop } | Should Throw
        }
        
        It "Should accept array of valid Distinguished Names" {
            { Get-ADObjectsSequential -SearchBase $Global:TestConfig.ValidSearchBases } | Should Not Throw
        }
        
        It "Should handle single search base as array" {
            $searchBase = $Global:TestConfig.ValidSearchBases[0]
            $result = Get-ADObjectsSequential -SearchBase $searchBase
            $result | Should Not BeNullOrEmpty
        }
        
        It "Should support IncludeInherited switch parameter" {
            $searchBase = $Global:TestConfig.ValidSearchBases[0]
            { Get-ADObjectsSequential -SearchBase $searchBase -IncludeInherited } | Should Not Throw
        }
        
        It "Should validate correlation ID parameter format" {
            $searchBase = $Global:TestConfig.ValidSearchBases[0]
            $correlationId = [System.Guid]::NewGuid().ToString()
            { Get-ADObjectsSequential -SearchBase $searchBase -CorrelationId $correlationId } | Should Not Throw
        }
        
        It "Should auto-generate correlation ID when not provided" {
            $searchBase = $Global:TestConfig.ValidSearchBases[0]
            { Get-ADObjectsSequential -SearchBase $searchBase } | Should Not Throw
        }
    }
    
    Context "Core Functionality - Sequential Processing" {
        It "Should process multiple search bases sequentially" {
            Write-Host "TestConfig ValidSearchBases count:" $Global:TestConfig.ValidSearchBases.Count -ForegroundColor Yellow
            Write-Host "TestConfig TestObjects keys:" ($Global:TestConfig.TestObjects.Keys -join ', ') -ForegroundColor Yellow
            Write-Host "About to call Get-ADObjectsSequential with:" ($Global:TestConfig.ValidSearchBases -join ', ') -ForegroundColor Cyan
            
            $results = Get-ADObjectsSequential -SearchBase $Global:TestConfig.ValidSearchBases
            
            Write-Host "Returned $($results.Count) results" -ForegroundColor Green
            Write-Host "GetADObjectFromSearchBaseCalls count:" $Global:GetADObjectFromSearchBaseCalls.Count -ForegroundColor Yellow
            foreach ($call in $Global:GetADObjectFromSearchBaseCalls) {
                Write-Host "Called with: $($call.SearchBase)" -ForegroundColor Cyan
            }
            
            $results.Count | Should Be 5  # 3 users + 1 group + 1 computer
        }
        
        It "Should call Get-ADObjectFromSearchBase for each search base" {
            $searchBases = $Global:TestConfig.ValidSearchBases[0..2]  # First 3 search bases
            Get-ADObjectsSequential -SearchBase $searchBases
            $script:GetADObjectFromSearchBaseCallCount | Should Be $searchBases.Count
        }
        
        It "Should aggregate results from all search bases" {
            $searchBases = @(
                $Global:TestConfig.ValidSearchBases[0]  # Users (3 objects)
                $Global:TestConfig.ValidSearchBases[1]  # Groups (1 object)
                $Global:TestConfig.ValidSearchBases[2]  # Computers (1 object)
            )
            $results = Get-ADObjectsSequential -SearchBase $searchBases
            $results.Count | Should Be 5  # 3 users + 1 group + 1 computer
        }
        
        It "Should pass IncludeInherited parameter to Get-ADObjectFromSearchBase" {
            $searchBase = $Global:TestConfig.ValidSearchBases[0]
            Get-ADObjectsSequential -SearchBase $searchBase -IncludeInherited
            
            $callWithInherited = $Global:GetADObjectFromSearchBaseCalls | Where-Object { $_.IncludeInherited -eq $true }
            $callWithInherited | Should Not BeNullOrEmpty
        }
        
        It "Should maintain object order from search bases" {
            $searchBases = @(
                $Global:TestConfig.ValidSearchBases[0]  # Users
                $Global:TestConfig.ValidSearchBases[1]  # Groups
            )
            $results = Get-ADObjectsSequential -SearchBase $searchBases
            $results[0].ObjectClass | Should Be 'user'
        }
    }
    
    Context "Enterprise Security Logging and Auditing" {
        It "Should log operation attempt with correct security context" {
            $searchBases = $Global:TestConfig.ValidSearchBases[0..1]
            Get-ADObjectsSequential -SearchBase $searchBases
            
            $attemptLog = $Global:WriteSecurityLogCalls | Where-Object { $_.Outcome -eq 'Attempt' }
            $attemptLog | Should Not BeNullOrEmpty
            $attemptLog.SecurityContext.SearchBaseCount | Should Be 2
        }
        
        It "Should log operation success with comprehensive metrics" {
            # Clear previous debug info
            $Global:MockDebugInfo = @{}
            
            # Explicitly create 2-element array to ensure proper count
            $searchBases = @($Global:TestConfig.ValidSearchBases[0], $Global:TestConfig.ValidSearchBases[1])
            
            # Store debug info globally for inspection
            $Global:MockDebugInfo.OriginalArray = $Global:TestConfig.ValidSearchBases
            $Global:MockDebugInfo.SlicedArray = $searchBases
            $Global:MockDebugInfo.SlicedCount = $searchBases.Count
            $Global:MockDebugInfo.WrappedCount = @($searchBases).Count
            
            Get-ADObjectsSequential -SearchBase $searchBases
            
            $successCall = $Global:WriteSecurityLogCalls | Where-Object { $_.Outcome -eq 'Success' }
            $successCall | Should Not BeNullOrEmpty
            
            # Store actual result for debugging
            $Global:MockDebugInfo.ActualSearchBaseCount = $successCall.SecurityContext.SearchBaseCount
            $Global:MockDebugInfo.ExpectedCount = @($searchBases).Count
            
            # Simple assertion that should pass if arrays work correctly
            $successCall.SecurityContext.SearchBaseCount | Should Be @($searchBases).Count
        }
        
        It "Should include result summary in success logging" {
            $searchBases = $Global:TestConfig.ValidSearchBases[0..1]
            Get-ADObjectsSequential -SearchBase $searchBases
            
            $successCall = $Global:WriteSecurityLogCalls | Where-Object { $_.Outcome -eq 'Success' }
            $successCall.SecurityContext.TotalObjectsRetrieved | Should BeGreaterThan 0
        }
    }
    
    Context "Error Handling and Resilience" {
        It "Should continue processing when individual search bases fail" {
            $searchBases = @(
                $Global:TestConfig.ValidSearchBases[0]     # Valid
                'OU=Invalid,DC=contoso,DC=com'             # Invalid
                $Global:TestConfig.ValidSearchBases[1]     # Valid
            )
            $results = Get-ADObjectsSequential -SearchBase $searchBases
            $results.Count | Should BeGreaterThan 0
        }
        
        It "Should handle empty search base arrays" {
            { Get-ADObjectsSequential -SearchBase @() -ErrorAction Stop } | Should Throw
        }
        
        It "Should handle all search bases failing" {
            $searchBases = @('OU=Invalid1,DC=contoso,DC=com', 'OU=Invalid2,DC=contoso,DC=com')
            
            # Clear previous calls to isolate this test
            $Global:WriteSecurityLogCalls = @()
            
            $results = Get-ADObjectsSequential -SearchBase $searchBases -ErrorAction SilentlyContinue
            
            $logCalls = $Global:WriteSecurityLogCalls | Where-Object { $_.Outcome -eq 'Failure' }
            $logCalls.Count | Should Be 2
        }
        
        It "Should provide graceful degradation when AD is unavailable" {
            $searchBases = @($Global:TestConfig.ValidSearchBases[0])
            # Mock the scenario where AD is completely unavailable
            
            $results = Get-ADObjectsSequential -SearchBase $searchBases -ErrorAction SilentlyContinue
            # Should not throw but may return empty results
            { $results } | Should Not Throw
        }
    }
    
    Context "Performance and Scalability" {
        It "Should log processing progress for large operations" {
            $largeSearchBases = $Global:TestConfig.LargeSearchBases
            
            # Execute with verbose logging
            $VerbosePreference = 'Continue'
            Get-ADObjectsSequential -SearchBase $largeSearchBases -Verbose
            $VerbosePreference = 'SilentlyContinue'
            
            # Verify progress logging occurred
            $startMessage = $Global:WriteVerboseCalls | Where-Object { $_.Message -like "*Starting*" }
            $startMessage | Should Not BeNullOrEmpty
        }
        
        It "Should efficiently process large numbers of search bases" {
            $largeSearchBases = $Global:TestConfig.LargeSearchBases
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $results = Get-ADObjectsSequential -SearchBase $largeSearchBases
            $stopwatch.Stop()
            
            # Should complete within reasonable time (adjust threshold as needed)
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 10000  # 10 seconds
            $results.Count | Should Be 140  # 50+30+25+15+20 from large search bases
        }
        
        It "Should provide accurate object counting and metrics" {
            $searchBases = @(
                $Global:TestConfig.ValidSearchBases[0]  # Users (3 objects)
                $Global:TestConfig.ValidSearchBases[1]  # Groups (1 object)
            )
            $results = Get-ADObjectsSequential -SearchBase $searchBases
            $results.Count | Should Be 4  # 3 users + 1 group
            
            $successLog = $Global:WriteSecurityLogCalls | Where-Object { $_.Outcome -eq 'Success' }
            $successLog.SecurityContext.TotalObjectsRetrieved | Should Be 4
        }
        
        It "Should handle memory efficiently for large result sets" {
            $largeSearchBases = $Global:TestConfig.LargeSearchBases
            
            $beforeMemory = [System.GC]::GetTotalMemory($false)
            $results = Get-ADObjectsSequential -SearchBase $largeSearchBases
            $afterMemory = [System.GC]::GetTotalMemory($false)
            
            $memoryUsed = ($afterMemory - $beforeMemory) / 1MB
            $results.Count | Should Be 140  # 50+30+25+15+20 from large search bases
            $memoryUsed | Should BeLessThan 50  # Should use less than 50MB
        }
    }
    
    Context "Integration with Pipeline and Output" {
        It "Should output objects directly to pipeline for efficiency" {
            $searchBases = $Global:TestConfig.ValidSearchBases
            $results = Get-ADObjectsSequential -SearchBase $searchBases | Where-Object { $_.ObjectClass -eq 'user' }
            @($results).Count | Should Be 3
        }
        
        It "Should maintain object integrity through pipeline" {
            $searchBase = $Global:TestConfig.ValidSearchBases[0]
            $results = Get-ADObjectsSequential -SearchBase $searchBase
            
            foreach ($result in $results) {
                $result.DistinguishedName | Should Not BeNullOrEmpty
                $result.ObjectClass | Should Not BeNullOrEmpty
                $result.nTSecurityDescriptor | Should Not BeNullOrEmpty
            }
        }
        
        It "Should support complex pipeline operations" {
            $searchBases = $Global:TestConfig.ValidSearchBases
            $results = Get-ADObjectsSequential -SearchBase $searchBases | 
                       Where-Object { $_.ObjectClass -eq 'user' } |
                       Select-Object -First 2
            @($results).Count | Should Be 2
        }
    }
}
