<#
.SYNOPSIS
    Disables Active Directory accounts older than specified date
.DESCRIPTION
    This script finds AD accounts that haven't logged in since the specified date
    and disables them. Includes test mode and CSV export options.
.PARAMETER DateInput
    Cutoff date in YYYY-MM-DD format (e.g., 2023-01-01). Accounts older than this will be disabled.
.PARAMETER WhatIf
    Shows which accounts would be disabled without actually making changes
.PARAMETER ExportOnly
    Only exports data to CSV without disabling any accounts
.EXAMPLE
    .\disable_inactive_ad_accounts.ps1 -DateInput "2023-01-01"
    Disables all accounts not used since January 1, 2023
.EXAMPLE
    .\disable_inactive_ad_accounts.ps1 -DateInput "2023-01-01" -WhatIf
    Shows which accounts would be disabled without making changes
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
    Write-Host "Processing accounts older than: $($CutoffDate.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan
}
catch {
    Write-Error "Invalid date format. Please use YYYY-MM-DD format (e.g., 2023-01-01)"
    exit 1
}

# Get all users with last logon date
try {
    Write-Host "Retrieving user accounts from Active Directory..." -ForegroundColor Yellow
    $users = Get-ADUser -Filter * -Properties sAMAccountName, LastLogonDate, Enabled, DistinguishedName -ErrorAction Stop | 
             Where-Object { $_.LastLogonDate -ne $null }
    Write-Host "Found $($users.Count) accounts with last logon information" -ForegroundColor Green
}
catch {
    Write-Error "Failed to retrieve users from AD: $_"
    exit 1
}

# Prepare results
$report = @()
$accountsToDisable = @()

Write-Host "Analyzing accounts..." -ForegroundColor Yellow
foreach ($user in $users) {
    $shouldDisable = $user.Enabled -and ($user.LastLogonDate -lt $CutoffDate)
    
    $report += [PSCustomObject]@{
        AccountName    = $user.sAMAccountName
        LastLogonDate  = $user.LastLogonDate
        Enabled        = $user.Enabled
        ToBeDisabled   = $shouldDisable
        DN            = $user.DistinguishedName
    }

    if ($shouldDisable) {
        $accountsToDisable += $user
    }
}

# Show statistics
Write-Host "`nStatistics:" -ForegroundColor Cyan
Write-Host "Total accounts scanned: $($users.Count)"
Write-Host "Accounts to be disabled: $($accountsToDisable.Count)`n"

# Export results
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvPath = "C:\temp\Inactive_AD_Accounts_$timestamp.csv"
$report | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Host "Report saved to: $csvPath`n" -ForegroundColor Green

# Account disable process
if (-not $ExportOnly -and $accountsToDisable.Count -gt 0) {
    if ($WhatIf) {
        Write-Host "WHAT IF: The following accounts would be disabled:" -ForegroundColor Yellow
        $accountsToDisable | ForEach-Object {
            Write-Host " - $($_.sAMAccountName) (Last logon: $($_.LastLogonDate))"
        }
    }
    else {
        $disabledCount = 0
        Write-Host "Starting account disable process..." -ForegroundColor Yellow
        $accountsToDisable | ForEach-Object {
            try {
                Disable-ADAccount -Identity $_.DistinguishedName
                Write-Host "Disabled: $($_.sAMAccountName) (Last logon: $($_.LastLogonDate))" -ForegroundColor Green
                $disabledCount++
            }
            catch {
                Write-Host "ERROR disabling $($_.sAMAccountName): $_" -ForegroundColor Red
            }
        }
        Write-Host "`nSuccessfully disabled accounts: $disabledCount" -ForegroundColor Green
    }
}

Write-Host "`nOperation completed!`n" -ForegroundColor Cyan