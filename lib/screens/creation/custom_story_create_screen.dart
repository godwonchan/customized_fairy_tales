// lib/screens/creation/custom_story_create_screen.dart
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:audioplayers/audioplayers.dart';
import 'story_preview_screen.dart';

enum LumiOverlayMode { intro, chat, naming }

class StoryCategory {
  final String id;
  final String title;
  final String fairyPrompt;
  final IconData icon;
  final bool isRequired;

  const StoryCategory({
    required this.id,
    required this.title,
    required this.fairyPrompt,
    required this.icon,
    this.isRequired = false,
  });
}

class CustomStoryCreateScreen extends StatefulWidget {
  const CustomStoryCreateScreen({super.key});

  @override
  State<CustomStoryCreateScreen> createState() => _CustomStoryCreateScreenState();
}

class _CustomStoryCreateScreenState extends State<CustomStoryCreateScreen>
    with TickerProviderStateMixin {
  static const String _lumiImagePath = 'assets/images/lumi.jpg';
  static const String _baseUrl = 'http://localhost:8000'; // 크롬: localhost, 에뮬레이터: 10.0.2.2

  final List<StoryCategory> _allCategories = const [
    StoryCategory(id: 'hero', title: '주인공', fairyPrompt: '안녕! 나는 이야기 요정 루미야 ✨ 우리 멋진 모험을 이끌어갈 주인공을 먼저 그려줄래?', icon: Icons.person_pin, isRequired: true),
    StoryCategory(id: 'companion', title: '단짝 친구', fairyPrompt: '멋진 주인공이 완성됐네! 이제 곁을 지켜줄 든든한 단짝 친구나 귀여운 동물 친구도 그려볼까?', icon: Icons.pets),
    StoryCategory(id: 'item', title: '마법 도구', fairyPrompt: '위험한 순간에 힘을 발휘할 신비한 마법 지팡이나 특별한 보물이 있을까?', icon: Icons.auto_awesome),
    StoryCategory(id: 'place', title: '비밀 장소', fairyPrompt: '모험이 시작될 장소를 그려줘! 우리 집, 마법의 성, 또는 신비한 나무도 좋아.', icon: Icons.castle),
    StoryCategory(id: 'vehicle', title: '특별한 탈것', fairyPrompt: '하늘을 나는 양탄자, 우주선, 구름 자전거처럼 신나는 탈것도 그려볼래?', icon: Icons.rocket_launch),
    StoryCategory(id: 'villain', title: '엉뚱한 악당', fairyPrompt: '이야기를 더 흥미진진하게 만들 귀여운 장난꾸러기 악당도 있으면 재밌을 거야!', icon: Icons.mood_bad),
    StoryCategory(id: 'food', title: '좋아하는 간식', fairyPrompt: '먹으면 힘이 솟아나는 달콤한 딸기 케이크나 마법 열매를 그려보는 건 어때?', icon: Icons.icecream),
    StoryCategory(id: 'treasure', title: '숨겨진 보물', fairyPrompt: '모험의 끝에서 발견하게 될 반짝이는 보물 상자나 비밀 열쇠를 그려보자!', icon: Icons.vpn_key),
  ];

  int _unlockedCategoryCount = 1;
  int _currentIndex = 0;

  final Map<String, List<DrawingPath>> _slotPaths = {};
  final Map<String, bool> _slotAiDelegated = {};
  final Map<String, Uint8List?> _slotPngBytes = {};
  final Map<String, Map<String, String>> _slotDescriptions = {};

  final List<DrawingPath> _paths = [];
  DrawingPath? _currentPath;
  Color _selectedColor = Colors.black;
  double _penWidth = 5.0;
  double _eraserWidth = 28.0;
  bool _isEraser = false;
  final GlobalKey _canvasKey = GlobalKey();

  // ── 오디오 플레이어 & 음성 캐시 ──
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Map<String, Uint8List> _ttsCache = {}; // 동일한 대사는 네트워크 재호출 없이 즉시 재생!
  int _ttsSessionId = 0; // 💡 비동기 오디오 레이스 컨디션 방지용 세션 번호

  // 애니메이션들
  late AnimationController _fairyAnimController;
  late Animation<double> _floatingAnim;

  bool _showLumiOverlay = true;
  LumiOverlayMode _overlayMode = LumiOverlayMode.intro;
  String _lumiDialogue = '';
  bool _isLumiThinking = false;
  late AnimationController _introAnimController;
  late Animation<double> _scaleAnimation;

  // STT 음성인식
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  String? _activeVoiceField;

  final TextEditingController _chatInputCtrl = TextEditingController();
  final TextEditingController _nameInputCtrl = TextEditingController();
  final TextEditingController _descInputCtrl = TextEditingController();

  // 💡 [추가] 포커스 명시 제어 노드
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _descFocusNode = FocusNode();

  // 💡 이미 방문해서 루미가 안내한 카테고리 ID 목록 (최초 1회만 TTS 재생)
  final Set<String> _visitedCategories = {'hero'}; // 주인공은 첫 화면이므로 등록
  bool _isDialogShowing = false; // 💡 팝업 중복 호출 방지 플래그

  // 💾 [3번 핵심] 이전에 생성했던 줄거리 및 연출 데이터 캐싱
  Map<String, dynamic>? _cachedStoryData;

  final List<Color> _colorPalette = [
    Colors.black,
    const Color(0xFFE53935),
    const Color(0xFFFF8F00),
    const Color(0xFFFFD600),
    const Color(0xFF43A047),
    const Color(0xFF1E88E5),
    const Color(0xFF8E24AA),
    const Color(0xFFEC407A),
    const Color(0xFF795548),
    const Color(0xFF80DEEA),
    const Color(0xFF455A64),
  ];

  StoryCategory get currentCat => _allCategories[_currentIndex];

  @override
  void initState() {
    super.initState();
    _lumiDialogue = '안녕! 나는 너만의 이야기 요정 루미야 ✨\n우리 함께 멋진 모험 이야기를 만들어 볼까?\n\n먼저 동화의 대장이 될\n멋진 [주인공]부터 자유롭게 그려줘!';

    _introAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _introAnimController,
      curve: Curves.easeOutBack,
    );

    if (_showLumiOverlay) {
      _introAnimController.forward();
      // 💡 화면 켜지자마자 첫 인트로 인사말 음성 낭독!
      _speakLumi(_lumiDialogue);
    }

    _fairyAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _floatingAnim = Tween<double>(begin: -6.0, end: 6.0).animate(
      CurvedAnimation(parent: _fairyAnimController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _introAnimController.dispose();
    _fairyAnimController.dispose();
    _chatInputCtrl.dispose();
    _nameInputCtrl.dispose();
    _descInputCtrl.dispose();
    // 💡 [추가] 포커스 노드 정리
    _nameFocusNode.dispose();
    _descFocusNode.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  //  🔊 루미 목소리 통합 낭독 엔진 (캐싱 지원)
  // ═══════════════════════════════════════════════════════════════
  Future<void> _speakLumi(String text, {String? directBase64}) async {
    final int currentSession = ++_ttsSessionId; // 고유 티켓 발급

    try {
      await _audioPlayer.stop();

      // 1. 이미 전달된 Base64 오디오가 있는 경우
      if (directBase64 != null && directBase64.isNotEmpty) {
        final bytes = base64Decode(directBase64);
        _ttsCache[text] = bytes;
        if (_ttsSessionId != currentSession) return; // 화면 전환되었으면 취소!
        await _audioPlayer.play(BytesSource(bytes));
        return;
      }

      // 2. 이미 캐시된 음성인 경우
      if (_ttsCache.containsKey(text)) {
        if (_ttsSessionId != currentSession) return; // 취소 확인
        await _audioPlayer.play(BytesSource(_ttsCache[text]!));
        return;
      }

      // 3. 백엔드 TTS 호출
      final res = await http.post(
        Uri.parse('$_baseUrl/api/chat/tts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );

      // 💡 핵심: 네트워크 다운로드 받는 동안 화면이 넘어갔다면 재생하지 않고 즉시 버림!
      if (_ttsSessionId != currentSession) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final String audioB64 = data['audio_base64'] ?? '';
        if (audioB64.isNotEmpty) {
          final bytes = base64Decode(audioB64);
          _ttsCache[text] = bytes;
          if (_ttsSessionId != currentSession) return; // 최종 재생 직전 재확인
          await _audioPlayer.play(BytesSource(bytes));
        }
      }
    } catch (e) {
      debugPrint('루미 음성 낭독 실패: $e');
    }
  }

  // ── 루미 오버레이 이벤트 3종 ──
  void _openLumiIntroEvent() {
    setState(() {
      _overlayMode = LumiOverlayMode.intro;
      _lumiDialogue = '안녕! 나는 너만의 이야기 요정 루미야 ✨\n우리 함께 멋진 모험 이야기를 만들어 볼까?\n\n먼저 동화의 대장이 될\n멋진 [주인공]부터 자유롭게 그려줘!';
      _showLumiOverlay = true;
    });
    _introAnimController.forward(from: 0.0);
    _speakLumi(_lumiDialogue); // 🔊 인사말 재생
  }

  void _openLumiChatEvent() {
    setState(() {
      _overlayMode = LumiOverlayMode.chat;
      _lumiDialogue = '무엇이든 물어봐! 마이크를 누르고 말해도 좋아 ✨';
      _isLumiThinking = false;
      _showLumiOverlay = true;
    });
    _introAnimController.forward(from: 0.0);
    _speakLumi(_lumiDialogue); // 🔊 질문 환영 멘트 재생
  }

  void _openLumiNamingEvent() {
    final existingInfo = _slotDescriptions[currentCat.id] ?? {};
    _nameInputCtrl.text = existingInfo['name'] ?? '';
    _descInputCtrl.text = existingInfo['desc'] ?? '';

    setState(() {
      _overlayMode = LumiOverlayMode.naming;
      _lumiDialogue = '정말 멋지게 잘 그렸어! ✨\n루미에게 이 [ ${currentCat.title} ]의 이름과\n어떤 특별한 힘이 있는지 소개해 줄래?';
      _showLumiOverlay = true;
    });
    _introAnimController.forward(from: 0.0);
    _speakLumi(_lumiDialogue); // 🔊 이름 질문 멘트 재생
    // 💡 [추가] 오버레이가 열리면 이름 입력창으로 커서 자동 이동
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocusNode.requestFocus();
    });
  }

  void _dismissLumiOverlay() {
    _speech.stop();
    _audioPlayer.stop(); // 닫으면 음성도 부드럽게 종료
    _introAnimController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _showLumiOverlay = false;
          _isListening = false;
          _activeVoiceField = null;
        });
      }
    });
  }

  Future<void> _submitNamingAndAdvance() async {
    _speech.stop();
    _audioPlayer.stop();
    final name = _nameInputCtrl.text.trim().isEmpty ? currentCat.title : _nameInputCtrl.text.trim();
    _slotDescriptions[currentCat.id] = {
      'name': name,
      'desc': _descInputCtrl.text.trim(),
    };

    _slotPaths[currentCat.id] = List.from(_paths);
    if (_paths.isNotEmpty) {
      _slotAiDelegated[currentCat.id] = false;
      _slotPngBytes[currentCat.id] = await _captureCanvasToPng();
    }

    _dismissLumiOverlay();

    if (_currentIndex == _unlockedCategoryCount - 1 && _unlockedCategoryCount < _allCategories.length) {
      setState(() => _unlockedCategoryCount++);
      _switchCategory(_currentIndex + 1);
    } else if (_currentIndex < _unlockedCategoryCount - 1) {
      _switchCategory(_currentIndex + 1);
    } else {
      _proceedToStoryReview();
    }
  }

  Future<void> _ensureSpeechInitialized() async {
    if (!_speechAvailable) {
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
  }

  Future<void> _toggleVoiceInput(String targetField) async {
    await _ensureSpeechInitialized();
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('마이크 권한을 허용해 줘!')),
      );
      return;
    }

    if (_isListening && _activeVoiceField == targetField) {
      await _speech.stop();
      setState(() {
        _isListening = false;
        _activeVoiceField = null;
      });
    } else {
      await _speech.stop();
      await _audioPlayer.stop(); // 아이가 말할 때는 루미 목소리 일시정지!
      setState(() {
        _isListening = true;
        _activeVoiceField = targetField;
        if (_overlayMode == LumiOverlayMode.chat) {
          _lumiDialogue = '루미가 귀를 쫑긋 세우고 듣고 있어... 👂✨';
        }
      });

      await _speech.listen(
        localeId: 'ko_KR',
        onResult: (result) {
          setState(() {
            if (targetField == 'chat') {
              _chatInputCtrl.text = result.recognizedWords;
            } else if (targetField == 'name') {
              _nameInputCtrl.text = result.recognizedWords;
            } else if (targetField == 'desc') {
              _descInputCtrl.text = result.recognizedWords;
            }

            if (result.finalResult) {
              _isListening = false;
              _activeVoiceField = null;
            }
          });
        },
      );
    }
  }

  // ── 백엔드 GPT-4o-mini 호출 및 루미 답변 음성 낭독 ──
  Future<void> _sendQuestionToLumi(String q) async {
    if (q.isEmpty) return;
    if (_isListening) {
      await _speech.stop();
      setState(() {
        _isListening = false;
        _activeVoiceField = null;
      });
    }

    setState(() => _isLumiThinking = true);

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/chat/lumi'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'question': q,
          'category_title': currentCat.title,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final replyText = data['reply'];
        final audioB64 = data['audio_base64'];

        setState(() {
          _isLumiThinking = false;
          _lumiDialogue = replyText;
          _chatInputCtrl.clear();
        });

        // 🔊 AI 생성 답변 즉시 음성 재생!
        _speakLumi(replyText, directBase64: audioB64);
      } else {
        throw Exception('서버 응답 오류');
      }
    } catch (e) {
      debugPrint('루미 API 통신 오류: $e');
      final fallbackText = '"$q"라니 정말 기발해! 동화 속에서는 무엇이든 마법처럼 가능하니까 캔버스에 자유롭게 그려봐! 🎨✨';
      setState(() {
        _isLumiThinking = false;
        _lumiDialogue = fallbackText;
        _chatInputCtrl.clear();
      });
      _speakLumi(fallbackText);
    }
  }

  Future<Uint8List?> _captureCanvasToPng() async {
    if (_paths.isEmpty) return null;
    try {
      final boundary = _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('PNG 캡처 에러: $e');
      return null;
    }
  }

  // ── 카테고리 전환 시 이전 음성 즉시 중단 및 안내 ──
  Future<void> _switchCategory(int newIndex) async {
    if (newIndex == _currentIndex) return;

    // 💡 [5번 핵심] 카테고리 이동 즉시 이전 음성 완전 정지 & 대기 중인 오디오 무효화!
    _ttsSessionId++;
    await _audioPlayer.stop();
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
      _activeVoiceField = null;
    }

    _slotPaths[currentCat.id] = List.from(_paths);
    if (_paths.isNotEmpty) {
      _slotAiDelegated[currentCat.id] = false;
      _slotPngBytes[currentCat.id] = await _captureCanvasToPng();
    }

    setState(() {
      _currentIndex = newIndex;
      _paths.clear();
      if (_slotPaths.containsKey(currentCat.id)) {
        _paths.addAll(_slotPaths[currentCat.id]!);
      }
      _isEraser = false;
    });

    // 🔊 처음 방문한 카테고리일 때만 새 카테고리 안내 음성 재생
    if (!_visitedCategories.contains(currentCat.id)) {
      _visitedCategories.add(currentCat.id);
      _speakLumi(currentCat.fairyPrompt);
    }
  }

  void _delegateToAiAndNext() {
    setState(() {
      _paths.clear();
      _slotPaths[currentCat.id] = [];
      _slotPngBytes[currentCat.id] = null;
      _slotAiDelegated[currentCat.id] = true;
      _slotDescriptions[currentCat.id] = {'name': '${currentCat.title} (AI 생성)', 'desc': '요정이 대신 상상해서 그릴 예정'};
    });

    final delegateNotice = '${currentCat.title}은 요정 루미가 마법으로 그려줄게! ✨';
    _speakLumi(delegateNotice); // 🔊 위임 안내 음성 낭독

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✨ $delegateNotice'),
        backgroundColor: const Color(0xFF7E57C2),
        duration: const Duration(seconds: 2),
      ),
    );

    if (_currentIndex == _unlockedCategoryCount - 1 && _unlockedCategoryCount < _allCategories.length) {
      setState(() => _unlockedCategoryCount++);
      _switchCategory(_currentIndex + 1);
    }
  }

  Future<void> _proceedToStoryReview() async {
    final hasHeroDrawing = (_slotPaths['hero']?.isNotEmpty ?? false);
    if (!hasHeroDrawing) {
      const warnText = '이야기의 대장이 될 주인공은 꼭 직접 그려줘야 해! 🎨';
      _speakLumi(warnText);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(warnText), backgroundColor: Color(0xFFE53935)),
      );
      _switchCategory(0);
      return;
    }

    // 💡 [수정됨] 캐시된 줄거리가 있을 경우 팝업 분기 처리!
    if (_cachedStoryData != null) {
      final String? action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.auto_stories_rounded, color: Color(0xFF7E57C2), size: 26),
              SizedBox(width: 8),
              Text('이야기 만들기 선택', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF3D2C8D))),
            ],
          ),
          content: const Text(
            '이전에 만든 멋진 줄거리가 남아있어요!\n어떻게 진행할까요?',
            style: TextStyle(fontSize: 14, color: Color(0xFF4A4458), height: 1.5),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'keep_story'),
                  icon: const Icon(Icons.brush_rounded, size: 18),
                  label: const Text('기존 줄거리에 바뀐 그림만 적용할래', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7E57C2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'new_story'),
                  icon: const Icon(Icons.refresh_rounded, size: 18, color: Color(0xFF7E57C2)),
                  label: const Text('줄거리도 완전히 새로 만들래', style: TextStyle(color: Color(0xFF7E57C2), fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFD1C4E9)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      if (action == null) return; // 바깥 터치로 팝업 닫음

      if (action == 'keep_story') {
        // 🚀 [핵심 해결] 줄거리(content)는 유지하되, 옛날 그림(박스, 동그라미)을 묘사한 시각 프롬프트(prompt)는 강제로 삭제!
        final updatedStoryData = Map<String, dynamic>.from(_cachedStoryData!);
        final List updatedPages = List.from(updatedStoryData['pages'] ?? []);

        for (int i = 0; i < updatedPages.length; i++) {
          final pageInfo = Map<String, dynamic>.from(updatedPages[i]);
          pageInfo['prompt'] = ''; // 옛날 시각 프롬프트 지우기 (백엔드가 새 그림을 보고 다시 짜도록)
          updatedPages[i] = pageInfo;
        }
        updatedStoryData['pages'] = updatedPages;
        _cachedStoryData = updatedStoryData; // 업데이트된 캐시 저장
      } else if (action == 'new_story') {
        _cachedStoryData = null; // 아예 초기화 (줄거리 전체 재생성)
      }
    }

    // 💡 진행 중인 오디오 무효화
    _ttsSessionId++;
    await _audioPlayer.stop();

    _slotPaths[currentCat.id] = List.from(_paths);
    if (_paths.isNotEmpty) {
      _slotPngBytes[currentCat.id] = await _captureCanvasToPng();
      _slotAiDelegated[currentCat.id] = false;
    }

    // 화면 이동
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoryPreviewScreen(
          assetPngBytes: _slotPngBytes,
          aiDelegated: _slotAiDelegated,
          assetDescriptions: _slotDescriptions,
          cachedStoryData: _cachedStoryData,
        ),
      ),
    );

    // 돌아왔을 때 줄거리 캐시 저장
    if (result is Map<String, dynamic>) {
      setState(() {
        _cachedStoryData = result;
      });
    }

    _ttsSessionId++;
    await _audioPlayer.stop();
  }

  // 🔙 스마트 뒤로가기 처리
  void _handleSmartBack() {
    // 1. 이미 다른 카테고리로 넘어간 상태라면 -> 이전 카테고리로 이동!
    if (_currentIndex > 0) {
      _switchCategory(_currentIndex - 1);
      return;
    }

    // 2. 첫 번째(주인공) 카테고리라면 -> 정말 나갈 것인지 확인 모달 띄우기
    _showExitConfirmDialog();
  }

// ⚠️ 작업 유실 방지 확인 모달
  Future<void> _showExitConfirmDialog() async {
    if (_isDialogShowing || !mounted) return;
    _isDialogShowing = true;

    final bool? shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFFF9800), size: 28),
            SizedBox(width: 8),
            Text(
              '동화 만들기 나가기',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF3D2C8D)),
            ),
          ],
        ),
        content: const Text(
          '지금 나가면 정성껏 그린 그림과 이야기가 모두 사라져요.\n정말 나갈까요? 😢',
          style: TextStyle(fontSize: 14, color: Color(0xFF4A4458), height: 1.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF7E57C2)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('계속 그릴래', style: TextStyle(color: Color(0xFF7E57C2), fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dialogCtx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5252),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('나가기', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    _isDialogShowing = false;

    if (shouldExit == true && mounted) {
      _audioPlayer.stop();
      Navigator.pop(context);
    }
  }

  Widget _buildLumiAvatar({required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7E57C2).withOpacity(0.4),
            blurRadius: size * 0.25,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          _lumiImagePath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) => Container(
            color: const Color(0xFF7E57C2),
            child: Icon(Icons.face_retouching_natural, color: Colors.white, size: size * 0.6),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 💡 PopScope로 감싸서 브라우저/스마트폰 시스템 뒤로가기 키도 낚아챔
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // 💡 브라우저의 Pop 신호 처리가 완전히 종료된 직후에 다이얼로그를 호출!
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _handleSmartBack();
          }
        });
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F5FC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Color(0xFF3D2C8D)),
            onPressed: _handleSmartBack, // 👈 기존의 Navigator.pop 대신 스마트 뒤로가기 호출!
          ),
          title: const Text('새로운 동화 만들기', style: TextStyle(color: Color(0xFF3D2C8D), fontSize: 18, fontWeight: FontWeight.bold)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ElevatedButton.icon(
                onPressed: () => _proceedToStoryReview(),
                icon: const Icon(Icons.auto_stories, size: 16),
                label: const Text('이야기 짓기'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7E57C2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildAnimatedFairyDialog(),
                  Expanded(child: _buildCanvasArea()),
                  _buildDrawingToolbar(),
                  _buildSequentialSlotTray(),
                ],
              ),
              if (_showLumiOverlay) _buildLumiFullScreenOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  // 상단 미니 루미 말풍선 바
  Widget _buildAnimatedFairyDialog() {
    return AnimatedBuilder(
      animation: _floatingAnim,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Transform.translate(
                offset: Offset(0, _floatingAnim.value),
                child: GestureDetector(
                  onTap: () => _openLumiChatEvent(),
                  child: _buildLumiAvatar(size: 52),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
                    border: Border.all(color: const Color(0xFFE0D8ED), width: 1.5),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('요정 루미 [ ${currentCat.title} ]', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF7E57C2))),
                          if (currentCat.isRequired) ...[
                            const SizedBox(width: 6),
                            const Text('(필수)', style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.w600)),
                          ],
                          const Spacer(),
                          // 🔊 다시 듣기 스피커 아이콘
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.volume_up_rounded, size: 18, color: Color(0xFF7E57C2)),
                            onPressed: () => _speakLumi(currentCat.fairyPrompt),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _openLumiChatEvent(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: const Color(0xFFF3EDFA), borderRadius: BorderRadius.circular(10)),
                              child: const Row(
                                children: [
                                  Icon(Icons.chat_bubble_outline, size: 12, color: Color(0xFF7E57C2)),
                                  SizedBox(width: 4),
                                  Text('루미에게 물어보기', style: TextStyle(fontSize: 11, color: Color(0xFF7E57C2), fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(currentCat.fairyPrompt, style: const TextStyle(fontSize: 13, color: Color(0xFF2C2440), height: 1.35)),
                      if (!currentCat.isRequired) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: InkWell(
                            onTap: () => _delegateToAiAndNext(),
                            child: const Text('✨ 그리기 어렵다면? 루미에게 맡기기', style: TextStyle(fontSize: 11, color: Color(0xFF9575CD), fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCanvasArea() {
    final isAi = _slotAiDelegated[currentCat.id] ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDED6ED)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            RepaintBoundary(
              key: _canvasKey,
              child: GestureDetector(
                onPanStart: (details) {
                  if (isAi) setState(() => _slotAiDelegated[currentCat.id] = false);
                  setState(() {
                    _currentPath = DrawingPath(
                      color: _selectedColor,
                      strokeWidth: _isEraser ? _eraserWidth : _penWidth,
                      isEraser: _isEraser,
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
                  painter: TransparentDrawingPainter(_paths),
                  child: Container(width: double.infinity, height: double.infinity, color: Colors.transparent),
                ),
              ),
            ),
            if (isAi)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(color: const Color(0xFFEDE7F6).withOpacity(0.95), borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome, color: Color(0xFF7E57C2), size: 36),
                      const SizedBox(height: 8),
                      Text('요정 루미가 [ ${currentCat.title} ]을(를) 대신 그릴 거야! ✨', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF3D2C8D))),
                      const SizedBox(height: 4),
                      const Text('직접 그리고 싶다면 화면에 터치해 봐 🎨', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              )
            else if (_paths.isEmpty)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(currentCat.icon, size: 54, color: Colors.grey[200]),
                    const SizedBox(height: 8),
                    Text('${currentCat.title}을(를) 자유롭게 그려봐!', style: TextStyle(fontSize: 14, color: Colors.grey[400])),
                  ],
                ),
              ),
            Positioned(
              top: 10, right: 10,
              child: Row(
                children: [
                  _circleIconButton(Icons.undo, () {
                    if (_paths.isNotEmpty) setState(() => _paths.removeLast());
                  }),
                  const SizedBox(width: 8),
                  _circleIconButton(Icons.refresh, () {
                    setState(() {
                      _paths.clear();
                      _slotPaths[currentCat.id] = [];
                      _slotPngBytes[currentCat.id] = null;
                      _slotDescriptions.remove(currentCat.id);
                    });
                  }),
                ],
              ),
            ),
            Positioned(
              bottom: 12, right: 12,
              child: ElevatedButton.icon(
                onPressed: (_paths.isNotEmpty || isAi) ? () => _openLumiNamingEvent() : null,
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: Text(_currentIndex == _allCategories.length - 1 ? '줄거리 보러가기' : '다음 단계로! ✨', style: const TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7E57C2),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  disabledForegroundColor: Colors.grey[500],
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4)]),
        child: Icon(icon, size: 18, color: Colors.grey[700]),
      ),
    );
  }

  Widget _buildDrawingToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          _toolItem(Icons.edit, !_isEraser, () => setState(() => _isEraser = false)),
          const SizedBox(width: 6),
          _toolItem(Icons.auto_fix_high, _isEraser, () => setState(() => _isEraser = true)),
          const SizedBox(width: 8),
          Text(_isEraser ? '지우개' : '펜', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7E57C2))),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(trackHeight: 4, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7)),
              child: Slider(
                value: _isEraser ? _eraserWidth : _penWidth,
                min: _isEraser ? 10 : 2,
                max: _isEraser ? 60 : 20,
                activeColor: _isEraser ? Colors.deepOrangeAccent : const Color(0xFF7E57C2),
                inactiveColor: const Color(0xFFE0D8ED),
                onChanged: (v) => setState(() => _isEraser ? _eraserWidth = v : _penWidth = v),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              shrinkWrap: true,
              itemCount: _colorPalette.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final color = _colorPalette[index];
                final isSelected = _selectedColor == color && !_isEraser;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedColor = color;
                    _isEraser = false;
                  }),
                  child: Container(
                    width: 26, height: 26,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: isSelected ? const Color(0xFF7E57C2) : Colors.grey[300]!, width: isSelected ? 2.5 : 1),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolItem(IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF7E57C2) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? const Color(0xFF7E57C2) : const Color(0xFFDDD5EC)),
        ),
        child: Icon(icon, size: 18, color: active ? Colors.white : Colors.grey[700]),
      ),
    );
  }

  Widget _buildSequentialSlotTray() {
    final visibleCategories = _allCategories.take(_unlockedCategoryCount).toList();

    return Container(
      height: 96,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -3))],
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: visibleCategories.length,
        itemBuilder: (context, index) {
          final cat = visibleCategories[index];
          final isSelected = _currentIndex == index;
          final isAi = _slotAiDelegated[cat.id] ?? false;

          final paths = isSelected ? _paths : (_slotPaths[cat.id] ?? []);
          final hasDrawing = paths.isNotEmpty;
          final desc = _slotDescriptions[cat.id];
          final label = desc?['name']?.isNotEmpty == true ? desc!['name']! : cat.title;

          return GestureDetector(
            onTap: () => _switchCategory(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 76,
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFF3EDFA) : const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isSelected ? const Color(0xFF7E57C2) : const Color(0xFFE5DFEE), width: isSelected ? 2 : 1),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: isAi
                            ? const Center(child: Icon(Icons.auto_awesome, size: 20, color: Color(0xFF7E57C2)))
                            : hasDrawing
                            ? CustomPaint(painter: MiniThumbnailPainter(paths))
                            : Icon(cat.icon, size: 22, color: Colors.grey[300]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? const Color(0xFF7E57C2) : Colors.grey[700],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  ✨ 루미 전체화면 인터랙티브 오버레이 (대사마다 자동 낭독)
  // ═══════════════════════════════════════════════════════════════
  Widget _buildLumiFullScreenOverlay() {
    return FadeTransition(
      opacity: _introAnimController,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFF231640).withOpacity(0.85),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              top: 20,
            ),
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.auto_awesome, color: Color(0xFF7E57C2), size: 22),
                            const SizedBox(width: 8),
                            Text(
                              _overlayMode == LumiOverlayMode.naming
                                  ? '루미에게 소개해 주기 ✨'
                                  : _overlayMode == LumiOverlayMode.chat
                                  ? '루미와의 마법 대화 ✨'
                                  : '동화 요정 루미',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF7E57C2)),
                            ),
                            const SizedBox(width: 8),
                            // 🔊 말풍선 대사 다시 듣기 버튼
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: const Icon(Icons.volume_up_rounded, size: 20, color: Color(0xFF7E57C2)),
                              onPressed: () => _speakLumi(_lumiDialogue),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        _isLumiThinking
                            ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7E57C2))),
                              SizedBox(width: 12),
                              Text('루미가 마법을 생각하고 있어... ✨', style: TextStyle(color: Color(0xFF7E57C2), fontSize: 14)),
                            ],
                          ),
                        )
                            : Text(
                          _lumiDialogue,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF2C2440),
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        if (_overlayMode == LumiOverlayMode.naming) ...[
                          const SizedBox(height: 16),
                          const Text('어떤 이름이야?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF4A4458))),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _nameInputCtrl,
                                  focusNode: _nameFocusNode, // 👈 [연결 1] 이름 포커스 노드
                                  textInputAction: TextInputAction.next,
                                  // 💡 엔터 치면 아래 설명 입력창으로 즉시 포커스 이동
                                  onSubmitted: (_) => _descFocusNode.requestFocus(),
                                  decoration: InputDecoration(
                                    hintText: (_isListening && _activeVoiceField == 'name') ? '듣고 있어요! 말씀해 보세요...' : '예: 불꽃 드래곤, 황금 지팡이',
                                    hintStyle: TextStyle(fontSize: 12, color: (_isListening && _activeVoiceField == 'name') ? const Color(0xFF7E57C2) : Colors.grey[400]),
                                    filled: true,
                                    fillColor: const Color(0xFFF9F7FC),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: () => _toggleVoiceInput('name'),
                                child: Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: (_isListening && _activeVoiceField == 'name') ? Colors.redAccent : const Color(0xFFF3EDFA),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: (_isListening && _activeVoiceField == 'name')
                                            ? Colors.redAccent.withOpacity(0.35)
                                            : const Color(0xFF7E57C2).withOpacity(0.15),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    (_isListening && _activeVoiceField == 'name') ? Icons.mic : Icons.mic_none_rounded,
                                    color: (_isListening && _activeVoiceField == 'name') ? Colors.white : const Color(0xFF7E57C2),
                                    size: 26,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Text('어떤 특별한 점이나 능력이 있어? (선택)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF4A4458))),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _descInputCtrl,
                                  focusNode: _descFocusNode, // 👈 [연결 2] 설명 포커스 노드
                                  textInputAction: TextInputAction.done,
                                  // 💡 엔터 치면 루미에게 바로 등록 완료 후 다음 단계 진행
                                  onSubmitted: (_) => _submitNamingAndAdvance(),
                                  decoration: InputDecoration(
                                    hintText: (_isListening && _activeVoiceField == 'desc') ? '듣고 있어요! 말씀해 보세요...' : '예: 하늘을 날아다니고 딸기를 좋아해!',
                                    hintStyle: TextStyle(fontSize: 12, color: (_isListening && _activeVoiceField == 'desc') ? const Color(0xFF7E57C2) : Colors.grey[400]),
                                    filled: true,
                                    fillColor: const Color(0xFFF9F7FC),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: () => _toggleVoiceInput('desc'),
                                child: Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: (_isListening && _activeVoiceField == 'desc') ? Colors.redAccent : const Color(0xFFF3EDFA),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: (_isListening && _activeVoiceField == 'desc')
                                            ? Colors.redAccent.withOpacity(0.35)
                                            : const Color(0xFF7E57C2).withOpacity(0.15),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    (_isListening && _activeVoiceField == 'desc') ? Icons.mic : Icons.mic_none_rounded,
                                    color: (_isListening && _activeVoiceField == 'desc') ? Colors.white : const Color(0xFF7E57C2),
                                    size: 26,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              // 💡 [핵심 해결] ExcludeFocus로 감싸서 엔터/키보드 탐색 대상에서 완전히 제외
                              Expanded(
                                flex: 4,
                                child: ExcludeFocus(
                                  child: OutlinedButton(
                                    onPressed: () => _dismissLumiOverlay(),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Color(0xFFDED6ED)),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    child: const Text('그림 더 그릴래', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 6,
                                child: ElevatedButton.icon(
                                  onPressed: () => _submitNamingAndAdvance(),
                                  icon: const Icon(Icons.check, size: 16),
                                  label: const Text('루미에게 알려주기 ✨', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF7E57C2),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else if (_overlayMode == LumiOverlayMode.chat) ...[
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            alignment: WrapAlignment.center,
                            children: [
                              ActionChip(
                                label: const Text('어떤 색이 어울릴까?', style: TextStyle(fontSize: 11)),
                                onPressed: () => _sendQuestionToLumi('어떤 색이 어울릴까?'),
                              ),
                              ActionChip(
                                label: const Text('그리기 너무 어려워!', style: TextStyle(fontSize: 11)),
                                onPressed: () {
                                  const cheerMsg = '완벽하지 않아도 괜찮아! 동그라미랑 네모만 이어 붙여도 멋진 작품이 된단다! 🎨';
                                  setState(() {
                                    _lumiDialogue = cheerMsg;
                                  });
                                  _speakLumi(cheerMsg);
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _chatInputCtrl,
                                  textInputAction: TextInputAction.send, // 👈 [1번] 엔터 치면 즉시 질문 전송!
                                  onSubmitted: (val) => _sendQuestionToLumi(val.trim()),
                                  decoration: InputDecoration(
                                    hintText: (_isListening && _activeVoiceField == 'chat') ? '듣고 있어요! 말씀해 보세요...' : '글로 쓰거나 마이크를 눌러봐!',
                                    hintStyle: TextStyle(fontSize: 12, color: (_isListening && _activeVoiceField == 'chat') ? const Color(0xFF7E57C2) : Colors.grey[400]),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    filled: true,
                                    fillColor: const Color(0xFFF9F7FC),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 🎤 [2번] 루미 질문창 마이크 버튼도 50x50으로 시원하게 확대
                              GestureDetector(
                                onTap: () => _toggleVoiceInput('chat'),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: (_isListening && _activeVoiceField == 'chat') ? Colors.redAccent : const Color(0xFFF3EDFA),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: (_isListening && _activeVoiceField == 'chat')
                                            ? Colors.redAccent.withOpacity(0.35)
                                            : const Color(0xFF7E57C2).withOpacity(0.15),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    (_isListening && _activeVoiceField == 'chat') ? Icons.mic : Icons.mic_none_rounded,
                                    color: (_isListening && _activeVoiceField == 'chat') ? Colors.white : const Color(0xFF7E57C2),
                                    size: 26,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () => _sendQuestionToLumi(_chatInputCtrl.text.trim()),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF7E57C2),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                ),
                                child: const Text('질문'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  CustomPaint(
                    size: const Size(22, 12),
                    painter: TrianglePainter(Colors.white),
                  ),
                  const SizedBox(height: 16),

                  _buildLumiAvatar(size: 110),
                  const SizedBox(height: 24),

                  if (_overlayMode != LumiOverlayMode.naming)
                    ElevatedButton.icon(
                      onPressed: () => _dismissLumiOverlay(),
                      icon: const Icon(Icons.brush, size: 20),
                      label: Text(
                        _overlayMode == LumiOverlayMode.chat ? '고마워, 이제 그릴래! 🎨' : '좋아, 그릴래! 🎨',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7E57C2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        elevation: 6,
                        shadowColor: const Color(0xFF7E57C2).withOpacity(0.5),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  데이터 모델 & 커스텀 페인터
// ═══════════════════════════════════════════════════════════════
class DrawingPath {
  final Color color;
  final double strokeWidth;
  final bool isEraser;
  final List<Offset> points;

  DrawingPath({required this.color, required this.strokeWidth, this.isEraser = false, required this.points});
}

class TransparentDrawingPainter extends CustomPainter {
  final List<DrawingPath> paths;
  TransparentDrawingPainter(this.paths);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    for (final path in paths) {
      if (path.points.isEmpty) continue;
      final paint = Paint()
        ..strokeWidth = path.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (path.isEraser) {
        paint.blendMode = BlendMode.clear;
      } else {
        paint.color = path.color;
        paint.blendMode = BlendMode.srcOver;
      }

      final drawPath = Path();
      drawPath.moveTo(path.points.first.dx, path.points.first.dy);
      for (int i = 1; i < path.points.length; i++) {
        drawPath.lineTo(path.points[i].dx, path.points[i].dy);
      }
      canvas.drawPath(drawPath, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(TransparentDrawingPainter oldDelegate) => true;
}

class MiniThumbnailPainter extends CustomPainter {
  final List<DrawingPath> paths;
  MiniThumbnailPainter(this.paths);

  @override
  void paint(Canvas canvas, Size size) {
    if (paths.isEmpty) return;

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final p in paths) {
      for (final pt in p.points) {
        if (pt.dx < minX) minX = pt.dx;
        if (pt.dx > maxX) maxX = pt.dx;
        if (pt.dy < minY) minY = pt.dy;
        if (pt.dy > maxY) maxY = pt.dy;
      }
    }

    final drawingWidth = maxX - minX;
    final drawingHeight = maxY - minY;
    if (drawingWidth <= 0 || drawingHeight <= 0) return;

    final scaleX = (size.width - 8) / drawingWidth;
    final scaleY = (size.height - 8) / drawingHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    canvas.save();
    canvas.translate(
      (size.width - drawingWidth * scale) / 2 - minX * scale,
      (size.height - drawingHeight * scale) / 2 - minY * scale,
    );
    canvas.scale(scale);

    for (final path in paths) {
      if (path.points.isEmpty || path.isEraser) continue;

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
    canvas.restore();
  }

  @override
  bool shouldRepaint(MiniThumbnailPainter oldDelegate) => true;
}

class TrianglePainter extends CustomPainter {
  final Color color;
  TrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}