# bilibeat Feature & Bug Tracking Register

这份文档是 bilibeat 项目的核心功能清单与 Bug 跟踪记录（Single Source of Truth），用于记录必须保留的功能与避免复发 Bug，确保后续迭代不会产生功能退化（Regression）。

---

## 目录
1. [功能清单 (Feature List)](#1-功能清单-feature-list)
   - [已实现功能 (Implemented Features)](#已实现功能-implemented-features)
   - [设计逻辑与规则 (Design Principles)](#设计逻辑与规则-design-principles)
2. [Bug 跟踪清单 (Bug List)](#2-bug-跟踪清单-bug-list)
   - [已修复 Bug (Fixed Bugs)](#已修复-bug-fixed-bugs)
   - [已知待解决 Bug / 隐患 (Not Fixed / Open Bugs)](#已知待解决-bug--隐患-not-fixed--open-bugs)

---

## 1. 功能清单 (Feature List)

### 已实现功能 (Implemented Features)

- [x] **全平台应用图标与应用名称配置 (Custom App Launcher Icon & Application Name)**
  - 自动从桌面图标源图像（`/Users/aeacu2/Desktop/bilibeat_app_icon_1785159018095.jpg`）精确裁剪出 1:1 圆角暗色发光 B 站音符 Logo。
  - **Android Mipmap 图标适配**：生成全部标准分辨率图标（`mipmap-mdpi` 48px, `mipmap-hdpi` 72px, `mipmap-xhdpi` 96px, `mipmap-xxhdpi` 144px, `mipmap-xxxhdpi` 192px）覆盖 `ic_launcher` 与 `ic_launcher_round`。
  - **iOS AppIcon 适配**：生成 1024x1024、180x180、120x120、87x87 等全部 iOS 标准图标集于 `Assets.xcassets/AppIcon.appiconset`。
  - **应用名称修正**：将 AndroidManifest 中的 `android:label` 从 `bilibeats` 规范更名为 **`bilibeat`**。
- [x] **粘贴 LRC 置顶第 1 位与对齐支持 (Pasted LRC at Top Index 0 with Calibration Support)**
  - 在「歌词」Tab 底部展开「粘贴 .lrc 文本」并点击按钮后，解析的歌词会自动排列在歌词列表的第 1 位（`📌 用户粘贴歌词 .lrc`），再次粘贴自动覆盖更新。
- [x] **对话框布局精简：双 Tab「信息」与「歌词」(Streamlined 2-Tab Edit Dialog: Info & Lyrics)**
  - 对话框标题重命名为 **「信息与歌词」**，极简双 Tab 架构。
- [x] **卡片点击零延时弹起全屏播放器 (Instant Synchronous NowPlaying Expansion on Card Tap)**
  - 点击卡片瞬间：**立即同步更新当前曲目信息 + 0ms 秒弹全屏 NowPlaying 播放界面**。
- [x] **在线播放即自动后台下载 (Automatic Background Download on Play Track)**
  - 在线歌曲点播放时通过 DASH 流式媒体~200ms秒播，同时后台自动将其全量下载保存为本地离线文件。
- [x] **搜索界面动态按钮切换 (Search Screen Dynamic Action Button: Download vs Play)**
  - 未下载歌曲显示下载图标；已下载歌曲自动替换为粉色播放图标。
- [x] **底层 Stack 架构重构：常驻播放器永不被遮挡 (Unblocked Permanently Anchored MiniPlayer)**
  - 常驻播放器 MiniPlayer 位于 Z-index 最顶部前端 `bottom: 0`。
- [x] **B 站 16:9 封面等比例正方形居中裁剪 (1:1 Center-Cropped Bilibili Cover Aspect Ratio)**
  - 接入 B 站 CDN 尺寸裁剪参数 `@${w}w_${h}h_1e_1c`，结合 `BoxFit.cover` + `Alignment.center` 居中裁剪为 1:1 正方形。
- [x] **品牌 Logo 渐变粉主题色 (Logo Signature Pink Theme `#FF3366` / `#FF6699`)**
  - 全应用统一采用 Logo 专属渐变粉主题（`Color(0xFFFF3366)` 至 `Color(0xFFFF6699)`）。

---

### 设计逻辑与规则 (Design Principles)

1. **统一的高清图标格式**：桌面与 Launcher 应用图标统一使用精准裁剪的 1:1 暗色发光音符 Icon。
2. **应用名一致性**：全系统（Android/iOS/Flutter）应用名称统一为 `bilibeat`。

---

## 2. Bug 跟踪清单 (Bug List)

### 已修复 Bug (Fixed Bugs)

#### 🐛 Bug #22: 默认 Flutter 图标未替换 & Android 应用名称全小写带 s (bilibeats)
- **彻底修复方式**：根据桌面设计图像精准裁切生成全套 Android (`mipmap`) 和 iOS (`AppIcon`) 各种尺寸分辨率图标，并修正 `AndroidManifest.xml` 中的标签为 `bilibeat`。
