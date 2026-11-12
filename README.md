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

本项目**不要求本地安装 Flutter/Dart**。推送 `v*` tag 或手动触发工作流即可：

```bash
git tag v1.0.0
git push origin v1.0.0
```

`.github/workflows/build.yml` 会并行构建 Windows（Inno Setup 安装包）、Linux（tar.gz）、Android TV（APK），创建 GitHub Release，并在配置好 Secrets 后把产物登记到分发服务。

需要在仓库 Settings → Secrets 中配置：

| Secret | 说明 |
| --- | --- |
| `DIST_URL` | 分发服务对外 HTTPS 地址，注入客户端 `AUSHD_DIST_URL` / `AUSHD_HUB_URL` |
| `ADMIN_TOKEN` | 分发服务管理 token，用于登记版本 |

未配置时仍会构建并发布 GitHub Release，只是跳过登记步骤，客户端会使用占位地址。

## 分发后端

见 [`server/README.md`](server/README.md)。零依赖 Node.js 服务：

```bash
cd server
npm test                 # 端到端自测
ADMIN_TOKEN=xxx PUBLIC_BASE_URL=https://dist.example.com npm start
```

客户端 `lib/services/updater/updater.dart` 读取 `GET /api/releases/latest`，下载后按 `sha256` 流式校验，再静默安装；不再访问上游作者的 GitHub releases。

## 本地化

- `l10n.yaml` 以 `app_en.arb` 为模板生成 `L10n`；新增 `app_zh.arb` 即自动加入支持语言。
- `lib/app/app_settings.dart` 中 `uiLanguages`、`metadataLanguages`、UI→TMDB 语言映射为硬编码常量，已同步加入中文。
- `lib/l10n/tag_names_zh.dart`（TMDB 关键词中文映射）待第二批接入，接入点是 `lib/ui/pages/title_extras.dart`。
- 中文字体、日期格式、10-foot UI 回归与简体/繁体拆分见项目目录下的《本地化方案.md》。

## 合规提醒

若对外分发安装包，除保留本文件与 `LICENSE` 外，还须提供**完整对应源码**（含 `server/`、`.github/` 与打包脚本）、保留界面中的许可与无担保声明、标明修改与日期，并随附 `NOTICE`。仅自用不分发时无此义务。
