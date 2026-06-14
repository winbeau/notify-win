#requires -RunAsAdministrator
# Finish notify-win setup: fix host-key perms, start sshd, install BurntToast. Logs to file.
Start-Transcript -Path 'C:\Users\YOUR_WIN_USER\notify-finish.log' -Force | Out-Null
$proxy = 'http://127.0.0.1:10808'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy($proxy, $true)
$dst = 'C:\Program Files\OpenSSH'
$pd  = "$env:ProgramData\ssh"
$log = @()
function Step($n, $sb) {
    try { & $sb; Write-Host "OK  $n"; $script:log += "OK  $n" }
    catch { Write-Host "ERR $n :: $($_.Exception.Message)"; $script:log += "ERR $n :: $($_.Exception.Message)" }
}

Step 'host keys (ssh-keygen -A)' { & "$dst\ssh-keygen.exe" -A | Out-Null }
Step 'fix host-key ACL' {
    if (-not (Test-Path $pd)) { New-Item -ItemType Directory -Path $pd -Force | Out-Null }
    Get-ChildItem "$pd\ssh_host_*_key" -ErrorAction SilentlyContinue | ForEach-Object {
        icacls $_.FullName /inheritance:r /grant 'SYSTEM:R' /grant 'BUILTIN\Administrators:R' | Out-Null
    }
}
Step 'sshd_config' {
    if (-not (Test-Path "$pd\sshd_config") -and (Test-Path "$dst\sshd_config_default")) {
        Copy-Item "$dst\sshd_config_default" "$pd\sshd_config"
    }
}
Step 'service Automatic' {
    Set-Service sshd -StartupType Automatic
    if (Get-Service ssh-agent -ErrorAction SilentlyContinue) { Set-Service ssh-agent -StartupType Automatic }
}
Step 'firewall TCP 22' {
    if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    }
}
Step 'default shell -> PowerShell' {
    if (-not (Test-Path 'HKLM:\SOFTWARE\OpenSSH')) { New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null }
    New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell `
        -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force | Out-Null
}
Step 'authorized key + ACL' {
    $pub = 'ssh-ed25519 AAAA...REPLACE_WITH_YOUR_PUBLIC_KEY'
    $akf = "$pd\administrators_authorized_keys"
    if (-not ((Test-Path $akf) -and (Select-String -Path $akf -SimpleMatch $pub -Quiet))) {
        Add-Content -Path $akf -Value $pub -Encoding ascii
    }
    icacls $akf /inheritance:r /grant 'SYSTEM:F' /grant 'BUILTIN\Administrators:F' | Out-Null
}
Step 'start sshd' { Start-Service sshd }
Step 'BurntToast (via proxy)' {
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Proxy $proxy | Out-Null
    }
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    if (-not (Get-Module -ListAvailable -Name BurntToast)) {
        Install-Module BurntToast -Scope AllUsers -Force -AllowClobber -Proxy $proxy
    }
}

Write-Host ''
Write-Host '=== SUMMARY ==='
$log | ForEach-Object { Write-Host $_ }
Write-Host ("sshd="       + (Get-Service sshd).Status)
Write-Host ("port22="     + (Test-NetConnection 127.0.0.1 -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue))
Write-Host ("burnttoast=" + [bool](Get-Module -ListAvailable BurntToast))
Write-Host '=== END ==='
Stop-Transcript | Out-Null
