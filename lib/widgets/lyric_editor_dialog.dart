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

  /// Which tab to land on: 0 = 信息, 1 = 歌词.
  final int initialTabIndex;

  const LyricEditorDialog({
    super.key,
    required this.songTitle,
    required this.artistName,
    this.coverUrl,
    this.positionNotifier,
    this.currentLines,
    required this.onApplyLyrics,
    this.onUpdateMetadata,
    this.initialTabIndex = 0,
  });

  @override
  State<LyricEditorDialog> createState() => _LyricEditorDialogState();
}

class _LyricEditorDialogState extends State<LyricEditorDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _titleController;
  late TextEditingController _artistController;
  late TextEditingController _coverUrlController;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _lrcController = TextEditingController();

  final ValueNotifier<Duration> _idlePosition = ValueNotifier(Duration.zero);

  List<LyricsResult> _searchResults = [];
  final List<LyricsResult> _pastedResults = [];
  int? _selectedIndex;
  LyricsResult? _previewingResult;
  double _previewOffset = 0.0;
  bool _calibrating = false;
  bool _isSearching = false;

  /// True while the full-screen LRC text editor is showing.
  bool _inLrcEditor = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 2, vsync: this, initialIndex: widget.initialTabIndex);
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
    _lrcController.dispose();
    _idlePosition.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Cover picker
  // ---------------------------------------------------------------------------

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
        final savedFile = File(
            '${coversDir.path}/cover_${DateTime.now().millisecondsSinceEpoch}.$ext');
        await File(image.path).copy(savedFile.path);

        if (mounted) {
          setState(() => _coverUrlController.text = savedFile.path);
        }
      }
    } catch (e) {
      debugPrint('Error picking cover image: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Search & results
  // ---------------------------------------------------------------------------

  String _fingerprint(List<LyricLine> lines) => lines
      .map((l) => l.text.trim())
      .where((t) => t.isNotEmpty)
      .join('\n');

  bool _matchesCurrent(LyricsResult r) {
    final current = widget.currentLines;
    if (current == null || current.isEmpty) return false;
    return _fingerprint(r.lines) == _fingerprint(current);
  }

  List<LyricsResult> _pinnedResults() {
    final pinned = <LyricsResult>[];
    final current = widget.currentLines;
    if (current != null && current.isNotEmpty) {
      pinned.add(LyricsResult(
        source: 'current',
        songTitle: widget.songTitle,
        artistName: widget.artistName,
        lines: current,
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

    final results = <LyricsResult>[..._pinnedResults()];

    final netease = await LyricsEngine.fetchFromNetEase(query);
    if (netease != null) results.add(netease);

    final lrclib = await LyricsEngine.fetchFromLRCLIB(query);
    if (lrclib != null) results.add(lrclib);

    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  String _snippet(LyricsResult res) {
    final texts = res.lines
        .map((l) => l.text.trim())
        .where((t) => t.isNotEmpty)
        .take(2)
        .join(' / ');
    return texts.isEmpty ? '无文本' : texts;
  }

  // ---------------------------------------------------------------------------
  // Apply / calibration
  // ---------------------------------------------------------------------------

  void _applyLyricResult(LyricsResult res, {double offset = 0.0}) {
    final adjustedLines = offset == 0.0
        ? res.lines
        : res.lines
            .map((l) => LyricLine(
                  time: (l.time + offset).clamp(0.0, 99999.0),
                  text: l.text,
                  translation: l.translation,
                ))
            .toList();

    widget.onApplyLyrics(LyricsResult(
      source: res.source,
      songTitle: res.songTitle,
      artistName: res.artistName,
      lines: adjustedLines,
    ));
    Navigator.pop(context);
  }

  void _applyTapCalibration(double offset) {
    setState(() => _previewOffset = offset);
  }

  // ---------------------------------------------------------------------------
  // LRC text editor
  // ---------------------------------------------------------------------------

  /// Opens the LRC editor. If [res] is given its lines are serialised into
  /// the text field for editing; otherwise the field starts empty (paste).
  void _openLrcEditor(LyricsResult? res) {
    _lrcController.text =
        (res != null && res.lines.isNotEmpty) ? LyricsEngine.toLrc(res.lines) : '';
    setState(() {
      _inLrcEditor = true;
      _previewingResult = null;
      _calibrating = false;
    });
  }

  /// Parses the editor text and jumps to preview/calibration.
  void _confirmLrcEdit() {
    final text = _lrcController.text.trim();
    if (text.isEmpty) return;

    final lines = LyricsEngine.parseLrc(text);
    final result = LyricsResult(
      source: 'user',
      songTitle: '自定义歌词',
      artistName: _artistController.text.trim().isNotEmpty
          ? _artistController.text.trim()
          : '自定义',
      lines: lines.isNotEmpty ? lines : [LyricLine(time: 0, text: text)],
    );

    // Keep it in the pasted list so it shows up in future searches.
    _pastedResults.removeWhere(
        (r) => _fingerprint(r.lines) == _fingerprint(result.lines));
    _pastedResults.add(result);

    setState(() {
      _inLrcEditor = false;
      _previewingResult = result;
      _previewOffset = 0.0;
      _calibrating = false;
      // Refresh list so the new paste is pinned.
      final searchOnly = _searchResults
          .where((r) => r.source != 'user' && r.source != 'current')
          .toList();
      _searchResults = [..._pinnedResults(), ...searchOnly];
    });
  }

  // ---------------------------------------------------------------------------
  // Metadata
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Offset bar (calibration controls)
  // ---------------------------------------------------------------------------

  Widget _offsetBar() {
    final off = _previewOffset;
    final label = off == 0
        ? '时间轴未调整'
        : '${off > 0 ? "歌词延迟" : "歌词提前"} ${off.abs().toStringAsFixed(1)} 秒';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
            color: _calibrating ? AppColors.accent30 : AppColors.hairline),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined,
              color: off == 0 && !_calibrating
                  ? AppColors.textFaint
                  : AppColors.accent,
              size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: off == 0 ? AppColors.textMuted : AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          if (off != 0) ...[
            _offsetBtn('重置', () => setState(() => _previewOffset = 0.0),
                muted: true),
            const SizedBox(width: 6),
          ],
          _offsetBtn(
            _calibrating ? '完成' : '校准',
            () => setState(() => _calibrating = !_calibrating),
            highlighted: _calibrating,
          ),
        ],
      ),
    );
  }

  Widget _offsetBtn(String label, VoidCallback onPressed,
      {bool muted = false, bool highlighted = false}) {
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        decoration: BoxDecoration(
          color: highlighted ? AppColors.accent22 : AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
              color: highlighted ? AppColors.accent30 : AppColors.hairline),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: muted
                ? AppColors.textMuted
                : (highlighted ? AppColors.accent : AppColors.textPrimary),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '信息与歌词',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
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
              tabs: const [Tab(text: '信息'), Tab(text: '歌词')],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildInfoTab(),
                  _buildLyricsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Info
  // ---------------------------------------------------------------------------

  Widget _buildInfoTab() {
    return SingleChildScrollView(
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
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _pickLocalCoverImage,
                  icon: const Icon(Icons.photo_library,
                      size: 18, color: AppColors.accent),
                  label: const Text('选择封面',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('歌名',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _titleController,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: '歌曲名称',
              hintStyle: const TextStyle(color: AppColors.textFaint),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          const Text('歌手 / UP主',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _artistController,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: '歌手或UP主名称',
              hintStyle: const TextStyle(color: AppColors.textFaint),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          const Text('封面 URL / 本地路径',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _coverUrlController,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'https:// 或本地路径',
              hintStyle: const TextStyle(color: AppColors.textFaint),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('保存',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Lyrics (three states: list → LRC editor → preview)
  // ---------------------------------------------------------------------------

  Widget _buildLyricsTab() {
    if (_previewingResult != null) return _buildPreview();
    if (_inLrcEditor) return _buildLrcEditor();
    return _buildResultList();
  }

  // --- State A: search results + paste card ---

  Widget _buildResultList() {
    return Column(
      children: [
        // Search bar
        TextField(
          controller: _searchController,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          onSubmitted: (_) => _performSearch(),
          decoration: InputDecoration(
            hintText: '搜索歌曲或歌手',
            hintStyle: const TextStyle(color: AppColors.textFaint),
            suffixIcon: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.accent)),
                  )
                : IconButton(
                    icon: const Icon(Icons.search, color: AppColors.accent),
                    onPressed: _performSearch,
                  ),
            filled: true,
            fillColor: Colors.white10,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        const SizedBox(height: 10),

        // Results
        Expanded(
          child: (_isSearching && _searchResults.isEmpty)
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.accent))
              : _searchResults.isEmpty
                  ? const Center(
                      child: Text('无结果',
                          style: TextStyle(color: AppColors.textFaint)))
                  : ListView.builder(
                      itemCount: _searchResults.length + 1, // +1 for paste card
                      itemBuilder: (context, index) {
                        // Last item: paste / edit LRC card
                        if (index == _searchResults.length) {
                          return _pasteCard();
                        }
                        return _resultRow(_searchResults[index], index);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _resultRow(LyricsResult res, int index) {
    final isSelected = _selectedIndex == index;
    final isUserPasted = res.source == 'user';
    final isCurrent = res.source == 'current';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppColors.success12
            : (isUserPasted ? AppColors.accent12 : AppColors.white06),
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
          // Body → preview
          Expanded(
            child: InkWell(
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(16)),
              onTap: () {
                setState(() {
                  _selectedIndex = index;
                  _previewingResult = res;
                  _previewOffset = 0.0;
                  _calibrating = false;
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isCurrent
                          ? '当前歌词'
                          : (isUserPasted
                              ? '粘贴歌词'
                              : (res.songTitle ?? '未知歌曲')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent
                            ? AppColors.success
                            : (isUserPasted
                                ? AppColors.pinkStart
                                : AppColors.textPrimary),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 5),
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
                          isCurrent ? '当前使用' : res.source.toUpperCase(),
                          style: const TextStyle(
                              color: AppColors.textFaint,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6),
                        ),
                        const SizedBox(width: 8),
                        Text('${res.lines.length} 行',
                            style: const TextStyle(
                                color: AppColors.textFaint, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Edit button → LRC editor
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: AppColors.textMuted,
            tooltip: '编辑 LRC',
            onPressed: () => _openLrcEditor(res),
          ),

          // Apply button
          IconButton(
            icon: Icon(
              isCurrent
                  ? Icons.check_circle
                  : (isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked),
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
            tooltip: isCurrent ? '当前歌词' : '应用',
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  /// "粘贴 / 编辑 LRC" card at the bottom of the results list.
  Widget _pasteCard() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openLrcEditor(null),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.white05,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: const Row(
          children: [
            Icon(Icons.content_paste, color: AppColors.accent, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '粘贴 / 编辑 LRC 文本',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: AppColors.textFaint, size: 14),
          ],
        ),
      ),
    );
  }

  // --- State B: LRC text editor ---

  Widget _buildLrcEditor() {
    return Column(
      children: [
        // Header
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
              onPressed: () => setState(() => _inLrcEditor = false),
            ),
            const Expanded(
              child: Text(
                '编辑 LRC',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Editor
        Expanded(
          child: TextField(
            controller: _lrcController,
            maxLines: null,
            expands: true,
            autofocus: true,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontFamily: 'monospace',
              height: 1.5,
            ),
            decoration: InputDecoration(
              hintText: '[00:12.34]歌词内容\n[00:16.00]下一行\n\n粘贴或编辑 LRC 文本',
              hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 13),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(14),
              alignLabelWithHint: true,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Confirm → preview
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            onPressed: _confirmLrcEdit,
            icon: const Icon(Icons.preview, color: AppColors.textPrimary, size: 20),
            label: const Text('预览并校准',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  // --- State C: preview + calibration ---

  Widget _buildPreview() {
    return Column(
      children: [
        // Header
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
              onPressed: () => setState(() {
                _previewingResult = null;
                _calibrating = false;
              }),
            ),
            Expanded(
              child: Text(
                _previewingResult!.songTitle ?? widget.songTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
            ),
            // Jump to LRC editor for the current preview
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  color: AppColors.textMuted, size: 20),
              tooltip: '编辑 LRC',
              onPressed: () => _openLrcEditor(_previewingResult),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Synced preview
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: Colors.black26,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SyncedLyricsView(
                lines: _previewingResult!.lines,
                positionNotifier: widget.positionNotifier ?? _idlePosition,
                offset: _previewOffset,
                calibrating: _calibrating,
                onCalibrateTap: _applyTapCalibration,
                autoFollow: widget.positionNotifier != null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _offsetBar(),
        const SizedBox(height: 10),

        // Apply
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            onPressed: () =>
                _applyLyricResult(_previewingResult!, offset: _previewOffset),
            icon: const Icon(Icons.check_circle,
                color: AppColors.textPrimary, size: 20),
            label: const Text('应用',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}
