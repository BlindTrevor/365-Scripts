<#
.SYNOPSIS
    Retrieves manager information for users in the organization.

.DESCRIPTION
    This script retrieves and displays manager details for specified users or all users in the directory.

.EXAMPLE
    .\Get-Managers.ps1

.NOTES
    File Name      : Get-Managers.ps1
    Author         : 
    Prerequisite   : PowerShell 5.0 or later
    Version        : 1.0

.LINK
    https://docs.microsoft.com/en-us/powershell/module/activedirectory/
#>

# Check and connect to Exchange Online
$getSessions = Get-ConnectionInformation | Select-Object Name
if (-not ((@($getSessions.Name) -like 'ExchangeOnline*').Count -gt 0)) {
    Connect-ExchangeOnline
}

Write-Progress -id 1 -Activity "Getting Manager Information" -Status "Starting" -PercentComplete 0

$managerList = @()
$users = Get-User

foreach ($user in $users) {
    $i++
    Write-Progress -id 1 -Activity "Getting Manager Information" -Status "Completed: $i of $($users.Count)" -PercentComplete (($i / $users.Count) * 100)
    
    $manager = if ($user.Manager) {
        Get-User $user.Manager | Select-Object UserPrincipalName, DisplayName
    }
    
    $managerList += [pscustomobject]@{
        Name        = $user.DisplayName
        UPN         = $user.UserPrincipalName
        Disabled    = $user.AccountDisabled
        Manager     = $manager.DisplayName
        ManagerUPN  = $manager.UserPrincipalName
    }
}

$managerList | Sort-Object Name | Format-Table *

Write-Progress -id 1 -Activity "Getting Manager Information" -Status "Starting" -PercentComplete 0

$managerList = @()
$users = Get-User
$i = 0

foreach($user in $users){
    $i++
    Write-Progress -id 1 -Activity "Getting Manager Information" -Status "Completed: $i of $($users.Count)" -PercentComplete (($i / $users.Count)  * 100)
#    Write-Host "Checking: " -NoNewline
#    Write-Host "$($user.DisplayName)" -NoNewline -ForegroundColor Cyan
    if($user.Manager){
        $manager = Get-User $user.Manager | Select-Object UserPrincipalName, DisplayName
#        Write-Host " - $($manager.DisplayName)" -ForegroundColor Green
    }else{
        $manager = ""
#        Write-Host " - No Manager" -ForegroundColor Red
    }
    $obj = New-Object psobject -Property @{
        "Name" = $user.DisplayName;
        "UPN" = $user.UserPrincipalName;
        "Disabled" = $user.AccountDisabled;
        "Manager" = $manager.DisplayName;
        "ManagerUPN" = $manager.UserPrincipalName;
    }
	$managerList += $obj | Select-Object Name,UPN,Disabled,Manager,ManagerUPN
}

$managerList = $managerList | Sort-Object Name
$managerList | Format-Table *