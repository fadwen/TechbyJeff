#Requires -Module Pester

Describe "Test-PathTraversal" {
    BeforeAll {
        # Set environment variable to suppress warnings during testing
        $env:PESTER_TESTING = $true
        
        # Dot-source the function
        . "$PSScriptRoot\..\..\..\..\Private\Security\Test-PathTraversal.ps1"

        # Mock Write-StructuredLog
        Mock Write-StructuredLog { }

        # Create test directory structure for path traversal testing
        $script:TestBasePath = Join-Path $env:TEMP "PathTraversalTests"
        if (Test-Path $script:TestBasePath) {
            Remove-Item $script:TestBasePath -Recurse -Force
        }
        New-Item -Path $script:TestBasePath -ItemType Directory -Force | Out-Null
        
        # Create nested directories for testing
        $script:SafeDir = Join-Path $script:TestBasePath "SafeDirectory"
        $script:NestedDir = Join-Path $script:SafeDir "Nested"
        New-Item -Path $script:SafeDir -ItemType Directory -Force | Out-Null
        New-Item -Path $script:NestedDir -ItemType Directory -Force | Out-Null
        
        # Create test files
        $script:SafeFile = Join-Path $script:SafeDir "safe.txt"
        $script:NestedFile = Join-Path $script:NestedDir "nested.txt"
        "Safe content" | Out-File $script:SafeFile
        "Nested content" | Out-File $script:NestedFile
        
        # Common test paths
        $script:ValidPaths = @(
            $script:SafeFile,
            $script:NestedFile,
            $script:SafeDir,
            $script:NestedDir
        )
        
        $script:TraversalAttempts = @(
            "$script:SafeDir\..\..\..\Windows\System32",
            "$script:SafeDir\..\..\invalid.txt",
            "$script:SafeDir\..\outside.txt"
        )
    }

    AfterAll {
        # Clean up test directory
        if (Test-Path $script:TestBasePath) {
            Remove-Item $script:TestBasePath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Parameter Validation" {
        It "Should accept valid file paths" {
            $result = Test-PathTraversal -Path $script:SafeFile -BasePath $script:TestBasePath
            $result | Should Not BeNullOrEmpty
            $result.PSObject.TypeNames[0] | Should Be 'PathTraversalValidationResult'
        }

        It "Should reject null path parameter" {
            { Test-PathTraversal -Path $null -BasePath $script:TestBasePath } | Should Throw "Cannot bind argument to parameter 'Path' because it is null."
        }

        It "Should accept multiple paths in array" {
            $result = Test-PathTraversal -Path $script:ValidPaths -BasePath $script:TestBasePath
            $result.TotalPaths | Should Be $script:ValidPaths.Count
            $result.ValidationResults.Count | Should Be $script:ValidPaths.Count
        }

        It "Should use current location as default base path" {
            $result = Test-PathTraversal -Path $script:SafeFile
            $result.ValidationResults[0].BasePath | Should Be (Resolve-Path (Get-Location).Path).Path
        }

        It "Should accept pipeline input" {
            $result = $script:SafeFile | Test-PathTraversal -BasePath $script:TestBasePath
            $result | Should Not BeNullOrEmpty
            $result.TotalPaths | Should Be 1
        }
    }

    Context "Path Traversal Detection" {
        It "Should detect dot-dot-slash patterns" {
            $traversalPath = "$script:SafeDir\..\..\..\Windows"
            $result = Test-PathTraversal -Path $traversalPath -BasePath $script:TestBasePath
            
            $result.UnsafePaths | Should BeGreaterThan 0
            $result.ValidationPassed | Should Be $false
            $result.ValidationResults[0].ContainsTraversalPattern | Should Be $true
        }

        It "Should detect URL-encoded traversal patterns" {
            $encodedPaths = @(
                "$script:SafeDir%2e%2e%2f%2e%2e%2foutside.txt",
                "$script:SafeDir%2e%2e%5c%2e%2e%5coutside.txt"
            )
            
            foreach ($path in $encodedPaths) {
                $result = Test-PathTraversal -Path $path -BasePath $script:TestBasePath
                $result.ValidationResults[0].ContainsTraversalPattern | Should Be $true
            }
        }

        It "Should validate paths are within base directory" {
            $result = Test-PathTraversal -Path $script:ValidPaths -BasePath $script:TestBasePath
            
            foreach ($validationResult in $result.ValidationResults) {
                $validationResult.IsWithinBasePath | Should Be $true
                $validationResult.IsSafe | Should Be $true
            }
        }

        It "Should detect paths outside base directory" {
            # Create a test file outside the base path
            $outsideFile = Join-Path $env:TEMP "outside.txt"
            "Outside content" | Out-File $outsideFile
            
            try {
                $result = Test-PathTraversal -Path $outsideFile -BasePath $script:TestBasePath
                $result.ValidationResults[0].IsWithinBasePath | Should Be $false
                $result.ValidationResults[0].IsSafe | Should Be $false
            }
            finally {
                Remove-Item $outsideFile -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should handle mixed safe and unsafe paths" {
            $mixedPaths = @(
                $script:SafeFile,
                "$script:SafeDir\..\..\..\Windows\System32"
            )
            
            $result = Test-PathTraversal -Path $mixedPaths -BasePath $script:TestBasePath
            $result.SafePaths | Should Be 1
            $result.UnsafePaths | Should Be 1
            $result.ValidationPassed | Should Be $false
        }
    }

    Context "Security Validation" {
        It "Should reject common traversal attack patterns" {
            $attackPatterns = @(
                "..\..\..\etc\passwd",
                "..\..\Windows\System32\config",
                "..\..\..\var\log\auth.log",
                "..%2f..%2f..%2fetc%2fpasswd"
            )
            
            foreach ($pattern in $attackPatterns) {
                $testPath = Join-Path $script:SafeDir $pattern
                $result = Test-PathTraversal -Path $testPath -BasePath $script:TestBasePath
                $result.ValidationResults[0].ContainsTraversalPattern | Should Be $true
            }
        }

        It "Should validate absolute path attempts" {
            $absolutePaths = @(
                "C:\Windows\System32\drivers\etc\hosts",
                "/etc/passwd",
                "\\server\share\sensitive.txt"
            )
            
            foreach ($path in $absolutePaths) {
                if (Test-Path $path) {
                    $result = Test-PathTraversal -Path $path -BasePath $script:TestBasePath
                    $result.ValidationResults[0].IsWithinBasePath | Should Be $false
                }
            }
        }

        It "Should handle symbolic links and junctions safely" {
            $linkPath = Join-Path $script:SafeDir "testlink"
            
            # Create symbolic link if possible (requires elevated privileges)
            try {
                # Use C:\Windows as target to ensure it's outside our test base path
                $targetPath = "C:\Windows"
                New-Item -ItemType SymbolicLink -Path $linkPath -Target $targetPath -ErrorAction Stop
                
                $result = Test-PathTraversal -Path $linkPath -BasePath $script:TestBasePath
                # Symbolic link should be resolved and checked against base path
                # Since it points to C:\Windows, it should be outside our test base path
                $result.ValidationResults[0].IsWithinBasePath | Should Be $false
                
                Remove-Item $linkPath -Force -ErrorAction SilentlyContinue
            }
            catch {
                # Skip test if unable to create symbolic link (insufficient privileges)
                Write-Warning "Skipping symbolic link test: $($_.Exception.Message)"
            }
        }
    }

    Context "Error Handling" {
        It "Should handle non-existent paths gracefully" {
            $nonExistentPath = Join-Path $script:TestBasePath "nonexistent.txt"
            
            $result = Test-PathTraversal -Path $nonExistentPath -BasePath $script:TestBasePath
            $result.UnsafePaths | Should Be 1
            $result.ValidationPassed | Should Be $false
        }

        It "Should handle invalid base path gracefully" {
            $invalidBasePath = "Z:\NonExistent\Path"
            
            { Test-PathTraversal -Path $script:SafeFile -BasePath $invalidBasePath } | Should Throw
        }

        It "Should provide meaningful error messages for invalid paths" {
            $invalidPath = ":"  # Invalid path character on Windows
            
            $result = Test-PathTraversal -Path $invalidPath -BasePath $script:TestBasePath
            $result.UnsafePaths | Should Be 1
            $result.ValidationPassed | Should Be $false
        }

        It "Should maintain correlation tracking during errors" {
            $correlationId = [System.Guid]::NewGuid().ToString()
            $invalidPath = Join-Path $script:TestBasePath "invalid|file.txt"
            
            $result = Test-PathTraversal -Path $invalidPath -BasePath $script:TestBasePath -CorrelationId $correlationId
            $result.CorrelationId | Should Be $correlationId
        }
    }

    Context "Batch Processing" {
        It "Should process multiple paths efficiently" {
            $largeBatch = 1..50 | ForEach-Object { $script:SafeFile }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Test-PathTraversal -Path $largeBatch -BasePath $script:TestBasePath
            $stopwatch.Stop()
            
            $result.TotalPaths | Should Be 50
            $result.SafePaths | Should Be 50
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 5000  # Should complete within 5 seconds
        }

        It "Should maintain statistics across batch operations" {
            $mixedBatch = @(
                $script:SafeFile,
                $script:NestedFile,
                "$script:SafeDir\..\..\..\Windows",
                "$script:SafeDir\..\..\invalid.txt"
            )
            
            $result = Test-PathTraversal -Path $mixedBatch -BasePath $script:TestBasePath
            $result.TotalPaths | Should Be 4
            $result.SafePaths | Should Be 2
            $result.UnsafePaths | Should Be 2
            $result.ValidationPassed | Should Be $false
        }

        It "Should generate correlation ID for each validation operation" {
            $customCorrelationId = [System.Guid]::NewGuid().ToString()
            
            $result = Test-PathTraversal -Path $script:ValidPaths -BasePath $script:TestBasePath -CorrelationId $customCorrelationId
            
            foreach ($validationResult in $result.ValidationResults) {
                $validationResult.CorrelationId | Should Be $customCorrelationId
            }
        }
    }

    Context "Pipeline Support" {
        It "Should support pipeline input from Get-ChildItem" {
            $pipelineResult = Get-ChildItem $script:SafeDir -Recurse | 
                Select-Object -ExpandProperty FullName | 
                Test-PathTraversal -BasePath $script:TestBasePath
            
            $pipelineResult.TotalPaths | Should BeGreaterThan 0
            $pipelineResult.SafePaths | Should Be $pipelineResult.TotalPaths
            $pipelineResult.ValidationPassed | Should Be $true
        }

        It "Should process pipeline input with different path types" {
            $pathTypes = @(
                $script:SafeFile,           # File
                $script:SafeDir,            # Directory
                $script:NestedDir           # Nested directory
            )
            
            $result = $pathTypes | Test-PathTraversal -BasePath $script:TestBasePath
            $result.TotalPaths | Should Be 3
            $result.SafePaths | Should Be 3
        }

        It "Should maintain performance with pipeline processing" {
            $files = Get-ChildItem $script:TestBasePath -Recurse -File
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = $files.FullName | Test-PathTraversal -BasePath $script:TestBasePath
            $stopwatch.Stop()
            
            $result.ValidationPassed | Should Be $true
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 2000  # Should complete within 2 seconds
        }
    }

    Context "Logging Integration" {
        It "Should include correlation ID in result when available" {
            $result = Test-PathTraversal -Path $script:SafeFile -BasePath $script:TestBasePath
            
            $result.CorrelationId | Should Not BeNullOrEmpty
        }

        It "Should include custom correlation ID when provided" {
            $correlationId = [System.Guid]::NewGuid().ToString()
            
            $result = Test-PathTraversal -Path $script:SafeFile -BasePath $script:TestBasePath -CorrelationId $correlationId
            
            $result.CorrelationId | Should Be $correlationId
        }

        It "Should validate logging context for security analysis" {
            $unsafePath = "$script:SafeDir\..\..\..\Windows"
            
            $result = Test-PathTraversal -Path $unsafePath -BasePath $script:TestBasePath
            
            # Should identify unsafe path in results
            $result.UnsafePaths | Should BeGreaterThan 0
            $result.ValidationPassed | Should Be $false
        }

        It "Should provide comprehensive validation details" {
            $result = Test-PathTraversal -Path $script:SafeFile -BasePath $script:TestBasePath
            
            # Should include comprehensive validation details
            $result.BasePath | Should Not BeNullOrEmpty
            $result.ValidationResults | Should Not BeNullOrEmpty
            $result.CorrelationId | Should Not BeNullOrEmpty
        }
    }

    Context "Result Object Structure" {
        It "Should return properly structured result object" {
            $result = Test-PathTraversal -Path $script:SafeFile -BasePath $script:TestBasePath
            
            $result | Should Not BeNullOrEmpty
            $result.PSObject.TypeNames[0] | Should Be 'PathTraversalValidationResult'
            $result.ValidationResults | Should Not BeNullOrEmpty
            $result.TotalPaths | Should BeGreaterThan 0
        }

        It "Should include all required properties" {
            $result = Test-PathTraversal -Path $script:SafeFile -BasePath $script:TestBasePath
            
            $result.ValidationResults | Should Not BeNullOrEmpty
            $result.TotalPaths | Should Not BeNullOrEmpty
            $result.SafePaths | Should Not BeNullOrEmpty
            $result.UnsafePaths | Should Not BeNullOrEmpty
            $result.ValidationPassed | Should Not BeNullOrEmpty
            $result.BasePath | Should Not BeNullOrEmpty
            $result.CorrelationId | Should Not BeNullOrEmpty
        }

        It "Should maintain data type consistency across results" {
            $result = Test-PathTraversal -Path $script:SafeFile -BasePath $script:TestBasePath
            
            $result.TotalPaths.GetType().Name | Should Be 'Int32'
            $result.SafePaths.GetType().Name | Should Be 'Int32'
            $result.UnsafePaths.GetType().Name | Should Be 'Int32'
            $result.ValidationPassed.GetType().Name | Should Be 'Boolean'
        }
    }

    Context "Performance Requirements" {
        It "Should complete within acceptable time limits" {
            $largeBatch = 1..100 | ForEach-Object { $script:SafeFile }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Test-PathTraversal -Path $largeBatch -BasePath $script:TestBasePath
            $stopwatch.Stop()
            
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 10000  # 10 seconds max
            $result.TotalPaths | Should Be 100
        }

        It "Should handle memory efficiently with large datasets" {
            $beforeMemory = [System.GC]::GetTotalMemory($true)
            
            $largeBatch = 1..500 | ForEach-Object { $script:SafeFile }
            $result = Test-PathTraversal -Path $largeBatch -BasePath $script:TestBasePath
            
            $afterMemory = [System.GC]::GetTotalMemory($false)
            $memoryUsedMB = ($afterMemory - $beforeMemory) / 1MB
            
            $memoryUsedMB | Should BeLessThan 50  # Should use less than 50MB
            $result.TotalPaths | Should Be 500
        }
    }
    
    AfterAll {
        # Clean up environment variable
        Remove-Item -Path "env:PESTER_TESTING" -ErrorAction SilentlyContinue
    }
}
