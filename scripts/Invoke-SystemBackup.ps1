#Requires -RunAsAdministrator
#Requires -Version 5.1
<#
.SYNOPSIS
    Automated Windows Server Backup via WSB with logging and Teams/email alerting.
.PARAMETER Target
    UNC path or local drive for backup destination.
.PARAMETER Type
    'Full' or 'Incremental'. Default: Incremental
.PARAMETER RetentionDays
    Delete backups older than N days. Default: 30
.PARAMETER TeamsWebhook
    Teams webhook URL for notifications.
.EXAMPLE
    .\Invoke-SystemBackup.ps1 -Target "\\NAS01\Backups\$env:COMPUTERNAME" -Type Full
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Target,
    [ValidateSet('Full','Incremental')][string] $Type = 'Incremental',
    [int]    $RetentionDays  = 30,
    [string] $TeamsWebhook   = '',
    [string] $LogPath        = "C:\Logs\Backup"
)

$start     = Get-Date
$logFile   = Join-Path $LogPath "backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$hostname  = $env:COMPUTERNAME

New-Item -ItemType Directory -Path $LogPath -Force | Out-Null

function Write-Log {
    param($Message, $Level = 'INFO')
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $logFile -Value $entry
    switch ($Level) {
        'ERROR' { Write-Host $entry -ForegroundColor Red }
        'WARN'  { Write-Host $entry -ForegroundColor Yellow }
        default { Write-Host $entry }
    }
}

function Send-TeamsNotification {
    param([string]$Title, [string]$Message, [string]$Color = '00CC00')
    if (-not $TeamsWebhook) { return }
    $payload = @{
        '@type'    = 'MessageCard'
        '@context' = 'https://schema.org/extensions'
        themeColor = $Color
        summary    = $Title
        title      = $Title
        text       = $Message
    } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Uri $TeamsWebhook -Method Post -ContentType 'application/json' -Body $payload -ErrorAction SilentlyContinue
}

Write-Log "Starting $Type backup of $hostname to $Target"

try {
    # Ensure WSB is installed
    if (-not (Get-Command wbadmin -ErrorAction SilentlyContinue)) {
        throw "Windows Server Backup (wbadmin) not found. Run: Install-WindowsFeature Windows-Server-Backup"
    }

    # Get all local volumes to backup
    $volumes = (Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }).DriveLetter |
               ForEach-Object { "$_`:" }
    Write-Log "Volumes to backup: $($volumes -join ', ')"

    # Build wbadmin command
    $backupType = if ($Type -eq 'Full') { '' } else { '-incremental' }
    $volArgs    = ($volumes | ForEach-Object { "-include:$_" }) -join ' '

    $cmd = "wbadmin start backup -backupTarget:$Target $volArgs $backupType -vssFull -quiet"
    Write-Log "Running: $cmd"

    $output = cmd /c $cmd 2>&1
    $output | ForEach-Object { Write-Log $_ }

    if ($LASTEXITCODE -ne 0) { throw "wbadmin exited with code $LASTEXITCODE" }

    $duration = [math]::Round(((Get-Date) - $start).TotalMinutes, 1)
    Write-Log "Backup completed successfully in $duration min"
    Send-TeamsNotification "Backup OK — $hostname" "Type: $Type`nDuration: $duration min`nTarget: $Target"

} catch {
    Write-Log "BACKUP FAILED: $_" 'ERROR'
    Send-TeamsNotification "Backup FAILED — $hostname" $_.ToString() 'FF0000'
    exit 1
} finally {
    # Retention cleanup
    Write-Log "Cleaning backups older than $RetentionDays days in $Target"
    try {
        Get-ChildItem -Path $Target -Recurse -File |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$RetentionDays) } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    } catch { Write-Log "Retention cleanup warning: $_" 'WARN' }
}
