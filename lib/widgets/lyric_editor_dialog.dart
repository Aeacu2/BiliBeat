import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/lyric_line.dart';
import '../services/lyrics_engine.dart';
import '../theme/app_theme.dart';
import 'cached_cover_image.dart';
import 'synced_lyrics_view.dart';

class LyricEditorDialog extends StatefulWidget {
  final String songTitle;
  final String artistName;
  final String? coverUrl;
  final ValueNotifier<Duration>? positionNotifier;
  final List<LyricLine>? currentLines;
  final Function(LyricsResult) onApplyLyrics;
  final Function(String title, String artist, String coverUrl)? onUpdateMetadata;

  const LyricEditorDialog({
    super.key,
    required this.songTitle,
    required this.artistName,
    this.coverUrl,
    this.positionNotifier,
    this.currentLines,
    required this.onApplyLyrics,
    this.onUpdateMetadata,
  });

  @override
  State<LyricEditorDialog> createState() => _LyricEditorDialogState();
}

class _LyricEditorDialogState extends State<LyricEditorDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _titleController;
  late TextEditingController _artistController;
  late TextEditingController _coverUrlController;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _importController = TextEditingController();

  /// Stand-in clock for the preview when the caller has no live position.
  /// This used to be constructed inline inside `build`, which handed the
  /// preview a brand-new notifier on every rebuild and leaked its listener.
  final ValueNotifier<Duration> _idlePosition = ValueNotifier(Duration.zero);

  List<LyricsResult> _searchResults = [];
  final List<LyricsResult> _pastedResults = [];
  int? _selectedIndex;
  LyricsResult? _previewingResult;
  double _previewOffset = 0.0;
  bool _isSearching = false;
  bool _showPasteLrcSection = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _titleController = TextEditingController(text: widget.songTitle);
    _artistController = TextEditingController(text: widget.artistName);
    _coverUrlController = TextEditingController(text: widget.coverUrl ?? '');

    _searchController.text = '${widget.artistName} ${widget.songTitle}'.trim();
    _searchResults = _pinnedResults();
    _performSearch();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _artistController.dispose();
    _coverUrlController.dispose();
    _searchController.dispose();
    _importController.dispose();
    _idlePosition.dispose();
    super.dispose();
  }

  Future<void> _pickLocalCoverImage() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final docs = await getApplicationDocumentsDirectory();
        final coversDir = Directory('${docs.path}/bilibeat_covers');
        if (!await coversDir.exists()) {
          await coversDir.create(recursive: true);
        }
        final ext = image.path.split('.').last;
        final savedFile = File('${coversDir.path}/cover_${DateTime.now().millisecondsSinceEpoch}.$ext');
        await File(image.path).copy(savedFile.path);

        if (mounted) {
          setState(() {
            _coverUrlController.text = savedFile.path;
          });
        }
      }
    } catch (e) {
      debugPrint('Error picking cover image: $e');
    }
  }

  /// Fingerprint used to compare lyric contents (ignores timing/whitespace).
  String _fingerprint(List<LyricLine> lines) => lines
      .map((l) => l.text.trim())
      .where((t) => t.isNotEmpty)
      .join('\n');

  bool _matchesCurrent(LyricsResult r) {
    final current = widget.currentLines;
    if (current == null || current.isEmpty) return false;
    return _fingerprint(r.lines) == _fingerprint(current);
  }

  /// Items always pinned to the top of the result list, in order: the
  /// currently-used lyrics first, then any user-pasted lyrics that differ from
  /// the current one. Search results come after these.
  List<LyricsResult> _pinnedResults() {
    final pinned = <LyricsResult>[];
    final current = widget.currentLines;
    if (current != null && current.isNotEmpty) {
      pinned.add(LyricsResult(
        source: 'current',
        songTitle: widget.songTitle,
        artistName: widget.artistName,
        lines: current,
        rawLrc: '',
      ));
    }
    for (final p in _pastedResults) {
      if (!_matchesCurrent(p)) pinned.add(p);
    }
    return pinned;
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() => _searchResults = _pinnedResults());
      return;
    }
    setState(() {
      _isSearching = true;
      _selectedIndex = null;
      _previewingResult = null;
    });

    // Pinned items (current + user-pasted) always come first.
    final results = <LyricsResult>[..._pinnedResults()];

    // NetEase
    final netease = await LyricsEngine.fetchFromNetEase(query);
    if (netease != null) results.add(netease);

    // LRCLIB
    final lrclib = await LyricsEngine.fetchFromLRCLIB(query);
    if (lrclib != null) results.add(lrclib);

    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  void _applyLyricResult(LyricsResult res, {double offset = 0.0}) {
    final adjustedLines = offset == 0.0
        ? res.lines
        : res.lines.map((l) => LyricLine(
            time: (l.time + offset).clamp(0.0, 99999.0),
            text: l.text,
            translation: l.translation,
          )).toList();

    final finalResult = LyricsResult(
      source: res.source,
      songTitle: res.songTitle,
      artistName: res.artistName,
      lines: adjustedLines,
      rawLrc: res.rawLrc,
    );

    widget.onApplyLyrics(finalResult);
    Navigator.pop(context);
  }

  void _importPastedLrcText() {
    final text = _importController.text.trim();
    if (text.isEmpty) return;

    final lines = LyricsEngine.parseLrc(text);
    final userResult = LyricsResult(
      source: 'user',
      songTitle: '用户粘贴歌词',
      artistName: _artistController.text.trim().isNotEmpty ? _artistController.text.trim() : '自定义',
      lines: lines.isNotEmpty ? lines : [LyricLine(time: 0, text: text)],
      rawLrc: text,
    );

    setState(() {
      _pastedResults.removeWhere(
          (r) => _fingerprint(r.lines) == _fingerprint(userResult.lines));
      _pastedResults.add(userResult);
      final searchOnly = _searchResults
          .where((r) => r.source != 'user' && r.source != 'current')
          .toList();
      _searchResults = [..._pinnedResults(), ...searchOnly];
      _selectedIndex = null;
      _showPasteLrcSection = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已成功在歌词列表第 1 位生成用户粘贴歌词！点击可进行对齐校准'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _saveMetadata() {
    final newTitle = _titleController.text.trim();
    final newArtist = _artistController.text.trim();
    final newCover = _coverUrlController.text.trim();

    if (newTitle.isNotEmpty && widget.onUpdateMetadata != null) {
      widget.onUpdateMetadata!(
        newTitle,
        newArtist.isNotEmpty ? newArtist : '未知UP主',
        newCover,
      );
    }
    Navigator.pop(context);
  }

  void _nudgeOffset(double delta) {
    setState(() => _previewOffset =
        double.parse((_previewOffset + delta).toStringAsFixed(1)));
  }

  /// Timeline calibration. A single horizontal bar with real-sized targets;
  /// the old vertical rail of five 50px buttons squeezed the preview and was
  /// fiddly to hit.
  Widget _offsetBar() {
    final label =
        '${_previewOffset >= 0 ? "+" : ""}${_previewOffset.toStringAsFixed(1)}s';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, color: AppColors.accent, size: 16),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const Spacer(),
          _offsetBtn('-0.5', () => _nudgeOffset(-0.5)),
          const SizedBox(width: 6),
          _offsetBtn('-0.1', () => _nudgeOffset(-0.1)),
          const SizedBox(width: 6),
          _offsetBtn('归零', () => setState(() => _previewOffset = 0.0),
              muted: true),
          const SizedBox(width: 6),
          _offsetBtn('+0.1', () => _nudgeOffset(0.1)),
          const SizedBox(width: 6),
          _offsetBtn('+0.5', () => _nudgeOffset(0.5)),
        ],
      ),
    );
  }

  Widget _offsetBtn(String label, VoidCallback onPressed,
      {bool muted = false}) {
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: muted ? AppColors.textMuted : AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// First couple of lines, so candidates are distinguishable at a glance
  /// instead of all reading "NETEASE • 42 行歌词".
  String _snippet(LyricsResult res) {
    final texts = res.lines
        .map((l) => l.text.trim())
        .where((t) => t.isNotEmpty)
        .take(2)
        .join(' / ');
    return texts.isEmpty ? '（无文本内容）' : texts;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // A hardcoded 580 overflowed short phones outright, and overflowed every
    // phone once the keyboard came up. Fit to what is actually available.
    final available = media.size.height - media.viewInsets.bottom - 80;
    final height = available.clamp(320.0, 620.0);

    return Dialog(
      backgroundColor: const Color(0xFF18181C),
      insetPadding: EdgeInsets.symmetric(
        horizontal: 20,
        vertical: media.viewInsets.bottom > 0 ? 12 : 32,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        padding: const EdgeInsets.all(20),
        height: height,
        child: Column(
          children: [
            // Header bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '信息与歌词',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            TabBar(
              controller: _tabController,
              indicatorColor: AppColors.accent,
              labelColor: AppColors.accent,
              unselectedLabelColor: AppColors.textMuted,
              tabs: const [
                Tab(text: '信息'),
                Tab(text: '歌词'),
              ],
            ),

            const SizedBox(height: 16),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Information Tab (Title, Artist, Cover Photo)
                  SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: CachedCoverImage(
                                  url: _coverUrlController.text.trim(),
                                  width: 96,
                                  height: 96,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: _pickLocalCoverImage,
                                icon: const Icon(Icons.photo_library, size: 18, color: AppColors.accent),
                                label: const Text('从手机相册选择封面', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.white24),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        const Text('歌名', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _titleController,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: '输入歌曲名称',
                            hintStyle: const TextStyle(color: AppColors.textFaint),
                            filled: true,
                            fillColor: Colors.white10,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),

                        const SizedBox(height: 12),

                        const Text('歌手 / UP主', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _artistController,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: '输入歌手或UP主名称',
                            hintStyle: const TextStyle(color: AppColors.textFaint),
                            filled: true,
                            fillColor: Colors.white10,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),

                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton(
                            onPressed: _saveMetadata,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('保存歌曲信息', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Tab 2: Lyrics Tab
                  _previewingResult != null
                      ? Column(
                          children: [
                            // Header bar for live preview
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                                  onPressed: () => setState(() => _previewingResult = null),
                                ),
                                Expanded(
                                  child: Text(
                                    '实时预览: ${_previewingResult!.songTitle ?? widget.songTitle}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),

                            // Live preview gets the full width; calibration
                            // sits beneath it.
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  color: Colors.black26,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  child: SyncedLyricsView(
                                    lines: _previewingResult!.lines,
                                    positionNotifier:
                                        widget.positionNotifier ??
                                            _idlePosition,
                                    offset: _previewOffset,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _offsetBar(),
                            const SizedBox(height: 10),
                            // Apply Button for Live Preview
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: ElevatedButton.icon(
                                onPressed: () => _applyLyricResult(_previewingResult!, offset: _previewOffset),
                                icon: const Icon(Icons.check_circle, color: AppColors.textPrimary, size: 20),
                                label: const Text('确认应用此歌词', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            // Search bar
                            TextField(
                              controller: _searchController,
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                              onSubmitted: (_) => _performSearch(),
                              decoration: InputDecoration(
                                hintText: '输入歌曲名或歌手搜索歌词',
                                hintStyle: const TextStyle(color: AppColors.textFaint),
                                suffixIcon: _isSearching
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: AppColors.accent),
                                      )
                                    : IconButton(
                                        icon: const Icon(Icons.search, color: AppColors.accent),
                                        onPressed: _performSearch,
                                      ),
                                filled: true,
                                fillColor: Colors.white10,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Search results list
                            Expanded(
                              child: (_isSearching && _searchResults.isEmpty)
                                  ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                                  : _searchResults.isEmpty
                                      ? const Center(child: Text('未搜到相关歌词', style: TextStyle(color: AppColors.textFaint)))
                                      : ListView.builder(
                                          itemCount: _searchResults.length,
                                          itemBuilder: (context, index) {
                                            final res = _searchResults[index];
                                            final isSelected = _selectedIndex == index;
                                            final isUserPasted = res.source == 'user';
                                            final isCurrent = res.source == 'current';

                                            return Container(
                                              margin: const EdgeInsets.only(bottom: 8),
                                              decoration: BoxDecoration(
                                                color: isCurrent
                                                    ? AppColors.success12
                                                    : (isUserPasted
                                                        ? AppColors.accent12
                                                        : AppColors.white06),
                                                borderRadius: BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: isSelected
                                                      ? AppColors.accent
                                                      : (isCurrent
                                                          ? AppColors.success50
                                                          : (isUserPasted ? AppColors.accent50 : Colors.white12)),
                                                  width: isSelected || isUserPasted || isCurrent ? 1.5 : 1.0,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  // Card Body (Tap to Enter Live Preview & Timing Calibration)
                                                  Expanded(
                                                    child: InkWell(
                                                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                                                      onTap: () {
                                                        setState(() {
                                                          _selectedIndex = index;
                                                          _previewingResult = res;
                                                          _previewOffset = 0.0;
                                                        });
                                                      },
                                                      child: Padding(
                                                        padding: const EdgeInsets.all(12),
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Row(
                                                              children: [
                                                                Expanded(
                                                                  child: Text(
                                                                    isCurrent
                                                                        ? '✅ 当前使用的歌词'
                                                                        : (isUserPasted ? '📌 用户粘贴歌词 (.lrc)' : (res.songTitle ?? '未知歌曲')),
                                                                    maxLines: 1,
                                                                    overflow: TextOverflow.ellipsis,
                                                                    style: TextStyle(
                                                                      color: isCurrent
                                                                          ? AppColors.success
                                                                          : (isUserPasted ? AppColors.pinkStart : AppColors.textPrimary),
                                                                      fontWeight: FontWeight.bold,
                                                                      fontSize: 14,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                            const SizedBox(height: 5),
                                                            // The actual words: without this every
                                                            // candidate looked identical.
                                                            Text(
                                                              _snippet(res),
                                                              maxLines: 2,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: const TextStyle(
                                                                color: AppColors.textSecondary,
                                                                fontSize: 12.5,
                                                                height: 1.35,
                                                              ),
                                                            ),
                                                            const SizedBox(height: 6),
                                                            Row(
                                                              children: [
                                                                Text(
                                                                  isCurrent
                                                                      ? '当前使用'
                                                                      : res.source.toUpperCase(),
                                                                  style: const TextStyle(
                                                                      color: AppColors.textFaint,
                                                                      fontSize: 11,
                                                                      fontWeight: FontWeight.w700,
                                                                      letterSpacing: 0.6),
                                                                ),
                                                                const SizedBox(width: 8),
                                                                Text(
                                                                  '${res.lines.length} 行',
                                                                  style: const TextStyle(
                                                                      color: AppColors.textFaint,
                                                                      fontSize: 11),
                                                                ),
                                                                const Spacer(),
                                                                const Text(
                                                                  '点击预览 / 校准 ➔',
                                                                  style: TextStyle(
                                                                      color: AppColors.pinkStart,
                                                                      fontSize: 11,
                                                                      fontWeight: FontWeight.w500),
                                                                ),
                                                              ],
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),

                                                  // Right Circle Icon (Tap directly to Select & Apply)
                                                  IconButton(
                                                    icon: Icon(
                                                      isCurrent
                                                          ? Icons.check_circle
                                                          : (isSelected ? Icons.check_circle : Icons.radio_button_unchecked),
                                                      color: isCurrent
                                                          ? AppColors.success
                                                          : (isSelected ? AppColors.accent : AppColors.textFaint),
                                                      size: 24,
                                                    ),
                                                    onPressed: isCurrent
                                                        ? null
                                                        : () {
                                                            setState(() => _selectedIndex = index);
                                                            _applyLyricResult(res);
                                                          },
                                                    tooltip: isCurrent ? '当前正在使用此歌词' : '直接选中并应用此歌词',
                                                  ),
                                                  const SizedBox(width: 4),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                            ),

                            const SizedBox(height: 8),

                            // Bottom Option: Paste .lrc Text Section
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.white05,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Column(
                                children: [
                                  InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () {
                                      setState(() {
                                        _showPasteLrcSection = !_showPasteLrcSection;
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Row(
                                            children: [
                                              Icon(Icons.content_paste, color: AppColors.accent, size: 18),
                                              SizedBox(width: 8),
                                              Text(
                                                '粘贴 .lrc 文本',
                                                style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                                              ),
                                            ],
                                          ),
                                          Icon(
                                            _showPasteLrcSection ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                            color: AppColors.textMuted,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (_showPasteLrcSection) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
                                      child: Column(
                                        children: [
                                          SizedBox(
                                            height: 90,
                                            child: TextField(
                                              controller: _importController,
                                              maxLines: null,
                                              expands: true,
                                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontFamily: 'monospace'),
                                              decoration: InputDecoration(
                                                hintText: '在此粘贴 LRC 格式歌词，如：[00:12.34]第一句歌词',
                                                hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 12),
                                                filled: true,
                                                fillColor: Colors.white10,
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                  borderSide: BorderSide.none,
                                                ),
                                                contentPadding: const EdgeInsets.all(10),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          SizedBox(
                                            width: double.infinity,
                                            height: 38,
                                            child: ElevatedButton(
                                              onPressed: _importPastedLrcText,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppColors.accent,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              ),
                                              child: const Text('生成并排在第 1 位', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
