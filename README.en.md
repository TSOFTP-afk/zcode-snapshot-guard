# ZCode Snapshot Guard

> 🛡️ Dual-layer local defense against the Zhipu ZCode desktop client silently packaging your entire workspace (including the full `.git` history) and attempting to upload it to the cloud.
> **Deployable with plain user privileges — no admin required.** Purely defensive; does not modify ZCode itself.

> 🇨🇳 **[中文文档（更完整）](README.md)**

## Background

In Sep 2026 the community disclosed that ZCode, while signed in, packages the whole workspace — including all `.git` objects, packfiles and reflog — into an encrypted tar.gz and uploads it to cloud storage (Aliyun OSS), with **no toggle to disable it**; the training-data opt-out does not stop the packaging/upload. The vendor responded that it came from a "codebase index / Repo Wiki" feature, claims it is fixed, and promised to open-source the client ([official response](https://forum.trae.cn/t/topic/181727)).

Coverage: [BlockBeats](https://en.theblockbeats.news/flash/367816) · [reverse-engineering writeup by ferstar](https://blog.ferstar.org/posts/zcode-silent-workspace-snapshot-upload/)

Full (sanitized) technical findings: [docs/EVIDENCE.md](docs/EVIDENCE.md)

## Quick start (Windows PowerShell, no admin)

```powershell
iwr https://raw.githubusercontent.com/TSOFTP-afk/zcode-snapshot-guard/main/ZcodeSnapshotGuard.ps1 -OutFile ZcodeSnapshotGuard.ps1
.\ZcodeSnapshotGuard.ps1 install
```

## How it works

| Layer | Mechanism | Effect |
|---|---|---|
| 1. ACL write-deny | `Deny (WD,AD)` on `%USERPROFILE%\.zcode\v2\checkpoints` | Snapshot artifacts can never be written; pipeline fails at write time, no race window |
| 2. Kill sentinel | Background loop (autostart, single-instance) deleting any `*.tar.gz.enc` / `*.envelope.json` / files under `checkpoints\` or `pending\` within `~\.zcode` | Catches relocated storage paths and ACL resets |

## Commands

```powershell
.\ZcodeSnapshotGuard.ps1 install | status | sweep | run | uninstall
```

## Verify it is working

Sentinel log: `%USERPROFILE%\.zcode-guard.log`. Any new `deleted:` line means ZCode attempted to write a snapshot — screenshot it as evidence.

## Optional layer 3: network quarantine (admin)

```powershell
.\Block-ZcodeNetwork.ps1 -TelemetryHosts     # hosts-pin known telemetry endpoints
.\Block-ZcodeNetwork.ps1 -FirewallBlock -ZcodeExe F:\Zcode\ZCode.exe   # full quarantine (kills model API too)
.\Block-ZcodeNetwork.ps1 -Undo
```

Note: blocking "Aliyun IP ranges" is counterproductive — the model API itself (e.g. `open.bigmodel.cn`) is also hosted on Aliyun IPs; and Windows Firewall has no domain-based rules.

## Known limitations

1. The vendor controls the client: future versions may relocate storage or reset ACLs. Re-run `status` after every ZCode update.
2. Local checkpoint / rollback features stop working (by design).
3. Telemetry channels (device id, DAU, OTLP/RUM) are not covered by layers 1–2.
4. v3.12.3 was built (Sep 16) *before* the vendor's Sep 18 "fixed" statement — keep the guard on after updating.

## License

[MIT](LICENSE). Not affiliated with Zhipu AI / ZCode. Community defense tool only.
