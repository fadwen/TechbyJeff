<#
.SYNOPSIS
    Calculates SHA256 hash for MOF files from local filesystem or S3.

.DESCRIPTION
    This script provides functions to calculate SHA256 hashes of MOF files from either
    local storage or directly from S3 objects. Essential for AWS Systems Manager State
    Manager caching and validation without requiring local file access.

.PARAMETER MOFFilePath
    The full path to a local MOF file for hash calculation.

.PARAMETER S3Bucket
    The S3 bucket name containing the MOF file.

.PARAMETER S3Key
    The S3 object key (path) to the MOF file.

.PARAMETER S3Uri
    Full S3 URI (s3://bucket/key) to the MOF file.

.EXAMPLE
    Get-MOFHash -MOFFilePath "C:\DSC\MyConfig.mof"
    Calculates hash for local MOF file.

.EXAMPLE
    Get-MOFHash -S3Bucket "my-dsc-configs" -S3Key "production/webserver.mof"
    Calculates hash for MOF file stored in S3.

.EXAMPLE
    Get-MOFHash -S3Uri "s3://my-dsc-configs/production/webserver.mof"
    Calculates hash using full S3 URI.

.NOTES
    Author: Jeffrey Stuhr
    Purpose: AWS Systems Manager MOF file validation and caching
    Requirements: PowerShell 5.0+, AWS CLI or AWS PowerShell module
#>

function Test-AWSConfiguration {
    <#
    .SYNOPSIS
        Validates AWS CLI and PowerShell module availability.
    #>
    $hasAWSCLI = $false
    $hasAWSModule = $false

    # Test AWS CLI
    try {
        $null = aws --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            $hasAWSCLI = $true
        }
    } catch { }

    # Test AWS PowerShell modules
    if ((Get-Module -Name AWS.Tools.S3 -ListAvailable) -or (Get-Module -Name AWSPowerShell -ListAvailable)) {
        $hasAWSModule = $true
    }

    return @{
        HasCLI = $hasAWSCLI
        HasModule = $hasAWSModule
        IsConfigured = $hasAWSCLI -or $hasAWSModule
    }
}

function Get-MOFHash {
    <#
    .SYNOPSIS
        Calculates SHA256 hash for MOF files from local or S3 sources.

    .DESCRIPTION
        Generates SHA256 hash for MOF files from local filesystem or S3, with deployment
        guidance and automatic clipboard copying for easy use in AWS Systems Manager.

    .PARAMETER MOFFilePath
        Full path to local MOF file to analyze.

    .PARAMETER S3Bucket
        S3 bucket name containing the MOF file.

    .PARAMETER S3Key
        S3 object key (path) to the MOF file.

    .PARAMETER S3Uri
        Full S3 URI in format s3://bucket/key.

    .OUTPUTS
        Returns hashtable with file information including path, size, hash, and metadata.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Local')]
    param(
        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'Local',
            HelpMessage = "Enter the full path to the local MOF file"
        )]
        [ValidateNotNullOrEmpty()]
        [string]$MOFFilePath,

        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'S3BucketKey',
            HelpMessage = "Enter the S3 bucket name"
        )]
        [ValidateNotNullOrEmpty()]
        [string]$S3Bucket,

        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'S3BucketKey',
            HelpMessage = "Enter the S3 object key (path)"
        )]
        [ValidateNotNullOrEmpty()]
        [string]$S3Key,

        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'S3Uri',
            HelpMessage = "Enter the full S3 URI (s3://bucket/key)"
        )]
        [ValidateNotNullOrEmpty()]
        [string]$S3Uri
    )

    try {
        if ($PSCmdlet.ParameterSetName -eq 'Local') {
            # Handle local file processing
            Write-Host "Calculating hash for local MOF file..." -ForegroundColor Cyan
            return Get-LocalMOFHash -FilePath $MOFFilePath
        }
        else {
            # Validate AWS configuration before proceeding
            $awsConfig = Test-AWSConfiguration
            if (-not $awsConfig.IsConfigured) {
                throw "AWS CLI or AWS PowerShell module is required for S3 operations. Please install AWS CLI or AWS PowerShell module."
            }

            # Handle S3 file processing
            if ($PSCmdlet.ParameterSetName -eq 'S3Uri') {
                # Parse S3 URI to extract bucket and key
                if ($S3Uri -match '^s3://([^/]+)/(.+)$') {
                    $S3Bucket = $matches[1]
                    $S3Key = $matches[2]
                } else {
                    throw "Invalid S3 URI format. Expected: s3://bucket/key"
                }
            }

            Write-Host "Calculating hash for S3 MOF file..." -ForegroundColor Cyan
            Write-Host "Bucket: $S3Bucket" -ForegroundColor Gray
            Write-Host "Key: $S3Key" -ForegroundColor Gray

            return Get-S3MOFHash -Bucket $S3Bucket -Key $S3Key
        }
    }
    catch {
        throw "Failed to calculate MOF hash: $($_.Exception.Message)"
    }
}

function Get-LocalMOFHash {
    param([string]$FilePath)

    if (-not (Test-Path $FilePath)) {
        throw "MOF file not found: $FilePath"
    }

    $fileInfo = Get-Item $FilePath
    $hash = (Get-FileHash $FilePath -Algorithm SHA256).Hash
    $sizeKB = [math]::Round($fileInfo.Length / 1024, 2)

    Write-Host ""
    Write-Host "=== Local MOF File Information ===" -ForegroundColor Yellow
    Write-Host "File Path: $FilePath" -ForegroundColor White
    Write-Host "File Size: $sizeKB KB" -ForegroundColor White
    Write-Host "SHA256 Hash: $hash" -ForegroundColor Green

    Show-DeploymentGuidance -SizeKB $sizeKB
    Copy-HashToClipboard -Hash $hash

    return @{
        Source = "Local"
        FilePath = $FilePath
        FileName = $fileInfo.Name
        SizeBytes = $fileInfo.Length
        SizeKB = $sizeKB
        Hash = $hash
        LastModified = $fileInfo.LastWriteTime
        S3Bucket = $null
        S3Key = $null
    }
}

function Get-S3MOFHash {
    param(
        [string]$Bucket,
        [string]$Key
    )

    # Try AWS CLI first (most commonly available)
    $s3Info = Get-S3ObjectInfo -Bucket $Bucket -Key $Key -Method "CLI"

    if (-not $s3Info) {
        # Fallback to AWS PowerShell module
        $s3Info = Get-S3ObjectInfo -Bucket $Bucket -Key $Key -Method "PowerShell"
    }

    if (-not $s3Info) {
        throw "Unable to retrieve S3 object information. Ensure AWS CLI is configured or AWS PowerShell module is installed."
    }

    $sizeKB = [math]::Round($s3Info.Size / 1024, 2)

    Write-Host ""
    Write-Host "=== S3 MOF File Information ===" -ForegroundColor Yellow
    Write-Host "S3 Location: s3://$Bucket/$Key" -ForegroundColor White
    Write-Host "File Size: $sizeKB KB" -ForegroundColor White
    Write-Host "SHA256 Hash: $($s3Info.Hash)" -ForegroundColor Green
    Write-Host "Last Modified: $($s3Info.LastModified)" -ForegroundColor Gray

    Show-DeploymentGuidance -SizeKB $sizeKB
    Copy-HashToClipboard -Hash $s3Info.Hash

    return @{
        Source = "S3"
        FilePath = "s3://$Bucket/$Key"
        FileName = Split-Path $Key -Leaf
        SizeBytes = $s3Info.Size
        SizeKB = $sizeKB
        Hash = $s3Info.Hash
        LastModified = $s3Info.LastModified
        S3Bucket = $Bucket
        S3Key = $Key
    }
}

function Get-S3ObjectInfo {
    param(
        [string]$Bucket,
        [string]$Key,
        [string]$Method
    )

    if ($Method -eq "CLI") {
        try {
            # Method 1: Use AWS CLI to get object metadata
            Write-Host "Using AWS CLI to retrieve S3 object information..." -ForegroundColor Gray

            # First check if object exists
            $s3Output = aws s3api head-object --bucket $Bucket --key $Key --output json 2>$null

            if ($LASTEXITCODE -ne 0) {
                throw "S3 object not found or access denied: s3://$Bucket/$Key"
            }

            $s3Metadata = $s3Output | ConvertFrom-Json

            # AWS S3 provides ETag which is MD5 for simple uploads, but we need SHA256
            # For SHA256, we need to check if it's stored as metadata or calculate it
            $sha256Hash = $null

            # Check if SHA256 is stored as metadata
            if ($s3Metadata.Metadata -and $s3Metadata.Metadata.'sha256') {
                $sha256Hash = $s3Metadata.Metadata.'sha256'
                Write-Host "✓ Found SHA256 in object metadata" -ForegroundColor Green
            }
            elseif ($s3Metadata.Metadata -and $s3Metadata.Metadata.'x-amz-content-sha256') {
                $sha256Hash = $s3Metadata.Metadata.'x-amz-content-sha256'
                Write-Host "✓ Found SHA256 in AMZ content metadata" -ForegroundColor Green
            }
            else {
                # Calculate SHA256 by downloading and hashing (for smaller files)
                Write-Host "SHA256 not in metadata, calculating..." -ForegroundColor Yellow
                $sha256Hash = Get-S3ObjectSHA256 -Bucket $Bucket -Key $Key -Method "CLI"
            }

            return @{
                Size = [long]$s3Metadata.ContentLength
                Hash = $sha256Hash
                LastModified = [DateTime]$s3Metadata.LastModified
                ETag = $s3Metadata.ETag.Trim('"')
            }
        }
        catch {
            Write-Host "AWS CLI method failed: $($_.Exception.Message)" -ForegroundColor Yellow
            return $null
        }
    }
    elseif ($Method -eq "PowerShell") {
        try {
            # Method 2: Use AWS PowerShell module
            Write-Host "Using AWS PowerShell module..." -ForegroundColor Gray

            if (-not (Get-Module -Name AWS.Tools.S3 -ListAvailable)) {
                if (-not (Get-Module -Name AWSPowerShell -ListAvailable)) {
                    throw "Neither AWS.Tools.S3 nor AWSPowerShell module is installed"
                }
            }

            $s3Object = Get-S3Object -BucketName $Bucket -Key $Key -ErrorAction Stop

            # Check for SHA256 in object metadata first
            $sha256Hash = $null
            $s3ObjectMetadata = Get-S3ObjectMetadata -BucketName $Bucket -Key $Key -ErrorAction Stop

            if ($s3ObjectMetadata.Metadata -and $s3ObjectMetadata.Metadata['sha256']) {
                $sha256Hash = $s3ObjectMetadata.Metadata['sha256']
                Write-Host "✓ Found SHA256 in object metadata" -ForegroundColor Green
            }
            else {
                # Calculate SHA256 by downloading and hashing
                Write-Host "SHA256 not in metadata, calculating..." -ForegroundColor Yellow
                $sha256Hash = Get-S3ObjectSHA256 -Bucket $Bucket -Key $Key -Method "PowerShell"
            }

            return @{
                Size = $s3Object.Size
                Hash = $sha256Hash
                LastModified = $s3Object.LastModified
                ETag = $s3Object.ETag
            }
        }
        catch {
            Write-Host "AWS PowerShell method failed: $($_.Exception.Message)" -ForegroundColor Yellow
            return $null
        }
    }

    return $null
}

function Get-S3ObjectSHA256 {
    param(
        [string]$Bucket,
        [string]$Key,
        [string]$Method = "CLI"
    )

    try {
        # For files under 100MB, download temporarily and hash
        # For larger files, this would need streaming or alternative approach
        $tempFile = [System.IO.Path]::GetTempFileName()

        Write-Host "Downloading S3 object to calculate SHA256..." -ForegroundColor Gray

        if ($Method -eq "CLI") {
            # Download using AWS CLI
            aws s3 cp "s3://$Bucket/$Key" $tempFile --quiet 2>$null

            if ($LASTEXITCODE -eq 0) {
                $hash = (Get-FileHash $tempFile -Algorithm SHA256).Hash
                Remove-Item $tempFile -Force
                Write-Host "✓ SHA256 calculated from downloaded file" -ForegroundColor Green
                return $hash
            }
            else {
                throw "Failed to download S3 object using AWS CLI"
            }
        }
        elseif ($Method -eq "PowerShell") {
            # Download using AWS PowerShell module
            Read-S3Object -BucketName $Bucket -Key $Key -File $tempFile -ErrorAction Stop

            $hash = (Get-FileHash $tempFile -Algorithm SHA256).Hash
            Remove-Item $tempFile -Force
            Write-Host "✓ SHA256 calculated from downloaded file" -ForegroundColor Green
            return $hash
        }
        else {
            throw "Invalid download method specified"
        }
    }
    catch {
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }
        Write-Host "⚠️  Could not calculate SHA256: $($_.Exception.Message)" -ForegroundColor Yellow
        return "HASH_CALCULATION_FAILED"
    }
}

function Show-DeploymentGuidance {
    param([double]$SizeKB)

    Write-Host ""
    if ($SizeKB -gt 4096) {
        Write-Host "⚠️  WARNING: Large MOF file ($SizeKB KB)" -ForegroundColor Red
        Write-Host "   Consider reducing batch sizes for deployment" -ForegroundColor Yellow
        Write-Host "   Monitor Systems Manager execution timeouts" -ForegroundColor Yellow
    }
    elseif ($SizeKB -gt 2048) {
        Write-Host "⚠️  NOTICE: Medium-sized MOF file ($SizeKB KB)" -ForegroundColor Yellow
        Write-Host "   Monitor deployment performance" -ForegroundColor Gray
    }
    else {
        Write-Host "✓ MOF file size is reasonable for deployment" -ForegroundColor Green
    }
}

function Copy-HashToClipboard {
    param([string]$Hash)

    try {
        $Hash | Set-Clipboard
        Write-Host "✓ Hash copied to clipboard" -ForegroundColor Green
    }
    catch {
        Write-Host "ℹ️  Hash not copied to clipboard (Set-Clipboard not available)" -ForegroundColor Gray
    }
}

# Script execution when run directly
if ($MyInvocation.InvocationName -ne '.' -and $args.Count -gt 0) {
    # Parse command line arguments manually to avoid parameter conflicts
    $paramHash = @{}

    for ($i = 0; $i -lt $args.Count; $i += 2) {
        if ($i + 1 -lt $args.Count) {
            $paramName = $args[$i] -replace '^-', ''
            $paramValue = $args[$i + 1]
            $paramHash[$paramName] = $paramValue
        }
    }

    try {
        if ($paramHash.S3Uri) {
            Get-MOFHash -S3Uri $paramHash.S3Uri
        }
        elseif ($paramHash.S3Bucket -and $paramHash.S3Key) {
            Get-MOFHash -S3Bucket $paramHash.S3Bucket -S3Key $paramHash.S3Key
        }
        elseif ($paramHash.MOFFilePath) {
            Get-MOFHash -MOFFilePath $paramHash.MOFFilePath
        }
        else {
            Write-Host "Usage examples:" -ForegroundColor Yellow
            Write-Host "  .\Get-MOFHash.ps1 -MOFFilePath 'C:\DSC\config.mof'" -ForegroundColor Gray
            Write-Host "  .\Get-MOFHash.ps1 -S3Bucket 'my-bucket' -S3Key 'configs/prod.mof'" -ForegroundColor Gray
            Write-Host "  .\Get-MOFHash.ps1 -S3Uri 's3://my-bucket/configs/prod.mof'" -ForegroundColor Gray
        }
    }
    catch {
        Write-Error "Script execution failed: $($_.Exception.Message)"
        exit 1
    }
}
elseif ($MyInvocation.InvocationName -ne '.' -and $args.Count -eq 0) {
    Write-Host "Usage examples:" -ForegroundColor Yellow
    Write-Host "  .\Get-MOFHash.ps1 -MOFFilePath 'C:\DSC\config.mof'" -ForegroundColor Gray
    Write-Host "  .\Get-MOFHash.ps1 -S3Bucket 'my-bucket' -S3Key 'configs/prod.mof'" -ForegroundColor Gray
    Write-Host "  .\Get-MOFHash.ps1 -S3Uri 's3://my-bucket/configs/prod.mof'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Or import as module:" -ForegroundColor Yellow
    Write-Host "  . .\Get-MOFHash.ps1" -ForegroundColor Gray
    Write-Host "  Get-MOFHash -MOFFilePath 'C:\DSC\config.mof'" -ForegroundColor Gray
}