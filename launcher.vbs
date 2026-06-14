' launcher.vbs — 部署在 Windows: C:\Users\YOUR_WIN_USER\.notify-win\launcher.vbs
' 计划任务 "notify-win" 调它来启动 show.ps1。
' 用 wscript 隐藏启动(窗口模式 0 = 完全无窗),避免任务计划直接跑 powershell 时
' 一闪而过的控制台触发"全屏自动免打扰";第三参数 True = 等 powershell 结束,
' 这样任务计划的 MultipleInstances=Queue 才能真正串行(否则异步秒退,串行失效)。
CreateObject("Wscript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""C:\Users\YOUR_WIN_USER\.notify-win\show.ps1""", 0, True
