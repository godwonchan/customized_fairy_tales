import 'package:flutter/material.dart';
import 'fairy_tale_list_screen.dart';
import 'tale_reading_screen.dart';

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

class _SceneEditScreenState extends State<SceneEditScreen>
    with SingleTickerProviderStateMixin {
  // ── 그림판 ──
  final List<DrawingPath> _paths = [];
  DrawingPath? _currentPath;
  Color _selectedColor = Colors.black;
  double _strokeWidth = 12.0;
  bool _isEraser = false;

  // ── 텍스트 선택 ──
  final Set<int> _selectedSentences = {};
  String _viewMode = '대분 전체 보기';

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

  // 샘플 대본 문장들
  late List<Map<String, dynamic>> _sentences;

  @override
  void initState() {
    super.initState();
    _initSentences();
  }

  void _initSentences() {
    final pageText = widget.taleBook.pages[widget.selectedPageIndex].text;
    final rawSentences = pageText.split('.');
    _sentences = rawSentences
        .where((s) => s.trim().isNotEmpty)
        .toList()
        .asMap()
        .entries
        .map((e) => {
              'index': e.key,
              'text': '${e.value.trim()}.',
              'type': e.key % 3 == 0
                  ? 'scene'
                  : e.key % 3 == 1
                      ? 'sentence'
                      : 'dialogue',
            })
        .toList();

    // 추가 샘플 문장
    if (_sentences.length < 5) {
      _sentences = [
        {'index': 0, 'text': '소녀는 숲에서 늑대를 만나 길을 물어보고,', 'type': 'sentence'},
        {'index': 1, 'text': '늑대는 할미니 댁까지 가는 길을 알려주었어요.', 'type': 'sentence'},
        {'index': 2, 'text': '길을 따라가던 소녀는 예쁜 꽃들과 나비를 보았어요.', 'type': 'scene'},
        {'index': 3, 'text': '나비가 소녀 주위를 날아다니며 인사를 했어요.', 'type': 'scene'},
        {'index': 4, 'text': '조금 더 가자, 사슴이 나타나 소녀를 반겼어요.', 'type': 'scene'},
        {'index': 5, 'text': '사슴을 만났어', 'type': 'dialogue'},
        {'index': 6, 'text': '함께 할미니댁으로 가기로 했어요.', 'type': 'sentence'},
        {'index': 7, 'text': '어느새 할미니 집이 보였어요.', 'type': 'scene'},
        {'index': 8, 'text': '할미니는 따뜻하게 맞아주셨어요.', 'type': 'scene'},
        {'index': 9, 'text': '소녀는 할미니와 맛있는 빵을 나눠 먹었어요.', 'type': 'sentence'},
        {'index': 10, 'text': '밖에서는 해가 따뜻하게 빛나고 있었어요.', 'type': 'scene'},
      ];
    }
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'scene':
        return const Color(0xFFFFD600);
      case 'sentence':
        return const Color(0xFF7E57C2);
      case 'dialogue':
        return const Color(0xFF1E88E5);
      default:
        return Colors.grey;
    }
  }

  void _toggleSentence(int index) {
    setState(() {
      if (_selectedSentences.contains(index)) {
        _selectedSentences.remove(index);
      } else {
        _selectedSentences.add(index);
      }
    });
  }

  void _clearCanvas() {
    setState(() => _paths.clear());
  }

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
      _chatMessages.add({
        'role': 'user',
        'text': _chatController.text.trim(),
      });
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
                  // 왼쪽 — 대본
                  SizedBox(
                    width: isTablet ? 280 : 220,
                    child: _buildScriptPanel(isTablet),
                  ),
                  // 가운데 — 그림판
                  Expanded(child: _buildCanvasPanel(isTablet)),
                  // 오른쪽 — AI 미리보기 패널
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
                  style: TextStyle(fontSize: 11, color: Colors.grey[400])),
            ],
          ),
          const Spacer(),
          // 스텝 인디케이터
          _buildStepIndicator(isTablet),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
              Icon(Icons.arrow_forward, size: 14, color: Colors.grey[300]),
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
                Icon(Icons.info_outline, size: 14, color: Colors.grey[400]),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _selectedSentences.clear()),
                  child: Text('초기화',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[400])),
                ),
              ],
            ),
          ),
          // 보기 모드 드롭다운
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[200]!),
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      Text(_viewMode,
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF3D2C8D))),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down,
                          size: 14, color: Color(0xFF7E57C2)),
                    ],
                  ),
                ),
                const Spacer(),
                Text('총 ${_sentences.length}문장',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[400])),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          // 문장 목록
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _sentences.length,
              itemBuilder: (context, index) {
                final sentence = _sentences[index];
                final isSelected =
                    _selectedSentences.contains(sentence['index']);
                final typeColor = _getTypeColor(sentence['type']);

                return GestureDetector(
                  onTap: () => _toggleSentence(sentence['index']),
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? typeColor.withOpacity(0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: isSelected
                          ? Border.all(
                              color: typeColor.withOpacity(0.5), width: 1)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            sentence['text'],
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected
                                  ? const Color(0xFF3D2C8D)
                                  : Colors.grey[600],
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              height: 1.5,
                              decoration: isSelected
                                  ? TextDecoration.underline
                                  : null,
                              decorationColor: typeColor,
                              decorationThickness: 2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${index + 1}문장',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey[400]),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // 하단 범례
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F4FF),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _legendItem('장면', const Color(0xFFFFD600)),
                _legendItem('단어/문장', const Color(0xFF7E57C2)),
                _legendItem('대사', const Color(0xFF1E88E5)),
              ],
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.emoji_nature,
                        size: 20, color: Color(0xFF7E57C2)),
                    const SizedBox(width: 6),
                    const Text('어떤 부분을 바꾸고 싶나요?',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF7E57C2))),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '목록에서 바꾸고 싶은 부분을 클릭하거나\n드래그해서 선택해 보세요.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.info_outline,
                          size: 12, color: Color(0xFF7E57C2)),
                      SizedBox(width: 4),
                      Text('선택 도움말 보기',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF7E57C2))),
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

  Widget _legendItem(String label, Color color) {
    return Row(
      children: [
        Container(
            width: 10, height: 10,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      ],
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
          // 탭 바
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
                Icon(Icons.info_outline, size: 14, color: Colors.grey[400]),
                const Spacer(),
                // 그림 그리기 탭
                _canvasTab(Icons.edit, '그림 그리기', true),
                const SizedBox(width: 8),
                // 스티커 탭
                _canvasTab(Icons.star_outline, '스티커', false),
                const SizedBox(width: 16),
                // 되돌리기
                _iconBtn(Icons.undo, _undo),
                const SizedBox(width: 8),
                _iconBtn(Icons.redo, () {}),
                const SizedBox(width: 8),
                // 전체 지우기
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
          // 메인 영역 (도구 + 캔버스)
          Expanded(
            child: Row(
              children: [
                // 도구 버튼
                _buildToolbar(),
                // 캔버스
                Expanded(child: _buildCanvas()),
              ],
            ),
          ),
          // 색상 팔레트 + 굵기
          _buildColorBar(),
          // AI 미리보기 버튼
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
                      padding: const EdgeInsets.symmetric(vertical: 14),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          Icon(icon, size: 14, color: isActive ? Colors.white : Colors.grey[500]),
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

  // ── 도구 버튼 ──
  Widget _buildToolbar() {
    final tools = [
      {'icon': Icons.edit, 'label': '펜', 'isEraser': false},
      {'icon': Icons.auto_fix_high, 'label': '지우개', 'isEraser': true},
      {'icon': Icons.crop_free, 'label': '선택', 'isEraser': false},
      {'icon': Icons.search, 'label': '도형', 'isEraser': false},
      {'icon': Icons.text_fields, 'label': '텍스트', 'isEraser': false},
      {'icon': Icons.undo, 'label': '되돌리기', 'isEraser': false},
      {'icon': Icons.redo, 'label': '다시실행', 'isEraser': false},
    ];

    return Container(
      width: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: tools.map((tool) {
          final isActive = tool['isEraser'] == true
              ? _isEraser
              : tool['isEraser'] == false &&
                  tool['label'] == '펜' &&
                  !_isEraser;

          return GestureDetector(
            onTap: () {
              if (tool['label'] == '펜') {
                setState(() => _isEraser = false);
              } else if (tool['label'] == '지우개') {
                setState(() => _isEraser = true);
              } else if (tool['label'] == '되돌리기') {
                _undo();
              }
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

  // ── 캔버스 ──
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

  // ── 색상 팔레트 + 굵기 ──
  Widget _buildColorBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // 색상
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
          // 색상 추가
          Container(
            margin: const EdgeInsets.only(right: 16),
            width: 28, height: 28,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey[300]!)),
            child: Icon(Icons.add, size: 16, color: Colors.grey[400]),
          ),
          // 굵기
          Text('굵기', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          Expanded(
            child: Slider(
              value: _strokeWidth,
              min: 2, max: 30,
              activeColor: const Color(0xFF7E57C2),
              onChanged: (v) => setState(() => _strokeWidth = v),
            ),
          ),
          Text('${_strokeWidth.round()}px',
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
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
          // 패널 헤더
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
                  onTap: () => setState(() => _showPreviewPanel = false),
                  child: const Icon(Icons.close, size: 18, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // 탭 (미리보기 / AI와 이야기하기)
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
          // 탭 내용
          Expanded(
            child: _showPreviewTab
                ? _buildPreviewContent()
                : _buildChatContent(),
          ),
          // 하단 버튼
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7E57C2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('이대로 적용하기',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
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
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFF7E57C2)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('다시 그리기',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '⊙ 미리보기는 참고용으로, 실제 결과와 다를 수 있어요.',
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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

  // ── 미리보기 내용 ──
  Widget _buildPreviewContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 바뀌는 내용
          if (_selectedSentences.isNotEmpty) ...[
            Text('바뀌는 내용',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[500])),
            const SizedBox(height: 8),
            ..._selectedSentences.map((idx) {
              final sentence = _sentences.firstWhere(
                  (s) => s['index'] == idx,
                  orElse: () => {'text': ''});
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F4FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(sentence['text'],
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
                              fontSize: 12, color: Colors.grey[600])),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 14),
          ],
          // 새롭게 그려질 장면
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
                                fontSize: 12, color: Color(0xFF7E57C2))),
                      ],
                    ),
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    widget.taleBook.pages[widget.selectedPageIndex].imagePath,
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
                            color: widget.tale.cardColor.withOpacity(0.4)),
                      ),
                    ),
                  ),
                ),
          const SizedBox(height: 14),
          // 토끼 메시지
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
                              fontSize: 11, color: Colors.grey[600])),
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

  // ── AI 채팅 내용 ──
  Widget _buildChatContent() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              // 기본 AI 메시지
              _chatBubble('ai', '어때요? 마음에 드나요?\n더 바꾸고 싶은 점이 있으면 저에게 이야기해 주세요!'),
              ..._chatMessages.map((msg) => _chatBubble(
                    msg['role']!,
                    msg['text']!,
                  )),
            ],
          ),
        ),
        // 채팅 입력
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Colors.grey[200]!)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '원하는 수정 내용을 말해보세요...',
                    hintStyle:
                        TextStyle(fontSize: 12, color: Colors.grey[400]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey[200]!),
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
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send, size: 16, color: Colors.white),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isAI ? const Color(0xFFEDE7F6) : const Color(0xFF7E57C2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(text,
                style: TextStyle(
                    fontSize: 12,
                    color: isAI ? const Color(0xFF3D2C8D) : Colors.white,
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