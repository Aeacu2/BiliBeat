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

- [x] **标题滚动跑马灯（无布局抖动）(Marquee Title Scrolling — Layout-Safe)**
  - 标题过长时自动横向滚动并带两端渐隐；宽度足够时保持静止。
  - **实现约束（必须保留）**：高度在 `build` 中由 `TextPainter` 同步测量得出，溢出量直接来自 `BoxConstraints`；滚动本身是 `Transform.translate`（绘制阶段），**永远不会反馈到布局**。禁止再用 post-frame `setState` 测量文本。
  - 回归测试见 `test/widget_test.dart`（高度稳定 / 不撑宽 / 兄弟组件不位移）。
- [x] **底部播放条重设计 (Redesigned Docked MiniPlayer)**
  - 实心渐变卡片 + 发丝描边 + 深投影替代 `BackdropFilter`（省一次 GPU 图层，规避 Android 前景擦除 Bug）。
  - 进度条改为贴合卡片底边并随圆角裁剪；播放键为独立圆形按钮并带图标缩放切换。
  - 手势：上滑展开全屏播放器，左右滑动切歌，点按展开。
  - `MiniPlayer.totalHeight(context)` 为全局唯一的「底部占位高度」来源。
- [x] **全屏播放器主控件语义修正 (NowPlaying Primary Control = Play/Pause)**
  - 主按钮恒为播放/暂停（未下载时自动下载并播放，进度以环形显示），下载状态收敛为标题旁的小图标。
  - 控件排布：播放模式 / 上一首 / 播放 / 下一首 / 收藏；音量条支持一键静音；下滑关闭。
- [x] **本地音频删除与歌单删除 (Delete Local Audio & Delete Playlist)**
  - 曲目长按菜单可删除本地音频释放空间；歌单内左滑移除曲目；歌单卡片长按删除歌单。
- [x] **播放页主按钮如实反映曲目状态 (Download-Then-Play Primary Control)**
  - 架构上「未下载即不可播放」，因此播放页主按钮按真实状态切换：**未下载 → 下载按钮**；**下载中 → 圆环进度条**（与列表中 `TrackDownloadButton` 同一视觉）；**已下载 → 播放/暂停**。
  - 移除播放页的「已下载 ✓」指示与顶部音源行：能播放本身即代表已下载，再标注是冗余。
  - handler 自身的下载不经过 `DownloadManager`，故播放开始时会复查一次落盘状态，避免按钮卡在「下载」。
- [x] **发布构建混淆 (Obfuscated Release Builds)**
  - `tool/build_release.sh`：强制 JDK 21+（AGP lint 依赖 `List.removeLast()`，JDK 17 会以无关的 `NoSuchMethodError` 失败），产出混淆 APK，符号写入 `symbols/<version>/`。
  - 实测 `libapp.so` 6.36MB → 5.31MB（−16.5%），APK −0.85MB。
  - **符号文件必须随版本归档**，否则该版本的崩溃栈不可读；`symbols/` 不入库，随 Release 附件发布。
- [x] **歌词磁盘缓存 (Persistent Lyrics Cache)**
  - 歌词写入 `bilibeat_lyrics.json`，重启不再重复联网；「未找到」结果不落盘，保证后续可重试。
- [x] **歌词界面重做 (Reworked Lyrics View)**
  - **用户滚动优先**：手动滚动时自动跟随立即让位，浮出「回到当前」胶囊，5 秒无操作后自动恢复；此前每 150ms 就会被强行拉回，根本无法往前翻看。
  - 居中基于**实测行高**＋视口比例留白（上 42% / 下 50%），首行与末行也能真正居中。
  - 当前行：24px / w700 ＋ 单层柔和辉光；相邻行按距离递减透明度（1.0 / 0.5 / 0.34 / 0.24），视线自然落在当前句。
  - 点击任意行跳转播放位置并带轻触反馈。
  - 无歌词时给出可操作空状态（搜索或粘贴 .lrc），此前该回调是死代码。
- [x] **歌词编辑器可用性修复 (Lyrics Editor Usability)**
  - 对话框高度自适应屏幕与键盘（原先固定 580 在小屏 / 弹出键盘时直接溢出）。
  - 候选歌词卡片展示**前两句实际歌词**，不必逐个预览才能分辨；来源与行数降为次要信息。
  - 时间轴校准由右侧 5 个 50px 竖排小按钮改为预览下方的横向控制条，预览区获得全部宽度。

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
3. **不要在布局之后改变自身尺寸**：任何组件都不得在 post-frame 回调里 `setState` 改变尺寸。需要「测量后再表现」的效果，一律用绘制阶段手段（`Transform` / `ClipRect` / `ShaderMask`）实现。
4. **不使用 `BackdropFilter`**：实时模糊在本项目已两次引发 Android 前景渲染问题，且每处都要一次全屏图层。用渐变 + 发丝描边 + 投影模拟玻璃质感。
5. **曲目身份 = `Track.id`（`bvid_cid`）**：任何去重、查找、收藏、下载键都以 id 为准，绝不用 `bvid`（会折叠多 P 视频）。
6. **底部占位高度唯一来源**：`MiniPlayer.totalHeight(context)`，禁止各处硬编码 `64 + inset`。
7. **广播式数据流**：数据层变化（下载、历史）通过 `DatabaseService` 的 stream 广播，UI 只订阅，不靠调用方顺手刷新。

---

## 2. Bug 跟踪清单 (Bug List)

### 已修复 Bug (Fixed Bugs)

#### 🐛 Bug #23: 滚动标题把播放界面其余部分挤走 / 布局坍塌
- **根因**：旧跑马灯在 post-frame 回调里测量文本并 `setState`，在布局完成之后改变自身尺寸，导致父 `Column` 中的兄弟组件被推挤。
- **修复**：见上文「标题滚动跑马灯」。此前的临时方案（直接删掉滚动功能）已撤销，功能与修复同时保留。

#### 🐛 Bug #24: 列表循环播完当前曲目后总是跳回第 1 首
- **根因**：`_handleQueueCompleted` 在 `LoopMode.all` 下无条件 `playTrack(_playlist[0])`。
- **修复**：先推进到 `_currentIndex + 1`，仅在到达末尾时才回绕到第 0 首。

#### 🐛 Bug #25: 关闭随机播放无法恢复原顺序
- **根因**：开启随机时直接就地打乱 `_playlist`，原顺序被永久丢弃。
- **修复**：新增 `_naturalOrder` 保存自然顺序，`setShuffle(false)` 精确还原。

#### 🐛 Bug #26: 切换「单曲循环」/「随机」会把当前歌曲从头开始播
- **根因**：两处都调用了 `_startCurrent()`，等于重建音源并 seek 到 0。
- **修复**：`LoopMode.one` 直接交给 just_audio 的 `LoopMode.one`；随机仅重排逻辑列表并裁剪预取窗口，均不打断当前播放。

#### 🐛 Bug #27: 多 P 视频的不同分 P 互相覆盖（已下载 / 最近播放少一首）
- **根因**：`DatabaseService` 按 `bvid` 去重，把同一视频的 P1/P2… 折叠成一条。
- **修复**：统一按 `Track.id`（`bvid_cid`）去重；`Track` 新增基于 id 的 `==`/`hashCode`。

#### 🐛 Bug #28: 自动切歌后「最近播放」不刷新
- **根因**：只有 UI 触发的播放才手动调 `_loadHistory()`，handler 自动推进时无人通知。
- **修复**：`DatabaseService.historyUpdateStream`，由数据层广播，UI 订阅。

#### 🐛 Bug #29: 编辑「信息与歌词」写到了错误的歌曲
- **根因**：编辑器固定读取 `_currentTrack`，而播放页可能正在预览另一首（搜索结果）。
- **修复**：回调改为 `onOpenLyricEditor(Track)`，由播放页传入真正在显示的曲目。

#### 🐛 Bug #30: 播放页打开后不再跟随队列切歌
- **根因**：「秒弹播放器」在 handler 换曲之前就打开了页面，`_followHandler` 被算成 false。
- **修复**：新增 `followHandler` 显式参数，由调用方声明意图。

#### 🐛 Bug #31: 中断的下载 / CDN 错误页被当成「已下载」
- **修复**：校验 Content-Type 与实际字节数，短读直接失败；封面图改为先写 `.part` 再 rename，杜绝半截缓存。

#### 🐛 Bug #32: 未播放的曲目也能拖动进度条
- **修复**：非当前曲目时禁用 seek 滑块。

#### 🐛 Bug #33: 歌词自动滚动与手动浏览打架
- **根因**：位置回调每 150ms 无条件 `animateTo`，用户一松手就被拉回当前行。
- **修复**：`ScrollStartNotification`（带 drag）即进入浏览态，浮出「回到当前」；`ScrollEnd` 后 5 秒自动恢复。回归测试见 `test/widget_test.dart`。

#### 🐛 Bug #34: 歌词居中偏上一个 padding 的距离
- **根因**：`_scrollToActive` 计算目标偏移时漏加了 ListView 的 top padding。
- **修复**：目标偏移改为 `topPadding + 累计高度 - 视口/2 + 当前行高/2`。

#### 🐛 Bug #35: 歌词编辑器对话框在小屏 / 键盘弹出时溢出
- **根因**：`height: 580` 硬编码。
- **修复**：按 `screenHeight - viewInsets.bottom` 自适应并 clamp 到 320–620。

#### 🐛 Bug #36: 歌词预览每次 rebuild 都新建 `ValueNotifier`
- **根因**：`positionNotifier ?? ValueNotifier(Duration.zero)` 写在 `build` 里，每帧换一个 notifier 且从不 dispose。
- **修复**：提升为 State 字段 `_idlePosition` 并在 `dispose` 中释放。

#### 🐛 Bug #22: 默认 Flutter 图标未替换 & Android 应用名称全小写带 s (bilibeats)
- **彻底修复方式**：根据桌面设计图像精准裁切生成全套 Android (`mipmap`) 和 iOS (`AppIcon`) 各种尺寸分辨率图标，并修正 `AndroidManifest.xml` 中的标签为 `bilibeat`。
