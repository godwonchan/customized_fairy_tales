import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'fairy_tale_list_screen.dart';
import 'tale_reading_screen.dart';
import 'ai_result_screen.dart';

// ═══════════════════════════════════════════════════════════════
//  하이라이트 범위 모델
// ═══════════════════════════════════════════════════════════════

class HighlightRange {
  final int start;
  final int end;
  final String text;

  HighlightRange({
    required this.start,
    required this.end,
    required this.text,
  });
}

// ═══════════════════════════════════════════════════════════════
//  장면 수정하기 화면
// ═══════════════════════════════════════════════════════════════

class SceneEditScreen extends StatefulWidget {
  final FairyTale tale;
  final TaleBook taleBook;
  final int selectedPageIndex;

  const SceneEditScreen({
    super.key,
    required this.tale,
    required this.taleBook,
    required this.selectedPageIndex,
  });

  @override
  State<SceneEditScreen> createState() => _SceneEditScreenState();
}

class _SceneEditScreenState extends State<SceneEditScreen> {
  // ── 그림판 ──
  final List<DrawingPath> _paths = [];
  DrawingPath? _currentPath;
  Color _selectedColor = Colors.black;
  double _strokeWidth = 12.0;
  bool _isEraser = false;

  // ── 텍스트 하이라이트 ──
  late String _fullText;
  final List<HighlightRange> _highlights = [];
  final TextEditingController _textController = TextEditingController();

  // ── AI 패널 ──
  bool _showPreviewPanel = false;
  bool _isGenerating = false;
  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, String>> _chatMessages = [];
  bool _showPreviewTab = true;

  final List<Color> _colorPalette = [
    Colors.black,
    const Color(0xFFE53935),
    const Color(0xFFFF8F00),
    const Color(0xFFFFD600),
    const Color(0xFF43A047),
    const Color(0xFF1E88E5),
    const Color(0xFF5E35B1),
    const Color(0xFF795548),
    const Color(0xFFEC407A),
  ];

  @override
  void initState() {
    super.initState();
    _initText();
  }

  void _initText() {
    final page = widget.taleBook.pages[widget.selectedPageIndex];
    _fullText = page.text;
    if (page.highlightText != null) {
      _fullText += '\n${page.highlightText}';
    }
    _textController.text = _fullText;
  }

  @override
  void dispose() {
    _chatController.dispose();
    _textController.dispose();
    super.dispose();
  }

  // ── 선택된 텍스트 하이라이트 추가 ──
  void _addHighlight(int start, int end) {
    if (start >= end) return;
    final selectedText = _fullText.substring(start, end);
    if (selectedText.trim().isEmpty) return;

    setState(() {
      // 중복 제거
      _highlights.removeWhere((h) =>
          (h.start <= start && h.end >= start) ||
          (h.start <= end && h.end >= end) ||
          (start <= h.start && end >= h.end));

      _highlights.add(HighlightRange(
        start: start,
        end: end,
        text: selectedText,
      ));
    });
  }

  void _removeHighlight(int index) {
    setState(() => _highlights.removeAt(index));
  }

  void _clearHighlights() {
    setState(() => _highlights.clear());
  }

  void _clearCanvas() => setState(() => _paths.clear());
  void _undo() {
    if (_paths.isNotEmpty) setState(() => _paths.removeLast());
  }

  void _showPreview() async {
    setState(() {
      _showPreviewPanel = true;
      _isGenerating = true;
    });
    await Future.delayed(const Duration(seconds: 2));
    setState(() => _isGenerating = false);
  }

  void _sendChat() {
    if (_chatController.text.trim().isEmpty) return;
    setState(() {
      _chatMessages
          .add({'role': 'user', 'text': _chatController.text.trim()});
      _chatController.clear();
    });
    Future.delayed(const Duration(seconds: 1), () {
      setState(() {
        _chatMessages.add({
          'role': 'ai',
          'text': '알겠어요! 말씀하신 대로 수정해볼게요.',
        });
      });
    });
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
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: isTablet ? 300 : 240,
                    child: _buildScriptPanel(isTablet),
                  ),
                  Expanded(child: _buildCanvasPanel(isTablet)),
                  if (_showPreviewPanel)
                    SizedBox(
                      width: isTablet ? 320 : 260,
                      child: _buildPreviewPanel(isTablet),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 헤더 ──
  Widget _buildHeader(BuildContext context, bool isTablet) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 24 : 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                  color: const Color(0xFFF8F4FF),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.chevron_left,
                  color: Color(0xFF7E57C2), size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('장면 수정하기',
                  style: TextStyle(
                      fontSize: isTablet ? 18 : 16,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF3D2C8D))),
              Text('선택한 장면을 그림으로 그리고, 바꾸고 싶은 내용을 적어주세요.',
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey[400])),
            ],
          ),
          const Spacer(),
          _buildStepIndicator(isTablet),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: const Color(0xFFF8F4FF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE0D7F5))),
            child: Row(
              children: const [
                Icon(Icons.lightbulb_outline,
                    size: 14, color: Color(0xFF7E57C2)),
                SizedBox(width: 4),
                Text('수정 가이드',
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF7E57C2),
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 스텝 인디케이터 ──
  Widget _buildStepIndicator(bool isTablet) {
    final steps = ['동화 읽기', '수정할 페이지 선택', '장면 수정하기'];
    return Row(
      children: steps.asMap().entries.map((entry) {
        final index = entry.key;
        final label = entry.value;
        final isDone = index < 2;
        final isCurrent = index == 2;
        return Row(
          children: [
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                  color: isDone || isCurrent
                      ? const Color(0xFF7E57C2)
                      : Colors.grey[300],
                  shape: BoxShape.circle),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text('${index + 1}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isCurrent
                                ? Colors.white
                                : Colors.grey[500])),
              ),
            ),
            const SizedBox(width: 4),
            if (isTablet)
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: isCurrent
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isCurrent
                          ? const Color(0xFF7E57C2)
                          : Colors.grey[400])),
            if (index < steps.length - 1) ...[
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward,
                  size: 14, color: Colors.grey[300]),
              const SizedBox(width: 6),
            ],
          ],
        );
      }).toList(),
    );
  }

  // ── 왼쪽 대본 패널 ──
  Widget _buildScriptPanel(bool isTablet) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 패널 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                const Text('바꾸고 싶은 내용 선택',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3D2C8D))),
                const SizedBox(width: 4),
                Icon(Icons.info_outline,
                    size: 14, color: Colors.grey[400]),
                const Spacer(),
                GestureDetector(
                  onTap: _clearHighlights,
                  child: Text('초기화',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[400])),
                ),
              ],
            ),
          ),
          // 선택된 하이라이트 수 표시
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _highlights.isEmpty
                    ? const Color(0xFFF8F4FF)
                    : const Color(0xFFEDE7F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _highlights.isEmpty
                        ? Icons.info_outline
                        : Icons.highlight,
                    size: 14,
                    color: _highlights.isEmpty
                        ? Colors.grey[400]
                        : const Color(0xFF7E57C2),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _highlights.isEmpty
                          ? '텍스트를 드래그해서 선택하세요'
                          : '${_highlights.length}개 구간 선택됨',
                      style: TextStyle(
                          fontSize: 11,
                          color: _highlights.isEmpty
                              ? Colors.grey[400]
                              : const Color(0xFF7E57C2),
                          fontWeight: _highlights.isEmpty
                              ? FontWeight.w400
                              : FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          // 드래그로 선택 가능한 텍스트
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 안내 텍스트
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFFFFE082), width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.touch_app,
                            size: 14, color: Color(0xFFFF8F00)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '바꾸고 싶은 단어나 문장을 드래그해서 선택하세요!',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange[800],
                                height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 하이라이트 적용된 텍스트
                  _buildHighlightedText(),
                  // 선택된 구간 목록
                  if (_highlights.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text('선택한 구간',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[500])),
                    const SizedBox(height: 8),
                    ..._highlights.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final h = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD600).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFFFFD600)
                                  .withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '"${h.text}"',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF3D2C8D),
                                    fontWeight: FontWeight.w500),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _removeHighlight(idx),
                              child: Icon(Icons.close,
                                  size: 16, color: Colors.grey[400]),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          // 토끼 안내
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEDE7F6),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.emoji_nature,
                    size: 20, color: Color(0xFF7E57C2)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '드래그로 단어나 문장을\n선택해 하이라이트해요!',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[600],
                        height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 하이라이트 텍스트 위젯 ──
  Widget _buildHighlightedText() {
    if (_highlights.isEmpty) {
      return SelectableText(
        _fullText,
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF3D2C8D),
          height: 1.9,
        ),
        onSelectionChanged: (selection, cause) {
          if (cause == SelectionChangedCause.longPress ||
              cause == SelectionChangedCause.drag) {
            final start = selection.start;
            final end = selection.end;
            if (start >= 0 && end > start) {
              _addHighlight(start, end);
            }
          }
        },
      );
    }

    // 하이라이트가 있을 때 RichText로 표시
    final List<TextSpan> spans = [];
    final sortedHighlights = List<HighlightRange>.from(_highlights)
      ..sort((a, b) => a.start.compareTo(b.start));

    int currentIndex = 0;
    for (final highlight in sortedHighlights) {
      if (highlight.start > currentIndex) {
        spans.add(TextSpan(
          text: _fullText.substring(currentIndex, highlight.start),
          style: const TextStyle(
              fontSize: 14, color: Color(0xFF3D2C8D), height: 1.9),
        ));
      }
      spans.add(TextSpan(
        text: _fullText.substring(highlight.start, highlight.end),
        style: TextStyle(
          fontSize: 14,
          color: const Color(0xFF3D2C8D),
          height: 1.9,
          fontWeight: FontWeight.w600,
          backgroundColor: const Color(0xFFFFD600).withOpacity(0.5),
        ),
      ));
      currentIndex = highlight.end;
    }

    if (currentIndex < _fullText.length) {
      spans.add(TextSpan(
        text: _fullText.substring(currentIndex),
        style: const TextStyle(
            fontSize: 14, color: Color(0xFF3D2C8D), height: 1.9),
      ));
    }

    return SelectableText.rich(
      TextSpan(children: spans),
      onSelectionChanged: (selection, cause) {
        if (cause == SelectionChangedCause.longPress ||
            cause == SelectionChangedCause.drag) {
          final start = selection.start;
          final end = selection.end;
          if (start >= 0 && end > start) {
            _addHighlight(start, end);
          }
        }
      },
    );
  }

  // ── 가운데 그림판 패널 ──
  Widget _buildCanvasPanel(bool isTablet) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                const Text('새롭게 그리고 싶은 장면을 그려주세요!',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3D2C8D))),
                const SizedBox(width: 4),
                Icon(Icons.info_outline,
                    size: 14, color: Colors.grey[400]),
                const Spacer(),
                _canvasTab(Icons.edit, '그림 그리기', true),
                const SizedBox(width: 8),
                _canvasTab(Icons.star_outline, '스티커', false),
                const SizedBox(width: 16),
                _iconBtn(Icons.undo, _undo),
                const SizedBox(width: 8),
                _iconBtn(Icons.redo, () {}),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _clearCanvas,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[200]!),
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline,
                            size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text('전체 지우기',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              children: [
                _buildToolbar(),
                Expanded(child: _buildCanvas()),
              ],
            ),
          ),
          _buildColorBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _showPreview,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7E57C2),
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.auto_awesome, size: 18),
                        SizedBox(width: 8),
                        Text('AI로 수정 결과 미리보기',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text('AI가 새롭게 그린 장면과 내용을 미리 보여드려요!',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[400])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _canvasTab(IconData icon, String label, bool isActive) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF7E57C2) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isActive
                ? const Color(0xFF7E57C2)
                : Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 14,
              color: isActive ? Colors.white : Colors.grey[500]),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: isActive ? Colors.white : Colors.grey[500],
                  fontWeight: isActive
                      ? FontWeight.w600
                      : FontWeight.w400)),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[200]!),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 16, color: Colors.grey[500]),
      ),
    );
  }

  Widget _buildToolbar() {
    final tools = [
      {'icon': Icons.edit, 'label': '펜'},
      {'icon': Icons.auto_fix_high, 'label': '지우개'},
      {'icon': Icons.crop_free, 'label': '선택'},
      {'icon': Icons.search, 'label': '도형'},
      {'icon': Icons.text_fields, 'label': '텍스트'},
      {'icon': Icons.undo, 'label': '되돌리기'},
      {'icon': Icons.redo, 'label': '다시실행'},
    ];

    return Container(
      width: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: tools.map((tool) {
          final isActive = tool['label'] == '펜' && !_isEraser ||
              tool['label'] == '지우개' && _isEraser;
          return GestureDetector(
            onTap: () {
              if (tool['label'] == '펜') setState(() => _isEraser = false);
              if (tool['label'] == '지우개')
                setState(() => _isEraser = true);
              if (tool['label'] == '되돌리기') _undo();
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              width: 44, height: 52,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFFEDE7F6)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(tool['icon'] as IconData,
                      size: 20,
                      color: isActive
                          ? const Color(0xFF7E57C2)
                          : Colors.grey[500]),
                  const SizedBox(height: 2),
                  Text(tool['label'] as String,
                      style: TextStyle(
                          fontSize: 9,
                          color: isActive
                              ? const Color(0xFF7E57C2)
                              : Colors.grey[400])),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCanvas() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: Colors.white,
        child: GestureDetector(
          onPanStart: (details) {
            setState(() {
              _currentPath = DrawingPath(
                color: _isEraser ? Colors.white : _selectedColor,
                strokeWidth: _isEraser ? 24 : _strokeWidth,
                points: [details.localPosition],
              );
              _paths.add(_currentPath!);
            });
          },
          onPanUpdate: (details) {
            setState(() {
              _currentPath?.points.add(details.localPosition);
            });
          },
          onPanEnd: (_) => _currentPath = null,
          child: CustomPaint(
            painter: DrawingPainter(_paths),
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          ...(_colorPalette.map((color) {
            final isSelected = _selectedColor == color && !_isEraser;
            return GestureDetector(
              onTap: () => setState(() {
                _selectedColor = color;
                _isEraser = false;
              }),
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: isSelected
                          ? const Color(0xFF7E57C2)
                          : Colors.grey[300]!,
                      width: isSelected ? 2.5 : 1),
                ),
              ),
            );
          })),
          Container(
            margin: const EdgeInsets.only(right: 16),
            width: 28, height: 28,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey[300]!)),
            child: Icon(Icons.add, size: 16, color: Colors.grey[400]),
          ),
          Text('굵기',
              style:
                  TextStyle(fontSize: 12, color: Colors.grey[500])),
          Expanded(
            child: Slider(
              value: _strokeWidth,
              min: 2, max: 30,
              activeColor: const Color(0xFF7E57C2),
              onChanged: (v) => setState(() => _strokeWidth = v),
            ),
          ),
          Text('${_strokeWidth.round()}px',
              style:
                  TextStyle(fontSize: 12, color: Colors.grey[500])),
        ],
      ),
    );
  }

  // ── 오른쪽 AI 미리보기 패널 ──
  Widget _buildPreviewPanel(bool isTablet) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              children: [
                const Text('수정 결과 미리보기',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3D2C8D))),
                const Spacer(),
                GestureDetector(
                  onTap: () =>
                      setState(() => _showPreviewPanel = false),
                  child: const Icon(Icons.close,
                      size: 18, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                _previewTab('미리보기', true),
                const SizedBox(width: 8),
                _previewTab('AI와 이야기하기', false),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          Expanded(
            child: _showPreviewTab
                ? _buildPreviewContent()
                : _buildChatContent(),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AIResultScreen(
                          tale: widget.tale,
                          taleBook: widget.taleBook,
                          editedPageIndex: widget.selectedPageIndex,
                        ),
                      ),
                    );
                  },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7E57C2),
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('이대로 적용하기',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _showPreviewPanel = false;
                        _paths.clear();
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF7E57C2),
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(
                          color: Color(0xFF7E57C2)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('다시 그리기',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '⊙ 미리보기는 참고용으로, 실제 결과와 다를 수 있어요.',
              style:
                  TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewTab(String label, bool isPreview) {
    final isActive = _showPreviewTab == isPreview;
    return GestureDetector(
      onTap: () => setState(() => _showPreviewTab = isPreview),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF7E57C2) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isActive
                  ? const Color(0xFF7E57C2)
                  : Colors.grey[200]!),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: isActive ? Colors.white : Colors.grey[500],
                fontWeight: isActive
                    ? FontWeight.w600
                    : FontWeight.w400)),
      ),
    );
  }

  Widget _buildPreviewContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_highlights.isNotEmpty) ...[
            Text('바뀌는 내용',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[500])),
            const SizedBox(height: 8),
            ..._highlights.map((h) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F4FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('"${h.text}"',
                            style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF7E57C2),
                                fontWeight: FontWeight.w500)),
                      ),
                      const Icon(Icons.arrow_forward,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('AI가 새롭게 바꿔드릴게요!',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600])),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 14),
          ],
          Text('새롭게 그려질 장면',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500])),
          const SizedBox(height: 8),
          _isGenerating
              ? Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F4FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                            color: Color(0xFF7E57C2), strokeWidth: 2),
                        SizedBox(height: 12),
                        Text('AI가 그림을 생성하고 있어요...',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF7E57C2))),
                      ],
                    ),
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    widget.taleBook
                        .pages[widget.selectedPageIndex].imagePath,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => Container(
                      height: 160,
                      decoration: BoxDecoration(
                        color: widget.tale.cardColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Icon(Icons.auto_stories,
                            size: 60,
                            color: widget.tale.cardColor
                                .withOpacity(0.4)),
                      ),
                    ),
                  ),
                ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEDE7F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.emoji_nature,
                    size: 20, color: Color(0xFF7E57C2)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('어때요? 마음에 드나요?',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF7E57C2))),
                      const SizedBox(height: 2),
                      Text(
                          '더 바꾸고 싶은 점이 있으면 저에게 이야기\n해 주세요!',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600])),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatContent() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _chatBubble('ai',
                  '어때요? 마음에 드나요?\n더 바꾸고 싶은 점이 있으면 저에게 이야기해 주세요!'),
              ..._chatMessages.map(
                  (msg) => _chatBubble(msg['role']!, msg['text']!)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              border:
                  Border(top: BorderSide(color: Colors.grey[200]!))),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '원하는 수정 내용을 말해보세요...',
                    hintStyle: TextStyle(
                        fontSize: 12, color: Colors.grey[400]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide:
                          BorderSide(color: Colors.grey[200]!),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  onSubmitted: (_) => _sendChat(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _sendChat,
                child: Container(
                  width: 36, height: 36,
                  decoration: const BoxDecoration(
                      color: Color(0xFF7E57C2),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.send,
                      size: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chatBubble(String role, String text) {
    final isAI = role == 'ai';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isAI ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isAI) ...[
            Container(
              width: 28, height: 28,
              decoration: const BoxDecoration(
                  color: Color(0xFFEDE7F6), shape: BoxShape.circle),
              child: const Icon(Icons.emoji_nature,
                  size: 16, color: Color(0xFF7E57C2)),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            constraints: const BoxConstraints(maxWidth: 200),
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isAI
                  ? const Color(0xFFEDE7F6)
                  : const Color(0xFF7E57C2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(text,
                style: TextStyle(
                    fontSize: 12,
                    color: isAI
                        ? const Color(0xFF3D2C8D)
                        : Colors.white,
                    height: 1.5)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  그림 데이터 모델
// ═══════════════════════════════════════════════════════════════

class DrawingPath {
  final Color color;
  final double strokeWidth;
  final List<Offset> points;

  DrawingPath({
    required this.color,
    required this.strokeWidth,
    required this.points,
  });
}

class DrawingPainter extends CustomPainter {
  final List<DrawingPath> paths;

  DrawingPainter(this.paths);

  @override
  void paint(Canvas canvas, Size size) {
    for (final path in paths) {
      if (path.points.isEmpty) continue;
      final paint = Paint()
        ..color = path.color
        ..strokeWidth = path.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final drawPath = Path();
      drawPath.moveTo(path.points.first.dx, path.points.first.dy);
      for (int i = 1; i < path.points.length; i++) {
        drawPath.lineTo(path.points[i].dx, path.points[i].dy);
      }
      canvas.drawPath(drawPath, paint);
    }
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) => true;
}