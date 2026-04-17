# Windows Backup Automation

PowerShell scripts for automating Windows Server backups using Windows Server Backup (WSB), VSS snapshots, and robocopy. Includes retention management, integrity verification, and reporting.

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/Invoke-SystemBackup.ps1` | Full/incremental system backup via WSB |
| `scripts/Invoke-VSSSnapshot.ps1` | Create VSS shadow copy for live database backup |
| `scripts/Invoke-RobocopyBackup.ps1` | Incremental file backup with hardlinks |
| `scripts/Test-BackupIntegrity.ps1` | Verify backup integrity and report |
| `scripts/Remove-OldBackups.ps1` | Retention cleanup with configurable policies |

## Quick Start

```powershell
# Install Windows Server Backup feature
Install-WindowsFeature Windows-Server-Backup

# Full backup to NAS
.\scripts\Invoke-SystemBackup.ps1 -Target "\\NAS01\Backups" -Type Full

# Schedule daily backup at 02:00
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
           -Argument '-NonInteractive -File C:\Scripts\Invoke-SystemBackup.ps1 -Type Incremental -Target \\NAS01\Backups'
$trigger = New-ScheduledTaskTrigger -Daily -At '02:00'
Register-ScheduledTask -TaskName 'DailyBackup' -Action $action -Trigger $trigger -RunLevel Highest
```

## Backup Strategy (3-2-1)

- **3** copies of data
- **2** different media types (local + NAS)
- **1** offsite (Azure Blob / S3)
