function Resolve-OktaTestApiToken {
    <#
    .SYNOPSIS
        Finds exactly one API token by name or id, or refuses

    .DESCRIPTION
        Revoking an API token is irreversible and there is no way to recreate the same token,
        so the only acceptable outcomes here are "exactly one match" or "an error naming the
        problem". Picking the first of several would eventually revoke somebody's working
        Postman or Terraform credential.

        The reason this has to be explicit rather than inferred deserves stating, because the
        obvious design is to have the module revoke whatever token it is currently using:

        - GET /api/v1/api-tokens/current returns 404. That endpoint does not exist on a
          standard org, verified against a live tenant.
        - The list endpoint returns id, name and timestamps, but never the token value. An SSWS
          string in hand therefore cannot be matched to a row in that list by any means.

        So the module genuinely cannot identify its own token, and a caller has to say which one
        they mean. Matching is by exact id or exact name, case-insensitively for the name.
        Nothing is matched by prefix or wildcard, because a near miss here is destructive.

    .PARAMETER NameOrId
        The token's name as shown in the admin console, or its id

    .OUTPUTS
        The matching token object

    .EXAMPLE
        $token = Resolve-OktaTestApiToken -NameOrId 'ci-automation'

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NameOrId
    )

    $tokens = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/api-tokens' -Paginate)

    if ($tokens.Count -eq 0) {
        throw 'The org reports no API tokens, so there is nothing to revoke.'
    }

    $matched = @($tokens | Where-Object {
        $_.id -ceq $NameOrId -or
        ($_.name -and $_.name.Equals($NameOrId, [StringComparison]::OrdinalIgnoreCase))
    })

    if ($matched.Count -eq 0) {
        $available = ($tokens | ForEach-Object { "'$($_.name)' ($($_.id))" }) -join ', '
        throw "No API token matches '$NameOrId'. The org holds: $available"
    }

    if ($matched.Count -gt 1) {
        $ambiguous = ($matched | ForEach-Object { "'$($_.name)' ($($_.id))" }) -join ', '
        throw ("'$NameOrId' matches $($matched.Count) API tokens: $ambiguous. Pass the id " +
            'instead, since revoking the wrong one cannot be undone.')
    }

    return $matched[0]
}
