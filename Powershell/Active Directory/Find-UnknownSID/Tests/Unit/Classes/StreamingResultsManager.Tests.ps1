#Requires -Version 5.1

# Import the class
$ModuleRoot = "C:\Users\Administrator\TechbyJeff\Powershell\Active Directory\Find-UnknownSID"
. "$ModuleRoot\Classes\StreamingResultsManager.ps1"

Describe "StreamingResultsManager Tests" {
    Context "Basic Tests" {
        It "Should create instance with 3-argument constructor" {
            $testDir = Join-Path $env:TEMP "StreamingResultsManagerTest_$(Get-Random)"
            $manager = [StreamingResultsManager]::new($testDir, 100, $true)

            $manager | Should Not BeNullOrEmpty
            $manager.TempDirectory | Should Be $testDir
            $manager.BatchSize | Should Be 100
            $manager.WhatIfMode | Should Be $true
            $manager.CurrentBatch | Should Be 0
            $manager.Disposed | Should Be $false
        }

        It "Should add result successfully" {
            $testDir = Join-Path $env:TEMP "StreamingResultsManagerTest_$(Get-Random)"
            $manager = [StreamingResultsManager]::new($testDir, 50, $true)
            $result = [PSCustomObject]@{ Name = "Test"; Value = 123 }

            $manager.AddResult($result)

            $manager.CurrentResults.Count | Should Be 1
            $manager.Summary.TotalResults | Should Be 1
        }

        It "Should dispose properly" {
            $testDir = Join-Path $env:TEMP "StreamingResultsManagerTest_$(Get-Random)"
            $manager = [StreamingResultsManager]::new($testDir, 50, $true)

            $manager.Dispose()

            $manager.Disposed | Should Be $true
        }
    }
}
