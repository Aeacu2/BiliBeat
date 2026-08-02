import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/lyric_line.dart';
import '../services/database_service.dart';
import '../services/lyrics_engine.dart';
import '../theme/app_theme.dart';
import '../theme/haptics.dart';
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
  final VoidCallback? onClose;

  /// Which tab to land on: 0 = 信息, 1 = 歌词.
  final int initialTabIndex;

  /// The playing track's id, used to look up the real provider of the
  /// currently-active lyrics so the pinned row shows it, not a redundant
  /// "当前使用" label under a title that already says 当前歌词.
  final String? currentTrackId;

  const LyricEditorDialog({
    super.key,
    required this.songTitle,
    required this.artistName,
    this.coverUrl,
    this.positionNotifier,
    this.currentLines,
    required this.onApplyLyrics,
    this.onUpdateMetadata,
    this.onClose,
    this.initialTabIndex = 0,
    this.currentTrackId,
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

  /// Real provider of the active lyrics (read from the cache); shown on the
  /// pinned 当前歌词 row.
  String? _currentSourceLabel;

  /// True while the full-screen LRC text editor is showing.
  bool _inLrcEditor = false;

  final GlobalKey _tabRowKey = GlobalKey();
  final List<GlobalKey> _tabKeys = [GlobalKey(), GlobalKey()];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 2, vsync: this, initialIndex: widget.initialTabIndex);
    _titleController = TextEditingController(text: widget.songTitle);
    _artistController = TextEditingController(text: widget.artistName);
    _coverUrlController = TextEditingController(text: widget.coverUrl ?? '');

    _tabController.addListener(() {
      setState(() {});
    });
    _titleController.addListener(() => setState(() {}));
    _artistController.addListener(() => setState(() {}));
    _searchController.text = '${widget.artistName} ${widget.songTitle}'.trim();
    _searchResults = _pinnedResults();
    _performSearch();

    // Surface the real provider of the active lyrics on the pinned row.
    final trackId = widget.currentTrackId;
    if (trackId != null) {
      DatabaseService.getCachedLyrics(trackId).then((cached) {
        if (mounted && cached != null && cached.source != 'none') {
          setState(() => _currentSourceLabel = cached.source);
        }
      });
    }
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

  /// Parses the editor text and applies it directly, returning to the
  /// player's lyrics view.
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

    // Apply directly and return to the player's lyrics view.
    _applyLyricResult(result);
  }

  // ---------------------------------------------------------------------------
  // Metadata
  // ---------------------------------------------------------------------------

  void _saveAll() {
    final newTitle = _titleController.text.trim();
    final newArtist = _artistController.text.trim();
    final newCover = _coverUrlController.text.trim();

    final hasMetadataEdit = newTitle.isNotEmpty &&
        (newTitle != widget.songTitle ||
         newArtist != widget.artistName ||
         newCover != (widget.coverUrl ?? ''));

    if (hasMetadataEdit && widget.onUpdateMetadata != null) {
      widget.onUpdateMetadata!(
        newTitle,
        newArtist.isNotEmpty ? newArtist : '未知UP主',
        newCover,
      );
    }

    final sel = _selectedResult ??
        (_previewOffset != 0.0 &&
                widget.currentLines != null &&
                widget.currentLines!.isNotEmpty
            ? LyricsResult(
                source: 'current',
                songTitle: newTitle.isNotEmpty ? newTitle : widget.songTitle,
                artistName: newArtist.isNotEmpty ? newArtist : widget.artistName,
                lines: widget.currentLines!,
              )
            : null);

    if (sel != null) {
      _applyLyricResult(sel, offset: _previewOffset);
    } else if (!hasMetadataEdit) {
      _close();
    }
  }

  // ---------------------------------------------------------------------------
  // Offset bar (calibration controls)
  // ---------------------------------------------------------------------------



  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_inLrcEditor || _previewingResult != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: SafeArea(bottom: false, child: _buildLyricsTab()),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          // Tabs — animation-driven indicator that follows drag in real time
          Row(
            children: [
              Expanded(
                child: Stack(
                  key: _tabRowKey,
                  children: [
                    // Animated indicator driven by TabController.animation
                    AnimatedBuilder(
                      animation: _tabController.animation!,
                      builder: (context, _) {
                        final rowBox = _tabRowKey.currentContext
                            ?.findRenderObject() as RenderBox?;
                        final box0 = _tabKeys[0].currentContext
                            ?.findRenderObject() as RenderBox?;
                        final box1 = _tabKeys[1].currentContext
                            ?.findRenderObject() as RenderBox?;
                        if (rowBox == null || box0 == null || box1 == null) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (context.mounted) (context as Element).markNeedsBuild();
                          });
                          return const SizedBox.shrink();
                        }
                        final off0 = box0.localToGlobal(Offset.zero, ancestor: rowBox);
                        final off1 = box1.localToGlobal(Offset.zero, ancestor: rowBox);
                        final t = _tabController.animation!.value;
                        final left = off0.dx + (off1.dx - off0.dx) * t;
                        final width = box0.size.width +
                            (box1.size.width - box0.size.width) * t;
                        return Positioned(
                          left: left,
                          width: width,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.accent14,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                              border: Border.all(color: AppColors.accent30),
                            ),
                          ),
                        );
                      },
                    ),
                    Row(
                      children: [
                        _tabItem(0, '信息'),
                        const SizedBox(width: 8),
                        _tabItem(1, '歌词'),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 2),
                child: Image.asset('assets/logo.png', height: 36),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildInfoTab(),
                _buildLyricsTab(),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Single stationary 确认 button fixed at the bottom of the dialog
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _saveAll,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('确认',
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
  // Segment tab helper
  // ---------------------------------------------------------------------------

  Widget _tabItem(int index, String label) {
    final active = _tabController.index == index;
    return GestureDetector(
      key: _tabKeys[index],
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.selection();
        _tabController.animateTo(index);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.textPrimary : AppColors.textMuted,
            fontSize: 23,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Info
  // ---------------------------------------------------------------------------

  Widget _buildInfoTab() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 8),
                // Cover art — tap to change, sized to match player page
                LayoutBuilder(
                  builder: (context, constraints) {
                    final availableWidth = constraints.maxWidth;
                    final coverSize = (availableWidth * 0.62).clamp(140.0, 320.0);
                    return Center(
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          GestureDetector(
                            onTap: _pickLocalCoverImage,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.xl),
                              child: CachedCoverImage(
                                url: _coverUrlController.text.trim(),
                                width: coverSize,
                                height: coverSize,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _pickLocalCoverImage,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.backgroundElevated,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.hairlineStrong),
                              ),
                              child: const Icon(Icons.image_outlined,
                                  color: AppColors.textSecondary, size: 18),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                _infoField(_titleController, '歌名'),
                const SizedBox(height: 12),
                _infoField(_artistController, '歌手 / UP主'),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: _autoParseTitleAndArtist,
                    icon: const Icon(Icons.auto_awesome, color: AppColors.accent, size: 18),
                    label: const Text('智能识别歌名与歌手',
                        style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.accent30),
                      backgroundColor: AppColors.accent14,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Future<void> _autoParseTitleAndArtist() async {
    Haptics.selection();
    // Always prefer parsing the original raw video title (which contains all
    // brackets like 【周深】《大鱼》) rather than the already-cleaned song title.
    final textToParse = _titleController.text.trim();
    final raw = (textToParse.contains('《') ||
            textToParse.contains('【') ||
            textToParse.contains('[') ||
            textToParse.contains('-'))
        ? textToParse
        : widget.songTitle;

    // Pass 1: Instant rule-based extraction for immediate UI feedback
    final syncParsed = LyricsEngine.cleanTitle(raw, defaultArtist: widget.artistName);
    if (mounted) {
      setState(() {
        if ((syncParsed['songTitle'] ?? '').isNotEmpty) {
          _titleController.text = syncParsed['songTitle']!;
        }
        final syncArtist = syncParsed['artist'] ?? '';
        if (syncArtist.isNotEmpty && syncArtist != widget.artistName) {
          _artistController.text = syncArtist;
        }
      });
    }

    // Pass 2: Official lyric DB cross-validation to refine song & artist
    final asyncParsed = await LyricsEngine.cleanTitleWithValidation(
      raw,
      defaultArtist: widget.artistName,
    );

    if (mounted) {
      setState(() {
        if ((asyncParsed['songTitle'] ?? '').isNotEmpty) {
          _titleController.text = asyncParsed['songTitle']!;
        }
        final asyncArtist = asyncParsed['artist'] ?? '';
        if (asyncArtist.isNotEmpty && asyncArtist != widget.artistName) {
          _artistController.text = asyncArtist;
        }
      });
    }
  }

  Widget _infoField(TextEditingController ctrl, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          ),
        ),
      ],
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

  /// The result highlighted for the 确认 button, or null when nothing is
  /// selected (e.g. right after a fresh search).
  LyricsResult? get _selectedResult => (_selectedIndex != null &&
          _selectedIndex! >= 0 &&
          _selectedIndex! < _searchResults.length)
      ? _searchResults[_selectedIndex!]
      : null;

  /// Human-readable provider name. For the pinned current row we surface the
  /// lyrics' real origin (read from the cache) rather than a redundant label.
  String _sourceLabel(LyricsResult res) {
    final raw = res.source == 'current'
        ? (_currentSourceLabel ?? 'current')
        : res.source;
    switch (raw) {
      case 'netease':
        return '网易云';
      case 'lrclib':
        return 'LRCLIB';
      case 'user':
        return '自定义';
      case 'current':
        return '当前';
      default:
        return raw.toUpperCase();
    }
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
          // Body → preview / calibration. Editing lives on the preview page's
          // top-right button, so the row carries no edit affordance of its own.
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
                    // Title with source + line count inline on the same line —
                    // they used to take a third line of their own.
                    Row(
                      children: [
                        Expanded(
                          child: Text(
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
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_sourceLabel(res)} · ${res.lines.length} 行',
                          maxLines: 1,
                          style: const TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
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
                  ],
                ),
              ),
            ),
          ),

          // Apply — the only per-row action; calibrate/edit happen in preview.
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

  /// "粘贴 LRC" card at the bottom of the results list.
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
                '粘贴 LRC 文本',
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
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: () => setState(() => _inLrcEditor = false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('取消',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: _confirmLrcEdit,
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
            ),
          ],
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
                autoFollow: false,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // 校准 / 应用 — calibrating: single 完成 button that applies;
        // otherwise: 校准 + 应用.
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: _calibrating
                      ? () => _applyLyricResult(_previewingResult!,
                          offset: _previewOffset)
                      : () => setState(() => _calibrating = true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _calibrating ? AppColors.accent : AppColors.textMuted,
                    side: BorderSide(color: _calibrating ? AppColors.accent30 : Colors.white24),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(_calibrating ? '完成' : '校准',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            if (!_calibrating) ...[
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () =>
                        _applyLyricResult(_previewingResult!, offset: _previewOffset),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('应用',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
