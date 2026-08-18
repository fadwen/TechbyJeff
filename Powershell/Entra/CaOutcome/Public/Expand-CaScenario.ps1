function Expand-CaScenario {
    <#
    .SYNOPSIS
        Expands a matrix of personas, resources and conditions into the individual sign-ins to
        evaluate

    .DESCRIPTION
        Core Functionality:
        Takes a matrix definition - a set of personas, a set of resources and a set of sign-in
        conditions - and returns every combination of the three as a scenario ready to send to
        the What If endpoint.

        Business Value:
        Conditional Access is not a per-user question, it is a per-population one, and the
        interesting failures live in combinations nobody thought to check by hand: the
        contractor on an unmanaged Mac, the break glass account from an unusual country, the
        service desk on a mobile client. Writing those out one at a time is how they get
        skipped. Declaring the axes and multiplying them out is how they get covered.

        Keeping the definition as data rather than code matters more than it looks. A matrix in
        a psd1 next to the tests can be reviewed, diffed and extended by someone who does not
        write PowerShell, and it is the same artefact whether it is driving an ad hoc check or a
        scheduled run.

        Use Cases:
        - Building the input for Invoke-CaScenarioMatrix
        - Reviewing what a run will actually cover before spending the API calls on it
        - Feeding a subset, by filtering the output, when only one persona is in question

        Dependencies:
        None. This is a pure expansion and touches nothing.

        Side Effects:
        None.

        Important:
        The count multiplies. Three personas, four resources and five conditions is sixty API
        calls, and the guard exists because that arithmetic is easy to get wrong by a factor of
        ten. MaxScenarioCount throws rather than truncating: a silently shortened matrix would
        report a clean run over a fraction of what was asked for.

    .PARAMETER Matrix
        [System.Object] (Mandatory, Accepts Pipeline Input)

        The matrix definition, a hashtable or object with Personas, Resources and Conditions.

        Each Persona needs Name and UserId. Each Resource needs Name plus one of
        ApplicationId, UserAction or AuthenticationContext. Each Condition needs Name plus any
        of the signInConditions properties, written in PascalCase - DevicePlatform,
        ClientAppType, SignInRiskLevel, UserRiskLevel, InsiderRiskLevel,
        ServicePrincipalRiskLevel, AgentIdRiskLevel, Country, IpAddress, DeviceInfo,
        AuthenticationFlow.

        Business Context: Unrecognised condition keys are passed through with their first
        letter lowercased rather than rejected, so a property Microsoft adds to signInConditions
        can be used the day it ships without waiting for this module to learn about it.

    .PARAMETER MaxScenarioCount
        [System.Int32] (Optional, No Pipeline Support)

        The most scenarios this matrix may expand to. Defaults to 250. Exceeding it throws.

    .OUTPUTS
        PSCustomObject per scenario, carrying Name, PersonaName, UserId, ResourceName, the
        resource target, ConditionName and a Conditions hashtable shaped for signInConditions.

    .EXAMPLE
        PS> $matrix = @{
                Personas   = @(@{ Name = 'standard'; UserId = $userId })
                Resources  = @(@{ Name = 'office365'
                                  ApplicationId = '00000003-0000-0ff1-ce00-000000000000' })
                Conditions = @(
                    @{ Name = 'managed'; DevicePlatform = 'windows'; ClientAppType = 'browser'
                       DeviceInfo = @{ isCompliant = $true } }
                    @{ Name = 'unmanaged'; DevicePlatform = 'windows'; ClientAppType = 'browser'
                       DeviceInfo = @{ isCompliant = $false } })
            }
        PS> Expand-CaScenario -Matrix $matrix

        DESCRIPTION: Expands one persona against one resource under two device states
        OUTPUT: Two scenarios, named standard/office365/managed and standard/office365/unmanaged
        DURATION: Instant
        USE CASE: The smallest useful matrix - the same user, managed and not

    .EXAMPLE
        PS> Expand-CaScenario -Matrix (Import-PowerShellDataFile .\ca-matrix.psd1) |
                Select-Object Name

        DESCRIPTION: Reviews the coverage of a matrix held as data, without calling Graph
        OUTPUT: One row per scenario the matrix describes
        DURATION: Instant
        USE CASE: Checking what a scheduled run covers, and what it quietly does not

    .EXAMPLE
        PS> Expand-CaScenario -Matrix $matrix |
                Where-Object PersonaName -eq 'breakglass' |
                Invoke-CaScenarioMatrix

        DESCRIPTION: Runs one persona out of a large matrix
        OUTPUT: Outcomes for the break glass account alone
        DURATION: Instant to expand; the API calls take the time
        USE CASE: Re-checking the account that matters most, without paying for the whole matrix

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.2.0
        Last Updated: 2026-08-17
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [object]$Matrix,

        [Parameter()]
        [ValidateRange(1, 100000)]
        [int]$MaxScenarioCount = 250
    )

    process {
        # The Where-Object is not decoration. A missing property reads as $null, and @($null)
        # has a count of one, so without it an absent axis passes the check below and then
        # fails much later with a confusing message about a nameless resource.
        $personas = @(Get-CaProperty -InputObject $Matrix -Name 'Personas' |
            Where-Object { $null -ne $_ })
        $resources = @(Get-CaProperty -InputObject $Matrix -Name 'Resources' |
            Where-Object { $null -ne $_ })
        $conditions = @(Get-CaProperty -InputObject $Matrix -Name 'Conditions' |
            Where-Object { $null -ne $_ })

        foreach ($axis in @(
            @{ Name = 'Personas'; Value = $personas }
            @{ Name = 'Resources'; Value = $resources }
            @{ Name = 'Conditions'; Value = $conditions }
        )) {
            if ($axis.Value.Count -eq 0) {
                throw "The matrix has no $($axis.Name). All three axes are required."
            }
        }

        $total = $personas.Count * $resources.Count * $conditions.Count
        if ($total -gt $MaxScenarioCount) {
            throw ("This matrix expands to $total scenarios, over the limit of " +
                "$MaxScenarioCount. Each one is an API call. Raise -MaxScenarioCount if that " +
                'is really what you want.')
        }

        foreach ($persona in $personas) {
            $personaName = [string](Get-CaProperty -InputObject $persona -Name 'Name')
            $userId = [string](Get-CaProperty -InputObject $persona -Name 'UserId')

            if ([string]::IsNullOrWhiteSpace($userId)) {
                throw "Persona '$personaName' has no UserId."
            }

            foreach ($resource in $resources) {
                $resourceName = [string](Get-CaProperty -InputObject $resource -Name 'Name')
                $applicationId = Get-CaProperty -InputObject $resource -Name 'ApplicationId'
                $userAction = Get-CaProperty -InputObject $resource -Name 'UserAction'
                $authContext = Get-CaProperty -InputObject $resource -Name 'AuthenticationContext'

                $targets = @($applicationId, $userAction, $authContext | Where-Object {
                    -not [string]::IsNullOrWhiteSpace([string]$_)
                })
                if ($targets.Count -ne 1) {
                    throw ("Resource '$resourceName' must set exactly one of ApplicationId, " +
                        "UserAction or AuthenticationContext; it sets $($targets.Count).")
                }

                foreach ($condition in $conditions) {
                    $conditionName = [string](Get-CaProperty -InputObject $condition -Name 'Name')

                    [PSCustomObject]@{
                        PSTypeName            = 'CaOutcome.Scenario'
                        Name                  = "$personaName/$resourceName/$conditionName"
                        PersonaName           = $personaName
                        UserId                = $userId
                        ResourceName          = $resourceName
                        ApplicationId         = $applicationId
                        UserAction            = $userAction
                        AuthenticationContext = $authContext
                        ConditionName         = $conditionName
                        Conditions            = ConvertTo-CaSignInCondition -Condition $condition
                    }
                }
            }
        }
    }
}
