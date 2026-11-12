# A 路径 · 首次构建与部署操作手册

> 目标：先拿到一个**自己能用**的中文版安装包（三平台），核心播放功能完整，更新器与 hub 不依赖原作者。
> 本手册对应 A 档（自用/小范围试用），不是对外发行。发行需另做正式签名、服务端功能与合规复核。

## 0. 现状

代码在 `D:\AusHD player\aushd-player`，分支 `main`，HEAD 为 A 路径改动提交；本地已创建 `v1.0.0` tag，**尚未 push**。

| 项目 | 状态 |
| --- | --- |
| logo 高清化、品牌资源接入 | 已完成 |
| 697 条中文本地化 + 术语门禁 | 已完成，PASS |
| 更新器改查自建服务 + SHA256 校验 | 已完成 |
| 分发后端（版本/下载/兑换码/日志/管理端） | 已完成，18 项测试 + 6 项部署自检 PASS |
| GitHub Actions 三平台流水线 + preflight | 已完成，YAML 校验 PASS |
| 未配置后端时的静默降级、hub 四功能关闭 | 已完成（本轮） |
| **Dart 代码真实编译** | **未验证**，本机无 Flutter，必须靠首次 CI |
| **后端部署到公网** | **未做**，需要你的服务器 |
| **代码推到 GitHub** | **未做**，需要你的仓库 |

### 需要你提供的 4 项

1. **真实 GitHub 仓库地址**（`origin` 目前是占位 `https://github.com/aushd/aushd-player.git`）。
2. **分发服务的公网域名**（例如 `https://dist.你的域名.com`），需可 HTTPS 访问。
3. **ADMIN_TOKEN**：一个长随机串，服务端 `.env` 与 GitHub Secret 用同一个值。生成命令见 §2。
4. **是否要 hub 功能**：A 路径建议留空（关闭）；需要兑换码时再单独配 `HUB_URL`。

---

## 1. 第一步：先跑一次"纯构建"，不需要后端

这一步的目的只有一个：**验证 Dart 代码到底能不能编译**。不需要任何 Secret、不需要服务器。

### 1.1 推代码

```bash
cd "/d/AusHD player/aushd-player"
git remote set-url origin https://github.com/<你的用户名>/<你的仓库>.git
git push -u origin main
```

### 1.2 手动触发 build-only

网页：仓库 → **Actions** → *Build AusHD Player* → **Run workflow** → 填 `tag=v1.0.0`，**保持 `skip_distribution` 勾选** → 运行。

或命令行：

```bash
gh workflow run build.yml -f tag=v1.0.0 -f skip_distribution=true
gh run watch
```

此时 `preflight` 直接通过，注入的 `AUSHD_DIST_URL` / `AUSHD_HUB_URL` 为空，客户端里：

- 启动 5 秒的自动更新检查**直接跳过**，不发任何网络请求；
- 设置页不显示「检查更新」；
- 不显示「发送日志」；
- 求片 / 一起看 / 云端配置 / 重新下载**全部关闭**（`HubFeatures` 强制返回全 false，即使本地存过旧的兑换码配置）。

产物仍会发到 GitHub Release：Windows `.exe`、Linux `.tar.gz`、Android TV `.apk`。**这个包可以正常装、正常看片**，只是没有自更新。

> 首次 CI 大概率需要按日志调 1–2 轮。把失败 job 的日志贴给我，我直接改。重点看 `Validate localizations`（`flutter gen-l10n`）和 Windows 打包那两步。

---

## 2. 第二步：部署分发后端

### 2.1 生成 token

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

### 2.2 Docker（推荐）

```bash
cd "/d/AusHD player/aushd-player/server"
cp .env.example .env
```

编辑 `.env`，至少改两处：

```
ADMIN_TOKEN=<上一步生成的串>
PUBLIC_BASE_URL=https://dist.你的域名.com
DIST_URL=https://dist.你的域名.com
```

> `PUBLIC_BASE_URL` 决定客户端拿到的下载地址，`DIST_URL` 是 CI 登记产物时访问的地址，两者应是同一个对外地址。生产环境必须置于 HTTPS 反代之后（Caddy / Nginx）。

```bash
docker compose up -d --build
```

Caddy 反代示例：

```
dist.你的域名.com {
    reverse_proxy 127.0.0.1:8787
}
```

裸 Node 启动（不推荐长期运行）：

```bash
ADMIN_TOKEN=<token> PUBLIC_BASE_URL=https://dist.你的域名.com PORT=8787 node src/server.js
```

### 2.3 部署自检

```bash
cd "/d/AusHD player/aushd-player/server"
npm run check:deploy -- --url https://dist.你的域名.com
```

期望 6/6 通过：健康检查、三平台版本接口、兑换码协议、管理接口鉴权。此时三平台版本接口返回 `204`（还没有登记过版本）是**正常的**。

---

## 3. 第三步：配 Secrets 并推 tag

仓库 **Settings → Secrets and variables → Actions → New repository secret**：

| Secret | 值 | 必填 |
| --- | --- | --- |
| `DIST_URL` | `https://dist.你的域名.com` | 是 |
| `ADMIN_TOKEN` | 与 `.env` 相同的 token | 是（否则跳过版本登记） |
| `HUB_URL` | 留空 / 不创建 | 否，A 路径关闭 hub |

然后：

```bash
cd "/d/AusHD player/aushd-player"
git push origin v1.0.0          # tag 已在本地创建
```

或网页触发工作流并**取消勾选** `skip_distribution`。

`preflight` 会校验 `DIST_URL`：非空、是完整 http(s) URL、不是 `example.com` / `localhost` / `127.0.0.1`。不通过就直接失败，**不会产出指向死域名的包**。

构建完成后 CI 会创建 GitHub Release，并调用 `server/scripts/publish.js` 把三个产物登记到分发服务（含 SHA256）。

---

## 4. 验收清单

- [ ] Actions 里 `preflight` / `build`（windows, linux, androidtv）/ `release` 全绿
- [ ] GitHub Release 有 3 个文件，文件名符合 `AusHD-Player-1.0.0-*`
- [ ] `npm run check:deploy -- --url https://dist.你的域名.com` 三平台都返回 `v1.0.0` 且带 `sha256`
- [ ] 装上 Windows 包，设置页是中文，日期显示 `2026年11月12日` 式
- [ ] 设置页「检查更新」点击后返回「已是最新」或正确的新版本提示，不是网络错误
- [ ] 播放本地文件 / 连接 Emby 或 Jellyfin 正常，中文片名与元数据正常
- [ ] 确认没有向原作者域名 `zerk.digital` 或上游 GitHub releases 发请求

---

## 5. 首次 CI 重点风险（按日志核对）

| 风险 | 表现 | 处理 |
| --- | --- | --- |
| `flutter gen-l10n` 中文复数 / 日期元数据 | 校验步骤报错 | 按报错调 `app_zh.arb` 的 ICU 分支；`tools/l10n/verify_zh.py` 已保证分支一致 |
| 中文 `intl` 日期初始化 | 运行时日期页报 `LocaleDataException` | 需要 `initializeDateFormatting('zh')`，本机无法验证，重点观察 |
| `pubspec.lock` 与新增 `crypto` 依赖不一致 | `flutter pub get` 警告或失败 | CI 会自动更新 lock，必要时本地跑一次并提交 |
| Windows Inno Setup 图标 / 路径 | 打包步骤失败 | 已改为 `aushd.ico`，核对 `installer/zerk_play.iss` 的相对路径 |
| Android 签名 | APK 是 debug 签名 | **A 路径已知并接受**：能装、能覆盖自己、不能上架 |
| 中文字体与 10-foot UI | 焦点框文字溢出 / 方块字 | 系统字体一般能兜底，实机看片时回归 |
| Linux 打包脚本 | tar.gz 命名与 CI artifact 不匹配 | `linux/packaging/make-tarball.sh` 已改 AusHD 命名 |

---

## 6. A 路径的能力边界（结论对照）

| 问题 | 结论 |
| --- | --- |
| 构建完能直接用吗 | **能装能播**：本地/网络播放、Emby / Jellyfin 直连、TMDB / MDBList 元数据、媒体库与合集、字幕音轨、倍速硬解插帧、IPTV、手机扫码配置。自更新要等 §2 §3 做完 |
| 原版功能全在吗 | **不全在**：GPL 只开源客户端，作者中心服务不在仓库。求片（Seerr 代理）、一起看（Janus 信令）、云端 profiles、redownload 在 A 路径明确关闭；兑换码只有协议壳 |
| 只差构建吗 | 代码侧已齐；差的是「真实仓库 + 公网服务地址 + Secrets」这 3 项外部信息，以及第一次 CI 编译验证 |

---

## 7. 已知技术债（不影响自用）

- 内部标识仍是上游的：`pubspec.yaml` 的 `name: zerk_play`、Android `applicationId cloud.zerk.play`、Linux `BINARY_NAME`、MethodChannel `zerk/updater`、日志前缀 `zerkplay-`。**两端一致所以功能正常**，仅命名未改；等 CI 稳定后再单独做一轮重命名。
- Android 正式签名与密钥管理。
- 繁体 `app_zh_TW.arb`、中文字体打包、原生层字符串。
- `tag_names_ro.dart` 的 TMDB 关键词按约定保留英文，不做中文映射。
- 若以后要 B 档对外发行：补齐 hub 四项功能的服务端实现、GPL 完整对应源码复核、三平台回归与应用商店审核风险。
