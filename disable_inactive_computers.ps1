<#
.SYNOPSIS
    Disables inactive computer accounts in Active Directory
.DESCRIPTION
    This script identifies computer accounts that haven't logged in since the specified date
    and disables them. Includes test mode and CSV export options.
.PARAMETER DateInput
    Cutoff date in YYYY-MM-DD format (e.g., 2023-01-01). Computers older than this will be disabled.
.PARAMETER WhatIf
    Shows which computers would be disabled without actually making changes
.PARAMETER ExportOnly
    Only exports data to CSV without disabling any computers
.EXAMPLE
    .\disable_inactive_computers.ps1 -DateInput "2023-01-01"
    Disables all computer accounts not used since January 1, 2023
.EXAMPLE
    .\disable_inactive_computers.ps1 -DateInput "2023-01-01" -WhatIf
    Shows which computers would be disabled without making changes
#>

param (
    [Parameter(Mandatory=$true, HelpMessage="Enter date in YYYY-MM-DD format (e.g., 2023-01-01)")]
    [string]$DateInput,
    
    [switch]$WhatIf,
    [switch]$ExportOnly
)

# Import Active Directory module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "ActiveDirectory module loaded successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to import ActiveDirectory module: $_"
    exit 1
}

# Parse input date
try {
    $CutoffDate = [datetime]::ParseExact($DateInput, 'yyyy-MM-dd', $null)
    Write-Host "Processing computer accounts older than: $($CutoffDate.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan
}
catch {
    Write-Error "Invalid date format. Please use YYYY-MM-DD format (e.g., 2023-01-01)"
    exit 1
}

# Get all computer accounts with last logon date
try {
    Write-Host "Retrieving computer accounts from Active Directory..." -ForegroundColor Yellow
    $computers = Get-ADComputer -Filter * -Properties Name, LastLogonDate, Enabled, DistinguishedName, OperatingSystem, WhenCreated -ErrorAction Stop | 
                 Where-Object { $_.LastLogonDate -ne $null }
    Write-Host "Found $($computers.Count) computer accounts with last logon information" -ForegroundColor Green
}
catch {
    Write-Error "Failed to retrieve computers from AD: $_"
    exit 1
}

# Prepare results
$report = @()
$computersToDisable = @()

Write-Host "Analyzing computer accounts..." -ForegroundColor Yellow
foreach ($computer in $computers) {
    $shouldDisable = $computer.Enabled -and ($computer.LastLogonDate -lt $CutoffDate)
    
    $report += [PSCustomObject]@{
        ComputerName   = $computer.Name
        LastLogonDate = $computer.LastLogonDate
        OS            = $computer.OperatingSystem
        CreatedDate   = $computer.WhenCreated
        Enabled       = $computer.Enabled
        ToBeDisabled  = $shouldDisable
        DN            = $computer.DistinguishedName
    }

    if ($shouldDisable) {
        $computersToDisable += $computer
    }
}

# Show statistics
Write-Host "`nStatistics:" -ForegroundColor Cyan
Write-Host "Total computers scanned: $($computers.Count)"
Write-Host "Computers to be disabled: $($computersToDisable.Count)`n"

# Export results
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvPath = "C:\temp\Inactive_AD_Computers_$timestamp.csv"
$report | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Host "Report saved to: $csvPath`n" -ForegroundColor Green

# Computer disable process
if (-not $ExportOnly -and $computersToDisable.Count -gt 0) {
    if ($WhatIf) {
        Write-Host "WHAT IF: The following computers would be disabled:" -ForegroundColor Yellow
        $computersToDisable | ForEach-Object {
            Write-Host " - $($_.Name) (Last logon: $($_.LastLogonDate)) OS: $($_.OperatingSystem)"
        }
    }
    else {
        $disabledCount = 0
        Write-Host "Starting computer disable process..." -ForegroundColor Yellow
        $computersToDisable | ForEach-Object {
            try {
                Disable-ADAccount -Identity $_.DistinguishedName
                Set-ADComputer -Identity $_.DistinguishedName -Description "Disabled by script on $(Get-Date -Format 'yyyy-MM-dd') - Last logon: $($_.LastLogonDate)"
                Write-Host "Disabled: $($_.Name) (Last logon: $($_.LastLogonDate))" -ForegroundColor Green
                $disabledCount++
            }
            catch {
                Write-Host "ERROR disabling $($_.Name): $_" -ForegroundColor Red
            }
        }
        Write-Host "`nSuccessfully disabled computers: $disabledCount" -ForegroundColor Green
    }
}

Write-Host "`nOperation completed!`n" -ForegroundColor Cyan