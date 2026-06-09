import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'fairy_tale_list_screen.dart';
import 'page_selection_screen.dart';
import '../data/story_asset_repository.dart';
import '../services/api_service.dart';
import '../widgets/story_image_view.dart';

class TalePage {
  final int pageNumber;
  final String text;
  final String imagePath;
  final String? highlightText;

  TalePage({
    required this.pageNumber,
    required this.text,
    required this.imagePath,
    this.highlightText,
  });

  TalePage copyWith({
    int? pageNumber,
    String? text,
    String? imagePath,
    String? highlightText,
    bool clearHighlightText = false,
  }) {
    return TalePage(
      pageNumber: pageNumber ?? this.pageNumber,
      text: text ?? this.text,
      imagePath: imagePath ?? this.imagePath,
      highlightText: clearHighlightText ? null : (highlightText ?? this.highlightText),
    );
  }
}

class TaleBook {
  final FairyTale tale;
  final List<TalePage> pages;

  TaleBook({required this.tale, required this.pages});

  int get totalPages => pages.length;

  TaleBook copyWith({FairyTale? tale, List<TalePage>? pages}) {
    return TaleBook(tale: tale ?? this.tale, pages: pages ?? this.pages);
  }
}

class TaleReadingScreen extends StatefulWidget {
  final FairyTale tale;
  final int initialPage;
  final bool useCurrentVersion;
  final TaleBook? overrideTaleBook;

  const TaleReadingScreen({
    super.key,
    required this.tale,
    this.initialPage = 0,
    this.useCurrentVersion = false,
    this.overrideTaleBook,
  });

  @override
  State<TaleReadingScreen> createState() => _TaleReadingScreenState();
}

class _TaleReadingScreenState extends State<TaleReadingScreen>
    with TickerProviderStateMixin {
  PageController? _pageController;
  TaleBook? _taleBook;
  int _currentPageIndex = 0;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isResettingForEdit = false;

  late AnimationController _pageFlipController;
  late Animation<double> _pageFlipAnim;

  final FlutterTts _flutterTts = FlutterTts();
  bool _isPlaying = false;
  bool _autoNextPage = true;
  double _volume = 0.7;
  double _progress = 0.0;
  double _totalDuration = 0.0;
  double _currentPosition = 0.0;
  double _fontSize = 15.0;
  double _speechRate = 0.5;

  bool get _shouldLoadServerPages {
    return widget.overrideTaleBook == null &&
        widget.tale.storyId != null &&
        (widget.useCurrentVersion || widget.tale.isUserStory);
  }

  @override
  void initState() {
    super.initState();
    _pageFlipController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _pageFlipAnim = CurvedAnimation(parent: _pageFlipController, curve: Curves.easeInOut);
    _loadBook();
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage('ko-KR');
    await _flutterTts.setSpeechRate(_speechRate);
    await _flutterTts.setVolume(_volume);
    await _flutterTts.setPitch(1.0);

    _flutterTts.setCompletionHandler(() {
      setState(() { _isPlaying = false; _progress = 1.0; });
      if (_autoNextPage && _taleBook != null && _currentPageIndex < _taleBook!.totalPages - 1) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _goNext();
          Future.delayed(const Duration(milliseconds: 500), () { _togglePlay(); });
        });
      }
    });

    _flutterTts.setProgressHandler((String text, int startOffset, int endOffset, String word) {
      if (_totalDuration > 0) {
        setState(() {
          _progress = endOffset / text.length;
          _currentPosition = _progress * _totalDuration;
        });
      }
    });

    _flutterTts.setErrorHandler((msg) => setState(() => _isPlaying = false));
  }

  Future<TaleBook> _loadBookFromServer() async {
    final storyId = widget.tale.storyId!;
    final rawPages = await ApiService.getCurrentPages(storyId);
    final pages = rawPages.map((raw) {
      final item = raw as Map<String, dynamic>;
      final pageNumber = item['page_number'] as int? ?? item['pageNumber'] as int? ?? 1;
      final text = (item['text_content'] ?? item['text'] ?? item['content'] ?? '').toString();
      final highlightText = item['highlight_text']?.toString();
      final imagePath = (item['image_url']?.toString().isNotEmpty ?? false)
          ? item['image_url'].toString()
          : ApiService.storyPageImageUrl(storyId, pageNumber);
      return TalePage(pageNumber: pageNumber, text: text, imagePath: imagePath, highlightText: highlightText);
    }).toList()..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    return TaleBook(tale: widget.tale, pages: pages);
  }

  Future<void> _loadBook() async {
    try {
      final book = widget.overrideTaleBook != null
          ? widget.overrideTaleBook!
          : _shouldLoadServerPages
              ? await _loadBookFromServer()
              : await StoryAssetRepository.loadTaleBook(widget.tale);
      final initial = widget.initialPage.clamp(0, book.totalPages - 1);
      if (!mounted) return;
      setState(() {
        _taleBook = book;
        _currentPageIndex = initial;
        _pageController = PageController(initialPage: initial);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _errorMessage = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _startEditingFromOriginal() async {
    if (_taleBook == null) return;
    _flutterTts.stop();
    if (widget.tale.storyId == null || !widget.tale.isUserStory) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PageSelectionScreen(tale: widget.tale, taleBook: _taleBook!)));
      return;
    }
    setState(() => _isResettingForEdit = true);
    try {
      await ApiService.resetToOriginal(storyId: widget.tale.storyId!);
      final resetBook = await _loadBookFromServer();
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => PageSelectionScreen(tale: widget.tale, taleBook: resetBook)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('원본으로 초기화 실패: $e')));
    } finally {
      if (mounted) setState(() => _isResettingForEdit = false);
    }
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _pageController?.dispose();
    _pageFlipController.dispose();
    super.dispose();
  }

  void _goPrev() {
    if (_pageController != null && _currentPageIndex > 0) {
      _flutterTts.stop();
      setState(() => _isPlaying = false);
      _pageFlipController.forward(from: 0).then((_) => _pageFlipController.reverse());
      _pageController!.previousPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    }
  }

  void _goNext() {
    if (_pageController != null && _taleBook != null && _currentPageIndex < _taleBook!.totalPages - 1) {
      _flutterTts.stop();
      setState(() => _isPlaying = false);
      _pageFlipController.forward(from: 0).then((_) => _pageFlipController.reverse());
      _pageController!.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    }
  }

  Future<void> _togglePlay() async {
    if (_taleBook == null) return;
    if (_isPlaying) {
      await _flutterTts.pause();
      setState(() => _isPlaying = false);
    } else {
      final page = _taleBook!.pages[_currentPageIndex];
      final text = page.highlightText != null ? '${page.text} ${page.highlightText}' : page.text;
      _totalDuration = (text.length / 5) / _speechRate;
      await _flutterTts.setVolume(_volume);
      await _flutterTts.setSpeechRate(_speechRate);
      await _flutterTts.speak(text);
      setState(() => _isPlaying = true);
    }
  }

  String _formatTime(double seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toInt().toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F4FF),
        appBar: AppBar(backgroundColor: Colors.white, foregroundColor: const Color(0xFF3D2C8D), elevation: 0, title: Text(widget.tale.title)),
        body: const Center(child: CircularProgressIndicator(color: Color(0xFF7E57C2))),
      );
    }
    if (_errorMessage != null || _taleBook == null || _pageController == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F4FF),
        appBar: AppBar(backgroundColor: Colors.white, foregroundColor: const Color(0xFF3D2C8D), elevation: 0, title: Text(widget.tale.title)),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_errorMessage ?? '동화를 불러오지 못했어요.', textAlign: TextAlign.center))),
      );
    }
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final isLastPage = _currentPageIndex == _taleBook!.totalPages - 1;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, isTablet),
            Expanded(child: isTablet ? _buildTabletLayout() : _buildPhoneLayout()),
            _buildThumbnailBar(isTablet),
            _buildBottomBar(isTablet, isLastPage),
          ],
        ),
      ),
    );
  }

  // ✅ v1: 헤더 배경 그라디언트 적용
  Widget _buildHeader(BuildContext context, bool isTablet) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFF5F0FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _isPlaying ? const Color(0xFF7E57C2) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF7E57C2), width: 1.5),
                boxShadow: [BoxShadow(color: const Color(0xFF7E57C2).withOpacity(0.15), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Row(
                children: [
                  Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                      size: 20, color: _isPlaying ? Colors.white : const Color(0xFF7E57C2)),
                  const SizedBox(width: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_isPlaying ? '일시정지' : '읽어주기',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                              color: _isPlaying ? Colors.white : const Color(0xFF7E57C2))),
                      Text(_isPlaying ? '탭하면 멈춰요' : 'AI가 읽어드려요',
                          style: TextStyle(fontSize: 9, color: _isPlaying ? Colors.white.withOpacity(0.8) : Colors.grey[400])),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _headerBtn(Icons.list_rounded, '목차', () {}),
          const SizedBox(width: 8),
          _headerBtn(Icons.text_fields_rounded, '가 글자 크기', _showFontSizeDialog),
        ],
      ),
    );
  }

  Widget _headerBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F4FF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE0D7F5)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF7E57C2)),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF7E57C2), fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildTabletLayout() {
    return PageView.builder(
      controller: _pageController,
      itemCount: _taleBook!.totalPages,
      onPageChanged: (index) => setState(() => _currentPageIndex = index),
      itemBuilder: (context, index) {
        final page = _taleBook!.pages[index];
        return Padding(padding: const EdgeInsets.all(16), child: _buildTabletPageContent(page));
      },
    );
  }

  Widget _buildTabletPageContent(TalePage page) {
    return AnimatedBuilder(
      animation: _pageFlipAnim,
      builder: (context, child) => Opacity(opacity: 1.0 - (_pageFlipAnim.value * 0.3), child: child),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 55, child: _buildImageArea(page, isTablet: true)),
          const SizedBox(width: 24),
          Expanded(flex: 45, child: _buildTextAndAudioArea(page, isTablet: true)),
        ],
      ),
    );
  }

  Widget _buildPhoneLayout() {
    return PageView.builder(
      controller: _pageController,
      itemCount: _taleBook!.totalPages,
      onPageChanged: (index) => setState(() => _currentPageIndex = index),
      itemBuilder: (context, index) {
        final page = _taleBook!.pages[index];
        return AnimatedBuilder(
          animation: _pageFlipAnim,
          builder: (context, child) => Opacity(opacity: 1.0 - (_pageFlipAnim.value * 0.3), child: child),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: [_buildImageArea(page, isTablet: false), const SizedBox(height: 16), _buildTextAndAudioArea(page, isTablet: false)]),
          ),
        );
      },
    );
  }

  Widget _buildImageArea(TalePage page, {required bool isTablet}) {
    return Stack(
      children: [
        Container(
          height: isTablet ? double.infinity : 300,
          decoration: BoxDecoration(
            color: widget.tale.cardColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: const Color(0xFF7E57C2).withOpacity(0.2), blurRadius: 24, offset: const Offset(0, 10)),
              BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 4)),
            ],
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(20), child: StoryImageView(imagePath: page.imagePath, fit: BoxFit.cover)),
        ),
        Positioned(top: 12, right: 12,
          child: Container(width: 36, height: 36,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.85), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.fullscreen, size: 20, color: Color(0xFF7E57C2)))),
        Positioned(left: 8, top: 0, bottom: 0,
          child: Center(child: GestureDetector(onTap: _goPrev,
            child: Container(width: 40, height: 40,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.85), shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)]),
              child: Icon(Icons.chevron_left, color: _currentPageIndex > 0 ? const Color(0xFF7E57C2) : Colors.grey[300]))))),
        Positioned(right: 8, top: 0, bottom: 0,
          child: Center(child: GestureDetector(onTap: _goNext,
            child: Container(width: 40, height: 40,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.85), shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)]),
              child: Icon(Icons.chevron_right, color: _taleBook != null && _currentPageIndex < _taleBook!.totalPages - 1 ? const Color(0xFF7E57C2) : Colors.grey[300]))))),
      ],
    );
  }

  Widget _buildTextAndAudioArea(TalePage page, {required bool isTablet}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: const Color(0xFFEDE7F6), borderRadius: BorderRadius.circular(20)),
          child: Text('${page.pageNumber} / ${_taleBook!.totalPages}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF7E57C2), fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 14),
        Text(widget.tale.title,
            style: TextStyle(fontSize: isTablet ? 28 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF3D2C8D))),
        const SizedBox(height: 14),
        Text(page.text, style: TextStyle(fontSize: _fontSize, color: const Color(0xFF3D2C8D), height: 1.8)),
        if (page.highlightText != null && page.highlightText!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFE082), width: 1.5),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_isPlaying ? Icons.volume_up : Icons.volume_up_outlined, size: 16, color: const Color(0xFFFF8F00)),
                const SizedBox(width: 8),
                Expanded(child: Text('"${page.highlightText!}"',
                    style: TextStyle(fontSize: _fontSize, color: const Color(0xFF5D4037), fontStyle: FontStyle.italic, height: 1.6))),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        _buildAudioPlayer(isTablet),
      ],
    );
  }

  Widget _buildAudioPlayer(bool isTablet) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.headphones_rounded, size: 16, color: Color(0xFF7E57C2)),
              const SizedBox(width: 6),
              const Text('이야기 들려주기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3D2C8D))),
              const Spacer(),
              Text('자동 넘김:', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => setState(() => _autoNextPage = !_autoNextPage),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44, height: 24,
                  decoration: BoxDecoration(
                    color: _autoNextPage ? const Color(0xFF7E57C2) : Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    alignment: _autoNextPage ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(margin: const EdgeInsets.all(2), width: 20, height: 20,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.volume_up, size: 18, color: Colors.grey[500]),
              Expanded(flex: 3,
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: const Color(0xFF7E57C2), inactiveTrackColor: Colors.grey[200],
                    thumbColor: const Color(0xFF7E57C2), thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    trackHeight: 3, overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(value: _volume, min: 0, max: 1,
                    onChanged: (v) { setState(() => _volume = v); _flutterTts.setVolume(v); }),
                )),
              SizedBox(width: 32, child: Text('${(_volume * 100).toInt()}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]), textAlign: TextAlign.center)),
              const Spacer(),
              _audioBtn(Icons.skip_previous_rounded, _goPrev),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _togglePlay,
                child: Container(width: 44, height: 44,
                  decoration: const BoxDecoration(color: Color(0xFF7E57C2), shape: BoxShape.circle),
                  child: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 26)),
              ),
              const SizedBox(width: 8),
              _audioBtn(Icons.skip_next_rounded, _goNext),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _showSpeedDialog,
                child: Container(width: 36, height: 36,
                  decoration: BoxDecoration(color: const Color(0xFFF8F4FF), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.settings_rounded, size: 20, color: Color(0xFF7E57C2))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(_formatTime(_currentPosition), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: const Color(0xFF7E57C2), inactiveTrackColor: Colors.grey[200],
                    thumbColor: const Color(0xFF7E57C2), thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    trackHeight: 3, overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(value: _progress.clamp(0.0, 1.0), min: 0, max: 1,
                    onChanged: (v) => setState(() { _progress = v; _currentPosition = v * _totalDuration; })),
                ),
              ),
              Text(_formatTime(_totalDuration), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _audioBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(width: 36, height: 36,
        decoration: BoxDecoration(color: const Color(0xFFF8F4FF), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 20, color: const Color(0xFF7E57C2))),
    );
  }

  Widget _buildThumbnailBar(bool isTablet) {
    if (_taleBook == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4FF),
        border: Border(top: BorderSide(color: const Color(0xFFEDE7F6), width: 1.5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.grid_view_rounded, size: 16, color: Color(0xFF7E57C2)),
            const SizedBox(width: 6),
            const Text('전체 페이지', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3D2C8D))),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 72,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_taleBook!.totalPages, (index) {
                final isSelected = _currentPageIndex == index;
                final page = _taleBook!.pages[index];
                return GestureDetector(
                  onTap: () {
                    _flutterTts.stop();
                    setState(() { _isPlaying = false; _currentPageIndex = index; });
                    _pageFlipController.forward(from: 0).then((_) => _pageFlipController.reverse());
                    _pageController?.animateToPage(index, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(children: [
                      Container(
                        width: 50, height: 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isSelected ? const Color(0xFF7E57C2) : Colors.transparent, width: 2.5),
                          boxShadow: isSelected ? [BoxShadow(color: const Color(0xFF7E57C2).withOpacity(0.3), blurRadius: 8)] : [],
                        ),
                        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: StoryImageView(imagePath: page.imagePath, fit: BoxFit.cover)),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(color: isSelected ? const Color(0xFF7E57C2) : Colors.transparent, shape: BoxShape.circle),
                        child: Center(child: Text('${index + 1}',
                            style: TextStyle(fontSize: 10, color: isSelected ? Colors.white : Colors.grey[400], fontWeight: FontWeight.w600))),
                      ),
                    ]),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(bool isTablet, bool isLastPage) {
    return Container(
      padding: EdgeInsets.fromLTRB(isTablet ? 24 : 16, 12, isTablet ? 24 : 16, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFF5F0FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          Container(width: 40, height: 40,
            decoration: BoxDecoration(color: const Color(0xFFEDE7F6), borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.emoji_nature, size: 24, color: Color(0xFF7E57C2))),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isLastPage ? '이야기를 다 읽었나요?' : '${_currentPageIndex + 1} / ${_taleBook!.totalPages} 페이지',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3D2C8D))),
              Text(isLastPage ? '이제 내가 바꾸고 싶은 장면을 선택해볼까요?' : '계속 읽어볼까요?',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _isResettingForEdit ? null : _startEditingFromOriginal,
            icon: _isResettingForEdit
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.edit, size: 16),
            label: const Text('수정 모드로 가기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7E57C2), foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  void _showFontSizeDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('글자 크기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF3D2C8D))),
              const SizedBox(height: 16),
              ...[
                {'label': '작게', 'size': 13.0},
                {'label': '중간', 'size': 15.0},
                {'label': '크게', 'size': 18.0},
              ].map((item) {
                final isSelected = _fontSize == item['size'];
                return GestureDetector(
                  onTap: () { setState(() => _fontSize = item['size'] as double); Navigator.pop(context); },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFEDE7F6) : const Color(0xFFF8F4FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isSelected ? const Color(0xFF7E57C2) : Colors.transparent),
                    ),
                    child: Row(children: [
                      Text(item['label'] as String,
                          style: TextStyle(fontSize: 14, color: isSelected ? const Color(0xFF7E57C2) : const Color(0xFF3D2C8D),
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400)),
                      const Spacer(),
                      if (isSelected) const Icon(Icons.check, size: 18, color: Color(0xFF7E57C2)),
                    ]),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showSpeedDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('읽기 속도', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF3D2C8D))),
              const SizedBox(height: 16),
              ...[
                {'label': '느리게', 'rate': 0.3},
                {'label': '보통', 'rate': 0.5},
                {'label': '빠르게', 'rate': 0.7},
              ].map((item) {
                final isSelected = _speechRate == item['rate'];
                return GestureDetector(
                  onTap: () {
                    setState(() => _speechRate = item['rate'] as double);
                    _flutterTts.setSpeechRate(item['rate'] as double);
                    Navigator.pop(context);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFEDE7F6) : const Color(0xFFF8F4FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isSelected ? const Color(0xFF7E57C2) : Colors.transparent),
                    ),
                    child: Row(children: [
                      Text(item['label'] as String,
                          style: TextStyle(fontSize: 14, color: isSelected ? const Color(0xFF7E57C2) : const Color(0xFF3D2C8D),
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400)),
                      const Spacer(),
                      if (isSelected) const Icon(Icons.check, size: 18, color: Color(0xFF7E57C2)),
                    ]),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}