function New-SecureRandomPassword {
    <#
    .SYNOPSIS
        Generates a cryptographically secure random password

    .DESCRIPTION
        Creates a random password using cryptographically secure random number generation
        that meets domain complexity requirements. Ensures at least one character from each
        required character set (uppercase, lowercase, numbers, special characters).

    .PARAMETER Length
        Length of the password to generate (minimum 8, default 16)

    .EXAMPLE
        New-SecureRandomPassword -Length 16
        Generates a 16-character secure password

    .EXAMPLE
        $password = New-SecureRandomPassword -Length 24
        Generates a 24-character secure password for high-security service accounts

    .OUTPUTS
        String containing the generated password that meets complexity requirements

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-03

        SECURITY CONSIDERATIONS:
        - Uses cryptographically secure random number generation
        - Ensures complexity requirements are met
        - Disposes of RNG resources properly
        - Suitable for service account passwords
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [ValidateRange(8, 128)]
        [int]$Length = 16
    )

    begin {
        Write-Verbose "Generating secure random password of length: $Length"
    }

    process {
        # Define character sets for complexity requirements
        $upperCase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        $lowerCase = 'abcdefghijklmnopqrstuvwxyz'
        $numbers = '0123456789'
        $specialChars = '!@#$%^&*()_+-=[]{}|;:,.<>?'
        
        # Combine all character sets
        $allChars = $upperCase + $lowerCase + $numbers + $specialChars
        
        # Create cryptographic random number generator
        $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
        
        try {
            # Generate password ensuring at least one character from each set
            $password = @()
            
            # Ensure at least one character from each required set
            $password += Get-RandomCharFromSet -CharSet $upperCase -RNG $rng
            $password += Get-RandomCharFromSet -CharSet $lowerCase -RNG $rng
            $password += Get-RandomCharFromSet -CharSet $numbers -RNG $rng
            $password += Get-RandomCharFromSet -CharSet $specialChars -RNG $rng
            
            # Fill remaining positions with random characters from all sets
            for ($i = 4; $i -lt $Length; $i++) {
                $password += Get-RandomCharFromSet -CharSet $allChars -RNG $rng
            }
            
            # Shuffle the password array to randomize positions
            $shuffledPassword = $password | Sort-Object { Get-SecureRandom -RNG $rng }
            
            $generatedPassword = ($shuffledPassword -join '')
            Write-Verbose "Password generated successfully with complexity requirements met"
            
            return $generatedPassword
        }
        finally {
            $rng.Dispose()
        }
    }
}

function Get-RandomCharFromSet {
    <#
    .SYNOPSIS
        Gets a random character from a character set using cryptographic randomness

    .DESCRIPTION
        Helper function that selects a random character from a specified character set
        using cryptographically secure random number generation.

    .PARAMETER CharSet
        The character set to select from

    .PARAMETER RNG
        The cryptographic random number generator instance

    .OUTPUTS
        Single character from the specified character set

    .NOTES
        This is a helper function for New-SecureRandomPassword and should not be called directly
        outside of password generation operations.
    #>
    [CmdletBinding()]
    [OutputType([char])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CharSet,
        
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.RNGCryptoServiceProvider]$RNG
    )
    
    $randomIndex = Get-SecureRandom -RNG $RNG -Max $CharSet.Length
    return $CharSet[$randomIndex]
}

function Get-SecureRandom {
    <#
    .SYNOPSIS
        Generates a cryptographically secure random number

    .DESCRIPTION
        Helper function that generates a cryptographically secure random number
        within a specified range using RNGCryptoServiceProvider.

    .PARAMETER RNG
        The cryptographic random number generator instance

    .PARAMETER Max
        Maximum value for the random number (exclusive)

    .OUTPUTS
        Cryptographically secure random integer

    .NOTES
        This is a helper function for password generation and should not be called directly
        outside of cryptographic operations.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.RNGCryptoServiceProvider]$RNG,
        
        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Max = [int]::MaxValue
    )
    
    $bytes = New-Object byte[] 4
    $RNG.GetBytes($bytes)
    $randomValue = [System.BitConverter]::ToUInt32($bytes, 0)
    return $randomValue % $Max
}
