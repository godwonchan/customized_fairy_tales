import 'package:flutter/material.dart';
import 'fairy_tale_list_screen.dart';
import 'tale_reading_screen.dart';
import 'scene_edit_screen.dart';
import '../widgets/story_image_view.dart';

class PageSelectionScreen extends StatefulWidget {
  final FairyTale tale;
  final TaleBook taleBook;

  const PageSelectionScreen({
    super.key,
    required this.tale,
    required this.taleBook,
  });

  @override
  State<PageSelectionScreen> createState() => _PageSelectionScreenState();
}

class _PageSelectionScreenState extends State<PageSelectionScreen> {
  int? _selectedPageIndex;
  int _currentGridPage = 0;
  final int _itemsPerPage = 10;

  int get _totalGridPages =>
      (widget.taleBook.totalPages / _itemsPerPage).ceil();

  List<TalePage> get _currentPageItems {
    final start = _currentGridPage * _itemsPerPage;
    final end = (start + _itemsPerPage).clamp(0, widget.taleBook.totalPages);
    return widget.taleBook.pages.sublist(start, end);
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
            _buildGuideBox(isTablet),
            Expanded(child: _buildGrid(isTablet)),
            if (_totalGridPages > 1) _buildPagination(),
            _buildBottomPreview(isTablet),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isTablet) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFF5F0FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: const Color(0xFFF8F4FF), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.chevron_left, color: Color(0xFF7E57C2), size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('수정할 페이지 선택',
                  style: TextStyle(fontSize: isTablet ? 18 : 16, fontWeight: FontWeight.w700, color: const Color(0xFF3D2C8D))),
              Text('이야기에서 바꾸고 싶은 장면을 하나 선택해주세요.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400])),
            ],
          ),
          const Spacer(),
          _buildStepIndicator(isTablet),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F4FF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE0D7F5)),
            ),
            child: Row(children: const [
              Icon(Icons.lightbulb_outline, size: 14, color: Color(0xFF7E57C2)),
              SizedBox(width: 4),
              Text('선택 가이드', style: TextStyle(fontSize: 12, color: Color(0xFF7E57C2), fontWeight: FontWeight.w500)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(bool isTablet) {
    final steps = ['동화 읽기', '수정할 페이지 선택', '장면 수정하기'];
    return Row(
      children: steps.asMap().entries.map((entry) {
        final index = entry.key;
        final label = entry.value;
        final isDone = index == 0;
        final isCurrent = index == 1;
        return Row(
          children: [
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                color: isDone || isCurrent ? const Color(0xFF7E57C2) : Colors.grey[300],
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text('${index + 1}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                            color: isCurrent ? Colors.white : Colors.grey[500])),
              ),
            ),
            const SizedBox(width: 4),
            if (isTablet)
              Text(label,
                  style: TextStyle(fontSize: 12,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                      color: isCurrent ? const Color(0xFF7E57C2) : Colors.grey[400])),
            if (index < steps.length - 1) ...[
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward, size: 14, color: Colors.grey[300]),
              const SizedBox(width: 6),
            ],
          ],
        );
      }).toList(),
    );
  }

  Widget _buildGuideBox(bool isTablet) {
    return Container(
      margin: EdgeInsets.all(isTablet ? 20 : 14),
      padding: EdgeInsets.all(isTablet ? 16 : 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFAF8FF), Color(0xFFEDE7F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8CCFF), width: 1.5),
        boxShadow: [BoxShadow(color: const Color(0xFF9575CD).withOpacity(0.1), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            width: isTablet ? 60 : 50, height: isTablet ? 60 : 50,
            decoration: BoxDecoration(color: const Color(0xFFEDE7F6), borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.emoji_nature, size: 32, color: Color(0xFF7E57C2)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('한 번에 한 장면만 선택할 수 있어요!',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF7E57C2))),
                const SizedBox(height: 4),
                Text('가장 바꾸고 싶은 장면을 하나 골라주세요.\nAI가 그 장면부터 이야기를 새롭게 이어갈 거예요.',
                    style: TextStyle(fontSize: isTablet ? 13 : 12, color: Colors.grey[600], height: 1.5)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F4FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE0D7F5)),
            ),
            child: Row(children: const [
              Icon(Icons.star, size: 14, color: Color(0xFF7E57C2)),
              SizedBox(width: 6),
              Text('선택한 페이지는 보라색 테두리로 표시돼요.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF7E57C2), fontWeight: FontWeight.w500)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(bool isTablet) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 14),
      child: Wrap(
        spacing: isTablet ? 12 : 8,
        runSpacing: isTablet ? 12 : 8,
        children: List.generate(_currentPageItems.length, (index) {
          final actualIndex = _currentGridPage * _itemsPerPage + index;
          final page = _currentPageItems[index];
          final isSelected = _selectedPageIndex == actualIndex;
          final cardWidth = isSelected ? (isTablet ? 180.0 : 150.0) : (isTablet ? 130.0 : 105.0);
          final cardHeight = isSelected ? (isTablet ? 170.0 : 140.0) : (isTablet ? 120.0 : 95.0);

          return GestureDetector(
            onTap: () => setState(() => _selectedPageIndex = actualIndex),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              width: cardWidth,
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    width: cardWidth, height: cardHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isSelected ? const Color(0xFF7E57C2) : Colors.transparent, width: 2.5),
                      boxShadow: [BoxShadow(
                          color: isSelected ? const Color(0xFF7E57C2).withOpacity(0.3) : Colors.black.withOpacity(0.06),
                          blurRadius: isSelected ? 14 : 6)],
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(borderRadius: BorderRadius.circular(10),
                            child: StoryImageView(imagePath: page.imagePath, fit: BoxFit.cover)),
                        Positioned(top: 4, left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(6)),
                            child: Text('${actualIndex + 1}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF3D2C8D))),
                          )),
                        Positioned(top: 4, right: 4,
                          child: isSelected
                              ? Container(width: 22, height: 22,
                                  decoration: const BoxDecoration(color: Color(0xFF7E57C2), shape: BoxShape.circle),
                                  child: const Icon(Icons.check, size: 14, color: Colors.white))
                              : const Icon(Icons.favorite_border, size: 16, color: Colors.white)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(_getPageDescription(actualIndex),
                      style: TextStyle(fontSize: isTablet ? 11 : 10,
                          color: isSelected ? const Color(0xFF7E57C2) : Colors.grey[600],
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, height: 1.3),
                      textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  String _getPageDescription(int index) {
    final pages = widget.taleBook.pages;
    if (index < pages.length) {
      final text = pages[index].text;
      return text.length > 15 ? '${text.substring(0, 15)}...' : text;
    }
    return '${index + 1}페이지';
  }

  Widget _buildPagination() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: _currentGridPage > 0 ? () => setState(() => _currentGridPage--) : null,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: _currentGridPage > 0 ? Colors.white : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Icon(Icons.chevron_left, size: 18,
                  color: _currentGridPage > 0 ? const Color(0xFF7E57C2) : Colors.grey[300]),
            ),
          ),
          const SizedBox(width: 12),
          Text('${_currentGridPage + 1} / $_totalGridPages',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3D2C8D))),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _currentGridPage < _totalGridPages - 1 ? () => setState(() => _currentGridPage++) : null,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: _currentGridPage < _totalGridPages - 1 ? Colors.white : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Icon(Icons.chevron_right, size: 18,
                  color: _currentGridPage < _totalGridPages - 1 ? const Color(0xFF7E57C2) : Colors.grey[300]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPreview(bool isTablet) {
    final selectedPage = _selectedPageIndex != null ? widget.taleBook.pages[_selectedPageIndex!] : null;
    return Container(
      padding: EdgeInsets.all(isTablet ? 20 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('선택한 페이지 미리보기',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[500])),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: widget.tale.cardColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF7E57C2), width: 2),
                    ),
                    child: selectedPage != null
                        ? ClipRRect(borderRadius: BorderRadius.circular(8),
                            child: StoryImageView(imagePath: selectedPage.imagePath, fit: BoxFit.cover))
                        : const Icon(Icons.image_outlined, color: Colors.grey, size: 24),
                  ),
                  const SizedBox(width: 12),
                  if (selectedPage != null)
                    SizedBox(
                      width: isTablet ? 200 : 140,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_getPageDescription(_selectedPageIndex!),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3D2C8D)),
                              maxLines: 2),
                          const SizedBox(height: 2),
                          Text(selectedPage.text.length > 30 ? '${selectedPage.text.substring(0, 30)}...' : selectedPage.text,
                              style: TextStyle(fontSize: 11, color: Colors.grey[500]), maxLines: 1),
                        ],
                      ),
                    )
                  else
                    Text('페이지를 선택해주세요', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
                ],
              ),
            ],
          ),
          const SizedBox(width: 16),
          if (isTablet)
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFF8F4FF), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: const [
                      Icon(Icons.lightbulb_outline, size: 14, color: Color(0xFF7E57C2)),
                      SizedBox(width: 4),
                      Text('기억해주세요!', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF7E57C2))),
                    ]),
                    const SizedBox(height: 6),
                    ...['한 번에 한 페이지(한 장면)만 선택할 수 있어요.', '선택한 장면 이후의 이야기가 새롭게 바뀌어요.', '원하지 않는 부분만 골라 바꿀 수 있어요!']
                        .map((hint) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(children: [
                                const Text('• ', style: TextStyle(fontSize: 11, color: Color(0xFF7E57C2))),
                                Text(hint, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                              ]),
                            )),
                  ],
                ),
              ),
            ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ElevatedButton(
                onPressed: _selectedPageIndex != null
                    ? () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => SceneEditScreen(tale: widget.tale, taleBook: widget.taleBook, selectedPageIndex: _selectedPageIndex!)))
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7E57C2), foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[200],
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0,
                ),
                child: Row(children: [
                  Text('이 장면을 선택하고 수정하기로 이동',
                      style: TextStyle(fontSize: isTablet ? 14 : 13, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 16),
                ]),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Row(children: const [
                  Icon(Icons.arrow_back, size: 14, color: Color(0xFF7E57C2)),
                  SizedBox(width: 4),
                  Text('이전 단계로 돌아가기', style: TextStyle(fontSize: 13, color: Color(0xFF7E57C2))),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}