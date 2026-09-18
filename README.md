# ZCode Snapshot Guard（快照歼灭哨兵）

> 🛡️ 针对智谱 ZCode 桌面客户端「静默打包整个工作区（含完整 `.git` 历史）并尝试上传云端」问题的本地双防线工具。
> **普通用户权限即可部署，无需管理员。** 纯防御用途，不修改 ZCode 本体。

---

## ⚠️ 背景：发生了什么

2026-09 社区披露：ZCode 客户端会在登录状态下，把整个工作区（包括 `.git` 全部历史对象、pack 文件、reflog）打包为加密 tar.gz，向云端（阿里云 OSS）上传，且：

- 应用内 **没有任何开关可以关闭** 该行为；
- 「优化计划」开关（仅控制训练用途）**关闭后依然打包上传**；
- 官方随后回应称源于「代码库索引 / Repo Wiki」功能，称已修复，并承诺开源（[官方回应全文](https://forum.trae.cn/t/topic/181727)）。

媒体报道与讨论：

- [BlockBeats：智谱 ZCode 被曝后台打包上传整个项目，连 Git 历史都不放过](https://en.theblockbeats.news/flash/367816)
- [新浪：《开关明明关闭，699MB 本地快照为何仍被上传？》](https://www.sina.cn/news/detail/5344548169714377.html)
- [V2EX 讨论](https://global.v2ex.co/t/1242957#reply0) · [大佬说讨论](https://locdd.com/t/topic/92383)
- 逆向分析原文：[ferstar 的博客](https://blog.ferstar.org/posts/zcode-silent-workspace-snapshot-upload/)

> 详细技术取证（已脱敏）见 [docs/EVIDENCE.md](docs/EVIDENCE.md)。

---

## 🚀 快速开始

**Windows PowerShell（普通权限，无需管理员）：**

```powershell
# 方式一：一键下载 + 安装
iwr https://raw.githubusercontent.com/TSOFTP-afk/zcode-snapshot-guard/main/ZcodeSnapshotGuard.ps1 -OutFile ZcodeSnapshotGuard.ps1
.\ZcodeSnapshotGuard.ps1 install

# 方式二：克隆仓库
git clone https://github.com/TSOFTP-afk/zcode-snapshot-guard.git
cd zcode-snapshot-guard
.\ZcodeSnapshotGuard.ps1 install
```

> 💡 **国内网络提示**：`raw.githubusercontent.com` 直连可能超时。可在 URL 前加任意加速前缀（如 `https://ghproxy.net/` + 原始地址），或直接用方式二 `git clone` / 网页下载 ZIP。

安装完成后建议重启一次 ZCode，然后随时用 `status` 检查防线状态。

---

## 🧱 双防线原理

```
┌─ 第一层：ACL 拒写（主防线）──────────────────────┐
│  对 %USERPROFILE%\.zcode\v2\checkpoints              │
│  施加 Deny (WD,AD)：ZCode 连第一个字节都写不进去，      │
│  快照流水线在「落盘」一步操作系统级失败。               │
│  ★ 不存在删除竞态窗口；仅拒绝当前用户，属文件属主权利，  │
│    无需管理员。                                       │
└──────────────────────────────────────────────┘
┌─ 第二层：歼灭哨兵（兑底）─────────────────────────┐
│  后台常驻（开机自启、单实例互斥），每 5 秒扫描           │
│  %USERPROFILE%\.zcode：                                │
│   • 任意 checkpoints\ 或 pending\ 目录内的文件          │
│   • 任意位置的 *.tar.gz.enc / *.envelope.json           │
│  一旦发现 → 立即删除（Remove-Item + cmd del 双保险，     │
│  文件被占用时自动重试）。                               │
│  ★ 防厂商换存储路径 / ACL 被更新程序重置。              │
└──────────────────────────────────────────────┘
```

---

## 📖 使用

```powershell
.\ZcodeSnapshotGuard.ps1 install    # 部署 ACL + 哨兵 + 开机自启
.\ZcodeSnapshotGuard.ps1 status     # 查看防线状态
.\ZcodeSnapshotGuard.ps1 sweep      # 手动清扫一次
.\ZcodeSnapshotGuard.ps1 run        # 前台运行哨兵（调试用）
.\ZcodeSnapshotGuard.ps1 uninstall  # 完整撤防
```

`status` 输出示例：

```
[*] data root   : C:\Users\you\.zcode
[+] layer 1 ACL     : ACTIVE (checkpoints is write-denied)
[+] autostart       : installed
[+] layer 2 sentinel: running (pid 13164)
[*] artifacts   : 0 snapshot file(s) currently on disk
```

## 🕵️ 抓现行

哨兵日志在 `%USERPROFILE%\.zcode-guard.log`。**只要出现新的 `deleted:` 记录，就说明 ZCode 正在试图生成快照**——这就是可截图留证的「现行」。

---

## 🔌 可选第三层：网络隔离（需管理员）

`Block-ZcodeNetwork.ps1` 提供两种网络层手段，按需选用：

```powershell
# 以管理员身份运行 PowerShell 后：
.\Block-ZcodeNetwork.ps1 -TelemetryHosts                    # B: hosts 钉死已知遥测域名（温和）
.\Block-ZcodeNetwork.ps1 -FirewallBlock -ZcodeExe F:\Zcode\ZCode.exe   # A: 防火墙整体断网（隔离模式）
.\Block-ZcodeNetwork.ps1 -Undo                              # 撤销
```

| 方案 | 挡住什么 | 代价 |
|---|---|---|
| B 遥测钉死 | SLS/RUM 遥测上报 | 挡不住快照上传（OSS 端点动态下发） |
| A 防火墙断网 | 一切外联 | **模型 API 也没了**，适合「暂弃用」期 |

> 为什么不建议按「阿里云 IP 段」屏蔽：模型 API 本身（如 `open.bigmodel.cn`）也托管在阿里云 IP 上，按段屏蔽会自断模型；且 Windows 自带防火墙不支持域名规则。

---

## 🪤 已知局限（必读）

1. **厂商控制客户端**。理论上后续版本可以更换存储路径、修改文件名，甚至由更新程序重置 ACL。哨兵的通配模式可兑住大部分变化，但不是绝对——每次 ZCode 大版本更新后请跑一次 `status`。
2. **本地检查点 / 历史回滚功能会一并失效**（快照写不进去，自然无法回滚）——这正是本工具的目的。
3. **不覆盖遥测通道**（设备号、日活、OTLP/RUM 上报），网络层请配合上面的可选项。
4. **版本注意**：官方 9/18 才回应「已修复」，而 3.12.3 构建于 9/16——修复大概率不在该包内。升级后请保留本防线并观察日志。

## 🧹 卸载

```powershell
.\ZcodeSnapshotGuard.ps1 uninstall
```

会：停掉哨兵进程、移除开机自启、解除 ACL 拒写。日志文件保留（可手动删 `%USERPROFILE%\.zcode-guard.log`）。

## ❓ FAQ

**会误删我的正常文件吗？**
不会。扫描范围仅限 `%USERPROFILE%\.zcode`（ZCode 私有数据目录），且只匹配 `checkpoints\`、`pending\` 目录内文件与 `*.tar.gz.enc`、`*.envelope.json` 两类快照产物名。你的项目、`.git` 本体都在别处，不受影响。

**为什么不用管理员权限就能改 ACL？**
`~\.zcode` 属于当前用户，文件属主天然有权修改自己的 DACL（拒绝项），无需提权。

**ZCode 自动更新后需要重新部署吗？**
不需要。防线基于目录与文件模式，与 ZCode 版本无关；但建议更新后跑 `status` 确认。

---

## 📄 License

[MIT](LICENSE) · 本项目与智谱 AI / ZCode 官方无任何关联，仅为社区防御工具。
