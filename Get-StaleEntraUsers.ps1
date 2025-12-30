
function Get-StaleEntraUsers {
    <#
    .SYNOPSIS
        Lists Entra ID users who haven't signed in for over N days, ignoring accounts created within the last M days.

    .DESCRIPTION
        Uses Microsoft Graph to retrieve users with signInActivity and createdDateTime.
        Filters to:
          - Created on or before (Today - GraceDays)
          - Last interactive sign-in older than (Today - StaleDays) OR never signed in
        Optionally excludes guests, disabled accounts, specific UPNs, UPNs containing #EXT#, and/or constrain by domain.

    .PARAMETER StaleDays
        Number of days since last interactive sign-in to consider a user stale. Default: 90.

    .PARAMETER GraceDays
        Ignore accounts created within the last N days. Default: 30.

    .PARAMETER ExcludeGuests
        When set, excludes Guest accounts (keeps only Members).

    .PARAMETER ExcludeDisabled
        When set, excludes accounts where accountEnabled is $false.

    .PARAMETER IncludeNonInteractiveColumn
        When set, includes the LastNonInteractiveSignIn column in the output.

    .PARAMETER ExcludeUpn
        One or more specific UPNs to exclude (e.g., break-glass or service accounts).

    .PARAMETER ExcludeExtUpns
        When set, excludes users whose UPN contains '#EXT#' (typical pattern for invited B2B guests).

    .PARAMETER Domain
        Only include users with UPNs in these domain(s). Accepts multiple.

    .EXAMPLE
        Get-StaleEntraUsers -ExcludeExtUpns

    .EXAMPLE
        Get-StaleEntraUsers -StaleDays 120 -GraceDays 45 -ExcludeGuests -ExcludeDisabled -ExcludeExtUpns

    .NOTES
        Requires Microsoft Graph PowerShell SDK and scopes:
          - User.Read.All
          - AuditLog.Read.All
        signInActivity is available in v1.0 when requested via -Property.
    #>
    [CmdletBinding()]
    param(
        [int]$StaleDays = 90,
        [int]$GraceDays = 30,
        [switch]$ExcludeGuests,
        [switch]$ExcludeDisabled,
        [switch]$IncludeNonInteractiveColumn,
        [string[]]$ExcludeUpn,
        [switch]$ExcludeExtUpns,
        [string[]]$Domain
    )

    # Ensure Graph connection with required scopes
    try {
        $ctx = Get-MgContext -ErrorAction Stop
    } catch {
        $ctx = $null
    }

    if (-not $ctx -or @("User.Read.All","AuditLog.Read.All") | Where-Object { $ctx.Scopes -notcontains $_ }) {
        Write-Verbose "Connecting to Microsoft Graph with required scopes..."
        Connect-MgGraph -Scopes "User.Read.All","AuditLog.Read.All" | Out-Null
    }

    $staleCutoff  = (Get-Date).AddDays(-[math]::Abs($StaleDays))
    $createCutoff = (Get-Date).AddDays(-[math]::Abs($GraceDays))

    # Properties we need
    $properties = "id,displayName,userPrincipalName,mail,accountEnabled,userType,createdDateTime,signInActivity"

    # Server-side filter when excluding guests
    $filter = $null
    if ($ExcludeGuests) {
        $filter = "userType eq 'Member'"
    }

    # Retrieve users
    if ($filter) {
        $users = Get-MgUser -All -Filter $filter -Property $properties
    } else {
        $users = Get-MgUser -All -Property $properties
    }

    # Base filter: ignore accounts created within GraceDays, and stale by StaleDays (or never signed in)
    $targets = $users | Where-Object {
        ([datetime]$_.CreatedDateTime) -le $createCutoff -and
        (
            -not $_.SignInActivity.LastSignInDateTime -or
            ([datetime]$_.SignInActivity.LastSignInDateTime) -lt $staleCutoff
        )
    }

    # Optional: exclude disabled accounts
    if ($ExcludeDisabled) {
        $targets = $targets | Where-Object { $_.AccountEnabled -eq $true }
    }

    # Optional: exclude specific UPNs
    if ($ExcludeUpn -and $ExcludeUpn.Count -gt 0) {
        $excludeSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $ExcludeUpn | ForEach-Object { [void]$excludeSet.Add($_) }
        $targets = $targets | Where-Object { -not $excludeSet.Contains($_.UserPrincipalName) }
    }

    # Optional: constrain to specific domains
    if ($Domain -and $Domain.Count -gt 0) {
        $domainSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $Domain | ForEach-Object { [void]$domainSet.Add($_) }
        $targets = $targets | Where-Object {
            if (-not $_.UserPrincipalName) { $false }
            else {
                $upnDomain = ($_.UserPrincipalName -split "@")[-1]
                $domainSet.Contains($upnDomain)
            }
        }
    }

    # NEW: exclude UPNs containing '#EXT#'
    if ($ExcludeExtUpns) {
        $targets = $targets | Where-Object {
            # Use case-insensitive check for '#EXT#' anywhere in UPN
            $_.UserPrincipalName -and ($_.UserPrincipalName -notmatch '#EXT#')
        }
    }

    # Output shaping
    $selectProps = @(
        'DisplayName',
        'UserPrincipalName',
        @{ Name = 'CreatedDateTime'; Expression = { [datetime]$_.CreatedDateTime } },
        @{ Name = 'LastInteractiveSignIn'; Expression = { $_.SignInActivity.LastSignInDateTime } },
        'AccountEnabled',
        'UserType'
    )

    if ($IncludeNonInteractiveColumn) {
        $selectProps += @{ Name = 'LastNonInteractiveSignIn'; Expression = { $_.SignInActivity.LastNonInteractiveSignInDateTime } }
    }

    $targets |
        Select-Object $selectProps |
        Sort-Object LastInteractiveSignIn, CreatedDateTime, UserPrincipalName |
        Format-Table -AutoSize
}