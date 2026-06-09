import 'package:flutter/material.dart';
import 'fairy_tale_list_screen.dart';
import 'my_stories_screen.dart';
import '../services/api_service.dart';
import '../widgets/story_image_view.dart';
import 'tale_reading_screen.dart';

class AIResultScreen extends StatefulWidget {
  final FairyTale tale;
  final TaleBook taleBook;
  final int editedPageIndex;
  final List<String>? revisedPages;
  final List<String>? generatedImagePaths;
  final String? confirmedRequest;

  const AIResultScreen({
    super.key,
    required this.tale,
    required this.taleBook,
    required this.editedPageIndex,
    this.revisedPages,
    this.generatedImagePaths,
    this.confirmedRequest,
  });

  @override
  State<AIResultScreen> createState() => _AIResultScreenState();
}

class _AIResultScreenState extends State<AIResultScreen>
    with SingleTickerProviderStateMixin {
  late int _currentPage;
  late PageController _pageController;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late TaleBook _updatedTaleBook;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    _currentPage = 0;
    _pageController = PageController(initialPage: 0);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();

    _updatedTaleBook = _buildUpdatedTaleBook();

    print('AI RESULT revisedPages = ${widget.revisedPages}');
    print('AI RESULT generatedImagePaths = ${widget.generatedImagePaths}');
    print(
      'AI RESULT updatedTexts = ${_updatedTaleBook.pages.map((e) => e.text).toList()}',
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  // ✅ 수정된 페이지 인덱스 이후는 모두 표시
  bool _isEditedIndex(int index) {
    if (widget.revisedPages == null) return false;
    if (index < widget.editedPageIndex) return false;
    if (index >= widget.revisedPages!.length) return false;
    return true;
  }

  String? _generatedImageForIndex(int index) {
    if (widget.generatedImagePaths == null) return null;
    if (index >= widget.generatedImagePaths!.length) return null;

    final path = widget.generatedImagePaths![index].trim();
    if (path.isEmpty) return null;
    return path;
  }

  TaleBook _buildUpdatedTaleBook() {
    final updatedPages = widget.taleBook.pages.asMap().entries.map((entry) {
      final index = entry.key;
      final page = entry.value;

      final hasRevisedText =
          widget.revisedPages != null && index < widget.revisedPages!.length;

      final revisedImage = _generatedImageForIndex(index);

      return page.copyWith(
        text: hasRevisedText ? widget.revisedPages![index] : page.text,
        imagePath: revisedImage ?? page.imagePath,
      );
    }).toList();

    return TaleBook(tale: widget.tale, pages: updatedPages);
  }

  void _goPrevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _goNextPage() {
    if (_currentPage < _updatedTaleBook.pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _showSaveDialog() async {
    if (widget.tale.storyId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('저장할 수 있는 동화가 아니에요.')));
      return;
    }

    final controller = TextEditingController(
      text: '${widget.tale.title} - 내 이야기',
    );

    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('동화 제목 정하기'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 50,
            decoration: const InputDecoration(
              hintText: '저장할 동화 제목을 입력하세요',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                final value = controller.text.trim();
                Navigator.pop(
                  dialogContext,
                  value.isEmpty ? '${widget.tale.title} - 내 이야기' : value,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3D2C8D),
                foregroundColor: Colors.white,
              ),
              child: const Text('저장'),
            ),
          ],
        );
      },
    );

    if (title == null) return;
    await _saveToMyStories(title);
  }

  Future<void> _saveToMyStories(String customTitle) async {
    if (widget.tale.storyId == null) return;

    setState(() => _isSaving = true);

    try {
      await ApiService.saveAsMyStory(
        storyId: widget.tale.storyId!,
        customTitle: customTitle,
      );

      if (!widget.tale.isUserStory) {
        await ApiService.resetToOriginal(storyId: widget.tale.storyId!);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('나의 책장에 저장되었어요!')));

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MyStoriesScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF3D2C8D),
        elevation: 0,
        title: const Text('AI 결과 보기'),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            // ── 페이지 뷰 ──
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _updatedTaleBook.pages.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) {
                  final page = _updatedTaleBook.pages[index];
                  final isEdited = _isEditedIndex(index);

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      children: [
                        // ✅ 이미지: 16:9 고정 비율, 전체 표시
                        Stack(
                          children: [
                            AspectRatio(
                              aspectRatio: 16 / 9,
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: widget.tale.cardColor,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.08),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: StoryImageView(
                                    imagePath: page.imagePath,
                                    fit: BoxFit.contain, // ✅ 전체 표시
                                  ),
                                ),
                              ),
                            ),
                            if (isEdited)
                              Positioned(
                                top: 14,
                                right: 14,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF7E57C2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'AI 수정',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // ✅ 텍스트 영역
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
                                '${page.pageNumber}페이지',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF7E57C2),
                                ),
                              ),
                              if (isEdited &&
                                  widget.confirmedRequest != null &&
                                  widget.confirmedRequest!
                                      .trim()
                                      .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  '반영 요청: ${widget.confirmedRequest!}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Text(
                                page.text,
                                style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.7,
                                  color: Color(0xFF3D2C8D),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // ── 하단 버튼 영역 ──
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F4FF),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _currentPage > 0 ? _goPrevPage : null,
                          child: const Text('이전 페이지'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${_currentPage + 1} / ${_updatedTaleBook.pages.length}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF3D2C8D),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed:
                              _currentPage < _updatedTaleBook.pages.length - 1
                              ? _goNextPage
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7E57C2),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('다음 페이지'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _showSaveDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3D2C8D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('나의 책장에 저장'),
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
