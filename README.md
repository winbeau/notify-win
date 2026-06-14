# notify-win

在 **Ubuntu** 上运行一条命令，向 **Windows 桌面**弹出通知 + 响铃。

## 用法

```bash
notify-win -m "消息正文"                 # 默认标题
notify-win -t "标题" -m "正文"           # 自定义标题
notify-win -q -m "无声通知"              # 静音(不响铃)
echo "管道内容" | notify-win -t "提醒"    # 从管道读正文

# 实战
long_task && notify-win -t '✅ 完成' -m '任务跑完了' \
          || notify-win -t '❌ 失败' -m '任务挂了, 见 log'
```

- `-m` 正文（必填，或管道）
- `-t` 标题（可选，默认 `Ubuntu 通知`）
- `-q` 静音
- `-s` 仍可传但**当前不影响声音**（声音已统一，见下）。标题/正文走 base64，中文/emoji/引号/空格全安全。

## 架构 / 为什么这么绕

```
Ubuntu                         Windows
┌──────────┐  SSH(key,:22)    ┌─ Session 0 (sshd/服务) ─┐   ┌─ Session 1 (桌面) ──────────┐
│notify-win│ ───────────────▶ │ 写 base64 消息到队列     │   │ 计划任务 notify-win          │
│  (bash)  │ powershell        │ schtasks /run ──────────┼──▶│  └ launcher.vbs(隐藏)       │
└──────────┘ -EncodedCommand  └─────────────────────────┘   │     └ show.ps1               │
                                                            │        ├ BurntToast 静音弹窗 │
                                                            │        └ SoundPlayer 响铃    │
                                                            └─────────────────────────────┘
```

踩过的坑(都已解决)：
1. **SSH 在 Session 0**，弹窗/声音到不了你的桌面(Session 1) → 用**计划任务**桥接到桌面会话。
2. **免打扰会静音 toast 声音** → 声音**不走 toast**(toast 设 `-Silent`)，改用 `SoundPlayer` 直接放 wav，免打扰管不着。
3. **任务计划跑 powershell 会闪控制台**(疑似触发"全屏自动免打扰") → 用 `launcher.vbs` 隐藏启动(窗口模式 0)。
4. **多条通知并发抢音频 → 只响第一条** → `launcher.vbs` 同步等待 + 任务 `MultipleInstances=Queue` + show.ps1 **全局互斥锁 + 排空循环**，严格串行。
5. **声音忽大忽小** → 播放前把系统主音量设为**绝对 40%**，放完**还原**(与当前音量无关)。
6. PowerShell 通知权限需在 Windows 设置里允许(否则 toast 不显示；声音不受影响)。

## 文件

| 位置 | 作用 |
|---|---|
| `notify-win` (Ubuntu, 软链到 `~/.local/bin/`) | CLI 主体 |
| `~/.config/notify-win/config` (Ubuntu) | host/user/key 等(见 `config.example`) |
| `C:\Users\<用户>\.notify-win\launcher.vbs` | 隐藏启动器(任务调它) |
| `C:\Users\<用户>\.notify-win\show.ps1` | 桥接执行体:弹窗 + 响铃 + 音量控制(本仓有副本) |
| `C:\Users\<用户>\.notify-win\queue\` | 消息队列(投递后自动清理) |
| 计划任务 `notify-win` (Queue, 交互登录) | 把弹窗/声音送到桌面 |

## Windows 端依赖

- **OpenSSH Server**(从 GitHub 经代理装，见 `notify-setup-v2.ps1` / `notify-finish.ps1`）
- **BurntToast**（toast）+ **AudioDeviceCmdlets**（控制主音量）。两者 `Install-Module -Scope CurrentUser`，必要时加 `-Proxy`。

## 在新机器上重建

1. 装 OpenSSH Server，导入公钥到 `administrators_authorized_keys`（管理员账户），`FixHostFilePermissions.ps1` 修权限后启动 sshd。
2. `Install-Module BurntToast,AudioDeviceCmdlets -Scope CurrentUser`。
3. 建 `~/.notify-win\{show.ps1,launcher.vbs,queue}`（本仓副本，改路径里的用户名）。
4. 注册计划任务 `notify-win`：`wscript.exe "...\launcher.vbs"`，`LogonType Interactive`，`MultipleInstances Queue`。
5. Windows 设置里允许"来自 PowerShell 的通知"。
6. 改 `~/.config/notify-win/config` 指向新机器。
