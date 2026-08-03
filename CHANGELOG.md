# 更新日志

本项目所有值得注意的变更均记录于此文件。
格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

每个版本对应一个 `vX.Y.Z` 标签，发布流程见 `tool/release.sh`。

## [3.10.2] - 2026-08-02

### Fixed
- 智能识别输入源修复：解析固定使用 B 站原始视频标题，不再受用户已编辑的显示标题影响。

## [3.10.1] - 2026-08-02

### Fixed
- 歌词智能识别确定性修复：同一标题多次点击结果恒定。

### Removed
- 移除 LRCLIB 兜底歌词源。

## [3.10.0] - 2026-08-02

### Changed
- 全栈代码审计修复：数据安全、竞态防护、性能优化与代码整理。
- README 中文化。
- 临时关闭 lint `abortOnError`，绕过 image_picker_android 的 JDK 兼容性 bug。

## [3.9.7] - 2026-08-02

### Fixed
- 交叉验证的 token 级噪声过滤与 appliedSong 选取修复。

## [3.9.6] - 2026-08-02

### Fixed
- 多书名号智能消歧：区分作品名与歌曲名（如《画绢》央视《衣裳中国》主题曲）。
- 剧集歌曲标签后缀识别泛化为任意以「曲」结尾的 1–4 字标签（印象曲、片尾曲、角色曲等）。

## [3.9.5] - 2026-08-02

### Changed
- 强制解析输入源不可变、规范化官方歌词库歌曲字幕，实现 100% 确定性解析。

## [3.9.4] - 2026-08-02

### Added
- 官方歌词库交叉验证算法（对原始标题两段式匹配）。

## [3.9.3] - 2026-08-02

### Changed
- UX 导航细化；歌词偏移校准结果保留。

### Fixed
- 智能识别仅在用户显式点击按钮时运行。

## [3.9.2] - 2026-08-02

### Fixed
- 重新解析不再把已提取的歌手覆盖回 UP 主。

## [3.9.1] - 2026-08-02

### Changed
- 基于 500+ 条真实 B 站标题语料优化标题解析；智能识别按钮加大并移至歌手字段下方。

## [3.9.0] - 2026-08-02

### Added
- 歌名与歌手智能识别：解析算法与「智能识别」按钮。

## [3.8.5] - 2026-08-02

### Removed
- 移除搜索页下拉刷新。

## [3.8.4] - 2026-08-02

### Fixed
- 确认按钮同时保存信息与歌词两个页签；主题强调色滑块进度条着色。

## [3.8.3] - 2026-08-02

### Fixed
- 编辑器底部确认按钮固定，不再随 TabBarView 滚动。

## [3.8.2] - 2026-08-02

### Fixed
- 编辑器操作按钮、页签指示器首帧渲染、搜索错误处理。

## [3.8.1] - 2026-08-01

### Changed
- 歌词结果行重设计；搜索与推荐无限滚动。

## [3.8.0] - 2026-08-01

### Added
- 统一动效系统。

### Fixed
- 导航与曲目同步问题；代码审计。

## [3.7.0] - 2026-08-01

### Changed
- 实时页签指示器、编辑器滑动过渡、封面尺寸调整。

## [3.6.4] - 2026-07-30

### Fixed
- 已下载曲目绿色图标；收藏页签不再变更封面。

## [3.6.3] - 2026-07-30

### Changed
- 编辑器视觉与首页对齐（滑动页签、logo、透明背景），并移入 NowPlayingSheet 内部。
- 新增 macOS 构建目标（`tool/build_release.sh macos`）。

### Fixed
- 通过 `SafeArea(minimum:)` 统一顶部留白。

## [3.6.2] - 2026-07-30

### Fixed
- LRC 编辑器布局（移除头部、全高文本框、取消/保存按钮）。
- 偏移栏简化为校准/完成两态；预览禁用 autoFollow；修复预览编辑按钮与粘贴卡片文案。

## [3.6.1] - 2026-07-30

### Removed
- 移除音量条；代码审计修复。

## [3.6.0] - 2026-07-30

### Added
- 点按设置歌词校准、LRC 文本编辑器。

### Fixed
- 歌词滚动与偏移问题。

## [3.5.2] - 2026-07-29

### Fixed
- 从所有歌单中清除已删除的本地曲目。

## [3.5.1] - 2026-07-29

### Changed
- 首页 logo 左移，与收藏播放按钮对齐；歌单顶栏移除 logo。

## [3.5.0] - 2026-07-29

### Added
- 歌单下滑退出、编辑模式多选、添加本地曲目。

## [3.4.1] - 2026-07-29

### Changed
- 歌单封面按钮位置调整、双击重命名、空状态文案更新。

## [3.4.0] - 2026-07-29

### Added
- 歌单封面、拖拽排序、仅音乐搜索、更轻量的氛围光效。

## [3.3.0] - 2026-07-29

### Changed
- 视觉整合：单一顶部光效、歌单行化、播放器与页面共享表面；拖拽校准移入信息/歌词编辑器。

### Fixed
- 下载状态缺陷、两处内存泄漏、多余重建；图标与头部标记重制。

## [3.2.0] - 2026-07-29

### Changed
- 单一顶部光效、下方纯黑；歌单行化；播放器共享光效表面。

## [3.1.5] - 2026-07-29

### Fixed
- 停靠卡片作为播放器页面的表面而非独立对象。

## [3.1.4] - 2026-07-29

### Fixed
- 下载控件位置与图标状态修复。

## [3.1.3] - 2026-07-29

### Fixed
- 移除停靠卡片下方分隔线，进度条移入卡片内部，修复时间读数。

## [3.1.2] - 2026-07-29

### Fixed
- 校准改为模式化操作，修正量按位移处理。

## [3.1.1] - 2026-07-29

### Fixed
- 每首歌唯一视觉标识；图标保留光晕、头部标记保留辉光。

## [3.1.0] - 2026-07-29

### Fixed
- 审计修复：下载状态缺陷、两处内存泄漏、减少重建。

## [3.0.0] - 2026-07-28

### Added
- 播放器/卡片一体化、拖拽校准歌词、iOS 发布。

### Changed
- 推荐引擎改为基于用户自有曲库；发布签名配置；结果标题跑马灯。

## [2.1.0] - 2026-07-28

### Added
- 下载后播放控件、混淆构建。

### Changed
- 仅保留 64 位架构；精简播放器栏与文案。

## [2.2.2] - 2026-07-28

### Fixed
- 元数据编辑不再被还原；全局连续跑马灯。

## [2.2.1] - 2026-07-28

### Added
- 正确的发布签名；推荐引擎基于用户自有曲库。

## [2.2.0] - 2026-07-28

### Changed
- 清除死代码、减少不必要的重建、修复 5 个潜在 bug。

## [2.1.1] - 2026-07-28

### Fixed
- 统一下载按钮状态；收藏/循环位置互换；歌词页签打开编辑器。

## [2.0.0] - 2026-07-28

### Added
- 恢复滚动标题；播放器表面重设计。

### Fixed
- 播放与歌词同步问题。

## [1.0.0] - 2026-07-28

### Added
- 首个发布版本。

[3.10.2]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.10.2
[3.10.1]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.10.1
[3.10.0]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.10.0
[3.9.7]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.9.7
[3.9.6]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.9.6
[3.9.5]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.9.5
[3.9.4]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.9.4
[3.9.3]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.9.3
[3.9.2]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.9.2
[3.9.1]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.9.1
[3.9.0]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.9.0
[3.8.5]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.8.5
[3.8.4]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.8.4
[3.8.3]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.8.3
[3.8.2]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.8.2
[3.8.1]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.8.1
[3.8.0]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.8.0
[3.7.0]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.7.0
[3.6.4]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.6.4
[3.6.3]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.6.3
[3.6.2]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.6.2
[3.6.1]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.6.1
[3.6.0]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.6.0
[3.5.2]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.5.2
[3.5.1]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.5.1
[3.5.0]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.5.0
[3.4.1]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.4.1
[3.4.0]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.4.0
[3.3.0]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.3.0
[3.0.0]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.0.0
[2.1.0]: https://github.com/Aeacu2/BiliBeat/releases/tag/v2.1.0
[2.0.0]: https://github.com/Aeacu2/BiliBeat/releases/tag/v2.0.0
[3.2.0]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.2.0
[3.1.5]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.1.5
[3.1.4]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.1.4
[3.1.3]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.1.3
[3.1.2]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.1.2
[3.1.1]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.1.1
[3.1.0]: https://github.com/Aeacu2/BiliBeat/releases/tag/v3.1.0
[2.2.2]: https://github.com/Aeacu2/BiliBeat/releases/tag/v2.2.2
[2.2.1]: https://github.com/Aeacu2/BiliBeat/releases/tag/v2.2.1
[2.2.0]: https://github.com/Aeacu2/BiliBeat/releases/tag/v2.2.0
[2.1.1]: https://github.com/Aeacu2/BiliBeat/releases/tag/v2.1.1
[1.0.0]: https://github.com/Aeacu2/BiliBeat/releases/tag/v1.0.0
