# notify-win

在 **Ubuntu** 上运行一条命令，向 **Windows 桌面**(`winbeau-win` / `YOUR_WIN_HOST`，用户 `YOUR_WIN_USER`)弹出通知 + 声音。

## 用法

```bash
notify-win -m "消息正文"                       # 默认标题、默认声音(Reminder)
notify-win -t "标题" -m "正文"                 # 自定义标题
notify-win -t 报警 -m "出错了" -s Alarm2        # 换声音
notify-win -t 静音 -m "无声通知" -q            # 静音
echo "管道里的内容" | notify-win -t 提醒        # 从管道读正文

# 实战
long_task && notify-win -m "任务完成 ✅" || notify-win -t 失败 -m "任务挂了 ❌" -s Alarm2
```

声音可选:`Default IM Mail Reminder SMS Alarm Alarm2..Alarm10 Call Call2..Call10`
退出码:`0` 成功；非 0 表示 SSH 或远端出错。

## 架构 / 为什么要桥接

```
Ubuntu                         Windows (winbeau-win YOUR_WIN_HOST)
┌──────────┐   SSH(key,:22)   ┌─ Session 0 (服务/SSH) ─┐   ┌─ Session 1 (你的桌面) ─┐
│notify-win│ ───────────────▶ │ 写队列 .txt           │   │ 计划任务 notify-win    │
│  (bash)  │  powershell      │ schtasks /run ────────┼──▶│  └ show.ps1            │
└──────────┘  -EncodedCommand └───────────────────────┘   │     └ BurntToast 弹窗  │
                                                           └────────────────────────┘
```

关键坑(已解决):
1. **SSH 登录在 Session 0**,它弹的 toast 在你桌面(Session 1)看不到 → 用**计划任务**桥接到桌面会话。
2. **PowerShell 通知权限默认可能被关** → Windows 设置里需允许"来自 PowerShell 的通知"(已开)。
3. 标题/正文各自 **base64(UTF-8)**,远端用 `powershell -EncodedCommand` → 中文/空格/引号全安全。

## 文件

| 位置 | 作用 |
|---|---|
| `notify-win` (Ubuntu, 已软链到 `~/.local/bin/`) | CLI 主体 |
| `~/.config/notify-win/config` (Ubuntu) | 覆盖 host/user/key/默认声音等 |
| `C:\Users\YOUR_WIN_USER\.notify-win\show.ps1` (Windows) | 计划任务执行体，读队列弹窗(本仓 `show.ps1` 是副本) |
| `C:\Users\YOUR_WIN_USER\.notify-win\queue\` (Windows) | 消息队列(投递后自动清理) |
| 计划任务 `notify-win` (Windows) | YOUR_WIN_USER 交互登录运行，把弹窗送到桌面 |

## 在新机器上重建

1. **Windows 装 OpenSSH Server + BurntToast**:参考 `notify-setup-v2.ps1`(管理员运行，经代理从 GitHub 装 OpenSSH，避开慢/卡的 Windows Update)。
2. **修主机密钥权限并启动 sshd**:参考 `notify-finish.ps1`(关键是 `FixHostFilePermissions.ps1`)。
3. **导入公钥**:管理员账户放 `C:\ProgramData\ssh\administrators_authorized_keys` 并收紧 ACL。
4. **建桥接计划任务 + show.ps1**:任务以 `LogonType Interactive` 运行 `show.ps1`(见上)。
5. **Windows 设置**:允许"来自 PowerShell 的通知"(否则 toast 被静默)。
6. 改 `~/.config/notify-win/config` 里的 `WIN_HOST/WIN_USER` 指向新机器。
