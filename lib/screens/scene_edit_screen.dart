import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;

import 'fairy_tale_list_screen.dart';
import 'tale_reading_screen.dart';
import 'ai_result_screen.dart';

const String kOpenAiApiKey =
    'YOUR_OPENAI_API_KEY'; // ← 키 입력

class HighlightRange {
  final int start;
  final int end;
  final String text;
  HighlightRange({required this.start, required this.end, required this.text});
}

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
  final List<DrawingPath> _paths = [];
  DrawingPath? _currentPath;
  final GlobalKey _canvasKey = GlobalKey();

  Color _selectedColor = Colors.black;
  double _strokeWidth = 12.0;
  bool _isEraser = false;

  late String _fullText;
  final List<HighlightRange> _highlights = [];
  final TextEditingController _textController = TextEditingController();

  bool _showPreviewPanel = false;
  bool _isGenerating = false;
  bool _showPreviewTab = true;

  Uint8List? _generatedImageBytes;
  String? _aiErrorMessage;
  String? _regeneratedText; // ← 추가

  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, String>> _chatMessages = [];

  final List<Color> _colorPalette = [
    Colors.black,
    Color(0xFFE53935),
    Color(0xFFFF8F00),
    Color(0xFFFFD600),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Color(0xFF5E35B1),
    Color(0xFF795548),
    Color(0xFFEC407A),
  ];

  @override
  void initState() {
    super.initState();
    _initText();
  }

  void _initText() {
    final page = widget.taleBook.pages[widget.selectedPageIndex];
    _fullText = page.text;
    if (page.highlightText != null) _fullText += '\n${page.highlightText}';
    _textController.text = _fullText;
  }

  @override
  void dispose() {
    _chatController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _addHighlight(int start, int end) {
    if (start >= end) return;
    final selectedText = _fullText.substring(start, end);
    if (selectedText.trim().isEmpty) return;
    setState(() {
      _highlights.removeWhere(
        (h) =>
            (h.start <= start && h.end >= start) ||
            (h.start <= end && h.end >= end) ||
            (start <= h.start && end >= h.end),
      );
      _highlights.add(
        HighlightRange(start: start, end: end, text: selectedText),
      );
    });
  }

  void _removeHighlight(int index) =>
      setState(() => _highlights.removeAt(index));
  void _clearHighlights() => setState(() => _highlights.clear());

  void _clearCanvas() {
    setState(() {
      _paths.clear();
      _generatedImageBytes = null;
      _aiErrorMessage = null;
    });
  }

  void _undo() {
    if (_paths.isNotEmpty) {
      setState(() {
        _paths.removeLast();
        _generatedImageBytes = null;
      });
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  AI 핵심 로직
  // ══════════════════════════════════════════════════════════════

  Future<Uint8List> _captureCanvasAsPng() async {
    final boundary =
        _canvasKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw Exception('캔버스 이미지를 변환하지 못했어요.');
    return byteData.buffer.asUint8List();
  }

  // Step 1: GPT-4o Vision으로 낙서 분석 → DALL-E 프롬프트 생성
  Future<String> _analyzeSketchWithGPT(String sketchBase64) async {
    final storyText = widget.taleBook.pages[widget.selectedPageIndex].text;
    final selectedTexts = _highlights.map((h) => h.text).join(', ');
    final taleTitle = widget.tale.title;

    final response = await http
        .post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $kOpenAiApiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': 'gpt-4o',
            'max_tokens': 600,
            'messages': [
              {
                'role': 'system',
                'content':
                    'You are a children\'s book illustration expert. Look at the user\'s sketch and write a safe, child-friendly English image generation prompt. Output only the prompt, nothing else. Always describe cute friendly characters in watercolor storybook style with soft pastel colors.',
              },
              {
                'role': 'user',
                'content': [
                  {
                    'type': 'text',
                    'text':
                        'The user drew a sketch. IMPORTANT: You MUST identify exactly what shape or object is drawn in the sketch and make it the MAIN subject of the illustration. Do NOT replace the drawn shape with something else. If the user drew a heart, the heart must appear prominently. If they drew a star, the star must appear. Fairy tale context: $taleTitle - $storyText. ${selectedTexts.isNotEmpty ? "Elements to change: $selectedTexts." : ""} Write a child-friendly DALL-E prompt where the sketched shape/object is the central element.',
                  },
                  {
                    'type': 'image_url',
                    'image_url': {
                      'url': 'data:image/png;base64,$sketchBase64',
                      'detail': 'low',
                    },
                  },
                ],
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('GPT 분석 실패 (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body);
    return data['choices'][0]['message']['content'] as String;
  }

  Future<String> _regenerateTextWithGPT() async {
    if (_highlights.isEmpty) return _fullText;

    final highlightedTexts = _highlights.map((h) => h.text).join(', ');
    final taleTitle = widget.tale.title;

    final response = await http
        .post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $kOpenAiApiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': 'gpt-4o',
            'max_tokens': 300,
            'messages': [
              {
                'role': 'system',
                'content':
                    '너는 어린이 동화 작가야. 사용자가 선택한 부분을 창의적으로 재창작해줘. 원본 문장의 흐름을 유지하면서 선택한 부분만 새롭게 바꿔줘. 한국어로 답변해. 수정된 전체 문장만 출력해.',
              },
              {
                'role': 'user',
                'content':
                    '동화 제목: $taleTitle\n원본 내용: $_fullText\n바꾸고 싶은 부분: $highlightedTexts\n\n위 내용에서 선택한 부분을 창의적으로 재창작해서 전체 문장을 새롭게 써줘.',
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('텍스트 재창작 실패: ${response.body}');
    }

    final data = jsonDecode(response.body);
    return data['choices'][0]['message']['content'] as String;
  }

  // Step 2: DALL-E 3로 이미지 생성
  Future<Uint8List> _generateImageWithDallE(String prompt) async {
    final response = await http
        .post(
          Uri.parse('https://api.openai.com/v1/images/generations'),
          headers: {
            'Authorization': 'Bearer $kOpenAiApiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': 'gpt-image-1',
            'prompt':
                '''
High quality children's fairy tale illustration in the style of a modern animated storybook.
Cute anime-inspired characters with big expressive eyes, detailed fantasy backgrounds,
vibrant and rich colors, magical atmosphere, Disney/Pixar inspired art style,
beautifully detailed clothing and accessories, warm lighting with magical sparkles,
professional children's book illustration quality.
Scene: $prompt
Art style requirements:
- Bright vibrant colors (not pastel, more saturated and rich)
- Cute chibi-style characters with detailed features  
- Elaborate fantasy castle/magical background settings
- Magical glowing effects and sparkles
- High detail on clothing, accessories, and environment
- Cinematic composition suitable for a storybook page
- NO scary or dark elements, keep it magical and cheerful
''',
            'n': 1,
            'size': '1024x1024',
          }),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw Exception(
        'DALL-E 생성 실패 (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body);
    final b64 = data['data'][0]['b64_json'] as String;
    return base64Decode(b64);
  }

  // Step 3: 전체 흐름
  Future<void> _showPreview() async {
    if (_paths.isEmpty) {
      setState(() {
        _showPreviewPanel = true;
        _aiErrorMessage = '먼저 그림판에 장면을 그려주세요.';
      });
      return;
    }

    setState(() {
      _showPreviewPanel = true;
      _showPreviewTab = true;
      _isGenerating = true;
      _aiErrorMessage = null;
      _generatedImageBytes = null;
    });

    try {
      // 1. 캔버스 캡처
      final pngBytes = await _captureCanvasAsPng();
      final sketchBase64 = base64Encode(pngBytes);

      // 2. 이미지 생성 + 텍스트 재창작 동시 실행
      final results = await Future.wait([
        _analyzeSketchWithGPT(
          sketchBase64,
        ).then((prompt) => _generateImageWithDallE(prompt)),
        _regenerateTextWithGPT(),
      ]);

      setState(() {
        _generatedImageBytes = results[0] as Uint8List;
        _regeneratedText = results[1] as String;
        _isGenerating = false;
      });
    } catch (e) {
      debugPrint('AI 에러: $e');
      setState(() {
        _isGenerating = false;
        _aiErrorMessage = 'AI 생성 중 오류가 발생했어요.\n$e';
      });
    }
  }

  void _sendChat() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _chatMessages.add({'role': 'user', 'text': text});
      _chatController.clear();
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _chatMessages.add({'role': 'ai', 'text': '좋아요! 반영해서 다시 그려볼게요 ✨'});
      });
      _regenerateWithFeedback(text);
    });
  }

  Future<void> _regenerateWithFeedback(String feedback) async {
    setState(() {
      _isGenerating = true;
      _generatedImageBytes = null;
      _aiErrorMessage = null;
    });
    try {
      final pngBytes = await _captureCanvasAsPng();
      final sketchBase64 = base64Encode(pngBytes);
      final basePrompt = await _analyzeSketchWithGPT(sketchBase64);
      final imageBytes = await _generateImageWithDallE(
        '$basePrompt Additionally: $feedback',
      );
      setState(() {
        _generatedImageBytes = imageBytes;
        _isGenerating = false;
      });
      if (mounted)
        setState(
          () => _chatMessages.add({'role': 'ai', 'text': '새로 그렸어요! 어때요? 😊'}),
        );
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _aiErrorMessage = e.toString();
        _chatMessages.add({'role': 'ai', 'text': '앗, 실패했어요. 다시 시도해주세요.'});
      });
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  UI (원본 코드와 동일 + 변경된 부분만 표시)
  // ══════════════════════════════════════════════════════════════

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

  Widget _buildHeader(BuildContext context, bool isTablet) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 24 : 16,
        vertical: 12,
      ),
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
              child: const Icon(
                Icons.chevron_left,
                color: Color(0xFF7E57C2),
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '장면 수정하기',
                style: TextStyle(
                  fontSize: isTablet ? 18 : 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF3D2C8D),
                ),
              ),
              Text(
                '선택한 장면을 그림으로 그리고, 바꾸고 싶은 내용을 적어주세요.',
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
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
            child: const Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 14,
                  color: Color(0xFF7E57C2),
                ),
                SizedBox(width: 4),
                Text(
                  '수정 가이드',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7E57C2),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
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
        final isDone = index < 2;
        final isCurrent = index == 2;
        return Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isDone || isCurrent
                    ? const Color(0xFF7E57C2)
                    : Colors.grey[300],
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isCurrent ? Colors.white : Colors.grey[500],
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 4),
            if (isTablet)
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                  color: isCurrent ? const Color(0xFF7E57C2) : Colors.grey[400],
                ),
              ),
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
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                const Text(
                  '바꾸고 싶은 내용 선택',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3D2C8D),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.info_outline, size: 14, color: Colors.grey[400]),
                const Spacer(),
                GestureDetector(
                  onTap: _clearHighlights,
                  child: Text(
                    '초기화',
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _highlights.isEmpty
                    ? const Color(0xFFF8F4FF)
                    : const Color(0xFFEDE7F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _highlights.isEmpty ? Icons.info_outline : Icons.highlight,
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
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFFFE082),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.touch_app,
                          size: 14,
                          color: Color(0xFFFF8F00),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '바꾸고 싶은 단어나 문장을 드래그해서 선택하세요!',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange[800],
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildHighlightedText(),
                  if (_highlights.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      '선택한 구간',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[500],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._highlights.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final h = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD600).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFFFD600).withOpacity(0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '"${h.text}"',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF3D2C8D),
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _removeHighlight(idx),
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.grey[400],
                              ),
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFFEDE7F6),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.emoji_nature,
                  size: 20,
                  color: Color(0xFF7E57C2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '드래그로 단어나 문장을\n선택해 하이라이트해요!',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
            if (selection.start >= 0 && selection.end > selection.start)
              _addHighlight(selection.start, selection.end);
          }
        },
      );
    }

    final List<TextSpan> spans = [];
    final sortedHighlights = List<HighlightRange>.from(_highlights)
      ..sort((a, b) => a.start.compareTo(b.start));
    int currentIndex = 0;
    for (final h in sortedHighlights) {
      if (h.start > currentIndex)
        spans.add(
          TextSpan(
            text: _fullText.substring(currentIndex, h.start),
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF3D2C8D),
              height: 1.9,
            ),
          ),
        );
      spans.add(
        TextSpan(
          text: _fullText.substring(h.start, h.end),
          style: TextStyle(
            fontSize: 14,
            color: const Color(0xFF3D2C8D),
            height: 1.9,
            fontWeight: FontWeight.w600,
            backgroundColor: const Color(0xFFFFD600).withOpacity(0.5),
          ),
        ),
      );
      currentIndex = h.end;
    }
    if (currentIndex < _fullText.length)
      spans.add(
        TextSpan(
          text: _fullText.substring(currentIndex),
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF3D2C8D),
            height: 1.9,
          ),
        ),
      );

    return SelectableText.rich(
      TextSpan(children: spans),
      onSelectionChanged: (selection, cause) {
        if (cause == SelectionChangedCause.longPress ||
            cause == SelectionChangedCause.drag) {
          if (selection.start >= 0 && selection.end > selection.start)
            _addHighlight(selection.start, selection.end);
        }
      },
    );
  }

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
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                const Text(
                  '새롭게 그리고 싶은 장면을 그려주세요!',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3D2C8D),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.info_outline, size: 14, color: Colors.grey[400]),
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
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[200]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 14,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '전체 지우기',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
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
                    onPressed: _isGenerating ? null : _showPreview,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7E57C2),
                      disabledBackgroundColor: const Color(
                        0xFF7E57C2,
                      ).withOpacity(0.5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isGenerating)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        else
                          const Icon(Icons.auto_awesome, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _isGenerating ? 'AI가 그리고 있어요...' : 'AI로 수정 결과 미리보기',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'AI가 새롭게 그린 장면과 내용을 미리 보여드려요!',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
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
          color: isActive ? const Color(0xFF7E57C2) : Colors.grey[200]!,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: isActive ? Colors.white : Colors.grey[500],
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isActive ? Colors.white : Colors.grey[500],
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[200]!),
          borderRadius: BorderRadius.circular(8),
        ),
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
          final label = tool['label'] as String;
          final isActive =
              label == '펜' && !_isEraser || label == '지우개' && _isEraser;
          return GestureDetector(
            onTap: () {
              if (label == '펜') setState(() => _isEraser = false);
              if (label == '지우개') setState(() => _isEraser = true);
              if (label == '되돌리기') _undo();
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              width: 44,
              height: 52,
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFFEDE7F6) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    tool['icon'] as IconData,
                    size: 20,
                    color: isActive
                        ? const Color(0xFF7E57C2)
                        : Colors.grey[500],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 9,
                      color: isActive
                          ? const Color(0xFF7E57C2)
                          : Colors.grey[400],
                    ),
                  ),
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
      child: RepaintBoundary(
        key: _canvasKey,
        child: Container(
          color: Colors.white,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque, // ← 이게 핵심
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
      ),
    );
  }

  Widget _buildColorBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          ..._colorPalette.map((color) {
            final isSelected = _selectedColor == color && !_isEraser;
            return GestureDetector(
              onTap: () => setState(() {
                _selectedColor = color;
                _isEraser = false;
              }),
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF7E57C2)
                        : Colors.grey[300]!,
                    width: isSelected ? 2.5 : 1,
                  ),
                ),
              ),
            );
          }),
          Container(
            margin: const EdgeInsets.only(right: 16),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Icon(Icons.add, size: 16, color: Colors.grey[400]),
          ),
          Text('굵기', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          Expanded(
            child: Slider(
              value: _strokeWidth,
              min: 2,
              max: 30,
              activeColor: const Color(0xFF7E57C2),
              onChanged: (v) => setState(() => _strokeWidth = v),
            ),
          ),
          Text(
            '${_strokeWidth.round()}px',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

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
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              children: [
                const Text(
                  '수정 결과 미리보기',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3D2C8D),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _showPreviewPanel = false),
                  child: const Icon(Icons.close, size: 18, color: Colors.grey),
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
                    onPressed: _generatedImageBytes == null
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AIResultScreen(
                                  tale: widget.tale,
                                  taleBook: widget.taleBook,
                                  editedPageIndex: widget.selectedPageIndex,
                                  generatedImageBytes:
                                      _generatedImageBytes, // ← 추가
                                  regeneratedText: _regeneratedText, // ← 추가
                                ),
                              ),
                            );
                          },

                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7E57C2),
                      disabledBackgroundColor: Colors.grey[300],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      '이대로 적용하기',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _showPreviewPanel = false;
                      _paths.clear();
                      _generatedImageBytes = null;
                      _aiErrorMessage = null;
                    }),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF7E57C2),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFF7E57C2)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '다시 그리기',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
            color: isActive ? const Color(0xFF7E57C2) : Colors.grey[200]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? Colors.white : Colors.grey[500],
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
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
            Text(
              '바뀌는 내용',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 8),
            ..._highlights.map(
              (h) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F4FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '"${h.text}"',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7E57C2),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward,
                      size: 14,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _regeneratedText != null
                          ? Text(
                              _regeneratedText!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF3D2C8D),
                                fontWeight: FontWeight.w600,
                                height: 1.5,
                              ),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            )
                          : Text(
                              _isGenerating ? '재창작 중...' : 'AI가 새롭게 바꿔드릴게요!',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            '새롭게 그려질 장면',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 8),
          _buildGeneratedImageBox(),
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
                const Icon(
                  Icons.emoji_nature,
                  size: 20,
                  color: Color(0xFF7E57C2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '어때요? 마음에 드나요?',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF7E57C2),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '더 바꾸고 싶은 점이 있으면 저에게 이야기해 주세요!',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
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

  Widget _buildGeneratedImageBox() {
    if (_isGenerating) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFFF8F4FF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Color(0xFF7E57C2),
                strokeWidth: 2,
              ),
              SizedBox(height: 12),
              Text(
                'AI가 그림을 분석하고 있어요...',
                style: TextStyle(fontSize: 12, color: Color(0xFF7E57C2)),
              ),
              SizedBox(height: 4),
              Text(
                '약 20~40초 소요됩니다',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }
    if (_aiErrorMessage != null) {
      return Container(
        height: 180,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEE),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                _aiErrorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _showPreview,
                child: const Text(
                  '다시 시도하기',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF7E57C2),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_generatedImageBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          _generatedImageBytes!,
          fit: BoxFit.cover,
          width: double.infinity,
        ),
      );
    }
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Text(
          '아직 생성된 이미지가 없어요.',
          style: TextStyle(fontSize: 12, color: Color(0xFF7E57C2)),
        ),
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
              _chatBubble('ai', '어때요? 마음에 드나요?\n더 바꾸고 싶은 점이 있으면 저에게 이야기해 주세요!'),
              ..._chatMessages.map(
                (msg) => _chatBubble(msg['role']!, msg['text']!),
              ),
            ],
          ),
        ),
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
                    hintText: '예) 더 밝게, 공주를 크게, 배경을 숲으로...',
                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey[200]!),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => _sendChat(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _sendChat,
                child: Container(
                  width: 36,
                  height: 36,
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
        mainAxisAlignment: isAI
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isAI) ...[
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: Color(0xFFEDE7F6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.emoji_nature,
                size: 16,
                color: Color(0xFF7E57C2),
              ),
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
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: isAI ? const Color(0xFF3D2C8D) : Colors.white,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
      for (int i = 1; i < path.points.length; i++)
        drawPath.lineTo(path.points[i].dx, path.points[i].dy);
      canvas.drawPath(drawPath, paint);
    }
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) => true;
}
