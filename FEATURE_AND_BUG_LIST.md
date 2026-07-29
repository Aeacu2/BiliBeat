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
- [x] **背景：顶部一层光晕，其余全黑 (One Aura, Then Black)**
  - 由当前封面取色的光晕**只挂在屏幕顶端**，浓度克制，向下渐隐——大约在第一行内容再往下一张歌曲卡片的高度处收干净；下半屏由一层线性渐变兜底，保证是精确的背景色而不是「几乎黑」。
  - 此前是左上 + 右下两团光晕铺满整屏，于是每一个列表都被染上颜色，屏幕上没有一处真正是黑的。
  - **播放页用同一套背景**，不再是一块纯黑板子。
  - 光晕不做圆形裁剪——渐变自身的衰减就是它的边缘，在通屏宽的盒子上裁圆会露出一道圈。
- [x] **玻璃只留给「卡片」，歌曲是「行」不是「盒子」(Glass for Cards, Rows for Songs)**
  - 列表里的歌曲不再各自套一层 `GlassCard`：描边 + 高光 + 外边距叠在每一行上，整页读起来就是一摞盒子，视线还没到标题就先累了。
  - 歌曲行改用 `TrackRow`：没有自身外观，只有按下去时的圆角高光；封面是行里唯一有形状的东西，行距收紧到 2pt——「像一个列表」而不是「一堆卡片」。搜索结果 / 下载中 / 歌单详情三处统一。
  - 玻璃保留给真正是卡片的东西：搜索框、快捷入口（已下载 / 收藏）。**歌单也已改为行**——一页歌单卡又是一摞盒子，而歌单没有理由比它里面的歌更重。
- [x] **顶部导航与品牌标识 (Header: Bigger Tabs + Logo)**
  - 「聆听 / 搜索」字号加大（18 → 23），右侧原本大片空白处放上品牌标识，页头才有形状。
  - 播放页顶部同样换成品牌标识：原来那行「正在播放」是用 11pt 大字距的小字，去说明整个屏幕本来就是什么；真正值得说的只有它**不是**的时候——预览别的曲目，此时标识下面才出现「预览」。
  - 标识由桌面原图抠出：按**粉色**（而非亮度）抠图——外框描边亮度足够高，纯亮度抠图会在标识后面留下一个淡淡的方框；霓虹的辉光边缘则被完整保留。
- [x] **歌单封面可自定义与编辑 (Playlist Covers & Editing - Release 3.4.1)**
  - 歌单详情页更换封面图标已移至标题右侧（与歌曲行图标风格统一），不在封面上叠加相机图标；双击歌单名称支持编辑重命名。
  - 歌单/收藏空状态提示统一为「暂无曲目」，并移除下面的「在搜索页添加」提示文本。
  - 「本地」是从下载库现搭出来的虚拟歌单，没有可写封面的记录，保持默认徽标。
- [x] **长按拖拽调整曲目顺序 (Drag to Reorder)**
  - 本地 / 收藏 / 任意歌单：长按一行拿起来拖动即可排序，落下即写入（本地写下载库，其余写歌单）。
  - **不加专门的拖拽手柄**：这一行上已经有两个按钮了；行本身就是手柄。因此原来挂在行上的长按菜单被去掉——同一个手势不能既是菜单又是拖拽。
  - 用 `onReorderItem` 而不是已废弃的 `onReorder`：前者给出的 newIndex 已经算好了「先移除再插入」的位移，后者需要手工减一，正是这类代码最容易错的地方。
- [x] **搜索只出音乐 (Search Stays in the Music Zone)**
  - 关键词搜索限定 B 站**音乐分区**（`tids=3`：原创音乐 / 翻唱 / 演奏 / VOCALOID / 音乐现场 / MV / 音乐综合）。
  - **BV 号与链接不受限制**：那条路走的是 `fetchVideoInfo`，按 id 要东西就是明确要它本身，无论它在哪个分区。
  - 分区搜索若返回空（确实没有，或接口不认这个参数），自动退回不限分区再搜一次——宁可多出几条无关结果，也不能让用户以为自己的歌不存在。
- [x] **合集可以直接开始播放 (Play a Collection In Place)**
  - 「本地」（原「已下载」）、「收藏」与每个歌单的行上都有播放键：**列表循环、按顺序**，点了就放，不打开任何页面；点卡片 / 行本身仍然是进去看。
  - **进去之后**头部那颗按钮是「随机播放」（图标也是随机的那个）——已经进到合集里再放一遍「从第一首开始」没有意义，那正是想随便听听的时候。
  - 随机是在把队列交给播放器**之前**设置的，这样洗牌顺序是围绕真正开始的那首歌建立的（`_applyShuffleOrder(pinned:)`）；两种入口都会把循环模式设为列表循环。
- [x] **歌单改为竖排条形卡 (Playlists as a Vertical Stack)**
  - 原来是横向滑动的方卡：第二张之后的歌单全藏在一个没人想得到去试的横向滚动里，而页面本身是纵向滚动的。现在自上而下排列，与搜索结果里的歌**同一种行**，末尾一行「新建歌单」。
  - 最近播放**仍是横向滚动**：它是「最近」的时间流，天然有限且可无限增长，不该把首页撑长。
- [x] **品牌资产由脚本从原稿生成 (Brand Assets, One Script)**
  - `tool/make_brand_assets.py` 从 `tool/brand/app_icon_source.jpg` 一次生成：应用内标识 `assets/logo.png` ＋ iOS / Android（含圆形）/ macOS / Web 全套 37 张图标。
  - **图标是「裁」不是「重画」**：音符与它自身的辉光保持原稿模样，只是把圆角矩形连同**外围一圈很窄的画布**一起裁出来。那圈画布正是关键——原稿在圆角矩形外面有一层很淡的粉光，留一点点它就有悬浮感；留多了，圆角矩形就会在系统的圆角遮罩里变成「方块套方块」。边距 20px（相对 630px 的方块）是对着这两者调的。
  - **应用内标识必须抠图**，因为它贴在纯深色页头上，带底就一定看得出方块。抠图按**色度**而非亮度：`R - max(G, B)`。原稿的方块、圆角描边与画布都是中性甚至偏蓝（描边采样为 80,79,85），色度恰好为零；霓虹与其辉光色度全为正。按亮度抠是不行的——描边比辉光外圈还亮，会活下来并在标识后面留下方框。笔画最亮的核心接近白色，靠亮度补救，但**限定在仍有粉色的地方**，否则方块下面那行白色 wordmark 会被一起抠出来。
  - 抠图取景**留在方块以内并对边缘羽化**：原稿的辉光在方块边界处是被裁断的（像素里真实存在的一道台阶），任何颜色抠图都消不掉；框内含那条边界就会出现圆角方形，而辉光在半路被切断同样会留下一圈方框。抠出的颜色做了反预乘，贴回近黑背景后与原稿一致，不会变暗。
- [x] **页面标题不再与顶部导航重复 (No Duplicate Page Titles)**
  - 顶部标签栏已经写着「聆听 / 搜索」，页面里再用大标题重复一遍同样的词毫无信息量，已删除；页面从内容直接开始。
- [x] **播放卡与播放页融为一体 (Docked Card ⇄ Player, One Object)**
  - 播放卡**贴着屏幕底边通栏**，左右与下方都不留空；因此只有上方两角是圆的（下面和两侧没有可圆的对象），阴影朝上投，把卡片从其下滚动的列表上「抬」起来。Home indicator 的安全区改为**卡片内部**的下内边距，控件不会压在指示条上，`totalHeight` 的语义不变。
  - **系统导航栏必须一起处理**：Android 默认会在手势区上方画一条分隔线（`systemNavigationBarDividerColor`），卡片贴得再实，那条线也还在。已改为 edge-to-edge ＋ 导航栏全透明、分隔线透明、不强制对比度。
  - **进度条在卡片内部且可拖拽**：左右内缩、圆头、与播放页同一套轨道与配色；按住时加粗并出现圆头把手，松手 seek。3pt 的线是抓不住的，因此底部有一条 22pt 的透明触控带，`behavior: opaque` ＋ 横向手势，在自己范围内截住横滑，不会漏给卡片的「左右滑切歌」。
  - **进度条是覆盖在行上的，不是行下面的一条独立车道**：车道会把整行往上顶，封面就不在卡片的水平中轴上了——这在这么小的一张卡上是第一眼就会看出来的。
  - **进度条必须显式占满宽度**：`SizedBox(width: double.infinity)`。让它自己收缩的话，填充条会决定轨道的宽度，于是整条进度从卡片正中往两边长。
  - 其余部分仍是播放页的「折叠态」，不是另一套控件：同样的 `AppRadius.xl` 圆角与抬升表面、同样的封面圆角、主控圆钮**位置与形状**与播放页一致、底边的进度发丝即播放页进度条的折叠形态。
  - **卡片与播放页是同一套外观，不是「卡片版」的另一套**：同样的近黑底色（`AppColors.background`，不是抬升面的灰）、同样的渐变粉色主控圆钮与辉光、同样的进度条轨道与配色。此前一度把底色留在抬升面、把主控换成半透明玻璃钮——那是把「统一」做成了「呼应」，两者放在一起就是两个东西。
  - 点击播放卡 → 卡片矩形**原地长大**成整页（圆角同时展开），关闭 → 同一段动画倒放，页面折回卡片落到底部（`ExpandFromCard`）。
  - **实现约束**：动画只动 `Clip` 与位置，页面始终以整屏尺寸布局（`OverflowBox`），否则歌词列表与进度条会在 60fps 下反复重排。动画结束后过渡组件完全让路（不留 clip / opacity 图层）。
  - 无卡片可长大时（尚未播放、直接从搜索结果打开预览）回退为上滑转场。
  - 仍不使用 `BackdropFilter`（省一次 GPU 图层，规避 Android 前景擦除 Bug）。
  - 手势：上滑展开，左右滑动切歌，点按展开。`MiniPlayer.totalHeight(context)` 仍是全局唯一的「底部占位高度」来源。
- [x] **拖拽歌词校准时间轴 (Drag-to-Calibrate Lyrics)**
  - 位置在**「信息 / 歌词」编辑器的歌词预览**里，不在播放页的歌词面板里：播放页是用来听歌看词的，校准是编辑动作。
  - **取代了原来的 ±0.1s / ±0.5s 按钮**。盲点微调本就是错的交互：零点一秒是看不出来的，只能点一下听一下再点一下，撞到对齐为止。
  - **是一个「模式」，不是长按手势**：点「校准」进入，中线出现基准线，此时纵向拖动移动的是时间轴，列表冻结；再点「完成」退出。长按行不通——手指按住不动再移动**正是滚动的做法**，长按识别器每次都会先赢下手势竞技场，于是翻歌词动不动就变成误校准。
  - **校准量是「位移」而不是「与播放进度之差」**：后者只在真的在播时才有定义；预览的时钟停在 0:00，于是每一拖都会算成「减去你已经滚到的那个时间」，时间轴直接乱掉。位移在两种情况下都是同一个修正量——因为基准线上本来就压着「时间轴认为此刻该唱的那句」。
  - **预览不跟随播放**（`autoFollow: false`）：编辑器里预览的曲目通常没在播，时钟恒为 0:00，而自动跟随会在每次滚动 5 秒后把列表拽回第一行——歌词根本没法翻。
  - 基准线与读数条都是 `IgnorePointer`：它们正好压在手指要起拖的位置上，不透传就会把手势整个吞掉。
  - 读数写作**「歌词延迟 / 歌词提前 X.X 秒」**——说清楚是歌词相对音频动了；显示的是**当前总偏移**（与下方状态条同一个数），不是本次校准的累计，否则退出再进入读数就归零了。
  - **像素↔时间的映射必须与真实布局一致**：高亮那一行是放大绘制的，若按普通行高计算，它下面所有行都会偏掉那点差值；而高亮行每校准一次就会换，于是误差每拖一次变一次、越积越大。
  - 「完成」左边是「重置」：拖了几下发现乱了，最快的出路是从头再来，而那正是校准仍开着的时候。
  - 松手即写入预览偏移，点「应用」时随歌词一起保存（沿用既有的 `_applyLyricResult`）。
- [x] **信息 / 歌词编辑器打开期间不自动切歌 (Auto-Advance Hold)**
  - 停留在「信息 / 歌词」编辑器时，当前曲目播完**不会自动跳下一首**（单曲循环除外——重复本曲正是该模式的目的），否则编辑对象会在编辑途中被换掉。
  - 以计数器实现（`holdAutoAdvance()` 返回释放回调）；持有期间同时裁掉原生预取队列，否则下一首会「无缝」抢跑，根本走不到播放完成的回调。
- [x] **全屏播放器主控件语义修正 (NowPlaying Primary Control = Play/Pause)**
  - 主按钮恒为播放/暂停（未下载时自动下载并播放，进度以环形显示），下载状态收敛为标题旁的小图标。
  - 控件排布：播放模式 / 上一首 / 播放 / 下一首 / 收藏；音量条支持一键静音；下滑关闭。
- [x] **本地音频删除与歌单删除 (Delete Local Audio & Delete Playlist)**
  - 曲目长按菜单可删除本地音频释放空间；歌单内左滑移除曲目；歌单卡片长按删除歌单。
- [x] **主按钮下载态与空闲态视觉统一 (Unified Download Button States)**
  - 「下载」与「下载中」是**同一个按钮**：圆形尺寸、填充、描边、图标完全一致，开始下载只是在外圈叠加一段进度弧。
  - 此前空闲态是实心圆形按钮、下载态却换成一个细圆环，点下去按钮像是凭空消失了。
  - 同时移除播放键外圈的红色不定式转圈（`isPreparing` 随之删除，已无使用方）。
- [x] **播放页主按钮如实反映曲目状态 (Download-Then-Play Primary Control)**
  - 架构上「未下载即不可播放」，因此播放页主按钮按真实状态切换：**未下载 → 下载按钮**；**下载中 → 圆环进度条**（与列表中 `TrackDownloadButton` 同一视觉）；**已下载 → 播放/暂停**。
  - 移除播放页的「已下载 ✓」指示与顶部音源行：能播放本身即代表已下载，再标注是冗余。
  - handler 自身的下载不经过 `DownloadManager`，故播放开始时会复查一次落盘状态，避免按钮卡在「下载」。
- [x] **iOS 发布 (iOS Release, Unsigned IPA)**
  - `tool/build_release.sh [android|ios|all]`：iOS 产出**混淆后的未签名 .ipa**（`build/ios/ipa/`），用 AltStore / Sideloadly / 自有描述文件自签安装；本项目没有 Apple 开发者账号，因此不上架、也无从签名。
  - 不用 `flutter build ipa`：它必须指定导出方式，也就必须有签名身份，未签名根本产不出包；改为 `flutter build ios --no-codesign` 后手工打包 `Payload/Runner.app` 成 zip（.ipa 本就是这个结构）。
  - **iOS 端已彻底移除 CocoaPods**：所用插件全部提供 `Package.swift`，项目改由 Swift Package Manager 集成，`ios/Podfile` 被**故意删除**——留着它会让构建以「CocoaPods not installed」失败，而其实一个 pod 都不需要。日后若有仅支持 Pods 的插件，用 `flutter create .` 重新生成并在此说明。
  - 顺带完成 Flutter 要求的两项迁移：iOS 最低版本 12 → 13，以及 UIScene 生命周期（`AppDelegate` 改为在 `didInitializeImplicitFlutterEngine` 里注册插件）。后台播放所需的 `UIBackgroundModes: audio` 保持不变。
- [x] **正式签名配置 (Release Signing)**
  - `android/app/build.gradle` 从 `android/key.properties` 读取签名信息；文件缺失时回退到 debug key 并打印警告，保证 `flutter run --release` 仍可用。
  - `tool/make_keystore.sh` 一次性生成密钥库（keytool 交互式输入密码，不进入命令行历史）。
  - **`*.jks` / `key.properties` 已加入 .gitignore，绝不入库。**
  - **⚠️ 换签名 = 老用户无法覆盖安装**：Android 以签名标识应用身份。v1.0.0–v2.2.0 均为 debug key 签名，**自 v2.2.1 起改用正式密钥**，从旧版本升级必须先卸载。当时应用尚无用户，故选择尽早切换。
  - **⚠️ `file()` 陷阱**：在 `app/build.gradle` 中 `file()` 相对 `android/app/` 解析，而 `key.properties` 与密钥库位于 `android/`，必须用 `rootProject.file()`，否则报 `Keystore file ... not found`。
  - 验证方式：`apksigner verify --print-certs`，确认 `Signer #1 certificate DN` 不再是 `CN=Android Debug`。
- [x] **基于收藏 / 播放 / 搜索的个性化推荐 (Local Taste-Based Recommendations)**
  - `RecommendationEngine` 完全基于**本地数据**构建口味画像，不上传任何信息：收藏（权重 3）、最近 30 条播放（权重 1）、搜索历史（权重 2）。
  - **中文分词问题**：不引入分词器，改用 **CJK 二元组**（「大鱼海棠」→ 大鱼/鱼海/海棠）＋ 拉丁词，足以支撑「相似推荐」。标题先经 `LyricsEngine.cleanTitle` 去噪。
  - 检索：取权重最高的 UP主 与词条作为种子词搜索（最多 4 次请求）；候选按画像打分排序，**已在库中的曲目不再推荐**。
  - **首次搜索前不展示推荐**（`_canRecommend => 搜索历史非空`），改为引导性空状态。
  - **清空搜索历史会同步清除其对推荐的影响**：画像每次都从零重建，不存在缓存的历史权重；清空后推荐区同时隐藏。
  - 推荐仅收录 ≤ 6 分钟的视频（过滤整场演唱会 / 合集 / 电台录音）；**搜索不做此过滤**——主动搜索长视频时就是想要它。
  - 搜索后不立即重算推荐（会额外增加数次请求），而是标记为 stale，回到推荐视图时再刷新。
- [x] **全局无间断滚动标题 (Continuous Marquee Everywhere)**
  - 滚动为**匀速无限循环**：没有起止停顿，第二份文本恰好落后一个周期，接缝不可见。
  - 覆盖范围统一：迷你播放条、全屏播放页、搜索 / 推荐、歌单详情、下载中列表。
  - 成本控制：仅在**确实溢出**时才动；每处包 `RepaintBoundary`，滚动不波及整行/整列表重绘；用 `phase`（0..1 相位偏移）错开各行，避免整屏同步平移——注意不能用「起始停顿」错开，因为已无停顿。
- [x] **代码瘦身与渲染优化 (Dead-Code Purge & Render Optimisation)**
  - **播放状态改为 Notifier**：`_currentTrack` / `_isPlaying` 此前是 `setState` 状态，每次播放/暂停、每次切歌都会重建整棵树（含两个页面子树），而真正关心它们的只有氛围背景与底部播放条。现改为 `ValueNotifier`，并把氛围背景从「内容的父节点」改为「内容的兄弟层」，切歌只重绘背景层。
  - **删除无人订阅的 `queueStream`**：每次队列变化都在做 `List.of(_playlist)` 全量拷贝，却没有任何监听者。
  - **模型瘦身**：`Track` 去掉 `uploaderFace / quality / isDownloaded / localFilePath / addedAt`（只写不读；其中 `isDownloaded` 还与磁盘真实状态存在冲突风险——下载状态的唯一真相是 `AudioDownloadService`）；`Playlist` 去掉 `coverUrl / createdAt / updatedAt`；`LyricsResult` 去掉 `rawLrc`。`fromMap` 对多余/缺失字段均容错，旧数据不受影响。
  - **删除死状态机**：`DownloadStatus.failed` 从未被赋值，所有 `status == downloading` 判断都是恒真；连同 `DownloadTask.received / total`（从未被读取）一并移除。
  - 其余移除：`AudioDownloadService.localPathIfDownloaded / usedBytes`、`handler.disposePlayer / playlist`、`DownloadManager.downloadingCount`、`AppSpacing` 整个类、5 个未使用颜色常量，以及 `GlassCard.margin`、`ProgressRing.color`、`CachedCoverImage.fallback`、`EmptyState.medallionSize/padding` 等无人传入的参数。
  - **MarqueeText** 不再每帧注册 post-frame 回调，仅在动画目标状态真正变化时注册。
  - **静态检查加严**：`analysis_options.yaml` 将 `unused_element / unused_field / unused_local_variable / dead_code` 提升为 **error**，并启用 `cancel_subscriptions`、`close_sinks`、`prefer_const_*` 等规则，防止死代码再次堆积。
- [x] **仅 64 位发布 (64-bit Only, Permanent)**
  - 构建脚本 `--target-platform android-arm64` ＋ `android/app/build.gradle` 中按 **release** variant 过滤 jniLibs，`armeabi-v7a` / `x86` / `x86_64` 永久移除。ARM 笔记本（Apple Silicon、Windows on ARM、ARM Chromebook）本就使用 arm64-v8a，同一个包即可覆盖。
  - **⚠️ `ndk { abiFilters }` 单独使用是不够的**：它不会剔除插件 AAR 里预编译的 .so。`jni` 包为每个 ABI 提供 `libdartjni.so`，仅凭它的存在，APK 就会声明 `native-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'`——32 位设备会认为可以安装，然后因为缺少 arm64 以外的 `libflutter.so`/`libapp.so` 而在启动时崩溃。**必须在打包阶段 exclude**，并用 `aapt2 dump badging` 核对 `native-code` 只剩 arm64-v8a。
  - **刻意只作用于 release**：作用于 debug 会导致 x86_64 模拟器无法运行。
  - **注意：这不会让 App 变快。** 拆分后的 arm64 APK 本来就只含 arm64 代码，机器码完全相同。收益是构建更快（110s → 35s）、产物从 3 个变 1 个。真正的体积收益来自混淆。
  - 与 `--split-per-abi` 互斥：AGP 会报 `Conflicting configuration ... splits abi filters`。单 ABI 本就无需拆分。
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

#### 🐛 Bug #44: 改完元数据，下方播放卡不刷新
- **根因**：`Track` 的 `==` 只比较 `id`（刻意如此，列表查找依赖它）。`ValueNotifier` 赋值前先判 `_value == newValue` 相等就直接 return，于是「同一首歌、改了标题/封面」的新对象被当成相同值**静默丢弃**，迷你播放器收不到通知；播放页因为走的是 Stream 所以正常刷新——才显出只有下方卡片是旧的。
- **修复**：`_currentTrack` 改用 `TrackNotifier`（`models/track.dart`），按**对象标识**而非 `==` 判断，任何新对象都通知。回归测试已覆盖。

#### 🐛 Bug #45: 播放页封面被拉伸（同一首歌在最近播放里却正常）
- **根因（两段联合作用，因此只有部分歌中招）**：
  1. **CDN 有下限**：`@{w}w_{h}h_1e_1c` 只在请求尺寸**不超过原图短边**时返回方形裁切；一旦超过，B 站直接返回**原始 16:9 大图**。实测同一张 2560×1440 封面：请求 1440 → 1440×1440 方图，请求 2000 → 原样 2560×1440。所以列表缩略图（130px 级）永远拿到方图，而播放页（≈1000px 级）在**原图短边偏小的封面**上就会拿到 16:9 图——这正是「只有那一首歌」的原因。
  2. **精确尺寸解码**：`Image.file` 同时传 `cacheWidth`/`cacheHeight` 是**不保比例**的解码，且不放大时是**逐轴**收敛的（2560×1440 配 960×960 目标 → 960×720），横向被压缩，于是画面拉伸。
- **修复**：改用 `ResizeImage(..., policy: ResizeImagePolicy.fit)` 保持比例解码，裁切仍交给 `BoxFit.cover`（与列表一致的中心裁切）；解码框留 16:9 余量，保证横图裁成方形后依旧清晰，且永不超过原图尺寸。自选的本地封面（任意比例）同时被此修复覆盖。

#### 🐛 Bug #47: 点最近播放的某首歌，放出来的却是另一首
- **根因**：`_player.currentIndexStream` 的回调用 `_queueBaseIndex + playerIndex` 把**原生队列下标**换算成逻辑下标，但在 `_startCurrent` 期间这个换算是无效的——新曲目要先下载（可能好几秒），此间原生队列里还是**上一首**，`_queueBaseIndex` 描述的也还是上一首；而 `clear()` / `setAudioSource()` 本身就会发出下标事件。于是一个陈旧下标被换算成了逻辑列表里的**任意一首**，既改写了 `_currentIndex` 也广播了错误曲目。
- **修复**：`_isRebuilding` 提前到下载之前置位（原来只包住队列重建那几行），并让下标回调在重建期间直接返回；只有最新一次 `_startCurrent`（token 相同）才有权清除该标志。

#### 🐛 Bug #46: 歌名滚到结尾会「跳」一下
- **根因**：`Text` 会把外层 `DefaultTextStyle` 合并进调用方给的样式，而跑马灯的 `TextPainter` 只测量了调用方样式——量的是另一套字体/字距。滚动位移用测量值、第二份副本的位置用真实布局，两者差几个像素，一圈结束时接不上，就是那一下跳动。
- **修复**：先解析出真正生效的样式，测量与两份 `Text` 都用它，圈长与副本间距严格相等。回归测试断言等时间步位移恒定（跨接缝也不例外）。

#### 🐛 Bug #52: 点下载后按钮往右跳，图标还换了一个
- **根因**：三种状态用了不同的组件搭出来——空闲态是 `IconButton`（自带 48pt 最小尺寸与内边距），下载中却是一个 `SizedBox(size + 14)`，两者宽度不同，一点下去整行就重排、控件向右偏；而且图标从 `download_rounded` 变成了 `arrow_downward`。菜单里用的又是第三个 `Icons.download`。
- **修复**：三态同一个 44pt 方框、同一个 `download_rounded` 字形，开始下载只是在外圈叠加进度环（与播放页主控件完全一致）。菜单里的下载图标一并统一。

#### 🐛 Bug #51: 同一个视频经搜索与经 BV 号进入库中会变成两首歌
- **根因**：曲目 id 原来是 `bvid_cid`，而**搜索接口不返回 cid**，于是搜索结果的 id 是 `bvid_0`，走 `fetchVideoInfo`（BV 号 / 链接 / 分 P）的却是 `bvid_<真实cid>`。同一个视频因此有两个身份：库里两条记录、下载状态各算各的、收藏与最近播放也会重复。
- **修复**：id 改为 `bvid_p<页码>`。页码在两条路径上都是已知的——搜索结果永远是第 1 P，详情接口本来就带 `page`——而 cid 只是播放时才需要的细节（`cid == 0` 时播放前会自行解析）。
- **注意**：id 同时是磁盘文件名，因此旧版本下载的文件仍以旧 id 存在。它们照常出现在库中也能播放（启动时的磁盘扫描按各自的 metadata 重建），只是重新搜索同一首歌会被当作新条目。当时应用尚无用户，故不做迁移。

#### 🐛 Bug #48: 「已开始下载」提示要等下载真的结束才弹
- **根因**：`_handleDownload` 里 `await DownloadManager.instance.startDownload(track)`，而 `startDownload` 要等文件真正落盘才返回。于是「已开始下载」这句话在网速慢时几分钟后才出现，且期间没有任何反馈。
- **修复**：改为 `unawaited(...)`，提示立即弹出，进度仍由下载环显示。

#### 🐛 Bug #49: 播放触发的下载不会刷新列表里的下载按钮
- **根因**：播放路径的下载不经过 `DownloadManager`（刻意如此），而 `TrackDownloadButton` 只订阅了 `DownloadManager`。因此「播放过、因而已落盘」的曲目，在列表里仍显示为「下载」按钮，直到该行被重建。
- **修复**：同时订阅 `AudioDownloadService.progressStream`，收到自己这首的 `done` 事件即刷新。

#### 🐛 Bug #50: 两处新建歌单对话框泄漏 `TextEditingController`
- **根因**：`showDialog` 前就地 `TextEditingController()`，对话框关闭后从未 `dispose`，每次新建歌单泄漏一个。
- **修复**：`await showDialog` 返回后立即释放。

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

#### 🐛 Bug #42: 编辑歌名 / 歌手 / 封面后，歌单里仍是旧信息，且重进依旧
- **根因（数据被覆盖，不只是界面没刷新）**：播放路径每次启动都会调用 `AudioDownloadService.saveTrackMetadata(track)` 与 `DatabaseService.saveDownloadedTrack(track)`，参数是**调用方手里那个 Track 对象**——可能是编辑之前的旧副本（来自旧列表、队列快照、最近播放等）。于是刚保存的编辑被旧数据**覆盖回磁盘**，重进自然还是旧的。
- **修复**：
  - `saveTrackMetadata` 默认**只创建不覆盖**，仅 `updateTrackMetadata` 以 `force: true` 覆盖；
  - `saveDownloadedTrack` 若库中已存在同 id 曲目则**原样保留**，只负责新增。
  - 即「显示用元数据的唯一写入者是 `updateTrackMetadata`」。
- **附带修复（界面）**：`PlaylistDetailSheet` 订阅 `libraryUpdateStream`，在其上方的播放页编辑元数据后，下方歌单会同步刷新；虚拟歌单「已下载」改为从下载库重建。

#### 🐛 Bug #43: 加入收藏抛 `Cannot add to an unmodifiable list`
- **根因**：`dart fix` 依据 `prefer_const_constructors` 把 `Playlist(id:'favorites', tracks: [])` 提升为 `const`，而 **const `[]` 是不可修改列表**，收藏插入直接抛异常。
- **修复**：`Playlist` 构造函数**刻意不再是 const**，且内部 `List.of(tracks)` 复制为可增长列表——从根源上杜绝该提升，lint 也不会再建议加回 `const`。回归测试已覆盖。

#### 🐛 Bug #37: 「歌手 - 歌名」永远无法拆分（死分支）
- **根因**：`cleanTitle` 第 7 步先把所有 `-` 替换成空格，第 8 步才判断 `title.contains('-')`——恒为 false，歌手提取从未执行。
- **修复**：拆分提前到标点清理之前，并要求两侧非空。回归测试已覆盖。

#### 🐛 Bug #38: LRC 解析丢行
- **根因**：正则强制要求毫秒段（`[mm:ss]` 直接跳过，整份歌词可能解析为 0 行），且只取每行第一个时间戳（副歌复用行只在第一次高亮）。
- **修复**：毫秒段改为可选、按位数解释（`.5`→0.5s、`.05`→0.05s），并对一行多个时间戳逐个展开。5 条回归测试覆盖。

#### 🐛 Bug #39: 签名 CDN 链接与设备指纹被写入日志
- **根因**：`debugPrint` 在 **release 构建中依然输出**，而代码打印了 `Search cookies`（buvid 设备指纹）、完整签名音源 URL 与本地文件路径。任何能读 logcat 的进程都可获取。
- **修复**：仅保留错误级日志，去掉全部 URL / Cookie / 路径打印。

#### 🐛 Bug #40: 快速连点下载可能重复下载
- **根因**：`startDownload` 先 `await isDownloaded()` 再登记任务，两次点击可在该 await 期间同时通过判断。
- **修复**：先同步占位再 await。

#### 🐛 Bug #41: 异步回调在 dispose 之后写入 Notifier / setState
- **根因**：取消订阅只能阻止**新**事件；已进入的回调在 await 之后仍会继续执行。`main` 的歌词回调与搜索页 `_performSearch` 都缺 `mounted` 判断。
- **修复**：每个 await 之后补 `mounted` 判断。

#### 🐛 Bug #36: 歌词预览每次 rebuild 都新建 `ValueNotifier`
- **根因**：`positionNotifier ?? ValueNotifier(Duration.zero)` 写在 `build` 里，每帧换一个 notifier 且从不 dispose。
- **修复**：提升为 State 字段 `_idlePosition` 并在 `dispose` 中释放。

#### 🐛 Bug #22: 默认 Flutter 图标未替换 & Android 应用名称全小写带 s (bilibeats)
- **彻底修复方式**：根据桌面设计图像精准裁切生成全套 Android (`mipmap`) 和 iOS (`AppIcon`) 各种尺寸分辨率图标，并修正 `AndroidManifest.xml` 中的标签为 `bilibeat`。

