# 技术取证记录（已脱敏）

> 基于本机 **ZCode 3.11.2**（Windows x64，构建时间 2026-09-04）的静态分析与本地残留物取证。
> 所有路径已脱敏为占位符；不包含任何用户数据、密钥或工作区内容。

## 1. 数据目录布局

```
%USERPROFILE%\.zcode\v2\
├── checkpoints\                          # 快照引擎工作区
│   └── <workspace-hash>\
│       ├── manifests\<manifest-hash>.json     # 文件清单（含完整 .git 路径）
│       ├── extra-manifests\<hash>.json        # 全局行为配置等附加物
│       ├── pending\<group>.tar.gz.enc         # ★ 加密快照包（待上传）
│       ├── pending\<group>.envelope.json      # ★ 加密信封（密钥包装参数）
│       └── state.json                         # 上传任务状态（凭证/失败计数）
├── logs\YYYY-MM-DD.log                   # 应用日志（对快照行为零记录）
├── telemetry-state.json                  # deviceMid + 日活
├── certs\zcode-network-ca.key            # ⚠ 本地 CA 私钥明文存放
└── config.json / credentials.json        # ⚠ 服务商 API Key 明文存放
```

## 2. 信封（envelope）结构

```json
{
  "schema": "repo_snapshot_encrypted_artifact/v2",
  "contentAlgorithm": "aes-256-ctr",
  "keyWrapAlgorithm": "rsa-oaep-sha256",
  "keyId": "1",
  "nonceEncoding": "ciphertext-prefix-16-byte",
  "aadEncoding": "canonical-json-v1",
  "aad": { "workspaceKeyHash": "<hash>", "kind": "baseline", "manifestHash": "<hash>", "compression": "tar.gz" },
  "encryptedDataKey": "<base64, 256 bytes = RSA-2048>",
  "plaintextSha256": "<hash>"
}
```

要点：内容为 AES-256-CTR（随机前缀 nonce），数据密钥用**服务端 RSA-2048-OAEP 公钥**包装（`keyId:"1"` 静态密钥对）。客户端代码只包含公钥处理逻辑（`normalizePublicKeySpkiPem`），**本地无私钥、无明文数据密钥缓存** —— 本地解密在数学上不可行；而服务端可通过上传回调拿回 `encrypted_aes_key`（见下），具备完全解密能力。

## 3. 上传任务状态（state.json）关键字段

```
activeUpload / pendingUpload:
  uploadCredentialHandle : <服务端下发的上传凭证句柄>
  encryptedArtifactPath  : <pending\*.tar.gz.enc>
  kind: baseline         # baseline→服务端 update_type "full"
  attemptCount / lastAttemptAt
  attribution:
    sessionId / queryId / requestId
    failureCount: 7       # 上传失败计数
    captureStage: "terminal"   # ★ 会话结束时触发采集
```

实测时间线：`repoSnapshotIndexingEnabled=false` 已落盘（00:05 应用日志可见）之后，01:25 仍生成全量 baseline 快照并尝试上传 → **开关不拦此行为**，与媒体报道一致。

## 4. 清单（manifest）包含完整 .git

`repo_snapshot_manifest/v2` 格式，实测单份清单 40,967 行（约 1 万文件），`.git` 相关条目包括：

```
.git/objects/**            # 全部历史对象
.git/objects/pack/*.pack|.idx|.rev
.git/logs/HEAD             # reflog
.git/config                # 远端配置（可能含带凭据的 remote URL）
.git/refs/heads/**, refs/tags/**, packed-refs
```

与媒体披露的商业项目案例（4.2 万文件、.git 占 86.6%）量级一致。

## 5. 客户端代码证据（打包产物 app.asar 内）

- `encodeOssCallback` / `replaceOssCallbackPlaceholders`：阿里云 OSS 直传 + 回调确认；
- 回调 `callbackBody` 携带 `encrypted_aes_key`（即被服务端公钥包装的 AES 数据密钥）与 `x:base_snapshot_id` —— **上传成功瞬间服务端即获得解密能力**；
- `toServerUpdateType`：`baseline→full`，`incremental→incremental`；
- 凭证校验：`max_size`、`snapshot_id`、`oss.path`（对象键由服务端指定）；
- 文件遍历器内置忽略集：`node_modules`、`.cache`、`.turbo`、顶层 `dist/build/out/.next/coverage`，及"疑似密钥路径"（`.env*`、`id_rsa`、`*.pem/*.key/*.p12/*.pfx`、含 `token/secret` 的名字）—— 但实际 baseline 照样打包了完整 `.git`，**规则与行为不符**；
- 触发时机：会话结束（`captureStage: "terminal"`），失败后驻留 `pending\` 无限重试。

## 6. 遥测通道（与快照相互独立）

- OpenTelemetry → `proj-xtrace-*.cn-beijing.log.aliyuncs.com`（`OTEL_SERVICE_NAME="zcode-cli-agent"`）
- ARMS RUM → `sdk.rum.aliyuncs.com`
- 服务端点：`zcode.z.ai`、`wss://zcode.z.ai/ws`、更新 CDN `cdn-zcode.z.ai`

## 7. 为什么本地无法解密（自证）

1. app.asar 全量搜索：仅存在公钥处理函数，无快照相关私钥；
2. `~/.zcode` 全盘搜索：`encryptedDataKey` 仅存在于信封文件，无明文密钥缓存；
3. AES-256-CTR + RSA-2048-OAEP 组合无已知攻击面；nonce 随机、AAD 绑定清单哈希。

结论：**加密防的是本地窃取，防不了厂商服务端**——后者通过回调自动获得解密钥匙。

## 8. 检测指标（IOC）

| 类型 | 指标 |
|---|---|
| 文件 | `%USERPROFILE%\.zcode\v2\checkpoints\**\pending\*.tar.gz.enc` |
| 文件 | `*.envelope.json`（schema `repo_snapshot_encrypted_artifact/v2`）|
| 目录 | `~/.zcode/**/checkpoints/`、`**/pending/` |
| 网络 | `*.log.aliyuncs.com`（OTLP/RUM）、动态 OSS 端点（`oss-cn-*.aliyuncs.com`）|
