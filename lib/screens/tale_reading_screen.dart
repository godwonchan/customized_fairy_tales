import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'fairy_tale_list_screen.dart';
import 'page_selection_screen.dart';
import '../data/story_asset_repository.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/crayong_widgets.dart';
import '../widgets/story_image_view.dart';

import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';

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

  final GlobalKey _audioPlayButtonKey = GlobalKey();
  final GlobalKey _editButtonKey = GlobalKey();
  TutorialCoachMark? _tutorialCoachMark;
  List<TargetFocus> _targets = [];

  late AnimationController _pageFlipController;
  late Animation<double> _pageFlipAnim;

  final FlutterTts _flutterTts = FlutterTts();
  bool _isPlaying = false;
  bool _autoNextPage = true;
  double _volume = 0.7;
  double _progress = 0.0;
  double _totalDuration = 0.0;
  double _currentPosition = 0.0;

  static const List<String> _fontLabels = ['작게', '보통', '크게'];
  static const List<double> _fontSizes = [17.0, 20.0, 24.0];
  int _fontIndex = 1;

  static const List<String> _speedLabels = ['느리게', '보통', '빠르게'];
  static const List<double> _speedRates = [0.8, 1.0, 1.2];
  int _speedIndex = 1;
  double get _speechRate => _speedRates[_speedIndex];

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isEnglish = false;
  bool _isTranslating = false;
  bool _isAudioLoading = false;
  final Map<int, String> _translatedPagesCache = {};

  final bool _useOriginalTts = false;

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
    _initAudioPlayer();
  }

  void _initAudioPlayer() {
    _audioPlayer.setVolume(_volume);

    _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _progress = 1.0;
      });

      if (_autoNextPage && _taleBook != null && _currentPageIndex < _taleBook!.totalPages - 1) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _goNext();
          Future.delayed(const Duration(milliseconds: 500), () { _togglePlay(); });
        });
      }
    });

    _audioPlayer.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() {
        _currentPosition = p.inMilliseconds / 1000.0;
        if (_totalDuration > 0) {
          _progress = (_currentPosition / _totalDuration).clamp(0.0, 1.0);
        }
      });
    });

    _audioPlayer.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() {
        _totalDuration = d.inMilliseconds / 1000.0;
      });
    });
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

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndShowTutorial();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _errorMessage = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _startEditingFromOriginal() async {
    if (_taleBook == null) return;
    _audioPlayer.stop();
    setState(() => _isPlaying = false);

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
      _showMessage(kDebugMode ? '원본으로 초기화 실패: $e' : '잠깐 문제가 생겼어요. 다시 눌러 줄래요?', image: CrayongImages.surprised);
    } finally {
      if (mounted) setState(() => _isResettingForEdit = false);
    }
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _audioPlayer.dispose();
    _pageController?.dispose();
    _pageFlipController.dispose();
    super.dispose();
  }

  void _showMessage(String text, {String image = CrayongImages.wink}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Image.asset(image, width: 30, height: 30),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: AppTextStyles.labelLarge(color: Colors.white))),
          ],
        ),
      ),
    );
  }

  void _goPrev() {
    if (_pageController != null && _currentPageIndex > 0) {
      _flutterTts.stop();
      _audioPlayer.stop();
      setState(() => _isPlaying = false);
      _pageFlipController.forward(from: 0).then((_) => _pageFlipController.reverse());
      _pageController!.previousPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    }
  }

  void _goNext() {
    if (_pageController != null && _taleBook != null && _currentPageIndex < _taleBook!.totalPages - 1) {
      _flutterTts.stop();
      _audioPlayer.stop();
      setState(() => _isPlaying = false);
      _pageFlipController.forward(from: 0).then((_) => _pageFlipController.reverse());
      _pageController!.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    }
  }

  void _goToPage(int index) {
    _audioPlayer.stop();
    setState(() { _isPlaying = false; _currentPageIndex = index; });
    if (_isEnglish) _translateCurrentPage();
    _pageFlipController.forward(from: 0).then((_) => _pageFlipController.reverse());
    _pageController?.animateToPage(index, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
  }

  void _onPageChanged(int index) {
    _audioPlayer.stop();
    setState(() {
      _isPlaying = false;
      _currentPageIndex = index;
    });
    if (_isEnglish) _translateCurrentPage();
  }

  Future<void> _togglePlay() async {
    if (_taleBook == null) return;

    if (_isPlaying) {
      await _audioPlayer.stop();
      await _flutterTts.stop();
      setState(() => _isPlaying = false);
      return;
    }

    final page = _taleBook!.pages[_currentPageIndex];

    if (_useOriginalTts) {
      final text = page.highlightText != null ? '${page.text} ${page.highlightText}' : page.text;
      await _flutterTts.setLanguage('ko-KR');
      await _flutterTts.setVolume(_volume);
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.speak(text);
      setState(() => _isPlaying = true);
      return;
    }

    setState(() => _isAudioLoading = true);
    try {
      if (_isEnglish && !_translatedPagesCache.containsKey(page.pageNumber)) {
        final fullKoreanText = page.highlightText != null ? '${page.text} ${page.highlightText}' : page.text;
        final translated = await ApiService.translateToEnglish(fullKoreanText);
        _translatedPagesCache[page.pageNumber] = translated;
      }

      final targetText = _isEnglish
          ? _translatedPagesCache[page.pageNumber]!
          : (page.highlightText != null ? '${page.text} ${page.highlightText}' : page.text);

      final audioBytes = await ApiService.getStoryTTS(
        text: targetText,
        language: _isEnglish ? 'en' : 'ko',
      );

      await _audioPlayer.play(BytesSource(audioBytes));
      await _audioPlayer.setPlaybackRate(_speechRate);

      if (!mounted) return;
      setState(() => _isPlaying = true);
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        kDebugMode ? 'AI 음성 재생 실패: $e' : '크레용 목소리를 못 불러왔어요. 다시 눌러 줄래요?',
        image: CrayongImages.surprised,
      );
    } finally {
      if (mounted) setState(() => _isAudioLoading = false);
    }
  }

  Future<void> _toggleLanguage() async {
    if (_isPlaying) {
      await _audioPlayer.stop();
      setState(() => _isPlaying = false);
    }

    if (_taleBook == null) return;
    final page = _taleBook!.pages[_currentPageIndex];

    if (!_isEnglish && !_translatedPagesCache.containsKey(page.pageNumber)) {
      setState(() => _isTranslating = true);
      try {
        final fullKoreanText = page.highlightText != null
            ? '${page.text} ${page.highlightText}'
            : page.text;

        final translated = await ApiService.translateToEnglish(fullKoreanText);
        if (!mounted) return;
        setState(() {
          _translatedPagesCache[page.pageNumber] = translated;
          _isEnglish = true;
        });
      } catch (e) {
        if (!mounted) return;
        _showMessage(kDebugMode ? '번역 실패: $e' : '영어로 못 바꿨어요. 다시 눌러 줄래요?', image: CrayongImages.surprised);
      } finally {
        if (mounted) setState(() => _isTranslating = false);
      }
    } else {
      setState(() {
        _isEnglish = !_isEnglish;
      });
    }
  }

  Future<void> _translateCurrentPage() async {
    if (_taleBook == null) return;
    final page = _taleBook!.pages[_currentPageIndex];

    if (_translatedPagesCache.containsKey(page.pageNumber)) return;

    setState(() => _isTranslating = true);
    try {
      final fullKoreanText = page.highlightText != null
          ? '${page.text} ${page.highlightText}'
          : page.text;

      final translated = await ApiService.translateToEnglish(fullKoreanText);
      if (!mounted) return;
      setState(() {
        _translatedPagesCache[page.pageNumber] = translated;
      });
    } catch (e) {
      if (!mounted) return;
      _showMessage(kDebugMode ? '번역 실패: $e' : '영어로 못 바꿨어요. 다시 눌러 줄래요?', image: CrayongImages.surprised);
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }

  Future<void> _cycleSpeed() async {
    setState(() => _speedIndex = (_speedIndex + 1) % _speedRates.length);
    await _audioPlayer.setPlaybackRate(_speechRate);
  }

  void _cycleFontSize() {
    setState(() => _fontIndex = (_fontIndex + 1) % _fontSizes.length);
  }

  String _formatTime(double seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toInt().toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _errorMessage != null || _taleBook == null || _pageController == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    RoundIconButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.tale.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.headingLarge(),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const CrayongStatusView(
                        image: CrayongImages.drawing,
                        title: '크레용이 책을 펼치고 있어요',
                        child: SizedBox(
                          width: 160,
                          child: LinearProgressIndicator(minHeight: 6, borderRadius: BorderRadius.all(Radius.circular(3))),
                        ),
                      )
                    : CrayongStatusView(
                        image: CrayongImages.surprised,
                        title: '앗, 동화책을 못 펼쳤어요',
                        message: kDebugMode ? _errorMessage : '잠시 후에 다시 열어 줄래요?',
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() { _isLoading = true; _errorMessage = null; });
                            _loadBook();
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          label: const Text('다시 해볼래요'),
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
    }

    final isLastPage = _currentPageIndex == _taleBook!.totalPages - 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 700;
            return Column(
              children: [
                _buildHeader(),
                Expanded(child: isWide ? _buildWideLayout() : _buildNarrowLayout()),
                _buildBottomArea(isLastPage),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final compact = MediaQuery.of(context).size.width < 640;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        children: [
          RoundIconButton(icon: Icons.arrow_back_rounded, tooltip: '나가기', onTap: () => Navigator.pop(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.tale.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.headingLarge(),
            ),
          ),
          const SizedBox(width: 12),
          _pillButton(
            icon: Icons.translate_rounded,
            label: compact ? (_isEnglish ? 'EN' : '한') : (_isEnglish ? 'English' : '한국어'),
            selected: _isEnglish,
            loading: _isTranslating,
            onTap: _isTranslating ? null : _toggleLanguage,
          ),
          const SizedBox(width: 8),
          _pillButton(
            icon: Icons.text_fields_rounded,
            label: compact ? _fontLabels[_fontIndex] : '글자 ${_fontLabels[_fontIndex]}',
            onTap: _cycleFontSize,
          ),
          const SizedBox(width: 8),
          RoundIconButton(
            icon: Icons.help_outline_rounded,
            tooltip: '도움말 다시보기',
            onTap: () => _checkAndShowTutorial(force: true),
          ),
        ],
      ),
    );
  }

  Widget _pillButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool selected = false,
    bool loading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.secondaryLight : AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: selected ? AppColors.secondary : AppColors.border, width: 2),
            boxShadow: [
              BoxShadow(
                color: selected ? const Color(0xFFBFDDA5) : AppColors.border,
                blurRadius: 0,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.secondaryDark),
                )
              else
                Icon(icon, size: 18, color: selected ? AppColors.secondaryDark : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.headingSmall(
                  color: selected ? const Color(0xFF3E6F2E) : AppColors.textSecondary,
                ).copyWith(fontSize: 16, height: 1.1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWideLayout() {
    return PageView.builder(
      controller: _pageController,
      itemCount: _taleBook!.totalPages,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        final page = _taleBook!.pages[index];
        final isCurrent = index == _currentPageIndex;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: AnimatedBuilder(
            animation: _pageFlipAnim,
            builder: (context, child) => Opacity(opacity: 1.0 - (_pageFlipAnim.value * 0.3), child: child),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 55, child: _buildImageArea(page)),
                const SizedBox(width: 22),
                Expanded(flex: 45, child: _buildTextCard(page, isCurrentPage: isCurrent, scrollable: true)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNarrowLayout() {
    return PageView.builder(
      controller: _pageController,
      itemCount: _taleBook!.totalPages,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        final page = _taleBook!.pages[index];
        return AnimatedBuilder(
          animation: _pageFlipAnim,
          builder: (context, child) => Opacity(opacity: 1.0 - (_pageFlipAnim.value * 0.3), child: child),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                SizedBox(height: 300, child: _buildImageArea(page)),
                const SizedBox(height: 16),
                _buildTextCard(page, isCurrentPage: index == _currentPageIndex, scrollable: false),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFullScreenImage(String imagePath) {
    showDialog(
      context: context,
      barrierColor: const Color(0xE63B2F27),
      builder: (dialogContext) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  clipBehavior: Clip.none,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(dialogContext).size.width * 0.92,
                      maxHeight: MediaQuery.of(dialogContext).size.height * 0.88,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: StoryImageView(imagePath: imagePath, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 24,
                right: 24,
                child: SafeArea(
                  child: RoundIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.pop(dialogContext),
                  ),
                ),
              ),
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '두 손가락으로 크게 보거나 움직일 수 있어요',
                      style: AppTextStyles.labelMedium(color: AppColors.textPrimary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImageArea(TalePage page) {
    final canPrev = _currentPageIndex > 0;
    final canNext = _taleBook != null && _currentPageIndex < _taleBook!.totalPages - 1;

    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.border, width: 2),
              boxShadow: const [BoxShadow(color: AppColors.border, blurRadius: 0, offset: Offset(0, 6))],
            ),
            child: Container(
              decoration: BoxDecoration(
                color: widget.tale.cardColor,
                borderRadius: BorderRadius.circular(22),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: StoryImageView(imagePath: page.imagePath, fit: BoxFit.cover),
              ),
            ),
          ),
        ),
        Positioned(
          top: 20,
          right: 20,
          child: _CircleIconButton(
            icon: Icons.fullscreen_rounded,
            onTap: () => _showFullScreenImage(page.imagePath),
            size: 40,
          ),
        ),
        Positioned(
          left: 20,
          top: 0,
          bottom: 0,
          child: Center(
            child: _CircleIconButton(
              icon: Icons.chevron_left_rounded,
              onTap: _goPrev,
              enabled: canPrev,
              size: 48,
            ),
          ),
        ),
        Positioned(
          right: 20,
          top: 0,
          bottom: 0,
          child: Center(
            child: _CircleIconButton(
              icon: Icons.chevron_right_rounded,
              onTap: _goNext,
              enabled: canNext,
              size: 48,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextCard(TalePage page, {required bool isCurrentPage, required bool scrollable}) {
    final storyText = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isEnglish
              ? (_translatedPagesCache[page.pageNumber] ?? (_isTranslating ? '크레용이 영어로 바꾸고 있어요...' : page.text))
              : page.text,
          style: AppTextStyles.storyBody(fontSize: _fontSizes[_fontIndex]),
        ),
        if (!_isEnglish && page.highlightText != null && page.highlightText!.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _isPlaying ? Icons.volume_up_rounded : Icons.format_quote_rounded,
                  size: 20,
                  color: AppColors.primaryText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '"${page.highlightText!}"',
                    style: AppTextStyles.storyBody(
                      fontSize: _fontSizes[_fontIndex],
                      color: const Color(0xFF6B4A1E),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      decoration: AppDecorations.card(radius: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${page.pageNumber} / ${_taleBook!.totalPages}',
              style: AppTextStyles.labelMedium(color: AppColors.primaryText),
            ),
          ),
          const SizedBox(height: 14),
          if (scrollable)
            Expanded(child: SingleChildScrollView(child: storyText))
          else
            storyText,
          const SizedBox(height: 16),
          _buildAudioPlayer(isCurrentPage: isCurrentPage),
        ],
      ),
    );
  }

  Widget _buildAudioPlayer({bool isCurrentPage = false}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.secondaryLight,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _CircleIconButton(icon: Icons.skip_previous_rounded, onTap: _goPrev, size: 40),
              const SizedBox(width: 10),
              GestureDetector(
                key: isCurrentPage ? _audioPlayButtonKey : null,
                onTap: _isAudioLoading ? null : _togglePlay,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: AppDecorations.primaryButton(radius: 32, depth: 4),
                    child: _isAudioLoading
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.onPrimary),
                          )
                        : Icon(
                            _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: AppColors.onPrimary,
                            size: 36,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _CircleIconButton(icon: Icons.skip_next_rounded, onTap: _goNext, size: 40),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isAudioLoading
                          ? '크레용이 목소리를 준비해요'
                          : (_isPlaying ? '크레용이 읽고 있어요' : '크레용이 읽어 줄게요'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.headingSmall(),
                    ),
                    Row(
                      children: [
                        Text(_formatTime(_currentPosition), style: AppTextStyles.caption(color: const Color(0xFF3E6F2E))),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: AppColors.secondaryDark,
                              inactiveTrackColor: AppColors.surface,
                              thumbColor: AppColors.secondaryDark,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                              trackHeight: 6,
                              overlayShape: SliderComponentShape.noOverlay,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Slider(
                                value: _progress.clamp(0.0, 1.0),
                                min: 0,
                                max: 1,
                                onChanged: (v) {
                                  final targetSeconds = v * _totalDuration;
                                  setState(() {
                                    _progress = v;
                                    _currentPosition = targetSeconds;
                                  });
                                  _audioPlayer.seek(Duration(milliseconds: (targetSeconds * 1000).toInt()));
                                },
                              ),
                            ),
                          ),
                        ),
                        Text(_formatTime(_totalDuration), style: AppTextStyles.caption(color: const Color(0xFF3E6F2E))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.volume_up_rounded, size: 18, color: AppColors.secondaryDark),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: AppColors.secondaryDark,
                    inactiveTrackColor: AppColors.surface,
                    thumbColor: AppColors.secondaryDark,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    trackHeight: 4,
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Slider(
                      value: _volume,
                      min: 0,
                      max: 1,
                      onChanged: (v) {
                        setState(() => _volume = v);
                        _audioPlayer.setVolume(v);
                      },
                    ),
                  ),
                ),
              ),
              _smallChip(
                icon: Icons.speed_rounded,
                label: _speedLabels[_speedIndex],
                onTap: _cycleSpeed,
              ),
              const SizedBox(width: 8),
              _smallChip(
                icon: _autoNextPage ? Icons.auto_stories_rounded : Icons.pan_tool_alt_rounded,
                label: _autoNextPage ? '자동 넘김' : '직접 넘김',
                onTap: () => setState(() => _autoNextPage = !_autoNextPage),
                selected: _autoNextPage,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _smallChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.secondaryDark : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: selected ? Colors.white : AppColors.secondaryDark),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppTextStyles.labelSmall(color: selected ? Colors.white : const Color(0xFF3E6F2E)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomArea(bool isLastPage) {
    final showMessage = MediaQuery.of(context).size.width >= 900;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 2)),
      ),
      child: Row(
        children: [
          Image.asset(isLastPage ? CrayongImages.celebrate : CrayongImages.wink, height: 48),
          const SizedBox(width: 10),
          if (showMessage) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 230),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLastPage ? '이야기를 다 읽었어요!' : '계속 읽어 볼까요?',
                    style: AppTextStyles.headingSmall(),
                  ),
                  Text(
                    isLastPage ? '이제 바꾸고 싶은 장면을 골라 봐요.' : '아래에서 페이지를 바로 고를 수도 있어요.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(child: _buildThumbnails()),
          const SizedBox(width: 12),
          _EditButton(
            key: _editButtonKey,
            loading: _isResettingForEdit,
            highlight: isLastPage,
            onTap: _isResettingForEdit ? null : _startEditingFromOriginal,
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnails() {
    return SizedBox(
      height: 66,
      child: Center(
        child: ListView.separated(
          shrinkWrap: true,
          scrollDirection: Axis.horizontal,
          itemCount: _taleBook!.totalPages,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final isSelected = _currentPageIndex == index;
            final page = _taleBook!.pages[index];
            return GestureDetector(
              onTap: () => _goToPage(index),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 56,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.border,
                          width: isSelected ? 3 : 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: StoryImageView(imagePath: page.imagePath, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${index + 1}',
                      style: AppTextStyles.labelSmall(
                        color: isSelected ? AppColors.textPrimary : AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _checkAndShowTutorial({bool force = false}) async {
    if (!mounted || _isLoading || _taleBook == null) return;

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final bool isTutorialSeen = prefs.getBool('is_reading_tutorial_seen') ?? false;

      if (!isTutorialSeen || force) {
        _initTutorialTargets();
        _tutorialCoachMark = TutorialCoachMark(
          targets: _targets,
          colorShadow: const Color(0xFF3B2F27),
          textSkip: "건너뛰기",
          paddingFocus: 8,
          opacityShadow: 0.75,
          onFinish: () async {
            await prefs.setBool('is_reading_tutorial_seen', true);
          },
          onSkip: () {
            prefs.setBool('is_reading_tutorial_seen', true);
            return true;
          },
        )..show(context: context);
      }
    } catch (e) {
      debugPrint('튜토리얼 실행 예외 무시: $e');
    }
  }

  void _initTutorialTargets() {
    _targets = [
      TargetFocus(
        identify: "audioPlayButtonTarget",
        keyTarget: _audioPlayButtonKey,
        shape: ShapeLightFocus.Circle,
        paddingFocus: 6,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return _buildTutorialBubble(
                context: context,
                image: CrayongImages.wink,
                title: "1단계: 크레용 목소리로 듣기",
                description: "이 노란 버튼을 누르면 크레용이\n실감 나는 목소리로 동화를 읽어 줘요!",
                onNext: () => controller.next(),
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "editButtonTarget",
        keyTarget: _editButtonKey,
        shape: ShapeLightFocus.RRect,
        radius: 20,
        paddingFocus: 6,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return _buildTutorialBubble(
                context: context,
                image: CrayongImages.painter,
                title: "2단계: 나만의 이야기 만들기",
                description: "이야기나 그림을 내 마음대로 바꾸고 싶다면\n'장면 바꾸기'를 눌러서 크레용이랑 바꿔 봐요!",
                isLast: true,
                onNext: () => controller.next(),
              );
            },
          ),
        ],
      ),
    ];
  }

  Widget _buildTutorialBubble({
    required BuildContext context,
    required String image,
    required String title,
    required String description,
    required VoidCallback onNext,
    bool isLast = false,
  }) {
    final screenSize = MediaQuery.of(context).size;
    final crayongHeight = (screenSize.height * 0.32).clamp(170.0, 300.0);

    return Material(
      color: Colors.transparent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(image, height: crayongHeight, fit: BoxFit.contain),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                decoration: AppDecorations.sticker(
                  color: AppColors.secondaryDark,
                  shadowColor: const Color(0xFF457A36),
                  radius: 20,
                  depth: 3,
                ),
                child: Text('크레용', style: AppTextStyles.labelLarge(color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(width: 14),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: (screenSize.width * 0.45).clamp(260.0, 380.0)),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.headingMedium()),
                  const SizedBox(height: 8),
                  Text(description, style: AppTextStyles.bodyMedium(color: AppColors.textPrimary)),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: onNext,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      ),
                      child: Text(isLast ? "알겠어요!" : "다음으로"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  final double size;

  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.enabled = true,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: enabled ? 1 : 0.4,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border, width: 2),
              boxShadow: const [BoxShadow(color: AppColors.border, blurRadius: 0, offset: Offset(0, 3))],
            ),
            child: Icon(icon, size: size * 0.55, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _EditButton extends StatefulWidget {
  final VoidCallback? onTap;
  final bool loading;
  final bool highlight;

  const _EditButton({super.key, required this.onTap, required this.loading, required this.highlight});

  @override
  State<_EditButton> createState() => _EditButtonState();
}

class _EditButtonState extends State<_EditButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const depth = 4.0;
    final color = widget.highlight ? AppColors.primary : AppColors.secondaryDark;
    final shadow = widget.highlight ? AppColors.primaryDark : const Color(0xFF457A36);
    final textColor = widget.highlight ? AppColors.onPrimary : Colors.white;

    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _pressed = false),
      onTapCancel: widget.onTap == null ? null : () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          transform: Matrix4.translationValues(0, _pressed ? depth : 0, 0),
          decoration: AppDecorations.sticker(
            color: color,
            shadowColor: shadow,
            radius: 20,
            depth: _pressed ? 0 : depth,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.loading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: textColor),
                )
              else
                Icon(Icons.brush_rounded, size: 20, color: textColor),
              const SizedBox(width: 8),
              Text('장면 바꾸기', style: AppTextStyles.button(color: textColor)),
            ],
          ),
        ),
      ),
    );
  }
}