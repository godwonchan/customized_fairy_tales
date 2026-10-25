// lib/screens/creation/story_preview_screen.dart
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'custom_story_create_screen.dart' show ChatRole, QuickReply;
import 'lumi_chat_controller.dart';
import 'lumi_chat_panel.dart';
import 'story_reader_screen.dart';
import '../../theme/app_theme.dart';

class StoryPreviewScreen extends StatefulWidget {
  final Map<String, Uint8List?> assetPngBytes;
  final Map<String, bool> aiDelegated;
  final Map<String, Map<String, String>> assetDescriptions;
  final List<Map<String, String>>? storyNotes; // 🎯 [추가!] 아이와 루미의 대화 메모 수신
  final Map<String, dynamic>? cachedStoryData;
  final String? taleId;

  const StoryPreviewScreen({
    super.key,
    required this.assetPngBytes,
    required this.aiDelegated,
    required this.assetDescriptions,
    this.storyNotes, // 🎯 [추가]
    this.cachedStoryData,
    this.taleId,
  });

  @override
  State<StoryPreviewScreen> createState() => _StoryPreviewScreenState();
}

class _StoryPreviewScreenState extends State<StoryPreviewScreen> {
  static const String _baseUrl = 'http://localhost:8000';
  static const String _lumiImagePath = CrayongImages.wink;
  static const int _minPageCount = 1;

  // 그리기 화면과 같은 색
  static const Color _purple = AppColors.secondaryDark;
  static const Color _purpleDark = Color(0xFF457A36);
  static const Color _ink = AppColors.textPrimary;
  static const Color _sub = AppColors.textSecondary;
  static const Color _cardLine = AppColors.border;
  static const Color _cardEdge = Color(0xFFE6D3AE);
  static const Color _bg = AppColors.background;

  bool _isGenerating = false;
  int _pageCount = 4;
  final TextEditingController _feedbackController = TextEditingController();

  // 아이가 직접 고치는 중인 곳 (null: 없음, -1: 동화 제목, 0 이상: 그 화)
  int? _editingIndex;
  final TextEditingController _editTitleCtrl = TextEditingController();
  final TextEditingController _editContentCtrl = TextEditingController();
  final LumiChatController _lumi = LumiChatController();
  int _seenLumiCount = 0; // 대화 시트에서 이미 본 메시지 수

  // STT 음성 인식
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  String _storyTitle = '크레용이 동화를 짓고 있어...';
  List<Map<String, dynamic>> _storyPages = [];

  bool get _hasStory => _storyPages.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _initSpeech();

    // 💡 더미 데이터("신나는 모험 이야기")가 아닌 유효한 캐시가 있을 때만 재사용
    final bool isDummyFallback = widget.cachedStoryData?['title'] == '신나는 모험 이야기' ||
        widget.cachedStoryData?['title'] == '신나는 모험';

    if (widget.cachedStoryData != null && !isDummyFallback) {
      _storyTitle = widget.cachedStoryData!['title'] ?? '우리가 만든 동화 이야기';
      _storyPages = List<Map<String, dynamic>>.from(widget.cachedStoryData!['pages'] ?? []);
      // 그림 화면에 다녀오기 전에 그려 둔 이미지 복원 (서명이 같은 페이지만 재사용됨)
      _pageImages.addAll(Map<int, String>.from(widget.cachedStoryData!['pageImages'] ?? {}));
      _pageImageSignatures.addAll(Map<int, String>.from(widget.cachedStoryData!['pageImageSignatures'] ?? {}));
      if (_storyPages.isNotEmpty) _pageCount = _storyPages.length;
      _lumi.addLumi('전에 만든 줄거리를 가져왔어!\n고치고 싶은 곳이 있으면 말하거나 써 줘');
    } else {
      // 🎯 더미 캐시이거나 처음 진입 시: 화 수를 고른 뒤 줄거리 생성
      _lumi.addLumi('몇 화짜리 동화로 만들까?\n위에서 고르고 "줄거리 만들기"를 눌러 줘!');
    }
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    _editTitleCtrl.dispose();
    _editContentCtrl.dispose();
    _lumi.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (val) => debugPrint('STT 오류: $val'),
        onStatus: (val) => debugPrint('STT 상태: $val'),
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('STT 초기화 실패: $e');
    }
  }

  void _toggleFeedbackListening() async {
    if (!_speechAvailable) {
      await _initSpeech();
    }
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('마이크 권한을 확인해 줘!')),
      );
      return;
    }

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);

      await _speech.listen(
        localeId: 'ko_KR',
        onResult: (result) {
          setState(() {
            _feedbackController.text = result.recognizedWords;
            if (result.finalResult) {
              _isListening = false;
            }
          });
        },
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  🌐 백엔드 FastAPI gpt-5.5 줄거리 생성 API 호출
  // ═══════════════════════════════════════════════════════════════
  Future<void> _fetchRealStory({String? feedback}) async {
    _stopListening();
    setState(() {
      _isGenerating = true;
      _editingIndex = null; // 이야기가 새로 바뀌므로 고치던 내용은 닫음
    });
    _lumi.setQuickReplies([]); // 이전 이야기에 대한 질문 버튼도 치움
    _lumi.setThinking(true);

    Map<String, dynamic>? previousStoryPayload;
    if (feedback != null && _storyPages.isNotEmpty) {
      previousStoryPayload = {
        'title': _storyTitle,
        'pages': _storyPages,
      };
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/story/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'asset_descriptions': widget.assetDescriptions,
          'story_notes': widget.storyNotes ?? [], // 🎯 아이와 루미가 나눈 대화 기록 전송!
          'feedback': feedback,
          'previous_story': previousStoryPayload,
          'page_count': _pageCount,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _storyTitle = data['title'] ?? '우리가 만든 동화 이야기';
          final List pagesRaw = data['pages'] ?? [];
          final oldPages = _storyPages;
          _storyPages = pagesRaw.map((p) => {
            'page': '${p['page']}화',
            'title': p['title'] ?? '',
            'content': p['content'] ?? '',
            'layout_type': p['layout_type'] ?? 'single',
            'prompt': p['visual_scene_prompt'] ?? '',
            'characters': List<String>.from(p['characters'] ?? []),
          }).toList();
          // 다시 지어도 본문이 그대로인 화는 장면 설명을 이어받아, 그 화 그림을 다시 그리지 않게 함
          for (int i = 0; i < _storyPages.length && i < oldPages.length; i++) {
            if (_storyPages[i]['content'] == oldPages[i]['content'] && oldPages[i]['scene_source'] != null) {
              for (final key in ['layout_type', 'prompt', 'characters', 'scene_source']) {
                _storyPages[i][key] = oldPages[i][key];
              }
            }
          }
          _isGenerating = false;
        });

        _lumi.setThinking(false);
        _lumi.addLumi(feedback != null
            ? '다 고쳤어! 새 줄거리를 읽어 봐'
            : '줄거리가 완성됐어!\n고치고 싶은 곳이 있으면 말하거나 써 줘');
      } else {
        throw Exception('서버 응답 에러: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('줄거리 생성 에러: $e');
      setState(() {
        _isGenerating = false;
        _storyTitle = '신비한 마법 모험 이야기';
        _storyPages = [
          {'page': '1화', 'title': '새로운 출발', 'content': '용감한 친구들이 함께 모여 신비한 비밀의 장소로 떠났어요!'},
          {'page': '2화', 'title': '마법의 힘', 'content': '위험한 순간이 찾아왔지만, 소중한 도구로 힘을 합쳐 이겨냈답니다.'},
          {'page': '3화', 'title': '모두의 축제', 'content': '마을 친구들과 함께 맛있는 간식을 나누며 행복한 파티를 열었어요!'},
        ];
      });
      _lumi.setThinking(false);
      _lumi.addLumi('앗, 이야기를 짓다가 문제가 생겼어\n위의 다시 짓기 버튼으로 다시 지어 볼래?');
    }
  }

  void _applyFeedback() {
    final prompt = _feedbackController.text.trim();
    if (prompt.isEmpty || _isGenerating || !_hasStory) return;

    if (_isListening) {
      _speech.stop();
      _isListening = false;
    }

    _lumi.addChild(prompt);
    _fetchRealStory(feedback: prompt);
    _feedbackController.clear();
  }

  // ── ✏️ 줄거리 직접 고치기 ──
  void _stopListening() {
    _dictationCtrl?.removeListener(_watchDictationCaret);
    _dictationCtrl = null;
    if (!_isListening) return;
    _speech.stop();
    setState(() => _isListening = false);
  }

  void _startEdit(int index) {
    _stopListening();
    setState(() {
      _editingIndex = index;
      if (index < 0) {
        _editTitleCtrl.text = _storyTitle;
      } else {
        _editTitleCtrl.text = _storyPages[index]['title'] ?? '';
        _editContentCtrl.text = _storyPages[index]['content'] ?? '';
      }
    });
  }

  void _cancelEdit() {
    _stopListening();
    setState(() => _editingIndex = null);
  }

  void _saveEdit() {
    final index = _editingIndex;
    if (index == null) return;
    _stopListening();
    final title = _editTitleCtrl.text.trim();
    final content = _editContentCtrl.text.trim();
    bool changed;
    if (index < 0) {
      changed = title.isNotEmpty && title != _storyTitle;
      setState(() {
        if (changed) _storyTitle = title;
        _editingIndex = null;
      });
      if (changed) _lumi.addLumi('"$title"! 멋진 제목이다');
    } else {
      final page = _storyPages[index];
      final oldContent = (page['content'] ?? '').toString();
      final contentChanged = content.isNotEmpty && content != oldContent;
      final wasSceneFresh = !_needsScene(index);
      changed = title != (page['title'] ?? '') || contentChanged;
      setState(() {
        page['title'] = title;
        if (content.isNotEmpty) page['content'] = content;
        _editingIndex = null;
      });
      if (changed) _lumi.addLumi('네가 고친 ${index + 1}화 정말 좋다!');
      if (contentChanged) _checkEdit(index, oldContent, wasSceneFresh);
    }
  }

  // 고친 본문을 AI가 살펴봄
  // - 다른 화와 어긋나는 변경(조연·캐릭터 바꿈)이면 루미가 다른 화에도 반영할지 물어봄
  // - 그림과 상관없는 변경(오타·말투)이면 기존 장면 설명을 그대로 써서 다시 그리지 않음
  // (판단에 실패하면 묻지 않고, 그 화만 다시 그리는 기본 동작)
  Future<void> _checkEdit(int index, String oldContent, bool wasSceneFresh) async {
    final page = _storyPages[index];
    final newContent = (page['content'] ?? '').toString();
    _lumi.setThinking(true);
    Map<String, dynamic>? result;
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/story/check_edit'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'page': index + 1,
          'old_content': oldContent,
          'new_content': newContent,
          'other_pages': [
            for (int i = 0; i < _storyPages.length; i++)
              if (i != index) {'page': i + 1, 'content': _storyPages[i]['content'] ?? ''},
          ],
        }),
      );
      if (res.statusCode == 200) result = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (e) {
      debugPrint('직접 수정 판단 에러: $e');
    }
    if (!_isGenerating) _lumi.setThinking(false);

    // 그사이 이야기를 새로 지었거나 같은 화를 또 고쳤으면 이 판단은 버림
    if (!mounted || result == null) return;
    if (index >= _storyPages.length || !identical(_storyPages[index], page) || page['content'] != newContent) return;

    if (result['changes_picture'] == false && wasSceneFresh) {
      page['scene_source'] = _sceneSource(page);
    }
    final suggestion = (result['suggestion'] ?? '').toString().trim();
    if (result['affects_other_pages'] == true && suggestion.isNotEmpty) {
      _lumi.addLumi('다른 화에도 $suggestion 바꿔 줄까?');
      _lumi.setQuickReplies([
        QuickReply(label: '바꿔 줘', primary: true, onTap: () => _applyEditToOtherPages(index, suggestion)),
        QuickReply(
          label: '이 화만',
          onTap: () {
            _lumi.addChild('이 화만!');
            _lumi.addLumi('알겠어! ${index + 1}화만 바꿀게');
          },
        ),
      ]);
    }
  }

  void _applyEditToOtherPages(int index, String suggestion) {
    if (_isGenerating) return;
    _lumi.addChild('바꿔 줘!');
    setState(() => _pageCount = _storyPages.length); // 화 수는 그대로
    _fetchRealStory(
      feedback: '아이가 ${index + 1}화를 직접 고쳤어($suggestion). 다른 화에도 이 변경을 똑같이 반영해 줘. '
          '${index + 1}화는 아이가 고친 그대로 두고, 나머지 내용도 최대한 그대로 유지해 줘.',
    );
  }

  // 받아쓴 말을 커서 자리에 끼워 넣음 (커서가 없으면 끝에 덧붙임, 말하는 동안 그 자리만 계속 갈아 끼움)
  Future<void> _toggleEditListening(TextEditingController ctrl) async {
    if (!_speechAvailable) await _initSpeech();
    if (!mounted) return;
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('마이크 권한을 확인해 줘!')),
      );
      return;
    }
    if (_isListening) {
      _stopListening();
      return;
    }

    final text = ctrl.text;
    final sel = ctrl.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final before = text.substring(0, start);
    final after = text.substring(end);
    final pre = before.isEmpty || before.endsWith(' ') || before.endsWith('\n') ? '' : ' ';
    final post = after.isEmpty || after.startsWith(' ') || after.startsWith('\n') ? '' : ' ';

    _dictationCtrl = ctrl;
    _dictationCaret = sel;
    ctrl.addListener(_watchDictationCaret);
    setState(() => _isListening = true);
    await _speech.listen(
      localeId: 'ko_KR',
      onResult: (result) {
        if (_dictationCtrl != ctrl) return; // 이미 멈춘 받아쓰기의 늦게 온 결과는 버림
        final words = result.recognizedWords;
        final inserted = words.isEmpty ? '' : '$pre$words$post';
        final caret = TextSelection.collapsed(offset: before.length + inserted.length);
        _dictationCaret = caret; // 아래 값 변경은 아이가 옮긴 커서가 아님
        setState(() => ctrl.value = TextEditingValue(text: '$before$inserted$after', selection: caret));
        if (result.finalResult) _stopListening();
      },
    );
  }

  // 받아쓰는 도중 아이가 커서를 옮기거나 직접 타이핑하면 받아쓰기를 멈춤
  // (받아쓴 말은 남고, 옮긴 자리에서 마이크를 다시 누르면 거기서 이어짐)
  TextEditingController? _dictationCtrl;
  TextSelection? _dictationCaret;

  void _watchDictationCaret() {
    final ctrl = _dictationCtrl;
    final caret = _dictationCaret;
    if (ctrl == null || caret == null) return;
    if (ctrl.selection.baseOffset != caret.baseOffset || ctrl.selection.extentOffset != caret.extentOffset) {
      _stopListening();
    }
  }

  void _changePageCount(int delta) {
    final next = _pageCount + delta;
    if (_isGenerating || next < _minPageCount) return;
    setState(() => _pageCount = next);
  }

  // 줄거리가 이미 있으면 기존 줄거리를 바탕으로 화 수만 늘리거나 줄임
  void _applyPageCount() {
    _lumi.addChild('$_pageCount화로 바꿔 줘!');
    _fetchRealStory(
      feedback: '지금 이야기를 살려서 전체 $_pageCount화로 늘리거나 줄여 줘. '
          '한 화는 3~4문장을 꼭 지키고, 줄일 때는 덜 중요한 장면을 빼서 줄여 줘.',
    );
  }

  void _popWithStoryData() {
    if (_storyPages.isNotEmpty) {
      Navigator.pop(context, {
        'title': _storyTitle,
        'pages': _storyPages,
        'pageImages': _pageImages,
        'pageImageSignatures': _pageImageSignatures,
      });
    } else {
      Navigator.pop(context);
    }
  }

  ThemeData _kidsTheme(BuildContext context) {
    final base = Theme.of(context);
    final String? kidsFont = GoogleFonts.gothicA1().fontFamily;
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: kidsFont, bodyColor: _ink, displayColor: _ink),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: kidsFont),
    );
  }

  BoxDecoration _card({double radius = 24, Color color = Colors.white, Color edge = _cardEdge}) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _cardLine, width: 2),
      boxShadow: [BoxShadow(color: edge, offset: const Offset(0, 4))],
    );
  }

  // 폭 390 폰을 기준(1배)으로 화면의 짧은 쪽 길이에 비례해 키움 (가로로 돌려도 그대로)
  double _uiScale(BuildContext context) =>
      (MediaQuery.sizeOf(context).shortestSide / 390).clamp(0.9, 1.4);

  // 기준 크기로 그린 화면을 실제 크기에 맞게 통째로 확대·축소 (글자·버튼·여백·터치 영역 모두 같은 비율)
  Widget _scaledToFit(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mq = MediaQuery.of(context);
        final scale = _uiScale(context);
        return FittedBox(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: constraints.maxWidth / scale,
            height: constraints.maxHeight / scale,
            // 안쪽에서 보는 화면 크기·안전 영역·키보드 높이도 기준 크기로 환산
            child: MediaQuery(
              data: mq.copyWith(
                size: mq.size / scale,
                padding: mq.padding / scale,
                viewPadding: mq.viewPadding / scale,
                viewInsets: mq.viewInsets / scale,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }

  static const Size _lumiWindowSize = Size(340, 420);
  static const double _lumiButtonSize = 64;

  // 창·버튼이 화면 밖으로 나가지 않게 (키보드가 올라와 화면이 줄면 그만큼 위로 밀림)
  Offset _keepInside(Size area, Size box, Offset p) {
    return Offset(
      p.dx.clamp(8.0, math.max(8.0, area.width - box.width - 8)),
      p.dy.clamp(8.0, math.max(8.0, area.height - box.height - 8)),
    );
  }

  void _closeLumiWindow() {
    _lumi.setOpen(false);
    setState(() => _seenLumiCount = _lumi.messages.length);
  }

  // 줄거리 화면 위에 떠 있는 루미 (접히면 얼굴 버튼, 펼치면 대화 창 / 둘 다 끌어서 옮김)
  Widget _buildLumiLayer(Size area) {
    // 직접 고치는 동안에는 저장 버튼 등을 가리지 않게 숨김 (그동안 루미 입력도 막혀 있음)
    if (_editingIndex != null) return const SizedBox.shrink();
    if (_lumi.isOpen) {
      final size = Size(
        math.min(_lumiWindowSize.width, area.width - 16),
        math.min(_lumiWindowSize.height, area.height - 16),
      );
      final pos = _keepInside(
        area,
        size,
        _lumi.windowPosition ?? Offset(area.width - size.width - 12, area.height - size.height - 86),
      );
      return Stack(
        children: [
          Positioned(
            left: pos.dx,
            top: pos.dy,
            width: size.width,
            height: size.height,
            child: _buildLumiWindow(area, size, pos),
          ),
        ],
      );
    }

    const size = Size(_lumiButtonSize, _lumiButtonSize);
    final pos = _keepInside(
      area,
      size,
      _lumi.buttonPosition ?? Offset(area.width - _lumiButtonSize - 16, area.height - _lumiButtonSize - 86),
    );
    final unread = _lumi.messages.skip(_seenLumiCount).where((m) => m.role == ChatRole.lumi).toList();
    final bool bubbleOnLeft = pos.dx + _lumiButtonSize / 2 > area.width / 2;
    return Stack(
      children: [
        // 닫혀 있는 동안 루미가 새로 한 말은 말풍선 미리보기로 알림
        if (unread.isNotEmpty)
          Positioned(
            top: pos.dy,
            left: bubbleOnLeft ? null : pos.dx + _lumiButtonSize + 8,
            right: bubbleOnLeft ? area.width - pos.dx + 8 : null,
            child: GestureDetector(
              onTap: () => _lumi.setOpen(true),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 220),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: _card(radius: 18),
                child: Text(
                  unread.last.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, height: 1.35, color: _ink),
                ),
              ),
            ),
          ),
        Positioned(
          left: pos.dx,
          top: pos.dy,
          child: GestureDetector(
            onTap: () => _lumi.setOpen(true),
            onPanUpdate: (d) => _lumi.moveButton(_keepInside(area, size, (_lumi.buttonPosition ?? pos) + d.delta)),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: _purpleDark, offset: Offset(0, 4))],
                  ),
                  child: _buildLumiAvatar(_lumiButtonSize),
                ),
                if (unread.isNotEmpty)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5252),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLumiWindow(Size area, Size size, Offset pos) {
    return Container(
      decoration: _card(color: const Color(0xFFF8F6FF), edge: _purpleDark),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          children: [
            // 제목줄을 끌어서 창을 옮김
            GestureDetector(
              onPanUpdate: (d) => _lumi.moveWindow(_keepInside(area, size, (_lumi.windowPosition ?? pos) + d.delta)),
              child: Container(
                color: _purple,
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                child: Row(
                  children: [
                    _buildLumiAvatar(36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('크레용', style: AppTextStyles.headingSmall(color: Colors.white)),
                    ),
                    IconButton(
                      tooltip: '접기',
                      icon: const Icon(Icons.close_fullscreen_rounded, color: Colors.white, size: 24),
                      onPressed: _closeLumiWindow,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: LumiChatPanel(
                controller: _lumi,
                inputController: _feedbackController,
                enabled: _hasStory && !_isGenerating && _editingIndex == null,
                isListening: _isListening && _editingIndex == null,
                hintText: '어떻게 고쳐 줄까?',
                onSend: _applyFeedback,
                onMicTap: _toggleFeedbackListening,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _kidsTheme(context),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _popWithStoryData();
        },
        child: _scaledToFit(Scaffold(
          backgroundColor: _bg,
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    _buildTopBar(),
                    _buildStepBar(),
                    _buildPageCountPicker(),
                    Expanded(child: _buildStoryArea()),
                    _buildBottomButtons(),
                  ],
                ),
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) => ListenableBuilder(
                      listenable: _lumi,
                      builder: (context, _) => _buildLumiLayer(constraints.biggest),
                    ),
                  ),
                ),
              ],
            ),
          ),
        )),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            iconSize: 26,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _ink),
            onPressed: _popWithStoryData,
          ),
          Expanded(
            child: Text('줄거리 만들기', textAlign: TextAlign.center, style: AppTextStyles.headingLarge()),
          ),
          IconButton(
            tooltip: '이야기 다시 짓기',
            iconSize: 28,
            icon: const Icon(Icons.refresh_rounded, color: _purple),
            onPressed: _isGenerating || !_hasStory ? null : () => _fetchRealStory(),
          ),
        ],
      ),
    );
  }

  // ① 몇 화? → ② 줄거리 보기 → ③ 고치기
  Widget _buildStepBar() {
    final bool asked = _lumi.messages.any((m) => m.role == ChatRole.child);
    final int current = !_hasStory ? 0 : (asked ? 2 : 1);
    const labels = ['몇 화?', '줄거리 보기', '고치기'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++) ...[
            if (i > 0)
              Expanded(child: Container(height: 3, color: i <= current ? _purple : _cardLine)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: i <= current ? _purple : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: i <= current ? _purple : _cardLine, width: 2),
              ),
              child: Text(
                '${i + 1}. ${labels[i]}',
                style: TextStyle(fontSize: 13, color: i <= current ? Colors.white : _sub),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPageCountPicker() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          // 좁은 폰에서 '바꾸기' 버튼이 생겨도 넘치지 않도록 글자가 줄바꿈되게 함
          Expanded(child: Text('몇 화로 만들까?', style: AppTextStyles.headingSmall())),
          _buildStepButton(Icons.remove_rounded, _pageCount > _minPageCount ? () => _changePageCount(-1) : null),
          SizedBox(
            width: 64,
            child: Text('$_pageCount화', textAlign: TextAlign.center, style: AppTextStyles.headingLarge()),
          ),
          _buildStepButton(Icons.add_rounded, () => _changePageCount(1)),
          // 줄거리가 있을 때 화 수를 바꾸면 눌러서 적용 (누를 때마다 다시 짓지 않도록)
          if (_hasStory && _pageCount != _storyPages.length) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isGenerating ? null : _applyPageCount,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: _card(radius: 16, color: _purple, edge: _purpleDark),
                child: Text('바꾸기', style: AppTextStyles.button(color: Colors.white).copyWith(fontSize: 18)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepButton(IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null && !_isGenerating;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 48,
        height: 48,
        decoration: _card(radius: 16),
        child: Icon(icon, size: 26, color: enabled ? _purple : _cardEdge),
      ),
    );
  }

  Widget _buildLumiAvatar(double size) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.06),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.secondaryLight,
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: Image.asset(_lumiImagePath, fit: BoxFit.contain),
    );
  }

  Widget _buildStoryArea() {
    if (_isGenerating && !_hasStory) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLumiAvatar(84),
            const SizedBox(height: 16),
            const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 4, color: _purple)),
            const SizedBox(height: 14),
            Text(
              '크레용이 $_pageCount화짜리 동화를\n짓고 있어...',
              textAlign: TextAlign.center,
              style: AppTextStyles.headingMedium(color: _purple),
            ),
          ],
        ),
      );
    }

    if (!_hasStory) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLumiAvatar(84),
            const SizedBox(height: 18),
            // 화면 폭의 절반 (좁은 폰에서 글자가 넘치지 않게 최소 260)
            LayoutBuilder(
              builder: (context, constraints) => SizedBox(
                width: math.max(constraints.maxWidth * 0.5, 260),
                child: _buildBigButton(
                  label: '$_pageCount화 줄거리 만들기',
                  icon: Icons.auto_fix_high_rounded,
                  onTap: () => _fetchRealStory(),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), // 아래쪽 루미 버튼에 마지막 카드가 가리지 않게
          itemCount: _storyPages.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == 0) {
              if (_editingIndex == -1) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _card(),
                  child: Column(
                    children: [
                      _buildEditField(_editTitleCtrl, fontSize: 22, hint: '동화 제목', autofocus: true),
                      const SizedBox(height: 10),
                      _buildEditActions(_editTitleCtrl),
                    ],
                  ),
                );
              }
              return Row(
                children: [
                  const SizedBox(width: 44), // 오른쪽 연필 버튼만큼 비워 제목을 가운데로
                  Expanded(
                    child: Text(
                      _storyTitle,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.display(),
                    ),
                  ),
                  _buildPencilButton(-1),
                ],
              );
            }
            return _buildPageCard(index - 1);
          },
        ),
        // 줄거리를 고치는 동안 기존 줄거리 위에 살짝 덮기
        if (_isGenerating)
          Positioned.fill(
            child: Container(
              color: _bg.withValues(alpha: 0.7),
              alignment: Alignment.center,
              child: const CircularProgressIndicator(strokeWidth: 4, color: _purple),
            ),
          ),
      ],
    );
  }

  Widget _buildPageCard(int index) {
    final page = _storyPages[index];
    final editing = _editingIndex == index;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(edge: editing ? _purple : _cardEdge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: _purple, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  page['page'] ?? '${index + 1}화',
                  style: AppTextStyles.labelMedium(color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: editing
                    ? _buildEditField(_editTitleCtrl, fontSize: 18, hint: '소제목')
                    : Text(page['title'] ?? '', style: AppTextStyles.headingMedium()),
              ),
              if (!editing) _buildPencilButton(index),
            ],
          ),
          const SizedBox(height: 10),
          if (editing) ...[
            _buildEditField(_editContentCtrl, fontSize: 17, hint: '이야기를 고쳐 봐!', multiline: true, autofocus: true),
            const SizedBox(height: 10),
            _buildEditActions(_editContentCtrl),
          ] else
            Text(
              page['content'] ?? '',
              style: const TextStyle(fontSize: 17, height: 1.6, color: _ink),
            ),
        ],
      ),
    );
  }

  // 다른 곳을 고치는 중이거나 이야기를 짓는 중에는 숨김
  Widget _buildPencilButton(int index) {
    if (_editingIndex != null || _isGenerating) return const SizedBox(width: 44);
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        tooltip: '직접 고치기',
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.edit_rounded, color: _purple, size: 24),
        onPressed: () => _startEdit(index),
      ),
    );
  }

  Widget _buildEditField(TextEditingController ctrl, {required double fontSize, required String hint, bool multiline = false, bool autofocus = false}) {
    return TextField(
      controller: ctrl,
      autofocus: autofocus,
      minLines: multiline ? 3 : 1,
      maxLines: multiline ? null : 1,
      style: TextStyle(fontSize: fontSize, height: multiline ? 1.6 : 1.3, color: _ink),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF8F6FF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _cardLine, width: 2)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _cardLine, width: 2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _purple, width: 2)),
      ),
    );
  }

  // 마이크(커서 자리에 받아쓰기) · 취소 · 저장
  Widget _buildEditActions(TextEditingController micTarget) {
    return Row(
      children: [
        // 입력칸의 일부로 취급해서, 마이크를 눌러도 입력칸 포커스·커서가 그대로 남게 함
        TextFieldTapRegion(
          child: GestureDetector(
            onTap: () => _toggleEditListening(micTarget),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 48,
              decoration: _card(radius: 24, color: _isListening ? AppColors.accent : Colors.white),
              child: Icon(
                _isListening ? Icons.mic : Icons.mic_none_rounded,
                color: _isListening ? Colors.white : _purple,
                size: 26,
              ),
            ),
          ),
        ),
        if (_isListening) ...[
          const SizedBox(width: 8),
          Text('듣고 있어! 말해 봐…', style: AppTextStyles.headingSmall(color: _purple).copyWith(fontSize: 16)),
        ],
        const Spacer(),
        TextButton(
          onPressed: _cancelEdit,
          child: Text('취소', style: AppTextStyles.button(color: _sub).copyWith(fontSize: 18)),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: _saveEdit,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.center,
            decoration: _card(radius: 16, color: _purple, edge: _purpleDark),
            child: Text('저장', style: AppTextStyles.button(color: Colors.white).copyWith(fontSize: 18)),
          ),
        ),
      ],
    );
  }

  Widget _buildBigButton({required String label, required IconData icon, required VoidCallback? onTap}) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        alignment: Alignment.center,
        decoration: _card(
          radius: 20,
          color: enabled ? _purple : Colors.grey[300]!,
          edge: enabled ? _purpleDark : Colors.black12,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(label, style: AppTextStyles.button(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: GestureDetector(
              onTap: _popWithStoryData,
              child: Container(
                height: 58,
                alignment: Alignment.center,
                decoration: _card(radius: 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.brush_rounded, color: _purple, size: 20),
                    const SizedBox(width: 6),
                    Text('그림 더 고칠래', style: AppTextStyles.button(color: _purple)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: _buildBigButton(
              label: '이 이야기로 완성!',
              icon: Icons.auto_stories_rounded,
              onTap: _isGenerating || !_hasStory || _editingIndex != null ? null : () => _createFinalStorybook(),
            ),
          ),
        ],
      ),
    );
  }

  // 페이지 인덱스별로 생성된 이미지와, 생성 당시의 장면 정보를 보관
  // (장면 정보와 등장 캐릭터 그림이 그대로인 페이지는 다시 그리지 않음)
  final Map<int, String> _pageImages = {};
  final Map<int, String> _pageImageSignatures = {};

  String _sceneSignature(int index) {
    final p = _storyPages[index];
    final List characters = p['characters'] ?? [];
    final drawings = [
      for (final id in characters)
        [Object.hashAll(widget.assetPngBytes[id] ?? const <int>[]), widget.aiDelegated[id] == true],
    ];
    return jsonEncode([p['prompt'] ?? '', p['layout_type'] ?? 'single', characters, drawings]);
  }

  bool _hasImage(int index) =>
      (_pageImages[index] ?? '').isNotEmpty &&
      _pageImageSignatures[index] == _sceneSignature(index);

  // 장면 설명은 "완성"을 누를 때 그 시점의 글로 만듦
  // → 아직 없거나, 만든 뒤에 본문이 바뀐 화(직접 고침·루미가 다시 지음)는 새로 만들어야 함
  //   (소제목만 고친 건 그림과 상관없으니 그대로 둠)
  String _sceneSource(Map<String, dynamic> p) => (p['content'] ?? '').toString();

  bool _needsScene(int index) {
    final p = _storyPages[index];
    return (p['prompt'] ?? '').toString().trim().isEmpty || p['scene_source'] != _sceneSource(p);
  }

  // ── 🎨 OpenAI gpt-image-2 일러스트 생성 요청 및 완성 뷰어 이동 ──
  // keepOld: 바뀐 화도 전에 그린 그림을 그대로 쓸지 (null이면 바뀐 화가 있을 때 물어봄)
  Future<void> _createFinalStorybook({bool? keepOld}) async {
    // 그림이 없거나, 그린 뒤로 글이나 그림이 바뀐 화
    final stale = [
      for (int i = 0; i < _storyPages.length; i++)
        if (_needsScene(i) || !_hasImage(i)) i,
    ];
    // 그중 전에 그린 그림이 있는 화는 새로 그릴지 물어봄
    final changed = [
      for (final i in stale)
        if ((_pageImages[i] ?? '').isNotEmpty) i,
    ];
    if (keepOld == null && changed.isNotEmpty) {
      final redraw = await _askRedrawChanged(changed);
      if (!mounted || redraw == null) return;
      keepOld = !redraw;
    }
    final bool useOld = keepOld ?? false;
    final targets = [
      for (final i in stale)
        if (!useOld || (_pageImages[i] ?? '').isEmpty) i,
    ];

    if (targets.isNotEmpty) {
      _showPrintingDialog();
      try {
        final sceneTargets = [
          for (final i in targets)
            if (_needsScene(i)) i,
        ];
        if (sceneTargets.isNotEmpty) await _requestScenes(sceneTargets);
        await _requestIllustrations(targets);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        debugPrint('최종 동화책 생성 에러: $e');
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('동화책을 인쇄하는 중에 문제가 생겼어. 다시 시도해 줘!')),
        );
        return;
      }
    }
    if (!mounted) return;

    final failed = [
      for (final i in targets)
        if (!_hasImage(i)) i,
    ];
    if (failed.isNotEmpty) {
      final retry = await _askRetryFailedPages(failed);
      if (!mounted || retry == null) return;
      if (retry) {
        await _createFinalStorybook(keepOld: useOld);
        return;
      }
    }

    _openReader(useOld);
  }

  // 바뀐 화가 있을 때 새로 그릴지 묻기 (true: 새로 그리기, false: 전에 그린 그림 쓰기, null: 닫기)
  Future<bool?> _askRedrawChanged(List<int> changedIndexes) {
    final pageLabels = changedIndexes.map((i) => '${i + 1}').join(', ');
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('바뀐 곳이 있어', style: AppTextStyles.headingMedium()),
        content: Text('$pageLabels화의 이야기나 그림이 바뀌었어.\n바뀐 화 그림을 새로 그릴까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('전에 그린 그림 쓸래', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondaryDark,
              foregroundColor: Colors.white,
            ),
            child: const Text('새로 그리기'),
          ),
        ],
      ),
    );
  }

  // 지정한 화의 장면 설명·등장 캐릭터를 지금 줄거리로 만들어 페이지에 반영
  Future<void> _requestScenes(List<int> targetIndexes) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/story/scenes'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'asset_descriptions': widget.assetDescriptions,
        'title': _storyTitle,
        'pages': [
          for (int i = 0; i < _storyPages.length; i++)
            {
              'page': i + 1,
              'title': _storyPages[i]['title'] ?? '',
              'content': _storyPages[i]['content'] ?? '',
              // 다시 만들지 않는 화의 장면 설명은 같은 조연을 같은 모습으로 그리도록 참고용으로 보냄
              'visual_scene_prompt': targetIndexes.contains(i) || _needsScene(i) ? '' : (_storyPages[i]['prompt'] ?? ''),
              'layout_type': targetIndexes.contains(i) || _needsScene(i) ? '' : (_storyPages[i]['layout_type'] ?? ''),
            },
        ],
        'target_pages': [for (final i in targetIndexes) i + 1],
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('장면 설명 생성 실패: ${res.statusCode}');
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes));
    for (final s in data['scenes'] ?? []) {
      final idx = (s['page'] as int) - 1;
      if (idx < 0 || idx >= _storyPages.length) continue;
      final p = _storyPages[idx];
      p['prompt'] = s['visual_scene_prompt'] ?? '';
      p['characters'] = List<String>.from(s['characters'] ?? []);
      p['layout_type'] = s['layout_type'] ?? 'single'; // 분할 여부는 AI가 화마다 판단
      p['scene_source'] = _sceneSource(p);
    }

    // 장면 설명 없이 그리면 엉뚱한 그림에 비용만 드니 여기서 멈춤
    if (targetIndexes.any(_needsScene)) {
      throw Exception('일부 화의 장면 설명을 받지 못함');
    }
  }

  void _showPrintingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          margin: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(CrayongImages.drawing, height: 120),
              const SizedBox(height: 14),
              const SizedBox(
                width: 180,
                child: LinearProgressIndicator(minHeight: 6, borderRadius: BorderRadius.all(Radius.circular(3))),
              ),
              const SizedBox(height: 16),
              Text(
                '크레용이 동화책에 그림을 그리고 있어!',
                textAlign: TextAlign.center,
                style: AppTextStyles.headingMedium(),
              ),
              const SizedBox(height: 8),
              Text(
                '예쁜 그림과 이야기를 엮는 중이야. 잠깐만 기다려 줘!',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 지정한 페이지들만 서버에 요청하고, 성공한 이미지를 _pageImages에 보관
  Future<void> _requestIllustrations(List<int> targetIndexes) async {
    final Map<String, String> drawnAssetsBase64 = {};
    widget.assetPngBytes.forEach((catId, bytes) {
      if (bytes != null && bytes.isNotEmpty && (widget.aiDelegated[catId] != true)) {
        drawnAssetsBase64[catId] = base64Encode(bytes);
      }
    });

    // 🎯 OpenAI gpt-image-2 파이프라인 전송 페이로드 구성
    final payload = {
      'drawn_assets_base64': drawnAssetsBase64,
      'asset_descriptions': widget.assetDescriptions, // 아이가 붙인 이름·특징
      'pages': targetIndexes.map((idx) {
        final p = _storyPages[idx];

        final safePrompt = (p['prompt'] != null && p['prompt'].toString().trim().isNotEmpty)
            ? p['prompt'].toString().trim()
            : 'A whimsical watercolor storybook illustration of the characters.';

        return {
          'page_number': idx + 1,
          'scene_prompt': safePrompt,
          'layout_type': p['layout_type'] ?? 'single',
          'characters': p['characters'] ?? [],
        };
      }).toList(),
    };

    final res = await http.post(
      Uri.parse('$_baseUrl/api/story/generate_illustrations'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (res.statusCode != 200) {
      throw Exception('일러스트 생성 실패: ${res.statusCode}');
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final List illustrations = data['illustrations'] ?? [];
    for (final item in illustrations) {
      final idx = (item['page_number'] as int) - 1;
      final url = (item['image_url'] ?? '').toString();
      if (url.isNotEmpty) {
        _pageImages[idx] = url;
        _pageImageSignatures[idx] = _sceneSignature(idx);
      } else {
        debugPrint('[${idx + 1}페이지] 그림 생성 실패: ${item['error']}');
      }
    }
  }

  // 실패한 페이지가 있을 때 다시 그릴지 묻기 (true: 다시 그리기, false: 그대로 보기, null: 닫기)
  Future<bool?> _askRetryFailedPages(List<int> failedIndexes) {
    final pageLabels = failedIndexes.map((i) => '${i + 1}').join(', ');
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('그림 몇 장을 못 그렸어', style: AppTextStyles.headingMedium()),
        content: Text('$pageLabels페이지 그림을 그리지 못했어.\n이 페이지만 다시 그려 볼까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('그림 없이 볼래', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondaryDark,
              foregroundColor: Colors.white,
            ),
            child: const Text('다시 그리기'),
          ),
        ],
      ),
    );
  }

  // useOld: 바뀐 화도 전에 그린 그림을 보여 줌
  void _openReader(bool useOld) {
    final List<Map<String, dynamic>> finalPages = [
      for (int i = 0; i < _storyPages.length; i++)
        {
          ..._storyPages[i],
          'imageUrl': _hasImage(i) || useOld ? (_pageImages[i] ?? '') : '',
        },
    ];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => StoryReaderScreen(
          title: _storyTitle,
          pages: finalPages,
          assetPngBytes: widget.assetPngBytes,
          taleId: widget.taleId,
        ),
      ),
    );
  }
}