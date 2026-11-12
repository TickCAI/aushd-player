# AusHD Player 分发后端

零依赖 Node.js 服务（Node ≥ 18），为 Flutter 客户端提供**版本检查、安装包托管、兑换码配置下发、日志接收**。不依赖 GitHub API，可部署在任意服务器或容器，CI 构建完成后把产物登记进来即可。

```
GitHub Actions 构建三平台
        │  node scripts/publish.js（Bearer token）
        ▼
AusHD 分发服务  ──GET /api/releases/latest──▶  客户端 Updater
        │                                        │
        ├── /download/:file（可选自建镜像）        └── 下载 + SHA256 校验 + 静默安装
        ├── POST /api/app/link（hub 协议）
        ├── POST /api/app/logs
        └── data/*.json（版本 / 兑换码 / 日志）
```

安装包可以只放在 GitHub Releases（推荐，省带宽），此时 `publish.js` 会把下载 URL 写成 GitHub asset 地址；也可以同时把文件放进 `artifacts/`，由 `/download/:file` 直接托管（支持断点续传）。

## 快速启动

```bash
cd server
npm test                 # 18 项端到端自测
ADMIN_TOKEN=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))") \
PUBLIC_BASE_URL=https://dist.example.com npm start
```

或 Docker：

```bash
cp .env.example .env     # 务必替换 ADMIN_TOKEN 与 PUBLIC_BASE_URL
docker compose up -d --build
```

生产环境请置于 HTTPS 反向代理之后（Caddy / Nginx），并把 `PUBLIC_BASE_URL` 设为对外 https 地址——客户端会把这个值当作 hub 地址与下载基址。

## API

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/healthz` | 健康检查、版本记录数、管理接口状态 |
| GET | `/api/releases?platform=&channel=` | 版本列表 |
| GET | `/api/releases/latest?platform=windows&channel=stable&current=v1.0.0` | 最新版本；已是最新或该平台无版本时返回 `204` |
| GET/HEAD | `/download/:file` | 安装包托管，支持 `Range` 断点续传 |
| POST | `/api/admin/releases` | 登记/更新版本（Bearer token） |
| DELETE | `/api/admin/releases?tag=&platform=&channel=` | 删除版本（Bearer token） |
| GET/POST | `/api/admin/codes` | 查询/新增兑换码（Bearer token） |
| POST | `/api/app/link` | 兼容上游 `HubLink.redeem` 的兑换码协议 |
| POST | `/api/app/logs` | 客户端诊断日志，返回 `{id}` |
| GET | `/api/admin/logs` | 日志 id 列表（Bearer token） |

`latest` 返回示例：

```json
{
  "available": true,
  "tag": "v1.0.1",
  "name": "AusHD Player 1.0.1",
  "platform": "windows",
  "channel": "stable",
  "download": "https://github.com/aushd/aushd-player/releases/download/v1.0.1/AusHD-Player-1.0.1-setup.exe",
  "size": 42123344,
  "sha256": "…64 hex…",
  "notes": "修复中文日期格式",
  "mandatory": false,
  "publishedAt": "2026-11-12T06:00:00.000Z"
}
```

客户端 `Updater.download()` 会用 `sha256` 做流式校验，不符即删除文件并报错。

## 版本登记

```bash
DIST_URL=https://dist.example.com ADMIN_TOKEN=xxx \
  node scripts/publish.js --platform windows --tag v1.0.1 \
    --file ../build/installer/AusHD-Player-1.0.1-setup.exe \
    --notes "修复中文日期格式"
```

脚本自动计算 `size` 与 `sha256`；在 GitHub Actions 里会根据 `GITHUB_REPOSITORY` 拼出 Release asset URL。也可用 `--url` 显式指定（例如自己的 CDN）。

## 兑换码

`data/codes.json` 每条兑换码对应一份下发给客户端的配置：

- `server`：`{name, url, kind}`，`url` 必须非空，否则客户端判定配置不完整。
- `features`：`requests / together / profiles / redownload` 四个功能开关。
- `metadataLanguage`：默认 `zh-CN`；`tmdbApiKey`、`mdblistApiKey`、`seerr`、`liveTv` 可选。
- `active` / `revoked` / `expiresAt`：状态与有效期。`revoked`、`unknown-code`、`inactive` 会触发客户端解绑。

仓库内 `AUSHD-DEMO` 默认 `active: false`，上线前请替换为自己的码并删除示例。

## 安全清单

- `ADMIN_TOKEN` 必须设置且足够随机；未设置时所有管理接口直接关闭。
- 管理接口用常量时间比较校验 token；`/api/app/link`、`/api/app/logs` 有基础限流。
- `data/` 与 `artifacts/` 不能暴露在静态站点目录之外；下载路径做了解码与目录穿越校验。
- 生产环境务必 HTTPS；`PUBLIC_BASE_URL` 不要写成 `localhost`。
- 客户端日志可能含服务器地址与用户名，按隐私数据保管，设置保留期。

## GitHub Actions 需要的 Secrets

| Secret | 用途 |
| --- | --- |
| `DIST_URL` | 分发服务对外地址，注入客户端 `--dart-define=AUSHD_DIST_URL` / `AUSHD_HUB_URL`，也用于 `publish.js` |
| `ADMIN_TOKEN` | 调用 `/api/admin/releases` |

未配置 `DIST_URL` 时流水线仍会构建并发布 GitHub Release，只是跳过"登记到分发服务"这一步；客户端会使用占位地址，需自行重新构建。
