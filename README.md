<p align="center">
  <img src="assets/brand/aushd-logo.png" alt="AusHD Player" width="420">
</p>

<p align="center">
  中文优先的 Emby / Jellyfin 客户端，支持 <b>Windows</b>、<b>Linux</b> 与 <b>Android TV / Google TV</b>。
</p>

# AusHD Player

> **修改声明（GNU GPL v3.0 第 5(a) 条）**
> 本仓库是上游 [`florinp93/Zerk-Play-2.0`](https://github.com/florinp93/Zerk-Play-2.0) 的**修改版本**，
> 由 AusHD 于 **2026-11-12** 基于上游提交 `a20b48f`（2 beta 9）fork 并修改。
> 修改内容包括：品牌标识与图标、版本号与更新分发机制、界面语言与语言配置、全量中文本地化文案与生成工具链、手机扫码配置页、分发服务端。
> 原作者版权归 florinp93 所有，原 `LICENSE`（GNU GPL v3.0 全文）完整保留。
> 本修改版整体仍以 **GNU GPL v3.0** 授权，**不附加任何额外限制**。

## 与上游及第三方的关系

- "Zerk Play" 名称、Logo 及相关商标属于上游作者；本项目的 "AusHD" 名称与图标为独立品牌资源。本项目与上游作者无关联，也**不隶属于** Emby、Jellyfin、Seerr 或 TMDB。
- 软件按 GPLv3 第 15、16 条"按原样"提供，**无任何担保**。
- 打包的第三方组件及其许可见 [`NOTICE`](NOTICE)。TMDB / Seerr / Xtream IPTV 等服务需用户自备账号与 API 密钥，其服务条款独立于本仓库的代码许可。

## 当前进度

| 项目 | 状态 |
| --- | --- |
| 品牌矢量资源与 Windows / Android TV / Linux 图标 | 已完成 |
| 更新器解耦：改查自建分发服务 + SHA256 校验 | 已完成 |
| 设置页加入 `简体中文` / `zh-CN` / `zh-TW` | 已完成 |
| 自建分发后端（版本 API、安装包托管、hub 兑换码、日志接收） | 已完成，18 项自测通过 |
| GitHub Actions 三平台构建与发布 | 已完成配置 |
| 中文文案 `lib/l10n/app_zh.arb` | 697 条全部译为简体中文，占位符 / ICU / 专名校验通过 |
| 术语表与本地化工具链 `tools/l10n/` | 已完成，见 [`docs/本地化术语表.md`](docs/本地化术语表.md) |
| 手机扫码配置页、中文日期格式、残留品牌清理 | 已完成 |
| 完整品牌重命名（内部包名 / 二进制名） | 未做，见下方说明 |

**有意保留的内部标识**：`pubspec.yaml` 的 `name: zerk_play`、Android `applicationId = cloud.zerk.play`、`BINARY_NAME zerk_play`、Kotlin 包目录 `cloud/zerk/play`。改这些会牵动签名、类名、桌面文件、安装包脚本与大量 import，风险高；显示名、图标与文案已全部改为 AusHD。等 CI 三平台构建稳定后再单独做一轮重命名。

## 构建（不在本地进行）

本项目**不要求本地安装 Flutter/Dart**，全部由 `.github/workflows/build.yml` 并行构建 Windows（Inno Setup）、Linux（tar.gz）、Android TV（APK）。

**两种模式**

| 触发方式 | 是否需要 Secret | 产物 |
| --- | --- | --- |
| 手动触发，保持 `skip_distribution` 勾选（默认） | 不需要 | 纯构建包；更新器、hub、日志上传静默关闭，适合先验证 Dart 能否编译并本地试用 |
| 推送 `v*` tag，或手动触发时取消勾选 | `DIST_URL` 必填 | 完整发布包；创建 GitHub Release 并把产物登记到分发服务，客户端开启自更新 |

```bash
git tag v1.0.0
git push origin v1.0.0
```

**Secrets**（Settings → Secrets and variables → Actions）

| Secret | 说明 |
| --- | --- |
| `DIST_URL` | 完整发布时必填。分发服务对外 https 地址，注入 `AUSHD_DIST_URL`。`preflight` 会校验格式，并拒绝 `example.com`、`localhost` 等占位地址 |
| `HUB_URL` | 可选。注入 `AUSHD_HUB_URL`；留空时求片、一起看、云端配置、重新下载全部关闭，客户端完全离线可用 |
| `ADMIN_TOKEN` | 可选但推荐。用于把构建产物登记到分发服务；不配则跳过登记，客户端查不到新版本 |

`preflight` 不通过时工作流直接失败，不会产生"构建成功但客户端指向死域名"的包。完整步骤见 [`docs/A路径-首次构建与部署.md`](docs/A路径-首次构建与部署.md)。

## 分发后端

见 [`server/README.md`](server/README.md)。零依赖 Node.js 服务：

```bash
cd server
npm test                 # 18 项端到端自测
npm run check:deploy -- --url https://你的域名   # 部署后自检 6 项
ADMIN_TOKEN=xxx PUBLIC_BASE_URL=https://你的域名 npm start
```

`https://dist.example.com` 只是示例占位，**必须替换成真实域名**：CI 的 `preflight` 与客户端都会拒绝 example.com。

客户端 `lib/services/updater/updater.dart` 读取 `GET /api/releases/latest`，下载后按 `sha256` 流式校验，再静默安装；不再访问上游作者的 GitHub releases。

## 运行时依赖

- **Windows**：安装包已内置 `libmpv-2.dll`（CI 构建时从 [shinchiro/mpv-winbuild-cmake](https://github.com/shinchiro/mpv-winbuild-cmake) 下载，见 NOTICE），开箱即用。
- **Linux**：tar.gz **不内置** libmpv，播放视频前需安装系统包，例如 `sudo apt install libmpv-2`（Debian/Ubuntu）或 `sudo pacman -S mpv`（Arch）。
- **Android TV**：APK 已内置 Media3 / FFmpeg，无需额外依赖。

## 本地化

- `l10n.yaml` 以 `app_en.arb` 为模板生成 `L10n`；新增 `app_zh.arb` 即自动加入支持语言。
- `lib/app/app_settings.dart` 中 `uiLanguages`、`metadataLanguages`、UI→TMDB 语言映射为硬编码常量，已同步加入中文。
- `lib/l10n/tag_names_ro.dart` 的 TMDB 关键词映射按约定保留英文，不新增中文映射；接入点是 `lib/ui/pages/title_extras.dart`。
- 中文日期格式已生效；中文字体打包、10-foot UI 回归与简体/繁体拆分仍待处理，见项目目录下的《本地化方案.md》与 [`docs/A路径-首次构建与部署.md`](docs/A路径-首次构建与部署.md) 的回归清单。

## 合规提醒

若对外分发安装包，除保留本文件与 `LICENSE` 外，还须提供**完整对应源码**（含 `server/`、`.github/` 与打包脚本）、保留界面中的许可与无担保声明、标明修改与日期，并随附 `NOTICE`。仅自用不分发时无此义务。
