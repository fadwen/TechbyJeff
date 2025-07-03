# Find-UnknownSIDs Memory Management & Security Troubleshooting

## Memory Management Issues

### High Memory Usage
**Symptoms:**
- Script consumes excessive memory (>1GB)
- System becomes slow during execution
- Out of memory errors

**Solutions:**
1. Reduce batch size: `-BatchSize 50`
2. Lower memory threshold: `-MaxMemoryUsageMB 512`
3. Run against smaller OUs first
4. Use `-NoOutput` to reduce memory overhead

### Memory Leaks
**Symptoms:**
- Memory usage continuously increases
- Script doesn't release memory between operations

**Solutions:**
1. Ensure proper disposal of DirectoryEntry objects
2. Force garbage collection with lower threshold
3. Check for unclosed file handles in logs

## Security Validation Issues

### Protected SID Removal Blocked
**Symptoms:**
- "Protected SID detected and blocked" errors
- High-risk operations cancelled

**Solutions:**
1. Review blocked SIDs in security validation report
2. Use `-ExcludeSIDs` parameter for legitimate exclusions
3. Contact security team before overriding protections

### Critical Object Protection
**Symptoms:**
- "Critical AD object detected" warnings
- Elevated confirmation required

**Solutions:**
1. Use `-RequireElevatedConfirmation` for additional safety
2. Test in non-production environment first
3. Review critical object patterns in SecurityValidator class

### ACL Integrity Failures
**Symptoms:**
- "Removal would result in empty ACL" errors
- ACL backup integrity check failures

**Solutions:**
1. Validate ACL structure before removal
2. Check backup directory permissions
3. Verify SDDL hash consistency in backups

## Best Practices

### Memory Optimization
- Set appropriate memory limits based on environment
- Monitor memory usage in verbose mode
- Use smaller batch sizes for large domains

### Security Validation
- Never skip security validation in production
- Always test with `-WhatIf` first
- Maintain ACL backups with integrity checking
- Review security validation reports thoroughly

### Error Recovery
- Keep correlation IDs for troubleshooting
- Maintain detailed logs with security events
- Test restore procedures before production use
