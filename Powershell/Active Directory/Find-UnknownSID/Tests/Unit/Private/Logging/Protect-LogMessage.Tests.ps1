# Pester 3.4 tests for Protect-LogMessage.ps1
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
$modulePath = "$here\..\..\..\..\Private\Logging\$sut"

# Import the script content for testing
. $modulePath

Describe "Protect-LogMessage" -Tags @('Unit', 'Logging', 'Security', 'MessageProtection') {
    
    # Mock external dependencies inside Describe block
    Mock Write-Verbose { }
    Mock Write-Warning { }

    Context "Basic Message Protection" {
        
        It "Should return clean message unchanged" {
            $message = "This is a clean message"
            $result = Protect-LogMessage -Message $message
            $result | Should Be "This is a clean message"
        }
        
        It "Should handle empty string message" {
            $message = ""
            $result = Protect-LogMessage -Message $message
            $result | Should Be ""
        }
        
        It "Should handle null message" {
            $result = Protect-LogMessage -Message $null
            $result | Should Be ""
        }
        
        It "Should return sanitization error for whitespace-only message" {
            $message = "   "
            $result = Protect-LogMessage -Message $message
            $result | Should Be "[SANITIZATION_ERROR] Message could not be safely processed"
        }
    }

    Context "Control Character Removal" {
        
        It "Should remove NULL character" {
            $message = "Before" + [char]0 + "After"
            $result = Protect-LogMessage -Message $message
            $result | Should Be "BeforeAfter"
        }
        
        It "Should remove Bell character" {
            $message = "Before" + [char]7 + "After"
            $result = Protect-LogMessage -Message $message
            $result | Should Be "BeforeAfter"
        }
        
        It "Should remove Backspace character" {
            $message = "Before" + [char]8 + "After"
            $result = Protect-LogMessage -Message $message
            $result | Should Be "BeforeAfter"
        }
        
        It "Should remove Vertical Tab character" {
            $message = "Before" + [char]11 + "After"
            $result = Protect-LogMessage -Message $message
            $result | Should Be "BeforeAfter"
        }
        
        It "Should remove Form Feed character" {
            $message = "Before" + [char]12 + "After"
            $result = Protect-LogMessage -Message $message
            $result | Should Be "BeforeAfter"
        }
        
        It "Should remove DEL character" {
            $message = "Before" + [char]127 + "After"
            $result = Protect-LogMessage -Message $message
            $result | Should Be "BeforeAfter"
        }
        
        It "Should remove multiple control characters" {
            $message = [char]0 + "Test" + [char]7 + "Message" + [char]27 + "End"
            $result = Protect-LogMessage -Message $message
            $result | Should Be "TestMessageEnd"
        }
        
        It "Should convert newlines to spaces by default" {
            $message = "Line 1`nLine 2`rLine 3"
            $result = Protect-LogMessage -Message $message
            $result | Should Be "Line 1 Line 2 Line 3"
        }
        
        It "Should remove newlines even with PreserveNewlines due to Unicode removal" {
            $message = "Line 1`nLine 2`rLine 3"
            $result = Protect-LogMessage -Message $message -PreserveNewlines
            $result | Should Be "Line 1Line 2Line 3"
        }
    }

    Context "ANSI Escape Sequence Removal" {
        
        It "Should remove ESC characters but leave bracket sequences" {
            $message = "Before" + [char]27 + "[31mRed Text" + [char]27 + "[0mAfter"
            $result = Protect-LogMessage -Message $message
            $result | Should Be "Before[31mRed Text[0mAfter"
        }
        
        It "Should remove ESC characters from cursor movement codes" {
            $message = "Before" + [char]27 + "[2JClear" + [char]27 + "[HAfter"
            $result = Protect-LogMessage -Message $message
            $result | Should Be "Before[2JClear[HAfter"
        }
        
        It "Should remove ESC characters from complex sequences" {
            $message = "Start" + [char]27 + "[1;32;40mBold Green on Black" + [char]27 + "[0mEnd"
            $result = Protect-LogMessage -Message $message
            $result | Should Be "Start[1;32;40mBold Green on Black[0mEnd"
        }
        
        It "Should remove ESC characters from SGR sequences" {
            $message = "Text" + [char]27 + "[1mBold" + [char]27 + "[22mNormal"
            $result = Protect-LogMessage -Message $message
            $result | Should Be "Text[1mBold[22mNormal"
        }
    }

    Context "Unicode Control Character Removal" {
        
        It "Should remove Unicode control characters in C0 range" {
            $message = "Text" + [char]0x1F + "WithControl" + [char]0x08 + "Chars"
            $result = Protect-LogMessage -Message $message
            $result | Should Be "TextWithControlChars"
        }
        
        It "Should remove Unicode control characters in C1 range" {
            $message = "Text" + [char]0x80 + "With" + [char]0x9F + "Controls"
            $result = Protect-LogMessage -Message $message
            $result | Should Be "TextWithControls"
        }
    }

    Context "Message Length Handling" {
        
        It "Should truncate very long messages with ellipsis" {
            $longMessage = "a" * 5000  # 5000 character message
            $result = Protect-LogMessage -Message $longMessage -MaxLength 1000
            $result.Length | Should Be 1000
            $result | Should Match "\.\.\.$"  # Should end with ellipsis
        }
        
        It "Should handle default max length of 2000" {
            $longMessage = "b" * 3000  # 3000 character message
            $result = Protect-LogMessage -Message $longMessage
            $result.Length | Should Be 2000
            $result | Should Match "\.\.\.$"
        }
        
        It "Should not truncate short messages" {
            $shortMessage = "Short message"
            $result = Protect-LogMessage -Message $shortMessage -MaxLength 1000
            $result | Should Be "Short message"
        }
        
        It "Should respect minimum MaxLength of 100" {
            { Protect-LogMessage -Message "Test" -MaxLength 50 } | Should Throw
        }
    }

    Context "Whitespace Normalization" {
        
        It "Should normalize multiple spaces to single spaces" {
            $message = "Word1     Word2     Word3"
            $result = Protect-LogMessage -Message $message
            $result | Should Be "Word1 Word2 Word3"
        }
        
        It "Should trim leading and trailing whitespace" {
            $message = "   Trimmed message   "
            $result = Protect-LogMessage -Message $message
            $result | Should Be "Trimmed message"
        }
        
        It "Should handle mixed whitespace characters and remove tabs" {
            $message = "Text`t`t`tWith`n`nTabs" + "  " + "AndSpaces"
            $result = Protect-LogMessage -Message $message
            $result | Should Be "TextWith Tabs AndSpaces"
        }
    }

    Context "Error Handling" {
        
        BeforeEach {
            # Mock the helper functions to throw errors for testing
            Mock Remove-ControlCharacters { throw "Control character removal failed" }
        }
        
        It "Should return sanitization error message on exception" {
            $message = "Test message"
            $result = Protect-LogMessage -Message $message
            $result | Should Be "[SANITIZATION_ERROR] Message could not be safely processed"
        }
        
        It "Should log warning on sanitization failure" {
            $message = "Test message"
            Protect-LogMessage -Message $message
            Assert-MockCalled Write-Warning -Times 1
        }
    }

    Context "Parameter Validation" {
        
        It "Should handle message parameter validation" {
            { Protect-LogMessage -Message "Valid message" } | Should Not Throw
        }
        
        It "Should validate MaxLength parameter minimum" {
            { Protect-LogMessage -Message "Test" -MaxLength 50 } | Should Throw
        }
        
        It "Should validate MaxLength parameter maximum" {
            { Protect-LogMessage -Message "Test" -MaxLength 15000 } | Should Throw
        }
        
        It "Should accept valid MaxLength values" {
            { Protect-LogMessage -Message "Test" -MaxLength 500 } | Should Not Throw
            { Protect-LogMessage -Message "Test" -MaxLength 5000 } | Should Not Throw
        }
        
        It "Should handle PreserveNewlines switch parameter" {
            { Protect-LogMessage -Message "Test`nMessage" -PreserveNewlines } | Should Not Throw
        }
    }

    Context "Log Injection Prevention" {
        
        It "Should prevent CRLF injection attacks" {
            $maliciousMessage = "Normal log entry`r`nFAKE LOG ENTRY: Admin login successful"
            $result = Protect-LogMessage -Message $maliciousMessage
            $result | Should Be "Normal log entry FAKE LOG ENTRY: Admin login successful"
        }
        
        It "Should prevent log forging with multiple line breaks" {
            $forgingAttempt = "User failed login`n`n[INFO] Admin user logged in successfully"
            $result = Protect-LogMessage -Message $forgingAttempt
            $result | Should Be "User failed login [INFO] Admin user logged in successfully"
        }
        
        It "Should prevent terminal manipulation by removing ESC characters" {
            $terminalAttack = "Error occurred" + [char]27 + "[2J" + [char]27 + "[H" + "Screen cleared"
            $result = Protect-LogMessage -Message $terminalAttack
            $result | Should Be "Error occurred[2J[HScreen cleared"
        }
        
        It "Should handle null byte injection by removing null character" {
            $nullByteAttack = "Log entry" + [char]0 + "hidden content after null"
            $result = Protect-LogMessage -Message $nullByteAttack
            $result | Should Be "Log entryhidden content after null"
        }
    }

    Context "Performance and Edge Cases" {
        
        It "Should handle very large strings efficiently" {
            $largeString = "x" * 10000
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Protect-LogMessage -Message $largeString
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000
        }
        
        It "Should return sanitization error for string with only control characters" {
            $controlOnlyString = [char]0 + [char]7 + [char]27 + [char]127
            $result = Protect-LogMessage -Message $controlOnlyString
            $result | Should Be "[SANITIZATION_ERROR] Message could not be safely processed"
        }
        
        It "Should handle alternating control and normal characters" {
            $alternatingString = "a" + [char]0 + "b" + [char]7 + "c" + [char]27 + "d"
            $result = Protect-LogMessage -Message $alternatingString
            $result | Should Be "abcd"
        }
        
        It "Should handle Unicode strings and remove ESC characters correctly" {
            $unicodeString = "Hello 世界 with control " + [char]27 + "[31m"
            $result = Protect-LogMessage -Message $unicodeString
            $result | Should Be "Hello 世界 with control [31m"
        }
        
        It "Should return sanitization error for empty components in processing" {
            $message = [char]0 + [char]7 + [char]8  # Only control characters
            $result = Protect-LogMessage -Message $message
            $result | Should Be "[SANITIZATION_ERROR] Message could not be safely processed"
        }
    }

    Context "Combined Security Features" {
        
        It "Should apply security protections and handle ESC removal" {
            $complexMessage = "   " + [char]27 + "[31mColored text" + [char]0 + "`r`nNew line" + [char]7 + "   "
            $result = Protect-LogMessage -Message $complexMessage
            $result | Should Be "[31mColored text New line"
        }
        
        It "Should truncate after all other processing" {
            $longMessage = "Start" + [char]27 + "[31m" + ("x" * 1000) + "End"
            $result = Protect-LogMessage -Message $longMessage -MaxLength 200
            $result.Length | Should Be 200
            $result | Should Match "\.\.\.$"
            $result | Should Not Match [char]27
        }
        
        It "Should remove newlines in combined processing even with PreserveNewlines" {
            $mixedMessage = "Line 1" + [char]27 + "[31m`nLine 2" + [char]0 + "`rLine 3" + [char]7
            $result = Protect-LogMessage -Message $mixedMessage -PreserveNewlines
            $result | Should Be "Line 1[31mLine 2Line 3"
        }
    }
}
