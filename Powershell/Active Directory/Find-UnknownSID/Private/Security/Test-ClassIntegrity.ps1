function Test-ClassIntegrity {
    <#
    .SYNOPSIS
        Validates the integrity of PowerShell class files
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$FilePath,

        [Parameter()]
        [hashtable]$ExpectedHashes = @{},

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        $verificationResults = @()
        $totalFiles = 0
        $passedFiles = 0
        $failedFiles = 0
    }

    process {
        foreach ($currentFile in $FilePath) {
            $totalFiles++

            try {
                if (Test-Path $currentFile -PathType Leaf) {
                    $fileName = Split-Path $currentFile -Leaf

                    if ($ExpectedHashes.ContainsKey($fileName)) {
                        try {
                            $fileContent = Get-Content $currentFile -Raw -Encoding UTF8
                            $actualHash = Get-StringHash -InputString $fileContent -Algorithm SHA256
                            $expectedHash = $ExpectedHashes[$fileName]

                            $verificationResult = [PSCustomObject]@{
                                FilePath = $currentFile
                                FileName = $fileName
                                ExpectedHash = $expectedHash
                                ActualHash = $actualHash
                                HashMatch = ($actualHash -eq $expectedHash)
                                CorrelationId = $CorrelationId
                            }

                            if ($verificationResult.HashMatch) {
                                $passedFiles++
                            } else {
                                $failedFiles++
                            }

                            $verificationResults += $verificationResult
                        } catch {
                            $failedFiles++
                            Write-Warning "Hash verification failed for $currentFile : $($_.Exception.Message)"
                        }
                    } else {
                        Write-Verbose "No expected hash found for $fileName, skipping verification"
                    }
                } else {
                    $failedFiles++
                    Write-Warning "File not found: $currentFile"
                }
            } catch {
                $failedFiles++
                Write-Error "Error processing file $currentFile : $($_.Exception.Message)"
            }
        }
    }

    end {
        $integrityPassed = ($failedFiles -eq 0)

        $verificationSummary = @{
            TotalFiles = $totalFiles
            PassedFiles = $passedFiles
            FailedFiles = $failedFiles
            IntegrityPassed = $integrityPassed
        }

        # Log completion summary
        if (Get-Command Write-StructuredLog -ErrorAction SilentlyContinue) {
            $logLevel = if (-not $integrityPassed) { 'Warning' } else { 'Information' }
            Write-StructuredLog -Level $logLevel -Message "File integrity verification completed" -CorrelationId $CorrelationId -Data $verificationSummary
        }

        # Return comprehensive integrity verification results
        return [PSCustomObject]@{
            PSTypeName = 'IntegrityVerificationResult'
            VerificationResults = $verificationResults
            TotalFiles = $totalFiles
            PassedFiles = $passedFiles
            FailedFiles = $failedFiles
            IntegrityPassed = $integrityPassed
            CorrelationId = $CorrelationId
        }
    }
}
