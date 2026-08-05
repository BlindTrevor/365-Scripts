<#
.SYNOPSIS
    Creates or refreshes a Microsoft Teams holiday schedule from the GOV.UK bank holiday feed.

.DESCRIPTION
    Builds a Teams fixed schedule (default name "UK Bank Holidays") from the bank
    holidays published at https://www.gov.uk/bank-holidays.json.

    Safe to run repeatedly and/or as a scheduled task:
      - Pulls the current GOV.UK feed
      - Keeps only holidays from today onwards
      - Limits to the next 50 (the Teams holiday limit)
      - If the schedule exists, it REPLACES the dates in place (no duplicates)
      - If it does not exist, it creates it
      - Touches nothing else (no auto attendants, call flows, greetings)

    Each holiday becomes a full-day range: 00:00 on the day through to 00:00 the
    following day.

.EXAMPLE
    .\Update-UKBankHolidaysSchedule.ps1

    Creates or refreshes "UK Bank Holidays" using the England & Wales feed.

.EXAMPLE
    .\Update-UKBankHolidaysSchedule.ps1 -Region scotland -ScheduleName "Scottish Bank Holidays"

    Creates or refreshes a separate schedule using the Scotland feed.

.NOTES
    File Name      : Update-UKBankHolidaysSchedule.ps1
    Author         : Andrew Samuel
    Prerequisite   : PowerShell 5.1 or later, MicrosoftTeams module
    Permissions    : Teams Administrator (or Teams Communications Administrator)
    Version        : 1.1

.LINK
    https://www.gov.uk/bank-holidays.json

.LINK
    https://learn.microsoft.com/en-us/powershell/module/teams/new-csonlineschedule
#>

[CmdletBinding()]
param(
    [string]$ScheduleName = "UK Bank Holidays",

    [ValidateSet("england-and-wales", "scotland", "northern-ireland")]
    [string]$Region = "england-and-wales",

    [int]$MaxDates = 50,

    [string]$GovUkUrl = "https://www.gov.uk/bank-holidays.json"
)

$ErrorActionPreference = "Stop"

# ---- Output helpers -------------------------------------------------------
$script:StepNumber = 0
$script:TotalSteps = 5

function Write-Step {
    param([string]$Message)
    $script:StepNumber++
    Write-Host ""
    Write-Host ("[{0}/{1}] {2}" -f $script:StepNumber, $script:TotalSteps, $Message) -ForegroundColor Cyan
}

function Write-Detail {
    param([string]$Message)
    Write-Host ("      {0}" -f $Message) -ForegroundColor Gray
}

function Write-Success {
    param([string]$Message)
    Write-Host ("      {0}" -f $Message) -ForegroundColor Green
}
# ---------------------------------------------------------------------------

$startedAt = Get-Date

Write-Host ""
Write-Host "=== Update-UKBankHolidaysSchedule ===" -ForegroundColor White
Write-Host ("Schedule : {0}" -f $ScheduleName)
Write-Host ("Region   : {0}" -f $Region)
Write-Host ("Max dates: {0}" -f $MaxDates)
Write-Host ("Started  : {0}" -f $startedAt.ToString("yyyy-MM-dd HH:mm:ss"))

# ---- 1. Connect -----------------------------------------------------------
Write-Step "Connecting to Microsoft Teams"

Import-Module MicrosoftTeams
$teamsModule = Get-Module MicrosoftTeams
Write-Detail ("MicrosoftTeams module version {0}" -f $teamsModule.Version)

$connection = Connect-MicrosoftTeams
if ($connection.Account) {
    Write-Success ("Connected as {0} (tenant {1})" -f $connection.Account, $connection.TenantId)
}
else {
    Write-Success "Connected."
}

# ---- 2. Fetch the GOV.UK feed --------------------------------------------
Write-Step "Getting bank holidays from GOV.UK"
Write-Detail $GovUkUrl

$govUkHolidays = Invoke-RestMethod -Uri $GovUkUrl

# The region key contains hyphens, so access it via the variable
$regionData = $govUkHolidays.$Region
if (-not $regionData) {
    throw "Could not find region '$Region' in the GOV.UK bank holiday feed."
}

$allEvents = @($regionData.events)
Write-Detail ("Feed division '{0}' returned {1} holiday(s) in total." -f $regionData.division, $allEvents.Count)

$today = (Get-Date).Date

# Build a clean, sorted list of upcoming holidays (next $MaxDates only)
$allUpcoming =
    $allEvents |
    ForEach-Object {
        [pscustomobject]@{
            Title = $_.title
            Date  = [datetime]$_.date     # GOV.UK dates are ISO yyyy-MM-dd
        }
    } |
    Where-Object { $_.Date -ge $today } |
    Sort-Object Date

$upcomingHolidays = @($allUpcoming | Select-Object -First $MaxDates)

if (-not $upcomingHolidays) {
    throw "No upcoming holidays were found from GOV.UK."
}

Write-Detail ("{0} holiday(s) are in the past and were skipped." -f (@($allEvents).Count - @($allUpcoming).Count))
if (@($allUpcoming).Count -gt $MaxDates) {
    Write-Detail ("Trimmed to the first {0} of {1} upcoming holiday(s) (Teams limit)." -f $MaxDates, @($allUpcoming).Count)
}

Write-Success ("{0} holiday(s) selected, {1} to {2}." -f
    $upcomingHolidays.Count,
    $upcomingHolidays[0].Date.ToString("yyyy-MM-dd"),
    $upcomingHolidays[-1].Date.ToString("yyyy-MM-dd"))

Write-Host ""
$upcomingHolidays |
    Select-Object @{ N = "Date"; E = { $_.Date.ToString("yyyy-MM-dd (ddd)") } }, Title |
    Format-Table -AutoSize

# ---- 3. Build the Teams date-time ranges ---------------------------------
Write-Step "Building Teams date/time ranges"

# Use the unambiguous 'yyyy-MM-ddTHH:mm:ss' string format (locale-proof).
# Each range is the full day: 00:00 on the day -> 00:00 the next day.
$dateRanges = foreach ($holiday in $upcomingHolidays) {
    $start = $holiday.Date.ToString("yyyy-MM-ddT00:00:00")
    $end   = $holiday.Date.AddDays(1).ToString("yyyy-MM-ddT00:00:00")
    Write-Verbose ("Range for '{0}': {1} -> {2}" -f $holiday.Title, $start, $end)
    New-CsOnlineDateTimeRange -Start $start -End $end
}

$dateRanges = @($dateRanges)
Write-Success ("Built {0} full-day range(s)." -f $dateRanges.Count)

# ---- 4. Find any existing schedule ---------------------------------------
Write-Step ("Checking for an existing schedule called '{0}'" -f $ScheduleName)

$existing = @( Get-CsOnlineSchedule | Where-Object { $_.Name -eq $ScheduleName } )

if ($existing.Count -gt 1) {
    throw "More than one schedule called '$ScheduleName' exists. Please tidy these up manually first."
}

# ---- 5. Create or update -------------------------------------------------
if ($existing.Count -eq 1) {
    $schedule = $existing[0]
    Write-Detail ("Found existing schedule (Id: {0})." -f $schedule.Id)

    if (-not $schedule.FixedSchedule) {
        throw "'$ScheduleName' exists but is not a fixed schedule. Not overwriting it."
    }

    $currentDates = @($schedule.FixedSchedule.DateTimeRanges |
        ForEach-Object { ([datetime]$_.Start).ToString("yyyy-MM-dd") })
    $newDates = @($upcomingHolidays | ForEach-Object { $_.Date.ToString("yyyy-MM-dd") })

    $added   = @($newDates     | Where-Object { $_ -notin $currentDates })
    $removed = @($currentDates | Where-Object { $_ -notin $newDates })

    Write-Detail ("Existing dates: {0}. New dates: {1}." -f $currentDates.Count, $newDates.Count)
    if ($added.Count)   { Write-Detail ("Adding   : {0}" -f ($added   -join ", ")) }
    if ($removed.Count) { Write-Detail ("Removing : {0}" -f ($removed -join ", ")) }
    if (-not $added.Count -and -not $removed.Count) {
        Write-Detail "No date changes - rewriting the schedule anyway to be certain."
    }

    Write-Step ("Updating '{0}'" -f $ScheduleName)
    $schedule.FixedSchedule.DateTimeRanges = @($dateRanges)
    Set-CsOnlineSchedule -Instance $schedule | Out-Null
    Write-Success ("Updated '{0}' with {1} date(s)." -f $ScheduleName, $dateRanges.Count)
}
else {
    Write-Detail "No existing schedule found."

    Write-Step ("Creating '{0}'" -f $ScheduleName)
    $newSchedule = New-CsOnlineSchedule -Name $ScheduleName -FixedSchedule -DateTimeRanges @($dateRanges)
    Write-Success ("Created '{0}' (Id: {1}) with {2} date(s)." -f $ScheduleName, $newSchedule.Id, $dateRanges.Count)
}

# ---- Summary -------------------------------------------------------------
$elapsed = (Get-Date) - $startedAt

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor White
Write-Host ("Schedule : {0}" -f $ScheduleName)
Write-Host ("Dates    : {0} ({1} to {2})" -f
    $dateRanges.Count,
    $upcomingHolidays[0].Date.ToString("yyyy-MM-dd"),
    $upcomingHolidays[-1].Date.ToString("yyyy-MM-dd"))
Write-Host ("Next up  : {0} on {1}" -f $upcomingHolidays[0].Title, $upcomingHolidays[0].Date.ToString("dddd d MMMM yyyy"))
Write-Host ("Elapsed  : {0:mm\:ss}" -f $elapsed)
Write-Host ""
