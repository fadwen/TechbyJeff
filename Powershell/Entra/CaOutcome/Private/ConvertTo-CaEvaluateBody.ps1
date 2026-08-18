function ConvertTo-CaEvaluateBody {
    <#
    .SYNOPSIS
        Builds the request body for one What If evaluation

    .DESCRIPTION
        Assembles the three required parts of the evaluate request - signInIdentity,
        signInContext and signInConditions - from a scenario.

        The verb is ConvertTo rather than New because nothing is created: a scenario goes in and
        the same information comes back out shaped for the API. New- belongs to functions that
        change something, and PSScriptAnalyzer is right to insist on the distinction.

        signInContext is an abstract type with three derived forms, and which one applies is
        decided by what the resource targets. An application sign-in is applicationContext with
        includeApplications, a user action is userActionContext with userAction, and an
        authentication context is authContext with authenticationContextValue. Getting the
        odata.type wrong is not a soft failure - Graph rejects the request - so the choice is
        made here from the scenario rather than left to the caller.

        appliedPoliciesOnly is pinned to false and is not a parameter. Every use this module has
        for a response needs the non-applying policies in it: without them a report-only policy
        that does not apply is indistinguishable from one that was never returned, and the
        projection quietly stops meaning anything. Making it configurable would only offer a way
        to break the module's own output.

    .PARAMETER Scenario
        A scenario from Expand-CaScenario.

    .OUTPUTS
        Hashtable ready to be serialised as the request body.

    .EXAMPLE
        $body = ConvertTo-CaEvaluateBody -Scenario $scenario
        $json = $body | ConvertTo-Json -Depth 10

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.2.0
        Last Updated: 2026-08-17
    #>

    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Scenario
    )

    $userId = [string](Get-CaProperty -InputObject $Scenario -Name 'UserId')
    if ([string]::IsNullOrWhiteSpace($userId)) {
        throw "Scenario '$(Get-CaProperty -InputObject $Scenario -Name 'Name')' has no UserId."
    }

    $applicationId = [string](Get-CaProperty -InputObject $Scenario -Name 'ApplicationId')
    $userAction = [string](Get-CaProperty -InputObject $Scenario -Name 'UserAction')
    $authContext = [string](Get-CaProperty -InputObject $Scenario -Name 'AuthenticationContext')

    if (-not [string]::IsNullOrWhiteSpace($applicationId)) {
        $context = @{
            '@odata.type'       = '#microsoft.graph.applicationContext'
            includeApplications = @($applicationId)
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($userAction)) {
        $context = @{
            '@odata.type' = '#microsoft.graph.userActionContext'
            userAction    = $userAction
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($authContext)) {
        $context = @{
            '@odata.type'              = '#microsoft.graph.authContext'
            authenticationContextValue = $authContext
        }
    } else {
        throw ("Scenario '$(Get-CaProperty -InputObject $Scenario -Name 'Name')' targets " +
            'no application, user action or authentication context.')
    }

    $conditions = Get-CaProperty -InputObject $Scenario -Name 'Conditions'
    if ($null -eq $conditions) { $conditions = @{} }

    return @{
        signInIdentity = @{
            '@odata.type' = '#microsoft.graph.userSignIn'
            userId        = $userId
        }
        signInContext  = $context
        signInConditions = $conditions
        # Pinned. See the description - the projection is meaningless without every policy.
        appliedPoliciesOnly = $false
    }
}
