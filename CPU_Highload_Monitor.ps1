# Define email parameters
$smtpServer = "smtp.office365.com"
$smtpPort = 587
$from = "IT@lfayou.co.il"
$to = "backup@lfayou.co.il"
$subject = "High CPU Usage Alert"
$credential = Import-Clixml -Path "C:\LFAMonitor\ps_credentials.xml"

# Define CPU threshold and monitoring duration
$cpuThreshold = 80  # CPU usage percentage
$monitorDuration = 10  # Monitoring duration in minutes
$checkInterval = 30  # Check every 30 seconds

# Path for logs
$logPath = "C:\LFAMonitor\CPU_Logs"
if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath
}

# Weekly log file management
$logFile = Join-Path $logPath "CPU_Log_$(Get-Date -Format 'yyyy-MM-dd').log"

# Track high CPU processes
$highCpuProcesses = @{}

Write-Output "[INFO] CPU Monitoring script started at $(Get-Date)"

# Monitor CPU usage
while ($true) {
    try {
        # Get processes using more CPU than the threshold
        $processes = Get-Process | Where-Object { $_.CPU -gt $cpuThreshold }

        foreach ($process in $processes) {
            $processId = $process.Id

            if (-not $highCpuProcesses.ContainsKey($processId)) {
                # Start tracking the process
                $highCpuProcesses[$processId] = [PSCustomObject]@{
                    Name = $process.ProcessName
                    Id = $process.Id
                    StartTime = Get-Date
                    CPU = $process.CPU
                }
            } else {
                # Calculate elapsed time
                $elapsedTime = (Get-Date) - $highCpuProcesses[$processId].StartTime

                if ($elapsedTime.TotalMinutes -ge $monitorDuration) {
                    # Send email if threshold exceeded for more than 10 minutes
                    $body = @"
High CPU Usage Detected!

Process Name: $($process.ProcessName)
Process ID: $($process.Id)
CPU Usage: $($process.CPU)%
Elapsed Time: $($elapsedTime.TotalMinutes) minutes

Please investigate.
"@

                    $mailMessage = New-Object System.Net.Mail.MailMessage($from, $to, $subject, $body)
                    $smtpClient = New-Object System.Net.Mail.SmtpClient($smtpServer, $smtpPort)
                    $smtpClient.EnableSsl = $true
                    $smtpClient.Credentials = $credential

                    try {
                        $smtpClient.Send($mailMessage)
                        Write-Output "[INFO] Email sent for process $($process.ProcessName) (PID: $($process.Id))"
                    } catch {
                        Write-Output "[ERROR] Failed to send email: $_"
                    }

                    # Log the email sent
                    $logMessage = "$(Get-Date) - High CPU detected: $($process.ProcessName) (PID: $($process.Id)), CPU: $($process.CPU)%, Elapsed Time: $($elapsedTime.TotalMinutes) min"
                    Add-Content -Path $logFile -Value $logMessage

                    # Remove the process from tracking
                    $highCpuProcesses.Remove($processId)
                }
            }
        }

        # Clean up tracked processes that no longer exist or are below the threshold
        $highCpuProcesses.Keys | ForEach-Object {
            if (-not (Get-Process -Id $_ -ErrorAction SilentlyContinue) -or $highCpuProcesses[$_].CPU -lt $cpuThreshold) {
                $highCpuProcesses.Remove($_)
            }
        }
    } catch {
        # Handle unexpected errors
        $errorDetails = $_.Exception.Message
        Write-Output "[ERROR] Monitoring error: $errorDetails"
        $errorMsg = "$(Get-Date) - Monitoring error: $errorDetails"
        Add-Content -Path $logFile -Value $errorMsg
    }

    Start-Sleep -Seconds $checkInterval
}
