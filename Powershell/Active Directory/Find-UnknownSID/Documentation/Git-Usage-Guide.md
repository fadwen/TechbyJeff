# Git Usage Guide for Find-UnknownSID Project

## Repository Status
✅ **Git Repository Initialized Successfully**
- Repository Location: `C:\temp\Find-UnknownSID`
- Initial Commit: `ce15a35` - Contains all project files and documentation
- Branch: `master` (default)
- Status: Clean working tree

## Basic Git Commands

### Daily Workflow Commands

#### Check Status
```powershell
git status
```
Shows which files are modified, staged, or untracked.

#### Stage Changes
```powershell
# Stage specific files
git add Find-UnknownSID.ps1
git add Classes/

# Stage all changes
git add .

# Stage with pattern
git add *.ps1
```

#### Commit Changes
```powershell
# Commit with inline message
git commit -m "Fix: Resolve SID validation issue"

# Commit with detailed message
git commit -m "Feature: Add memory optimization

- Implement streaming results processing
- Reduce memory footprint by 40%
- Add garbage collection triggers
- Update documentation"
```

#### View History
```powershell
# Compact view
git log --oneline

# Detailed view
git log

# Graph view
git log --graph --oneline --all

# Show changes in last commit
git show
```

### File Management

#### View Changes
```powershell
# See what changed (unstaged)
git diff

# See staged changes
git diff --staged

# Compare specific files
git diff Find-UnknownSID.ps1
```

#### Undo Changes
```powershell
# Discard unstaged changes to file
git checkout -- Find-UnknownSID.ps1

# Unstage file (keep changes)
git reset HEAD Find-UnknownSID.ps1

# Undo last commit (keep changes)
git reset --soft HEAD~1

# Undo last commit (discard changes) - DANGEROUS
git reset --hard HEAD~1
```

### Branching (Future Use)

#### Create and Switch Branches
```powershell
# Create and switch to new branch
git checkout -b feature/memory-optimization

# Switch to existing branch
git checkout master

# List branches
git branch

# Delete branch
git branch -d feature/memory-optimization
```

#### Merge Changes
```powershell
# Switch to target branch
git checkout master

# Merge feature branch
git merge feature/memory-optimization
```

## Project-Specific Guidelines

### Commit Message Format
Follow this format for consistency:
```
Type: Brief description (50 chars max)

Detailed explanation if needed:
- What changed
- Why it changed
- Impact on functionality
- Breaking changes (if any)
```

**Types:**
- `Feature:` - New functionality
- `Fix:` - Bug fixes
- `Refactor:` - Code restructuring
- `Docs:` - Documentation updates
- `Test:` - Test additions/modifications
- `Security:` - Security-related changes
- `Performance:` - Performance improvements

### File Organization
The repository includes these key areas:
- **Root**: Main script (`Find-UnknownSID.ps1`)
- **Classes/**: PowerShell class definitions
- **Private/**: Internal functions and modules
- **Tests/**: Pester test suites
- **Documentation/**: Project documentation
- **Tools/**: Utility scripts
- **Troubleshooting/**: Support documentation

### What to Commit
✅ **Always Commit:**
- Source code changes
- Documentation updates
- Test modifications
- Configuration changes
- New features

❌ **Never Commit:**
- Log files (`*.log`)
- Temporary files (`*.tmp`)
- Personal settings
- Sensitive credentials
- Large binary files

*Note: `.gitignore` is already configured to handle these exclusions.*

### Backup Integration
Since you have a robust backup system:
1. **Git complements** your timestamped backups
2. **Use Git for** version tracking and collaboration
3. **Use backups for** disaster recovery and point-in-time restoration

## Remote Repository Setup (Optional)

### GitHub Integration
To sync with GitHub:

1. **Create GitHub Repository**
   - Go to github.com
   - Create new repository: `Find-UnknownSID`
   - Don't initialize with README (we already have one)

2. **Add Remote**
   ```powershell
   git remote add origin https://github.com/yourusername/Find-UnknownSID.git
   ```

3. **Push to GitHub**
   ```powershell
   git push -u origin master
   ```

### Azure DevOps Integration
To sync with Azure DevOps:
```powershell
git remote add origin https://dev.azure.com/yourorg/yourproject/_git/Find-UnknownSID
git push -u origin master
```

## Security Considerations

### Credential Safety
- Never commit passwords or API keys
- Use environment variables for sensitive data
- Review commits before pushing to remote repositories

### File Permissions
- Maintain Windows file permissions
- Be cautious with executable permissions on scripts

## Maintenance Tasks

### Regular Maintenance
```powershell
# Clean up repository
git gc

# Verify repository integrity
git fsck

# Show repository statistics
git count-objects -v
```

### Backup Git Repository
Your existing backup system will capture the `.git` folder, but for additional safety:
```powershell
# Create bundle backup
git bundle create Find-UnknownSID-backup.bundle master

# Restore from bundle (if needed)
git clone Find-UnknownSID-backup.bundle restored-repo
```

## Quick Reference Card

| Command | Purpose |
|---------|---------|
| `git status` | Check repository status |
| `git add .` | Stage all changes |
| `git commit -m "message"` | Commit changes |
| `git log --oneline` | View commit history |
| `git diff` | See unstaged changes |
| `git checkout -- file` | Discard file changes |
| `git push` | Upload to remote (if configured) |
| `git pull` | Download from remote (if configured) |

## Support

### Common Issues
- **Line Ending Warnings**: Already configured with `core.autocrlf true`
- **Large Files**: Use `.gitignore` to exclude (already configured)
- **Merge Conflicts**: Resolve manually in affected files

### Getting Help
```powershell
# Git help system
git help
git help commit
git help status

# Show current configuration
git config --list
```

---

**Repository Configured By:** Jeffrey Stuhr
**Date:** $(Get-Date)
**Git Version:** $(git --version)
**Initial Commit:** ce15a35
