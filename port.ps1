# Requires running PowerShell as Administrator

# Define the name of your WSL distribution (e.g., Ubuntu, Debian, etc.)
# Run 'wsl -l -q' to see your installed distributions.
param(
	[string]$DistroName = (wsl.exe -l -q | Select-Object -First 1)
)

if ([string]::IsNullOrWhiteSpace($DistroName)) {
	throw "Unable to resolve default WSL distribution. Please rerun with -DistroName <Name>."
}

$DistroName = $DistroName.Trim()

# Validate that the distribution exists before proceeding
$existingDistros = wsl.exe -l -q 2>$null
if ($existingDistros -notcontains $DistroName) {
	throw "WSL distribution '$DistroName' not found. Available distros:`n$existingDistros"
}

$baseName = ($DistroName -split '[-_\s]')[0]
if ([string]::IsNullOrWhiteSpace($baseName)) {
	$baseName = $DistroName
}

$sanitize = {
	param (
		[string]$value,
		[int]$maxLength = 63
	)

	if ([string]::IsNullOrWhiteSpace($value)) { return "WSL" }
	$clean = [regex]::Replace($value, '[^A-Za-z0-9_-]+', '_')
	$clean = $clean.Trim('_')
	if ([string]::IsNullOrWhiteSpace($clean)) { $clean = "WSL" }
	if ($clean.Length -gt $maxLength) {
		$clean = $clean.Substring(0, $maxLength)
	}
	return $clean
}

$distroDescription = $baseName
$distroSlug = & $sanitize $baseName
if ([string]::IsNullOrWhiteSpace($distroSlug)) {
	$distroSlug = & $sanitize $DistroName
}

Write-Host "Using WSL distribution label: $distroDescription (slug: $distroSlug)" -ForegroundColor Yellow

# Define the task name and description
$TaskName = "Start-WSL-$distroSlug-on-Boot"
$TaskDescription = "Automatically starts the $distroDescription WSL distribution on system boot."

# Remove any existing Start-WSL* scheduled tasks to avoid duplicates
try {
	$matchingTasks = Get-ScheduledTask -TaskName 'Start-WSL*' -ErrorAction SilentlyContinue
	if ($matchingTasks) {
		foreach ($task in $matchingTasks) {
			try {
				Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction Stop
				Write-Host "Removed existing scheduled task '$($task.TaskName)'." -ForegroundColor DarkYellow
			} catch {
				Write-Warning "Failed to remove scheduled task '$($task.TaskName)': $($_.Exception.Message)"
			}
		}
	}
} catch {
	Write-Warning "Unable to enumerate existing Start-WSL tasks: $($_.Exception.Message)"
}

# This PowerShell script forwards port 80 on Windows to WSL (nginx) and sets a firewall rule for inbound connections on port 80
# Run as Administrator on Windows

$wsl_ip = (wsl hostname -I).Split(" ")[0]
# 1) Forward host → WSL loopback for all three ports
netsh interface portproxy add v4tov4 listenport=80   listenaddress=0.0.0.0 connectport=80   connectaddress=$wsl_ip
netsh interface portproxy add v4tov4 listenport=8081 listenaddress=0.0.0.0 connectport=8081 connectaddress=$wsl_ip
netsh interface portproxy add v4tov4 listenport=8080 listenaddress=0.0.0.0 connectport=8080 connectaddress=$wsl_ip

# 2) Allow inbound traffic on those ports
New-NetFirewallRule -DisplayName "Allow HTTP 80"   -Direction Inbound -LocalPort 80   -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "Allow Privoxy 8081" -Direction Inbound -LocalPort 8081 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "Allow SSHSOCKS 8080"-Direction Inbound -LocalPort 8080 -Protocol TCP -Action Allow

Write-Host "Current portproxy entries:" -ForegroundColor Cyan
netsh interface portproxy show all

# 3) Ensure WSL proxy services start automatically on Windows boot
$Action = New-ScheduledTaskAction -Execute "C:\Windows\System32\wsl.exe" -Argument "-d $DistroName"
# Older PowerShell builds do not support the -Delay switch, so we skip it for compatibility.
$Trigger = New-ScheduledTaskTrigger -AtStartup
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType Service
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit "00:00:00" -StartWhenAvailable

$taskRegistered = $false
try {
	Register-ScheduledTask -TaskName $TaskName -Description $TaskDescription -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force | Out-Null
	$taskRegistered = $true
	Write-Host "Scheduled Task '$TaskName' created successfully." -ForegroundColor Green
} catch {
	Write-Warning "Failed to register scheduled task '$TaskName': $($_.Exception.Message)"
}

if ($taskRegistered) {
	try {
		Write-Host "Scheduled Task status:" -ForegroundColor Cyan
		Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo | Format-List *
	} catch {
		Write-Warning "Unable to query scheduled task '$TaskName': $($_.Exception.Message)"
	}
}
