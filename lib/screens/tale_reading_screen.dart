import 'package:flutter/material.dart';
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
      highlightText:
          clearHighlightText ? null : (highlightText ?? this.highlightText),
    );
  }
}

class TaleBook {
  final FairyTale tale;
  final List<TalePage> pages;

  TaleBook({
    required this.tale,
    required this.pages,
  });

  int get totalPages => pages.length;

  TaleBook copyWith({
    FairyTale? tale,
    List<TalePage>? pages,
  }) {
    return TaleBook(
      tale: tale ?? this.tale,
      pages: pages ?? this.pages,
    );
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

class _TaleReadingScreenState extends State<TaleReadingScreen> {
  PageController? _pageController;
  TaleBook? _taleBook;
  int _currentPageIndex = 0;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isResettingForEdit = false;

  bool get _shouldLoadServerPages {
    return widget.overrideTaleBook == null &&
        widget.tale.storyId != null &&
        (widget.useCurrentVersion || widget.tale.isUserStory);
  }

  @override
  void initState() {
    super.initState();
    _loadBook();
  }

  Future<TaleBook> _loadBookFromServer() async {
    final storyId = widget.tale.storyId!;
    final rawPages = await ApiService.getCurrentPages(storyId);

    final pages = rawPages.map((raw) {
      final item = raw as Map<String, dynamic>;

      final pageNumber =
          item['page_number'] as int? ?? item['pageNumber'] as int? ?? 1;

      final text =
          (item['text_content'] ?? item['text'] ?? item['content'] ?? '')
              .toString();

      final highlightText = item['highlight_text']?.toString();

      final imagePath = (item['image_url']?.toString().isNotEmpty ?? false)
          ? item['image_url'].toString()
          : ApiService.storyPageImageUrl(storyId, pageNumber);

      return TalePage(
        pageNumber: pageNumber,
        text: text,
        imagePath: imagePath,
        highlightText: highlightText,
      );
    }).toList()
      ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

    return TaleBook(
      tale: widget.tale,
      pages: pages,
    );
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
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _startEditingFromOriginal() async {
    if (_taleBook == null) return;

    if (widget.tale.storyId == null || !widget.tale.isUserStory) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PageSelectionScreen(
            tale: widget.tale,
            taleBook: _taleBook!,
          ),
        ),
      );
      return;
    }

    setState(() {
      _isResettingForEdit = true;
    });

    try {
      await ApiService.resetToOriginal(storyId: widget.tale.storyId!);
      final resetBook = await _loadBookFromServer();

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PageSelectionScreen(
            tale: widget.tale,
            taleBook: resetBook,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('원본으로 초기화 실패: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResettingForEdit = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  void _goPrev() {
    if (_pageController != null && _currentPageIndex > 0) {
      _pageController!.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _goNext() {
    if (_pageController != null &&
        _taleBook != null &&
        _currentPageIndex < _taleBook!.totalPages - 1) {
      _pageController!.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F4FF),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF3D2C8D),
          elevation: 0,
          title: Text(widget.tale.title),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null || _taleBook == null || _pageController == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F4FF),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF3D2C8D),
          elevation: 0,
          title: Text(widget.tale.title),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _errorMessage ?? '동화를 불러오지 못했어요.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final isLastPage = _currentPageIndex == _taleBook!.totalPages - 1;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF3D2C8D),
        elevation: 0,
        title: Text(widget.tale.title),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _taleBook!.totalPages,
                onPageChanged: (index) {
                  setState(() {
                    _currentPageIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  final item = _taleBook!.pages[index];

                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: widget.tale.cardColor,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: StoryImageView(
                                imagePath: item.imagePath,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item.pageNumber}페이지',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF7E57C2),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                item.text,
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.7,
                                  color: Color(0xFF3D2C8D),
                                ),
                              ),
                              if (item.highlightText != null &&
                                  item.highlightText!.trim().isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  '"${item.highlightText!}"',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF7E57C2),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (isLastPage)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isResettingForEdit ? null : _startEditingFromOriginal,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7E57C2),
                      foregroundColor: Colors.white,
                    ),
                    child: _isResettingForEdit
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('동화 수정하기'),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _currentPageIndex > 0 ? _goPrev : null,
                      child: const Text('이전'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_currentPageIndex + 1} / ${_taleBook!.totalPages}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3D2C8D),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          _currentPageIndex < _taleBook!.totalPages - 1 ? _goNext : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7E57C2),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('다음'),
                    ),
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