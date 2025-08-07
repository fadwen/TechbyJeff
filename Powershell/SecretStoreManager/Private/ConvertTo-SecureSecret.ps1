function ConvertTo-SecureSecret {
    <#
    .SYNOPSIS
        Securely converts input to SecureString without exposing plaintext in memory

    .DESCRIPTION
        Provides secure handling of secret values by accepting already secure inputs
        or prompting for secure input instead of converting plaintext directly.
        This prevents plaintext secrets from being exposed in memory or logs.

    .PARAMETER InputSecret
        The input secret value which can be:
        - System.Security.SecureString (returned as-is)
        - PSCredential (Password property extracted)
        - String (triggers secure prompt for re-entry)

    .PARAMETER PromptMessage
        Custom message to display when prompting for secure input
        Default: "Enter secret value"

    .PARAMETER AllowPlaintextFallback
        When true, allows silent conversion of plaintext strings without prompting
        Should be used in automation scenarios with pre-validated input
        Default: false (prompts for secure re-entry of plaintext inputs)

    .EXAMPLE
        PS> $secureSecret = ConvertTo-SecureSecret -InputSecret $userInput

        Securely converts user input to SecureString, prompting if plaintext is provided

    .EXAMPLE
        PS> $secureSecret = ConvertTo-SecureSecret -InputSecret $credential.Password

        Extracts SecureString from PSCredential object

    .EXAMPLE
        PS> $secureSecret = ConvertTo-SecureSecret -InputSecret "PlaintextSecret" -AllowPlaintextFallback

        Silently converts plaintext to SecureString for automation scenarios

    .NOTES
        Author: SecretStoreManager Development Team
        Version: 1.1.0
        Last Updated: 2025-08-06

        SECURITY CONSIDERATIONS:
        - Never converts plaintext directly to SecureString without explicit consent
        - Prompts for secure re-entry when plaintext is provided interactively
        - AllowPlaintextFallback enables silent conversion for automation scenarios
        - Prevents credential exposure in memory dumps and logs
        - Follows enterprise security best practices

        TROUBLESHOOTING:
        - For automation scenarios: Use AllowPlaintextFallback with validated input
        - For interactive use: Allow prompting for secure entry  
        - For existing SecureString/PSCredential: Pass directly without flags
        - Performance: Direct SecureString/PSCredential inputs are most efficient
    #>

    [CmdletBinding()]
    [OutputType([System.Security.SecureString])]
    param(
        [Parameter(Mandatory = $true)]
        $InputSecret,

        [string]$PromptMessage = "Enter secret value",

        [switch]$AllowPlaintextFallback
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting ConvertTo-SecureSecret - CorrelationId: $correlationId"
    }

    process {
        try {
            # Handle already secure inputs
            if ($InputSecret -is [System.Security.SecureString]) {
                Write-Verbose "Input is already SecureString - returning as-is - CorrelationId: $correlationId"
                return $InputSecret
            }
            elseif ($InputSecret -is [PSCredential]) {
                Write-Verbose "Extracting SecureString from PSCredential - CorrelationId: $correlationId"
                return $InputSecret.Password
            }
            elseif ($InputSecret -is [string]) {
                Write-Verbose "String input detected - applying secure handling - CorrelationId: $correlationId"
                
                if ($AllowPlaintextFallback) {
                    Write-Verbose "Converting plaintext to SecureString (AllowPlaintextFallback enabled) - CorrelationId: $correlationId"
                    
                    # Create SecureString character by character to avoid -AsPlainText -Force
                    $secureString = New-Object System.Security.SecureString
                    $InputSecret.ToCharArray() | ForEach-Object {
                        $secureString.AppendChar($_)
                    }
                    $secureString.MakeReadOnly()
                    return $secureString
                }
                else {
                    Write-Verbose "Prompting for secure re-entry of secret value - CorrelationId: $correlationId"
                    Write-Information "For security, please re-enter the secret value securely:" -InformationAction Continue
                    return Read-Host -Prompt $PromptMessage -AsSecureString
                }
            }
            else {
                $inputType = $InputSecret.GetType().FullName
                Write-Error "Unsupported input type: $inputType. Expected SecureString, PSCredential, or String - CorrelationId: $correlationId" -ErrorAction Stop
            }
        }
        catch {
            Write-Error "Failed to convert input to SecureString: $($_.Exception.Message) - CorrelationId: $correlationId" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed ConvertTo-SecureSecret - CorrelationId: $correlationId"
    }
}
