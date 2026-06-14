# notify-win show.ps1 — 部署在 Windows: C:\Users\YOUR_WIN_USER\.notify-win\show.ps1
# 计划任务 "notify-win" 经隐藏启动器 launcher.vbs 在【桌面会话】执行本脚本。
# 读队列 *.txt(4 行: titleB64 / msgB64 / sound / silent),弹静音 toast,再播放报警音。
# 要点:
#   - 互斥锁 + 排空循环 → 多条通知严格串行,杜绝并发抢音频(否则"只响第一条")。
#   - 声音不走 toast(会被免打扰静音),改用 SoundPlayer 直接放 wav。
#   - 播放前把系统主音量设为绝对 $VOL%,放完还原(与当前音量无关)。
$ErrorActionPreference='SilentlyContinue'
$base="$env:USERPROFILE\.notify-win"; $dir="$base\queue"
if(-not(Test-Path $dir)){return}
$WAV='C:\Windows\Media\Alarm01.wav'   # 响亮报警音
$VOL=40                                # 播放时的绝对音量(机器最大的%);放完还原原值
function D($s){ [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s)) }
Import-Module BurntToast
Import-Module AudioDeviceCmdlets
$mtx=New-Object System.Threading.Mutex($false,'Global\notifywin_show'); if(-not $mtx.WaitOne(30000)){return}
try{
  do{
    $files=@(Get-ChildItem "$dir\*.txt" -EA SilentlyContinue | Sort-Object Name)
    foreach($f in $files){
      try{
        $l=Get-Content $f.FullName
        $title=D $l[0]; $msg=D $l[1]; $silent=($l[3] -eq '1')
        Remove-Item $f.FullName -Force
        New-BurntToastNotification -Text $title,$msg -Silent
        if(-not $silent){
          $ov=$null;$om=$null
          try{ $ov=[int][math]::Round([double]((Get-AudioDevice -PlaybackVolume) -replace '[^\d.]','')); $om=[bool](Get-AudioDevice -PlaybackMute) }catch{}
          try{ Set-AudioDevice -PlaybackMute $false; Set-AudioDevice -PlaybackVolume $VOL }catch{}
          try{ (New-Object Media.SoundPlayer $WAV).PlaySync() }catch{}
          try{ if($ov -ne $null){ Set-AudioDevice -PlaybackVolume $ov }; if($om -ne $null){ Set-AudioDevice -PlaybackMute $om } }catch{}
        }
      }catch{}
    }
  } while($files.Count -gt 0)
} finally{ $mtx.ReleaseMutex(); $mtx.Dispose() }
