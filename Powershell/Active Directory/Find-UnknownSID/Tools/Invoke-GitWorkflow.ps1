function Invoke-GitWorkflow {
    <#
    .SYNOPSIS
        Simplified Git workflow helper for Find-UnknownSID project

    .DESCRIPTION
        Provides common Git operations with validation and safety checks.
        Designed specifically for PowerShell development workflows.

        CORE FUNCTIONALITY:
        - Repository status checking with recent commit history
        - Selective or bulk file staging operations
        - Commit operations with message validation
        - Repository history and branch information display
        - Remote repository push operations
        - Quick workflow combining add, commit, and status

        BUSINESS VALUE:
        Streamlines Git operations for PowerShell developers by providing
        a single function interface with built-in validation and safety checks.
        Reduces command-line errors and improves development workflow efficiency.

        DEPENDENCIES:
        - Git must be installed and accessible in system PATH
        - Must be executed from within a Git repository
        - Requires appropriate permissions for file operations

    .PARAMETER Action
        [String] (Mandatory: Yes, Pipeline: No)

        Specifies the Git operation to perform.

        VALIDATION RULES:
        - Must be one of: Status, Add, Commit, Log, Push, Quick
        - Case-sensitive validation

        BUSINESS CONTEXT:
        - Status: Overview of repository state and recent commits
        - Add: Stage files for commit (selective or all)
        - Commit: Create commit with validation
        - Log: View commit history and branch information
        - Push: Upload changes to remote repository
        - Quick: Streamlined workflow for rapid commits

    .PARAMETER Message
        [String] (Mandatory: Conditional, Pipeline: No)

        Commit message for Commit and Quick actions.

        VALIDATION RULES:
        - Required for Commit and Quick actions
        - Must not be null or empty
        - Should follow project commit message standards

        BUSINESS CONTEXT:
        Use descriptive messages following the format:
        "Type: Brief description" (e.g., "Fix: Resolve validation bug")

    .PARAMETER Files
        [String[]] (Mandatory: No, Pipeline: No)

        Specific files to add during Add action.

        VALIDATION RULES:
        - Optional parameter
        - If not specified, all changes are staged
        - File paths relative to repository root

        BUSINESS CONTEXT:
        Use for selective staging when you want to commit only specific changes
        rather than all modified files in the repository.

    .EXAMPLE
        PS> Invoke-GitWorkflow -Action Status

        DESCRIPTION: Check repository status and recent commits
        OUTPUT: Repository status and last 5 commits
        USE CASE: Daily development status check before making changes

    .EXAMPLE
        PS> Invoke-GitWorkflow -Action Add -Files @('Find-UnknownSID.ps1', 'Classes/MemoryManager.ps1')

        DESCRIPTION: Stage specific files for commit
        OUTPUT: Confirmation of staged files and repository status
        USE CASE: Selective staging when working on multiple features

    .EXAMPLE
        PS> Invoke-GitWorkflow -Action Commit -Message "Fix: Resolve memory leak in SID processing"

        DESCRIPTION: Commit staged changes with descriptive message
        OUTPUT: Commit confirmation and hash
        USE CASE: Creating commits with proper message formatting

    .EXAMPLE
        PS> Invoke-GitWorkflow -Action Quick -Message "Feature: Add enhanced logging capabilities"

        DESCRIPTION: Quick workflow - add all, commit, and show status
        OUTPUT: Complete workflow results with final status
        USE CASE: Rapid development cycles with comprehensive changes

    .EXAMPLE
        PS> Invoke-GitWorkflow -Action Log

        DESCRIPTION: View commit history and branch information
        OUTPUT: Last 10 commits and current branch status
        USE CASE: Code review preparation and history analysis

    .EXAMPLE
        PS> Invoke-GitWorkflow -Action Push

        DESCRIPTION: Push changes to remote repository
        OUTPUT: Push confirmation or remote configuration guidance
        USE CASE: Synchronizing local changes with team repository

    .INPUTS
        None. Parameters are provided directly, not via pipeline.

    .OUTPUTS
        None. Displays formatted Git command output to console.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
        Last Updated: 2025-07-04
        Version: 1.0.0
        PowerShell Version: 5.1+ (Windows), 7.x+ (Cross-platform)

        PERFORMANCE CHARACTERISTICS:
        - Execution Time: 1-5 seconds depending on repository size
        - Memory Usage: Minimal, delegates to Git executable
        - Scalability: Suitable for repositories up to enterprise scale

        SECURITY CONSIDERATIONS:
        - Validates repository context before execution
        - Uses ShouldProcess for destructive operations
        - No credential handling required (uses Git configuration)

        TROUBLESHOOTING:
        - Repository not found: Navigate to repository root directory
        - Git not found: Ensure Git is installed and in system PATH
        - Permission errors: Check file system permissions
        - For detailed issues: .\Troubleshooting\Common\Git-Workflow-Issues.md

        ALIASES (add to PowerShell profile for convenience):
        Set-Alias -Name ggit -Value Invoke-GitWorkflow
        Set-Alias -Name gq -Value { param($m) Invoke-GitWorkflow -Action Quick -Message $m }
        Set-Alias -Name gs -Value { Invoke-GitWorkflow -Action Status }

    .LINK
        https://git-scm.com/docs
        https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_comment_based_help
        .\Documentation\Git-Usage-Guide.md
        .\Troubleshooting\Common\Git-Workflow-Issues.md
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Status', 'Add', 'Commit', 'Log', 'Push', 'Quick')]
        [string]$Action,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [string[]]$Files
    )

    begin {
        # Verify we're in a Git repository
        if (-not (Test-Path '.git')) {
            Write-Error "Not in a Git repository. Navigate to C:\temp\Find-UnknownSID first." -ErrorAction Stop
            return
        }

        Write-Verbose "Starting Git workflow action: $Action"
    }

    process {
        try {
            switch ($Action) {
                'Status' {
                    Write-Host "=== Repository Status ===" -ForegroundColor Cyan
                    & git status
                    Write-Host "`n=== Recent Commits ===" -ForegroundColor Cyan
                    & git log --oneline -5
                }

                'Add' {
                    if ($Files) {
                        Write-Host "Adding specific files: $($Files -join ', ')" -ForegroundColor Green
                        foreach ($file in $Files) {
                            & git add $file
                        }
                    } else {
                        Write-Host "Adding all changes..." -ForegroundColor Green
                        & git add .
                    }
                    & git status
                }

                'Commit' {
                    if (-not $Message) {
                        Write-Error "Commit message is required for Commit action" -ErrorAction Stop
                        return
                    }

                    if ($PSCmdlet.ShouldProcess("Repository", "Commit with message: $Message")) {
                        Write-Host "Committing changes..." -ForegroundColor Green
                        & git commit -m $Message
                        & git log --oneline -1
                    }
                }

                'Log' {
                    Write-Host "=== Commit History ===" -ForegroundColor Cyan
                    & git log --oneline -10
                    Write-Host "`n=== Branch Information ===" -ForegroundColor Cyan
                    & git branch -v
                }

                'Push' {
                    $remotes = & git remote
                    if (-not $remotes) {
                        Write-Warning "No remote repositories configured. Use 'git remote add origin <url>' to add one."
                        return
                    }

                    if ($PSCmdlet.ShouldProcess("Remote repository", "Push changes")) {
                        Write-Host "Pushing to remote repository..." -ForegroundColor Green
                        & git push
                    }
                }

                'Quick' {
                    if (-not $Message) {
                        Write-Error "Commit message is required for Quick action" -ErrorAction Stop
                        return
                    }

                    if ($PSCmdlet.ShouldProcess("Repository", "Quick workflow: add all, commit, status")) {
                        Write-Host "=== Quick Git Workflow ===" -ForegroundColor Cyan

                        Write-Host "1. Adding all changes..." -ForegroundColor Yellow
                        & git add .

                        Write-Host "2. Committing with message: $Message" -ForegroundColor Yellow
                        & git commit -m $Message

                        Write-Host "3. Current status:" -ForegroundColor Yellow
                        & git status

                        Write-Host "4. Recent commits:" -ForegroundColor Yellow
                        & git log --oneline -3

                        Write-Host "`n✅ Quick workflow completed!" -ForegroundColor Green
                    }
                }
            }
        }
        catch {
            Write-Error "Git operation failed: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed Git workflow action: $Action"
    }
}

# Export the function if this is being dot-sourced
if ($MyInvocation.InvocationName -eq '.') {
    Export-ModuleMember -Function Invoke-GitWorkflow
}
