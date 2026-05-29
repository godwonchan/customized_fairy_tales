import 'package:flutter/material.dart';
import 'fairy_tale_list_screen.dart';
import 'tale_reading_screen.dart';
import 'page_selection_screen.dart';
import 'plot_image_generation_screen.dart';

class AIResultScreen extends StatefulWidget {
  final FairyTale tale;
  final TaleBook taleBook;
  final int editedPageIndex;
  final List<String> revisedPages;
  final String? confirmedRequest;

  const AIResultScreen({
    super.key,
    required this.tale,
    required this.taleBook,
    required this.editedPageIndex,
    required this.revisedPages,
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

  late List<Map<String, String>> _resultPages;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.editedPageIndex;
    _pageController = PageController(initialPage: _currentPage);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    _initResultPages();
  }

  void _initResultPages() {
    _resultPages = widget.taleBook.pages.asMap().entries.map((entry) {
      final index = entry.key;
      final page = entry.value;
      final revisedText =
          index < widget.revisedPages.length ? widget.revisedPages[index] : page.text;

      return {
        'imagePath': page.imagePath,
        'text': revisedText,
        'title': _getPageTitle(index),
      };
    }).toList();
  }

  String _getPageTitle(int index) {
    final titles = [
      '마법의 성을 찾아서',
      '신비한 만남',
      '새로운 친구들',
      '모험의 시작',
      '마법사의 선물',
      '행복한 결말',
    ];
    return index < titles.length ? titles[index] : '${index + 1}번째 이야기';
  }

  TaleBook _buildUpdatedTaleBook() {
    final updatedPages = widget.taleBook.pages.asMap().entries.map((entry) {
      final index = entry.key;
      final page = entry.value;
      final revisedText =
          index < widget.revisedPages.length ? widget.revisedPages[index] : page.text;

      return TalePage(
        pageNumber: page.pageNumber,
        imagePath: page.imagePath,
        text: revisedText,
        highlightText: page.highlightText,
        imageUrl: page.imageUrl,
      );
    }).toList();

    return TaleBook(
      tale: widget.tale,
      pages: updatedPages,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    setState(() => _currentPage = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    _animController.forward(from: 0);
  }

  void _nextPage() {
    if (_currentPage < _resultPages.length - 1) _goToPage(_currentPage + 1);
  }

  void _prevPage() {
    if (_currentPage > 0) _goToPage(_currentPage - 1);
  }

  void _goBackToEdit() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PageSelectionScreen(
          tale: widget.tale,
          taleBook: widget.taleBook,
        ),
      ),
    );
  }

  void _goToMoreEdit() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PageSelectionScreen(
          tale: widget.tale,
          taleBook: _buildUpdatedTaleBook(),
        ),
      ),
    );
  }

  void _goToPlotImageGeneration() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlotImageGenerationScreen(
          tale: widget.tale,
          taleBook: _buildUpdatedTaleBook(),
          editedPageIndex: widget.editedPageIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, isTablet),
            if (widget.confirmedRequest != null &&
                widget.confirmedRequest!.trim().isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE7F6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '반영된 요청: ${widget.confirmedRequest}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7E57C2),
                  ),
                ),
              ),
            Expanded(
              child: isTablet ? _buildTabletLayout() : _buildPhoneLayout(),
            ),
            _buildThumbnailBar(isTablet),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isTablet) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI 재구성 결과',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                Text(widget.tale.title,
                    style: TextStyle(
                      fontSize: isTablet ? 18 : 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF3D2C8D),
                    )),
              ],
            ),
            const SizedBox(width: 20),
            _headerButton('다시 만들기', _goBackToEdit),
            const SizedBox(width: 8),
            _headerButton('더 수정하기', _goToMoreEdit),
            const SizedBox(width: 8),
            _headerButton('플롯 이미지 만들기', _goToPlotImageGeneration),
          ],
        ),
      ),
    );
  }

  Widget _headerButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF7E57C2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildTabletLayout() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Expanded(flex: 55, child: _buildImageArea(isTablet: true)),
          const SizedBox(width: 32),
          Expanded(flex: 45, child: _buildTextArea(isTablet: true)),
        ],
      ),
    );
  }

  Widget _buildPhoneLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildImageArea(isTablet: false),
          const SizedBox(height: 20),
          _buildTextArea(isTablet: false),
        ],
      ),
    );
  }

  Widget _buildImageArea({required bool isTablet}) {
    final page = _resultPages[_currentPage];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: FadeTransition(
          opacity: _fadeAnim,
          child: page['imagePath']!.isNotEmpty
              ? Image.asset(
                  page['imagePath']!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: isTablet ? double.infinity : 320,
                  errorBuilder: (_, __, ___) => Container(
                    height: isTablet ? 400 : 320,
                    color: const Color(0xFFEDE7F6),
                    child: const Center(child: Icon(Icons.auto_stories, size: 80)),
                  ),
                )
              : Container(
                  height: isTablet ? 400 : 320,
                  color: const Color(0xFFEDE7F6),
                  child: const Center(child: Icon(Icons.auto_stories, size: 80)),
                ),
        ),
      ),
    );
  }

  Widget _buildTextArea({required bool isTablet}) {
    final page = _resultPages[_currentPage];

    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        height: isTablet ? double.infinity : 320,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              page['title']!,
              style: TextStyle(
                fontSize: isTablet ? 24 : 20,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF3D2C8D),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  page['text']!,
                  style: TextStyle(
                    fontSize: isTablet ? 16 : 14,
                    color: const Color(0xFF3D2C8D),
                    height: 1.9,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (_currentPage > 0)
                  TextButton(
                    onPressed: _prevPage,
                    child: const Text('이전'),
                  ),
                const Spacer(),
                if (_currentPage < _resultPages.length - 1)
                  ElevatedButton(
                    onPressed: _nextPage,
                    child: const Text('다음'),
                  )
                else
                  ElevatedButton(
                    onPressed: _goToPlotImageGeneration,
                    child: const Text('플롯 이미지 만들기'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnailBar(bool isTablet) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: Colors.white,
      child: SizedBox(
        height: isTablet ? 72 : 64,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _resultPages.length,
          itemBuilder: (context, index) {
            final isSelected = _currentPage == index;
            return GestureDetector(
              onTap: () => _goToPage(index),
              child: Container(
                alignment: Alignment.center,
                margin: const EdgeInsets.only(right: 8),
                width: isTablet ? 60 : 52,
                height: isTablet ? 60 : 52,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFEDE7F6)
                      : const Color(0xFFF8F4FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF7E57C2)
                        : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? const Color(0xFF7E57C2)
                        : Colors.grey[600],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}