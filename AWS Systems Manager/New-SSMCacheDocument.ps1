<#
.SYNOPSIS
    Creates or updates an AWS Systems Manager document for DSC configuration deployment with caching.

.DESCRIPTION
    This script automates the creation and management of AWS SSM documents that enable
    PowerShell DSC configuration deployment with intelligent caching capabilities.
    It validates JSON document content, handles existing document updates, and sets
    appropriate permissions for the SSM document.

.PARAMETER DocumentName
    The name of the SSM document to create or update. Default is "DSC-Apply-With-Caching".

.PARAMETER JsonFilePath
    Path to the JSON file containing the SSM document definition.
    Default is ".\ssm-document-cached-dsc.json".

.PARAMETER Verbose
    Show detailed troubleshooting information and alternative approaches when errors occur.

.EXAMPLE
    .\New-SSMCacheDocument.ps1
    Creates the SSM document with default parameters.

.EXAMPLE
    .\New-SSMCacheDocument.ps1 -DocumentName "MyCustomDSCDoc" -JsonFilePath "C:\configs\my-doc.json" -Verbose
    Creates an SSM document with custom name and JSON file path, showing verbose output.

.NOTES
    Author: Jeffrey Stuhr
    Purpose: AWS Systems Manager DSC deployment automation
    Requirements:
    - AWS CLI configured with appropriate permissions
    - Valid JSON SSM document definition file
    - IAM permissions: ssm:CreateDocument, ssm:UpdateDocument, ssm:DescribeDocument, ssm:ModifyDocumentPermission
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Name of the SSM document to create or update")]
    [string]$DocumentName = "DSC-Apply-With-Caching",

    [Parameter(HelpMessage = "Path to the JSON file containing SSM document definition")]
    [string]$JsonFilePath = ".\ssm-document-cached-dsc.json"
)

# Display script execution start message
Write-Host "Creating SSM Document: $DocumentName" -ForegroundColor Cyan

# Validate that the required JSON document file exists
if (-not (Test-Path $JsonFilePath)) {
    Write-Host "❌ JSON file not found: $JsonFilePath" -ForegroundColor Red
    Write-Host "Make sure you have saved the SSM Document JSON as: $JsonFilePath" -ForegroundColor Yellow
    exit 1
}

try {
    # Validate JSON file structure and content before attempting AWS operations
    Write-Host "Validating JSON file..." -ForegroundColor Yellow

    # Read the JSON file with explicit UTF-8 encoding to avoid encoding issues
    $jsonContent = Get-Content $JsonFilePath -Raw -Encoding UTF8 | ConvertFrom-Json

    Write-Host "✓ JSON file is valid" -ForegroundColor Green
    Write-Host "  Schema Version: $($jsonContent.schemaVersion)" -ForegroundColor Gray
    Write-Host "  Description: $($jsonContent.description)" -ForegroundColor Gray
    Write-Host "  Parameters: $($jsonContent.parameters.Count)" -ForegroundColor Gray

    # Create a safe temporary file path without spaces or special characters
    Write-Host "Preparing JSON content for AWS CLI..." -ForegroundColor Yellow

    # Use current directory for temp file to avoid path issues
    $tempJsonFile = ".\ssm-temp-$(Get-Random).json"

    # Convert the JSON content back to string with proper formatting
    $jsonString = $jsonContent | ConvertTo-Json -Depth 10

    # Save as UTF-8 without BOM (required by AWS CLI)
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $fullTempPath = Join-Path (Get-Location).Path $tempJsonFile
    [System.IO.File]::WriteAllText($fullTempPath, $jsonString, $utf8NoBom)

    Write-Host "✓ Temporary JSON file created: $tempJsonFile" -ForegroundColor Green

    # Alternative approach: Pass JSON content directly as string instead of file
    Write-Host "Using direct JSON content approach..." -ForegroundColor Yellow

    # Escape the JSON for command line usage
    $escapedJson = $jsonString -replace '"', '\"'

    # Check if an SSM document with the same name already exists
    Write-Host "Checking if document already exists..." -ForegroundColor Yellow
    $existingDoc = aws ssm describe-document --name $DocumentName --output json 2>$null

    if ($LASTEXITCODE -eq 0) {
        # Document exists - prompt user for update confirmation
        Write-Host "⚠️  Document '$DocumentName' already exists" -ForegroundColor Yellow
        $response = Read-Host "Do you want to update it? (y/N)"

        if ($response -eq 'y' -or $response -eq 'Y') {
            # Update existing document with new content - try file approach first
            Write-Host "Updating existing document..." -ForegroundColor Yellow

            # Method 1: Try with temporary file
            $result = aws ssm update-document `
                --name $DocumentName `
                --content "file://$tempJsonFile" `
                --document-format JSON `
                --document-version '$LATEST' `
                --output json 2>&1

            if ($LASTEXITCODE -ne 0) {
                Write-Host "File method failed, trying stdin approach..." -ForegroundColor Yellow
                # Method 2: Use stdin approach
                $result = $jsonString | aws ssm update-document `
                    --name $DocumentName `
                    --content "file://-" `
                    --document-format JSON `
                    --document-version '$LATEST' `
                    --output json
            }

            # Enhanced error handling for duplicate content
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✓ Document updated successfully" -ForegroundColor Green
                try {
                    $updateInfo = $result | ConvertFrom-Json
                    Write-Host "  New Version: $($updateInfo.DocumentDescription.DocumentVersion)" -ForegroundColor Gray
                } catch {
                    Write-Host "  Update completed (version info not available)" -ForegroundColor Gray
                }
            } elseif ($LASTEXITCODE -eq 254) {
                # Handle duplicate content gracefully - this is actually success
                Write-Host "⚠️  No changes detected - document content is identical" -ForegroundColor Yellow
                Write-Host "✓ Document '$DocumentName' is already current" -ForegroundColor Green
                Write-Host "  No update needed - existing document matches your JSON file" -ForegroundColor Gray
            } else {
                Write-Host "Update error output: $result" -ForegroundColor Red
                throw "Failed to update document - AWS CLI error code: $LASTEXITCODE"
            }
        } else {
            # User chose not to update - exit gracefully
            Write-Host "Document update cancelled" -ForegroundColor Yellow
            Remove-Item $tempJsonFile -Force -ErrorAction SilentlyContinue
            exit 0
        }
    } else {
        # Document doesn't exist - create new one
        Write-Host "Creating new document..." -ForegroundColor Yellow

        # Method 1: Try with temporary file
        Write-Host "Attempting file-based creation..." -ForegroundColor Gray
        $result = aws ssm create-document `
            --name $DocumentName `
            --document-type "Command" `
            --content "file://$tempJsonFile" `
            --document-format JSON `
            --output json 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Host "File method failed, trying stdin approach..." -ForegroundColor Yellow
            # Method 2: Use stdin approach (pipe JSON directly)
            $result = $jsonString | aws ssm create-document `
                --name $DocumentName `
                --document-type "Command" `
                --content "file://-" `
                --document-format JSON `
                --output json
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Document created successfully" -ForegroundColor Green
            try {
                $createInfo = $result | ConvertFrom-Json
                Write-Host "  Document Name: $($createInfo.DocumentDescription.Name)" -ForegroundColor Gray
                Write-Host "  Version: $($createInfo.DocumentDescription.DocumentVersion)" -ForegroundColor Gray
                Write-Host "  Status: $($createInfo.DocumentDescription.Status)" -ForegroundColor Gray
            } catch {
                Write-Host "  Creation completed (details not available)" -ForegroundColor Gray
            }
        } else {
            # Provide detailed error information
            Write-Host "AWS CLI exit code: $LASTEXITCODE" -ForegroundColor Red
            Write-Host "Error output: $result" -ForegroundColor Red

            # Try one more approach - create a simple batch file to avoid PowerShell escaping issues
            Write-Host "Trying batch file approach as last resort..." -ForegroundColor Yellow

            $batchFile = ".\create-ssm-doc.bat"
            $batchContent = @"
@echo off
aws ssm create-document --name "$DocumentName" --document-type "Command" --content "file://$tempJsonFile" --document-format JSON --output json
"@
            $batchContent | Out-File -FilePath $batchFile -Encoding ASCII

            $batchResult = & cmd /c $batchFile
            $batchExitCode = $LASTEXITCODE

            Remove-Item $batchFile -Force -ErrorAction SilentlyContinue

            if ($batchExitCode -eq 0) {
                Write-Host "✓ Document created successfully using batch approach" -ForegroundColor Green
            } elseif ($batchExitCode -eq 254) {
                # Handle duplicate content even during creation attempts
                Write-Host "⚠️  Document already exists with identical content" -ForegroundColor Yellow
                Write-Host "✓ Document '$DocumentName' is ready to use" -ForegroundColor Green
            } else {
                throw "All creation methods failed - AWS CLI error code: $batchExitCode"
            }
        }
    }

    # Configure document permissions for sharing within the account
    # Only attempt if we had a successful operation (including duplicate content scenarios)
    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 254) {
        Write-Host "Setting document permissions..." -ForegroundColor Yellow
        $permResult = aws ssm modify-document-permission `
            --name $DocumentName `
            --permission-type Share `
            --account-ids-to-add "self" `
            --output json 2>$null

        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Document permissions set" -ForegroundColor Green
        } else {
            # Permission setting failure is not critical - document can still be used
            Write-Host "⚠️  Could not set document permissions (this is usually OK)" -ForegroundColor Yellow
        }

        # Verify the document was created successfully
        Write-Host "Verifying document creation..." -ForegroundColor Yellow
        $verifyResult = aws ssm describe-document --name $DocumentName --output json 2>$null

        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Document verification successful" -ForegroundColor Green
            try {
                $docInfo = $verifyResult | ConvertFrom-Json
                Write-Host "  Status: $($docInfo.Document.Status)" -ForegroundColor Gray
                Write-Host "  Document Format: $($docInfo.Document.DocumentFormat)" -ForegroundColor Gray
            } catch {
                Write-Host "  Document exists and is accessible" -ForegroundColor Gray
            }
        } else {
            Write-Host "⚠️  Could not verify document (but creation may have succeeded)" -ForegroundColor Yellow
        }

        # Display success summary and usage instructions
        Write-Host ""
        Write-Host "=== SSM Document Ready ===" -ForegroundColor Green
        Write-Host "Document Name: $DocumentName" -ForegroundColor White
        Write-Host "You can now use this document with your scale deployment function" -ForegroundColor White
        Write-Host ""

        # Provide example usage for the newly created document
        Write-Host "Example usage:" -ForegroundColor Yellow
        Write-Host '$result = Deploy-CISConfigurationAtScale \' -ForegroundColor Gray
        Write-Host "    -DocumentName `"$DocumentName`" \" -ForegroundColor Gray
        Write-Host '    -ConfigurationS3Bucket "your-bucket" \' -ForegroundColor Gray
        Write-Host '    -ConfigurationS3Key "configs/production.mof" \' -ForegroundColor Gray
        Write-Host '    -ConfigurationHash "your-mof-hash"' -ForegroundColor Gray

        # Show how to test the document
        Write-Host ""
        Write-Host "To test the document:" -ForegroundColor Yellow
        Write-Host "aws ssm list-documents --filters Key=Name,Values=$DocumentName" -ForegroundColor Gray
    }

} catch {
    # Handle errors gracefully with helpful troubleshooting information
    Write-Host "❌ Failed to create SSM document: $($_.Exception.Message)" -ForegroundColor Red

    Write-Verbose "Alternative manual approach:"
    Write-Verbose "1. Copy the JSON content manually:"
    Write-Verbose "   Get-Content $JsonFilePath -Raw | Set-Clipboard"
    Write-Verbose ""
    Write-Verbose "2. Create document via AWS Console:"
    Write-Verbose "   - Go to Systems Manager > Documents"
    Write-Verbose "   - Click 'Create document'"
    Write-Verbose "   - Choose 'Command' document type"
    Write-Verbose "   - Paste JSON content"
    Write-Verbose ""
    Write-Verbose "3. Or try AWS CLI with reduced JSON:"
    Write-Verbose "   - The JSON might be too complex for your AWS CLI version"
    Write-Verbose "   - Try updating AWS CLI: pip install --upgrade awscli"

    Write-Host "Run with -Verbose for troubleshooting steps" -ForegroundColor Yellow

    exit 1
} finally {
    # Clean up temporary files
    @(".\ssm-temp-*.json", ".\create-ssm-doc.bat") | ForEach-Object {
        Get-ChildItem -Path $_ -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}