# Systems Manager PowerShell Scripts

## Overview & Purpose

This directory contains PowerShell scripts for Systems Manager related tasks.

## Available Scripts

| Script Name | Description |
|-------------|-------------|
| [Test-SystemsManagerSetup](./Test-SystemsManagerSetup.ps1) | Tests AWS Systems Manager connectivity and setup on Windows instances |

| [Deploy-DSCAtScale](./Deploy-DSCAtScale.ps1) | Deploys DSC configurations at scale across multiple AWS EC2 instances using intelligent batching |
| [Get-DSCComplianceMetrics](./Get-DSCComplianceMetrics.ps1) | A PowerShell script named Get-DSCComplianceMetrics |
| [Get-DSCPerformanceImpact](./Get-DSCPerformanceImpact.ps1) | Aggregates DSC performance results from multiple AWS Systems Manager managed instances |
| [Get-MOFHash](./Get-MOFHash.ps1) | Calculates SHA256 hash for MOF files from local filesystem or S3 |
| [Get-SSMCompliance](./Get-SSMCompliance.ps1) | Generates comprehensive AWS Systems Manager compliance reports for managed instances |
| [New-SSMCacheDocument](./New-SSMCacheDocument.ps1) | Creates or updates an AWS Systems Manager document for DSC configuration deployment with caching |
| [Set-CISSecurityConfiguration](./Set-CISSecurityConfiguration.ps1) | A PowerShell script named Set-CISSecurityConfiguration |
| [generate-clean-json](./generate-clean-json.ps1) | A PowerShell script named generate-clean-json |
## Test-SystemsManagerSetup

### Overview & Purpose

Tests AWS Systems Manager connectivity and setup on Windows instances

This script performs a comprehensive verification of AWS Systems Manager (SSM)
    prerequisites and connectivity on Windows EC2 instances, helping to diagnose
    common SSM connection issues