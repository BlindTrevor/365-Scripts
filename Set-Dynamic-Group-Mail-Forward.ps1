<#
.SYNOPSIS
    Configures dynamic groups to enable mail forwarding to members' inboxes.

.DESCRIPTION
    This script connects to Exchange Online and Microsoft Graph to identify dynamic distribution groups,
    reports on their current forwarding configuration, and enables auto-subscription and conversation
    forwarding for all members.

.NOTES
    Requires permissions: Group.Read.All (Microsoft Graph), Exchange Online management role
    
.EXAMPLE
    .\Set-Dynamic-Group-Mail-Forward.ps1
#>

Connect-ExchangeOnline
Connect-MgGraph -Scopes "Group.Read.All"

$dynGrps = Get-MgGroup -Filter "groupTypes/any(c:c eq 'Unified') and groupTypes/any(c:c eq 'DynamicMembership')" -All | 
    Select-Object DisplayName, Id, MembershipRule, MembershipRuleProcessingState, Visibility

function Get-UnifiedGroupByObjectId {
    param([Parameter(Mandatory=$true)][string]$ObjectId)
    Get-UnifiedGroup -Filter "ExternalDirectoryObjectId -eq '$ObjectId'" -ErrorAction SilentlyContinue
}

function Get-GroupReport {
    param([Parameter(Mandatory=$true)]$Groups)
    
    foreach ($g in $Groups) {
        $exGroup = Get-UnifiedGroupByObjectId -ObjectId $g.Id

        if (-not $exGroup) {
            [PSCustomObject]@{
                DisplayName                         = $g.DisplayName
                ObjectId                            = $g.Id
                PrimarySmtpAddress                  = $null
                AutoSubscribeNewMembers             = $null
                SubscribeMembersToCalendarEvents    = $null
                SubscriberCount                     = 0
                Subscribers                         = $null
                ForwardsConversationsToMembersInbox = $false
                Note                                = "Unified group not found in Exchange"
            }
            continue
        }

        $subscribers = @()
        try {
            $subscribers = Get-UnifiedGroupLinks -Identity $exGroup.Identity -LinkType Subscribers -ErrorAction Stop |
                Select-Object -ExpandProperty PrimarySmtpAddress
        } catch {
            $subscribers = @()
        }

        $forwards = ($subscribers.Count -gt 0) -or ($exGroup.AutoSubscribeNewMembers -eq $true)

        [PSCustomObject]@{
            DisplayName                         = $g.DisplayName
            ObjectId                            = $g.Id
            PrimarySmtpAddress                  = $exGroup.PrimarySmtpAddress
            AutoSubscribeNewMembers             = $exGroup.AutoSubscribeNewMembers
            SubscribeMembersToCalendarEvents    = $exGroup.SubscribeMembersToCalendarEvents
            SubscriberCount                     = $subscribers.Count
            Subscribers                         = ($subscribers -join "; ")
            ForwardsConversationsToMembersInbox = $forwards
            Note                                = if ($subscribers.Count -gt 0) {"Has subscribers"} elseif ($exGroup.AutoSubscribeNewMembers) {"Auto-subscribe enabled"} else {"No subscribers, auto-subscribe disabled"}
        }
    }
}

# Generate initial report
$report = Get-GroupReport -Groups $dynGrps
$report | Format-Table DisplayName, PrimarySmtpAddress, AutoSubscribeNewMembers, SubscriberCount, ForwardsConversationsToMembersInbox

# Configure groups for mail forwarding
foreach ($g in $dynGrps) {
    $exGroup = Get-UnifiedGroupByObjectId -ObjectId $g.Id
    if ($exGroup) {
        Set-UnifiedGroup -Identity $exGroup.Identity -AutoSubscribeNewMembers:$true -SubscriptionEnabled:$true
        $members = Get-UnifiedGroupLinks -Identity $exGroup.Identity -LinkType Members | Select-Object -ExpandProperty PrimarySmtpAddress
        if ($members.Count -gt 0) {
            Add-UnifiedGroupLinks -Identity $exGroup.Identity -LinkType Subscribers -Links $members
        }
    }
}

# Generate final report to verify changes
$finalReport = Get-GroupReport -Groups $dynGrps
$finalReport | Format-Table DisplayName, PrimarySmtpAddress, AutoSubscribeNewMembers, SubscriberCount, ForwardsConversationsToMembersInbox

# Cleanup
Disconnect-ExchangeOnline -Confirm:$false
Disconnect-MgGraph