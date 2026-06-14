#requires -RunAsAdministrator
# notify-win setup v2 : install OpenSSH from GitHub + BurntToast, all via proxy.
$ErrorActionPreference = 'Stop'
$proxy = 'http://127.0.0.1:10808'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy($proxy, $true)
Write-Host "== notify-win setup v2 (proxy $proxy) ==" -ForegroundColor Cyan

$dst = 'C:\Program Files\OpenSSH'
$haveBin = (Test-Path 'C:\Windows\System32\OpenSSH\sshd.exe') -or (Test-Path "$dst\sshd.exe")

# 1. Download Win32-OpenSSH from GitHub via proxy
if (-not $haveBin) {
    $zip = "$env:TEMP\OpenSSH-Win64.zip"
    $urls = @(
        'https://github.com/PowerShell/Win32-OpenSSH/releases/latest/download/OpenSSH-Win64.zip',
        'https://github.com/PowerShell/Win32-OpenSSH/releases/download/v9.5.0.0p1-Beta/OpenSSH-Win64.zip'
    )
    $ok = $false
    foreach ($u in $urls) {
        try {
            Write-Host "[1/8] Downloading OpenSSH via proxy: $u"
            Invoke-WebRequest -Uri $u -OutFile $zip -Proxy $proxy -UseBasicParsing
            $ok = $true; break
        } catch { Write-Host "   failed: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
    if (-not $ok) { throw 'OpenSSH download failed on all URLs' }
    Write-Host '   expanding ...'
    Expand-Archive -Path $zip -DestinationPath $env:TEMP -Force
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    Move-Item "$env:TEMP\OpenSSH-Win64" $dst
    Get-ChildItem $dst -Recurse | Unblock-File
} else { Write-Host '[1/8] OpenSSH binaries already present' }

$sshDir = if (Test-Path "$dst\sshd.exe") { $dst } else { 'C:\Windows\System32\OpenSSH' }

# 2. Register sshd / ssh-agent services
Write-Host '[2/8] Registering sshd service ...'
if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
    & powershell.exe -ExecutionPolicy Bypass -File "$sshDir\install-sshd.ps1"
}

# 3. Host keys + default config
Write-Host '[3/8] Host keys & sshd_config ...'
$pd = "$env:ProgramData\ssh"
if (-not (Test-Path $pd)) { New-Item -ItemType Directory -Path $pd -Force | Out-Null }
& "$sshDir\ssh-keygen.exe" -A | Out-Null
if ((Test-Path "$sshDir\sshd_config_default") -and -not (Test-Path "$pd\sshd_config")) {
    Copy-Item "$sshDir\sshd_config_default" "$pd\sshd_config"
}

# 4. Service Automatic
Write-Host '[4/8] sshd -> Automatic ...'
Set-Service sshd -StartupType Automatic
if (Get-Service ssh-agent -ErrorAction SilentlyContinue) { Set-Service ssh-agent -StartupType Automatic }

# 5. Firewall
Write-Host '[5/8] Firewall TCP 22 ...'
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}

# 6. Default shell = PowerShell
Write-Host '[6/8] Default shell -> PowerShell ...'
if (-not (Test-Path 'HKLM:\SOFTWARE\OpenSSH')) { New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null }
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell `
    -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force | Out-Null

# 7. Authorized key (admin -> administrators_authorized_keys) + ACL
Write-Host '[7/8] Importing public key ...'
$pub = 'ssh-ed25519 AAAA...REPLACE_WITH_YOUR_PUBLIC_KEY'
$akf = "$pd\administrators_authorized_keys"
if (-not ((Test-Path $akf) -and (Select-String -Path $akf -SimpleMatch $pub -Quiet))) {
    Add-Content -Path $akf -Value $pub -Encoding ascii
}
icacls $akf /inheritance:r /grant 'SYSTEM:F' /grant 'BUILTIN\Administrators:F' | Out-Null

Start-Service sshd

# 8. BurntToast via proxy
Write-Host '[8/8] Installing BurntToast via proxy ...'
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Proxy $proxy | Out-Null
}
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
if (-not (Get-Module -ListAvailable -Name BurntToast)) {
    Install-Module BurntToast -Scope AllUsers -Force -AllowClobber -Proxy $proxy
} else { Write-Host '   BurntToast already installed' }

Restart-Service sshd
Write-Host ''
Write-Host 'DONE. sshd running, key imported, BurntToast ready.' -ForegroundColor Green
