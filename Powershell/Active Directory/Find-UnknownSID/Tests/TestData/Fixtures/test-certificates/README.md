# Test certificates for SSL/TLS and authentication testing
# 
# This directory contains test certificates for various security scenarios:
# 
# 1. test-ssl-cert.pfx - Self-signed certificate for SSL/TLS testing
#    - Subject: CN=test.contoso.local
#    - Valid: 2024-01-01 to 2025-01-01
#    - Private key included
#    - Password: TestPassword123!
# 
# 2. test-client-cert.pfx - Client certificate for mutual authentication
#    - Subject: CN=FindUnknownSID-Client
#    - Valid: 2024-01-01 to 2025-01-01
#    - Private key included
#    - Password: ClientPassword123!
# 
# 3. test-ca-cert.crt - Test Certificate Authority root certificate
#    - Subject: CN=Test-CA, O=Contoso Test, C=US
#    - Self-signed CA certificate
#    - Used to validate other test certificates
# 
# 4. expired-cert.pfx - Expired certificate for negative testing
#    - Subject: CN=expired.test.local
#    - Valid: 2023-01-01 to 2023-06-01 (EXPIRED)
#    - Password: ExpiredPassword123!
# 
# 5. invalid-cert.pfx - Invalid certificate for error testing
#    - Subject: CN=invalid.test.local
#    - Corrupted certificate data
#    - Password: InvalidPassword123!
# 
# Security Note:
# These are TEST CERTIFICATES ONLY and should never be used in production.
# All private keys are included for testing purposes.
# 
# Usage in Tests:
# - SSL/TLS connection testing
# - Certificate validation scenarios
# - Authentication testing
# - Error handling with invalid certificates
# - Performance testing with certificate operations
# 
# Test Scenarios:
# 1. Valid certificate - should succeed
# 2. Expired certificate - should fail with specific error
# 3. Invalid certificate - should fail with parsing error
# 4. Wrong password - should fail with authentication error
# 5. Missing certificate - should fail with file not found error
# 
# PowerShell Usage Examples:
# $cert = Get-PfxCertificate -FilePath "test-ssl-cert.pfx" -Password (ConvertTo-SecureString "TestPassword123!" -AsPlainText -Force)
# $clientCert = Get-PfxCertificate -FilePath "test-client-cert.pfx" -Password (ConvertTo-SecureString "ClientPassword123!" -AsPlainText -Force)
# 
# For security testing, use the expired and invalid certificates to verify
# proper error handling and certificate validation logic.

Test Certificate Inventory:
=========================

Certificate Name       | Type    | Status  | Password           | Use Case
--------------------- | ------- | ------- | ------------------ | ---------
test-ssl-cert.pfx     | SSL/TLS | Valid   | TestPassword123!   | HTTPS connections
test-client-cert.pfx  | Client  | Valid   | ClientPassword123! | Client authentication  
test-ca-cert.crt      | CA Root | Valid   | N/A                | Certificate validation
expired-cert.pfx      | SSL/TLS | Expired | ExpiredPassword123!| Negative testing
invalid-cert.pfx      | SSL/TLS | Invalid | InvalidPassword123!| Error testing

Generation Commands (for reference):
===================================

# Self-signed SSL certificate
$cert = New-SelfSignedCertificate -DnsName "test.contoso.local" -CertStoreLocation "cert:\LocalMachine\My" -NotAfter (Get-Date).AddYears(1)
Export-PfxCertificate -Cert $cert -FilePath "test-ssl-cert.pfx" -Password (ConvertTo-SecureString "TestPassword123!" -AsPlainText -Force)

# Client certificate
$clientCert = New-SelfSignedCertificate -Subject "CN=FindUnknownSID-Client" -CertStoreLocation "cert:\LocalMachine\My" -KeyUsage DigitalSignature,KeyEncipherment -NotAfter (Get-Date).AddYears(1)
Export-PfxCertificate -Cert $clientCert -FilePath "test-client-cert.pfx" -Password (ConvertTo-SecureString "ClientPassword123!" -AsPlainText -Force)

Important Notes:
===============
- These certificates are for TESTING ONLY
- Never use in production environments
- Passwords are hardcoded for test repeatability
- Certificates should be regenerated if they expire
- Add new certificates as needed for additional test scenarios
