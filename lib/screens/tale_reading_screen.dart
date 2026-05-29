import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/api_service.dart';
import 'fairy_tale_list_screen.dart';
import 'page_selection_screen.dart';

class TalePage {
  final int pageNumber;
  final String imagePath;
  final String text;
  final String? highlightText;
  final String? imageUrl;

  TalePage({
    required this.pageNumber,
    required this.imagePath,
    required this.text,
    this.highlightText,
    this.imageUrl,
  });
}

class TaleBook {
  final FairyTale tale;
  final List<TalePage> pages;

  TaleBook({required this.tale, required this.pages});

  int get totalPages => pages.length;
}

class TaleReadingScreen extends StatefulWidget {
  final FairyTale tale;
  final int initialPage;
  final bool useCurrentVersion;

  const TaleReadingScreen({
    super.key,
    required this.tale,
    this.initialPage = 0,
    this.useCurrentVersion = false,
  });

  @override
  State<TaleReadingScreen> createState() => _TaleReadingScreenState();
}

class _TaleReadingScreenState extends State<TaleReadingScreen>
    with SingleTickerProviderStateMixin {
  TaleBook? _taleBook;
  late int _currentPage;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  final FlutterTts _flutterTts = FlutterTts();
  bool _isPlaying = false;
  bool _autoNextPage = true;
  double _volume = 0.7;
  double _progress = 0.0;
  double _fontSize = 15.0;
  double _speechRate = 0.5;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();

    _initTts();
    _loadBook();
  }

  Future<void> _loadBook() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (widget.tale.storyId == null) {
        throw Exception('storyId가 없습니다.');
      }

      final pageMaps = widget.useCurrentVersion
          ? await ApiService.getCurrentPages(widget.tale.storyId!)
          : await ApiService.getOriginalPages(widget.tale.storyId!);

      final pages = pageMaps
          .where((e) => (e['is_cover'] ?? false) == false)
          .map<TalePage>((e) {
        final pageNumber = e['page_number'] as int;
        final imageUrl = widget.useCurrentVersion
            ? ApiService.storyPageImageUrl(widget.tale.storyId!, pageNumber)
            : ApiService.storyPageOriginalImageUrl(
                widget.tale.storyId!,
                pageNumber,
              );

        return TalePage(
          pageNumber: pageNumber,
          imagePath: '',
          imageUrl: imageUrl,
          text: (e['text_content'] ?? '').toString(),
        );
      }).toList();

      if (!mounted) return;

      setState(() {
        _taleBook = TaleBook(tale: widget.tale, pages: pages);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage('ko-KR');
    await _flutterTts.setSpeechRate(_speechRate);
    await _flutterTts.setVolume(_volume);
    await _flutterTts.setPitch(1.0);

    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isPlaying = false;
        _progress = 1.0;
      });
      if (_autoNextPage &&
          _taleBook != null &&
          _currentPage < _taleBook!.totalPages - 1) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _nextPage();
          _togglePlay();
        });
      }
    });

    _flutterTts.setProgressHandler((String text, int start, int end, String word) {
      if (_taleBook == null) return;
      final fullText = _taleBook!.pages[_currentPage].text;
      if (fullText.isNotEmpty) {
        setState(() {
          _progress = end / fullText.length;
        });
      }
    });
  }

  Future<void> _togglePlay() async {
    if (_taleBook == null) return;

    if (_isPlaying) {
      await _flutterTts.stop();
      setState(() => _isPlaying = false);
    } else {
      setState(() {
        _isPlaying = true;
        _progress = 0.0;
      });
      await _flutterTts.speak(_taleBook!.pages[_currentPage].text);
    }
  }

  void _nextPage() {
    if (_taleBook == null) return;
    if (_currentPage < _taleBook!.totalPages - 1) {
      setState(() {
        _currentPage++;
        _progress = 0.0;
      });
      _animController.forward(from: 0);
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      setState(() {
        _currentPage--;
        _progress = 0.0;
      });
      _animController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F4FF),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF7E57C2)),
        ),
      );
    }

    if (_errorMessage != null || _taleBook == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F4FF),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _errorMessage ?? '동화를 불러오지 못했어요.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      );
    }

    final page = _taleBook!.pages[_currentPage];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Expanded(
                      flex: 6,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: page.imageUrl != null
                            ? Image.network(
                                '${page.imageUrl}?ts=${DateTime.now().millisecondsSinceEpoch}',
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (_, __, ___) => Container(
                                  color: const Color(0xFFEDE7F6),
                                  child: const Center(
                                    child: Icon(Icons.auto_stories, size: 80),
                                  ),
                                ),
                              )
                            : Container(
                                color: const Color(0xFFEDE7F6),
                                child: const Center(
                                  child: Icon(Icons.auto_stories, size: 80),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      flex: 4,
                      child: FadeTransition(
                        opacity: _fadeAnim,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_currentPage + 1} / ${_taleBook!.totalPages} 페이지',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF3D2C8D),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Text(
                                    page.text,
                                    style: TextStyle(
                                      fontSize: _fontSize,
                                      height: 1.8,
                                      color: const Color(0xFF3D2C8D),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              LinearProgressIndicator(
                                value: _progress,
                                minHeight: 6,
                                backgroundColor: const Color(0xFFEDE7F6),
                                valueColor: const AlwaysStoppedAnimation(
                                  Color(0xFF7E57C2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF8F4FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.chevron_left,
                  color: Color(0xFF7E57C2), size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.tale.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3D2C8D),
              ),
            ),
          ),
          IconButton(
            onPressed: _togglePlay,
            icon: Icon(
              _isPlaying ? Icons.stop_circle : Icons.play_circle_fill,
              color: const Color(0xFF7E57C2),
              size: 32,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      color: Colors.white,
      child: Row(
        children: [
          OutlinedButton(
            onPressed: _currentPage > 0 ? _prevPage : null,
            child: const Text('이전'),
          ),
          const Spacer(),
          if (_currentPage == _taleBook!.totalPages - 1 && !widget.useCurrentVersion)
            ElevatedButton.icon(
              onPressed: () {
                _flutterTts.stop();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PageSelectionScreen(
                      tale: widget.tale,
                      taleBook: _taleBook!,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('수정 모드로 가기'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7E57C2),
                foregroundColor: Colors.white,
              ),
            )
          else
            ElevatedButton(
              onPressed:
                  _currentPage < _taleBook!.totalPages - 1 ? _nextPage : null,
              child: const Text('다음'),
            ),
        ],
      ),
    );
  }
}