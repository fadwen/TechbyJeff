# AWS Systems Manager PowerShell Scripts

## Overview & Purpose

This directory contains a comprehensive collection of PowerShell scripts designed for managing, monitoring, and automating AWS Systems Manager (SSM) operations. These scripts provide capabilities for DSC (Desired State Configuration) management, compliance monitoring, performance analysis, security configuration, and general Systems Manager administration.

The scripts are designed to work in enterprise environments and support batch operations, detailed reporting, and integration with AWS CloudWatch for monitoring and alerting.

## Prerequisites

### Required Software
- **PowerShell 5.1** or later (PowerShell 7+ recommended)
- **AWS PowerShell Module** (AWS.Tools or AWSPowerShell)
- **AWS CLI** (for some operations)

### AWS Requirements
- Valid AWS credentials configured (via AWS CLI, IAM roles, or environment variables)
- Appropriate IAM permissions for Systems Manager operations
- EC2 instances with SSM Agent installed and properly configured
- VPC endpoints for Systems Manager (if using private subnets)

### Required IAM Permissions
Your AWS credentials need the following permissions:
- `ssm:*` (Systems Manager operations)
- `ec2:DescribeInstances` (Instance information)
- `cloudwatch:PutMetricData` (For metrics publishing)
- `s3:GetObject`, `s3:PutObject` (For S3 operations)

## Installation & Setup

1. **Install required PowerShell modules:**
   ```powershell
   Install-Module -Name AWS.Tools.EC2, AWS.Tools.SimpleSystemsManagement, AWS.Tools.CloudWatch -Force
   ```

2. **Configure AWS credentials:**
   ```powershell
   Set-AWSCredential -AccessKey "YOUR_ACCESS_KEY" -SecretKey "YOUR_SECRET_KEY" -Region "us-east-1"
   ```

3. **Verify Systems Manager setup:**
   ```powershell
   .\Test-SystemsManagerSetup.ps1 -InstanceId "i-1234567890abcdef0"
   ```

## Available Scripts

| Script Name | Purpose | Key Features |
|-------------|---------|--------------|
| [Deploy-DSCAtScale.ps1](#deploy-dscatscale) | DSC configuration deployment | Intelligent batching, progress tracking, rollback |
| [Get-DSCComplianceMetrics.ps1](#get-dsccompliancemetrics) | DSC compliance monitoring | Detailed compliance reports, trend analysis |
| [Get-DSCPerformanceImpact.ps1](#get-dscperformanceimpact) | DSC performance analysis | Resource usage tracking, bottleneck identification |
| [Get-SSMCompliance.ps1](#get-ssmcompliance) | SSM compliance reporting | Comprehensive compliance dashboards |
| [Test-SystemsManagerSetup.ps1](#test-systemsmanagersetup) | SSM connectivity verification | Diagnostic testing, troubleshooting |
| [Set-CISSecurityConfiguration.ps1](#set-cissecurityconfiguration) | CIS security baseline deployment | Automated security hardening |
| [New-SSMCacheDocument.ps1](#new-ssmcachedocument) | SSM document management | Document creation with caching |
| [Get-MOFHash.ps1](#get-mofhash) | MOF file validation | Hash calculation and verification |
| [generate-clean-json.ps1](#generate-clean-json) | JSON document processing | Clean JSON generation and formatting |

## Supporting Files

| File Name | Purpose | Description |
|-----------|---------|-------------|
| `DSC-Apply-Configuration.json` | SSM Document | Template for DSC configuration application |
| `ssm-document-cached-dsc.json` | SSM Document | Cached DSC deployment document |
| `cloudwatch-config.json` | CloudWatch Config | CloudWatch agent configuration |
| `dashboard.json` | CloudWatch Dashboard | Pre-configured monitoring dashboard |
| `AWS-SystemsManager-CLI-Examples.md` | Documentation | CLI usage examples and reference |

---

## Script Documentation

### Deploy-DSCAtScale

**Purpose:** Deploys DSC configurations at scale across multiple AWS EC2 instances using intelligent batching and progress tracking.

**Key Features:**
- Intelligent batching based on instance capacity
- Real-time progress monitoring
- Automatic rollback on failures
- CloudWatch metrics integration
- Detailed deployment reporting

**Parameters:**
- `ConfigurationName` - Name of the DSC configuration to deploy
- `InstanceIds` - Array of target EC2 instance IDs
- `BatchSize` - Number of instances to process simultaneously (default: 10)
- `MaxErrors` - Maximum allowed errors before stopping (default: 5)
- `WaitForCompletion` - Wait for deployment completion (default: true)

**Usage Examples:**
```powershell
# Deploy to specific instances
.\Deploy-DSCAtScale.ps1 -ConfigurationName "WebServerConfig" -InstanceIds @("i-123", "i-456") -BatchSize 5

# Deploy with custom error tolerance
.\Deploy-DSCAtScale.ps1 -ConfigurationName "DatabaseConfig" -InstanceIds $instanceList -MaxErrors 10
```

### Get-DSCComplianceMetrics

**Purpose:** Collects and analyzes DSC compliance status across managed instances, providing detailed metrics and trend analysis.

**Key Features:**
- Comprehensive compliance reporting
- Historical trend analysis
- Export to multiple formats (CSV, JSON, HTML)
- CloudWatch metrics publishing
- Automated alerting capabilities

**Parameters:**
- `InstanceIds` - Target instances (optional, defaults to all managed instances)
- `ConfigurationName` - Specific configuration to check
- `OutputFormat` - Report format (CSV, JSON, HTML)
- `ExportPath` - Output file path
- `PublishMetrics` - Publish to CloudWatch (default: false)

**Usage Examples:**
```powershell
# Generate compliance report for all instances
.\Get-DSCComplianceMetrics.ps1 -OutputFormat "HTML" -ExportPath "C:\Reports\compliance.html"

# Check specific configuration compliance
.\Get-DSCComplianceMetrics.ps1 -ConfigurationName "WebServerConfig" -PublishMetrics
```

### Get-DSCPerformanceImpact

**Purpose:** Analyzes DSC performance impact across multiple Systems Manager managed instances, identifying resource bottlenecks and optimization opportunities.

**Key Features:**
- Resource usage analysis (CPU, Memory, Disk I/O)
- Performance trend identification
- Bottleneck detection
- Optimization recommendations
- Performance baseline establishment

**Parameters:**
- `InstanceIds` - Target instances for analysis
- `TimeRange` - Analysis time period (hours)
- `MetricTypes` - Specific metrics to analyze
- `ExportResults` - Save results to file
- `GenerateRecommendations` - Include optimization suggestions

**Usage Examples:**
```powershell
# Analyze performance for last 24 hours
.\Get-DSCPerformanceImpact.ps1 -InstanceIds $instances -TimeRange 24 -GenerateRecommendations

# Focus on specific metrics
.\Get-DSCPerformanceImpact.ps1 -MetricTypes @("CPU", "Memory") -ExportResults "C:\Reports\perf.csv"
```

### Get-SSMCompliance

**Purpose:** Generates comprehensive AWS Systems Manager compliance reports for managed instances, including patch compliance, association status, and inventory data.

**Key Features:**
- Multi-dimensional compliance reporting
- Patch compliance analysis
- Association status tracking
- Inventory data collection
- Custom compliance rules
- Automated remediation suggestions

**Parameters:**
- `InstanceIds` - Target instances
- `ComplianceTypes` - Types of compliance to check
- `OutputFormat` - Report format
- `IncludeRemediation` - Include remediation steps
- `FilterNonCompliant` - Show only non-compliant items

**Usage Examples:**
```powershell
# Full compliance report
.\Get-SSMCompliance.ps1 -OutputFormat "HTML" -IncludeRemediation

# Patch compliance only
.\Get-SSMCompliance.ps1 -ComplianceTypes @("Patch") -FilterNonCompliant
```

### Test-SystemsManagerSetup

**Purpose:** Performs comprehensive verification of AWS Systems Manager prerequisites and connectivity on Windows EC2 instances.

**Key Features:**
- SSM Agent status verification
- Network connectivity testing
- IAM role validation
- VPC endpoint testing
- Detailed diagnostic reporting
- Automated troubleshooting suggestions

**Parameters:**
- `InstanceId` - Target EC2 instance ID
- `RunDiagnostics` - Perform deep diagnostic tests
- `TestNetworking` - Test network connectivity
- `GenerateReport` - Create detailed report
- `FixIssues` - Attempt automatic issue resolution

**Usage Examples:**
```powershell
# Basic connectivity test
.\Test-SystemsManagerSetup.ps1 -InstanceId "i-1234567890abcdef0"

# Full diagnostic with auto-fix
.\Test-SystemsManagerSetup.ps1 -InstanceId "i-123" -RunDiagnostics -FixIssues
```

### Set-CISSecurityConfiguration

**Purpose:** Applies CIS (Center for Internet Security) security baseline configurations to Windows instances through Systems Manager.

**Key Features:**
- CIS benchmark compliance
- Automated security hardening
- Configuration validation
- Rollback capabilities
- Compliance reporting
- Custom policy support

**Parameters:**
- `InstanceIds` - Target instances
- `CISLevel` - CIS benchmark level (1 or 2)
- `Categories` - Security categories to apply
- `ValidateOnly` - Test mode without applying changes
- `CreateBackup` - Backup current settings

**Usage Examples:**
```powershell
# Apply Level 1 CIS benchmarks
.\Set-CISSecurityConfiguration.ps1 -InstanceIds $instances -CISLevel 1 -CreateBackup

# Validate configuration without applying
.\Set-CISSecurityConfiguration.ps1 -InstanceIds $instances -ValidateOnly
```

### New-SSMCacheDocument

**Purpose:** Creates or updates AWS Systems Manager documents for DSC configuration deployment with intelligent caching mechanisms.

**Key Features:**
- Document template creation
- Intelligent caching strategies
- Version management
- Document validation
- Performance optimization
- Automated testing

**Parameters:**
- `DocumentName` - Name for the SSM document
- `DocumentContent` - Document content or template path
- `CachingStrategy` - Caching approach (None, Basic, Advanced)
- `ValidateDocument` - Validate before creation
- `DocumentType` - Type of SSM document

**Usage Examples:**
```powershell
# Create cached DSC document
.\New-SSMCacheDocument.ps1 -DocumentName "CachedDSCConfig" -CachingStrategy "Advanced"

# Update existing document
.\New-SSMCacheDocument.ps1 -DocumentName "ExistingDoc" -DocumentContent "template.json"
```

### Get-MOFHash

**Purpose:** Calculates SHA256 hash values for MOF (Managed Object Format) files from local filesystem or S3 storage for integrity verification.

**Key Features:**
- Local and S3 file support
- SHA256 hash calculation
- Batch processing
- Integrity verification
- Hash comparison utilities
- Detailed logging

**Parameters:**
- `FilePath` - Local file path or S3 URI
- `S3Bucket` - S3 bucket name (if using S3)
- `S3Key` - S3 object key
- `OutputFormat` - Hash output format
- `CompareWith` - Compare with existing hash

**Usage Examples:**
```powershell
# Calculate hash for local file
.\Get-MOFHash.ps1 -FilePath "C:\DSC\config.mof"

# Calculate hash for S3 object
.\Get-MOFHash.ps1 -S3Bucket "my-dsc-bucket" -S3Key "configs/web-server.mof"
```

### generate-clean-json

**Purpose:** Processes and cleans JSON documents for AWS Systems Manager, ensuring proper formatting and validation.

**Key Features:**
- JSON validation and formatting
- Schema compliance checking
- Error detection and correction
- Batch processing
- Backup creation
- Format standardization

**Parameters:**
- `InputPath` - Source JSON file or directory
- `OutputPath` - Destination for cleaned JSON
- `ValidateSchema` - Validate against schema
- `CreateBackup` - Backup original files
- `RecursiveProcessing` - Process subdirectories

**Usage Examples:**
```powershell
# Clean single JSON file
.\generate-clean-json.ps1 -InputPath "document.json" -OutputPath "clean-document.json"

# Process entire directory
.\generate-clean-json.ps1 -InputPath "C:\Documents\" -RecursiveProcessing -CreateBackup
```

## Best Practices

### Security
- Always use IAM roles instead of hardcoded credentials
- Follow principle of least privilege for IAM permissions
- Enable CloudTrail logging for audit trails
- Use VPC endpoints for private subnet communications

### Performance
- Use appropriate batch sizes for large-scale operations
- Monitor CloudWatch metrics during script execution
- Implement proper error handling and retry logic
- Cache frequently accessed data when possible

### Monitoring
- Enable CloudWatch logging for all script executions
- Set up automated alerting for failed operations
- Use the provided dashboard for operational visibility
- Regularly review compliance and performance reports

## Troubleshooting

### Common Issues

**SSM Agent Not Responding**
```powershell
# Check agent status
.\Test-SystemsManagerSetup.ps1 -InstanceId "i-123" -RunDiagnostics
```

**Permission Denied Errors**
- Verify IAM role attachments
- Check VPC endpoint policies
- Validate security group rules

**DSC Configuration Failures**
```powershell
# Check DSC compliance status
.\Get-DSCComplianceMetrics.ps1 -InstanceIds @("i-123") -OutputFormat "JSON"
```

**Performance Issues**
```powershell
# Analyze performance impact
.\Get-DSCPerformanceImpact.ps1 -InstanceIds @("i-123") -TimeRange 24
```

### Log Locations
- PowerShell transcript logs: `$env:TEMP\SSM-Scripts\`
- CloudWatch logs: `/aws/ssm/powershell-scripts`
- Windows Event Log: `Applications and Services\AWS Systems Manager`

## Contributing

When contributing to these scripts:
1. Follow PowerShell best practices and style guidelines
2. Include comprehensive help documentation
3. Add appropriate error handling and logging
4. Test with both single instances and batch operations
5. Update this README with any new functionality

## License

These scripts are provided under the MIT License. See the LICENSE file for details.

---

*Last Updated: May 2025*
*Version: 2.0*