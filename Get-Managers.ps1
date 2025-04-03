$getSessions = Get-ConnectionInformation | Select-Object Name
$isConnected = (@($getSessions.Name) -like 'ExchangeOnline*').Count -gt 0
if (-not $isConnected) {
    Connect-ExchangeOnline
}

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
	$managerList += $obj | select Name,UPN,Disabled,Manager,ManagerUPN
}

$managerList = $managerList | Sort-Object Name
$managerList | ft *
