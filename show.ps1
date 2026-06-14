# show.ps1  —  部署在 Windows: C:\Users\YOUR_WIN_USER\.notify-win\show.ps1
# 由计划任务 "notify-win" 在【桌面会话】里执行(SSH 在 Session 0 无法直接弹窗，故用它桥接)。
# 读取队列目录里的 *.txt(每文件 4 行: titleB64 / msgB64 / sound / silent)，逐条弹 BurntToast 后删除。
$ErrorActionPreference='SilentlyContinue'
$dir="$env:USERPROFILE\.notify-win\queue"
if(-not(Test-Path $dir)){return}
Import-Module BurntToast
function D($s){ [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s)) }
Get-ChildItem "$dir\*.txt" | Sort-Object Name | ForEach-Object {
  try{
    $l = Get-Content $_.FullName
    $title=D $l[0]; $msg=D $l[1]; $sound=$l[2]; $silent=($l[3] -eq '1')
    if($silent){ New-BurntToastNotification -Text $title,$msg -Silent }
    else { New-BurntToastNotification -Text $title,$msg -Sound $sound }
  }catch{}
  Remove-Item $_.FullName -Force
}
