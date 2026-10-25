import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:audioplayers/audioplayers.dart';
import 'story_preview_screen.dart';
import '../../theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CreationStage { choosing, drawing, askName, askDesc, askCustomWhat, askCustomRole, askStory, askEnding }

class StoryNote {
  final String slotId;
  final String about;
  final String question;
  final String answer;
  final bool byLumi;
  const StoryNote({required this.slotId, required this.about, required this.question, required this.answer, this.byLumi = false});
}

enum ChatRole { lumi, child }

class ChatMessage {
  final ChatRole role;
  final String text;
  ChatMessage(this.role, this.text);
}

class QuickReply {
  final String label;
  final String? emoji;
  final Color? color;
  final VoidCallback? onTap;
  final bool primary;
  const QuickReply({required this.label, this.emoji, this.color, this.onTap, this.primary = false});
}

class StoryCategory {
  final String id;
  final String title;
  final String fairyPrompt;
  final IconData icon;
  final String emoji;
  final Color color;
  final bool isRequired;

  const StoryCategory({
    required this.id,
    required this.title,
    required this.fairyPrompt,
    required this.icon,
    required this.emoji,
    required this.color,
    this.isRequired = false,
  });
}

class CustomStoryCreateScreen extends StatefulWidget {
  // 📖 보관함(수정모드)에서 넘겨받는 1~4화 줄거리 대본 캐시
  final Map<String, dynamic>? initialStoryData;
  final String? taleId; // 👈 [추가!] 보관함에서 넘어온 동화 고유 식별자

  const CustomStoryCreateScreen({
    super.key,
    this.initialStoryData,
    this.taleId, // 👈 [추가]
  });

  @override
  State<CustomStoryCreateScreen> createState() => _CustomStoryCreateScreenState();
}

class _CustomStoryCreateScreenState extends State<CustomStoryCreateScreen>
    with TickerProviderStateMixin {
  static const String _lumiImagePath = CrayongImages.wink;
  static const String _baseUrl = 'http://localhost:8000';
  static const Color _purple = AppColors.secondaryDark;
  static const Color _deep = AppColors.textPrimary;

  final List<StoryCategory> _allCategories = [
    StoryCategory(id: 'hero', title: '주인공', fairyPrompt: '좋아! 우리 멋진 모험을 이끌어갈 주인공을 그려줘\n사람, 동물, 로봇… 뭐든지 괜찮아!', icon: Icons.person_pin, emoji: '🧒', color: Color(0xFFE0A126), isRequired: true),
    StoryCategory(id: 'companion', title: '단짝 친구', fairyPrompt: '주인공 곁을 지켜줄 든든한 단짝 친구나 귀여운 동물 친구를 그려볼까?', icon: Icons.pets, emoji: '🐶', color: Color(0xFF5E9E4A)),
    StoryCategory(id: 'item', title: '마법 도구', fairyPrompt: '위험한 순간에 힘을 발휘할 신비한 마법 지팡이나 특별한 도구를 그려줘!', icon: Icons.auto_awesome, emoji: '🪄', color: Color(0xFFC9684B)),
    StoryCategory(id: 'place', title: '비밀 장소', fairyPrompt: '모험이 펼쳐질 장소를 그려줘! 우리 집, 마법의 성, 신비한 숲도 좋아.', icon: Icons.castle, emoji: '🏰', color: Color(0xFF4F93C2)),
    StoryCategory(id: 'vehicle', title: '특별한 탈것', fairyPrompt: '하늘을 나는 양탄자, 우주선, 구름 자전거처럼 신나는 탈것을 그려볼래?', icon: Icons.rocket_launch, emoji: '🚀', color: Color(0xFFE0A126)),
    StoryCategory(id: 'villain', title: '엉뚱한 악당', fairyPrompt: '이야기를 더 흥미진진하게 만들 귀여운 장난꾸러기 악당을 그려보자!', icon: Icons.mood_bad, emoji: '😈', color: Color(0xFF8A7360)),
    StoryCategory(id: 'food', title: '좋아하는 간식', fairyPrompt: '먹으면 힘이 솟아나는 달콤한 케이크나 마법 열매를 그려보는 건 어때?', icon: Icons.icecream, emoji: '🍰', color: Color(0xFFEE8C6E)),
    StoryCategory(id: 'treasure', title: '숨겨진 보물', fairyPrompt: '모험의 끝에서 발견할 반짝이는 보물 상자나 비밀 열쇠를 그려보자!', icon: Icons.vpn_key, emoji: '💎', color: Color(0xFF5E9E4A)),
  ];

  CreationStage _stage = CreationStage.choosing;
  String? _currentId;
  final List<String> _drawnOrder = [];
  final Map<String, String> _customSubject = {};
  String? _pendingCustomName;
  static const String _endingKey = '_ending';
  final Map<String, StoryNote> _storyNotes = {};
  String? _pendingStorySlot;
  String _pendingStoryQuestion = '';
  static const String _heroKey = '_hero';
  static const String _meetKey = '_meet';
  final Set<String> _askedMoments = {};
  String? _meetWith;
  bool _showHints = false;
  bool _inFollowUp = false;
  List<String> _currentHints = [];
  final math.Random _random = math.Random();

  // ── 갤러리 접기/펼치기 및 캔버스 화면 맞춤 ──
  bool _isGalleryCollapsed = false; // 갤러리 접힘 상태 플래그
  final TransformationController _transformCtrl = TransformationController();
  bool _isPanMode = false;
  final GlobalKey _workspaceKey = GlobalKey(); // 작업대 영역 크기 측정용 키
  static const Size _virtualCanvasSize = Size(2000, 1600);
  // ── 화면 맞춤 동적 도화지 크기 추적 ──
  Size _currentCanvasSize = const Size(1200, 800); // 현재 화면 카드 크기 자동 보관

  final Map<String, List<DrawingPath>> _slotPaths = {};
  final Map<String, bool> _slotAiDelegated = {};
  final Map<String, Uint8List?> _slotPngBytes = {};
  final Map<String, Uint8List?> _restoredBasePng = {}; // 👈 [추가!] 복원된 원본 밑그림 전용 보관소
  final Map<String, Map<String, String>> _slotDescriptions = {};

  late String _activeTaleId; // 👈 [추가!] 현재 작업 중인 동화의 격리 네임스페이스 ID

  final List<DrawingPath> _paths = [];
  final List<DrawingPath> _redoStack = [];
  DrawingPath? _currentPath;
  Color _selectedColor = const Color(0xFF4A3728);
  int _penLevel = 1;
  int _eraserLevel = 1;
  static const List<double> _penSizes = [4.0, 8.0, 14.0];
  static const List<double> _eraserSizes = [16.0, 30.0, 50.0];
  bool _isEraser = false;
  final GlobalKey _canvasKey = GlobalKey();

  final AudioPlayer _audioPlayer = AudioPlayer();
  final Map<String, Uint8List> _ttsCache = {};
  int _ttsSessionId = 0;

  late AnimationController _fairyAnimController;
  late Animation<double> _floatingAnim;
  late AnimationController _sceneController;

  final List<ChatMessage> _messages = [];
  bool _isLumiThinking = false;
  final ScrollController _chatScrollCtrl = ScrollController();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  final TextEditingController _chatInputCtrl = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  bool _isDialogShowing = false;
  Map<String, dynamic>? _cachedStoryData;

  final List<Color> _colorPalette = const [
    Color(0xFF4A3728),
    Color(0xFFEE8C6E),
    Color(0xFFFF9F1C),
    Color(0xFFFFD93D),
    Color(0xFF6BCB77),
    Color(0xFF4D96FF),
    Color(0xFF9B5DE5),
    Color(0xFFFF6FB5),
    Color(0xFF8D6E63),
    Color(0xFF7FD8FF),
    Color(0xFF9E9E9E),
  ];

  double get _currentStrokeWidth => _isEraser ? _eraserSizes[_eraserLevel] : _penSizes[_penLevel];

  StoryCategory _catById(String id) => _allCategories.firstWhere((c) => c.id == id);

  StoryCategory? get currentCat => _currentId == null ? null : _catById(_currentId!);

  List<StoryCategory> get _remainingCategories =>
      _allCategories.where((c) => !_drawnOrder.contains(c.id)).toList();

  bool get _heroDrawn {
    final heroPaths = _currentId == 'hero' ? _paths : (_slotPaths['hero'] ?? []);
    final hasPng = (_slotPngBytes['hero'] != null) || (_restoredBasePng['hero'] != null);
    return heroPaths.isNotEmpty || hasPng;
  }

  String _labelOf(String id) {
    final name = _slotDescriptions[id]?['name'];
    if (name != null && name.isNotEmpty) return name;
    return _customSubject[id] ?? _catById(id).title;
  }

  Map<String, Map<String, String>> _descriptionsForServer() {
    final result = <String, Map<String, String>>{};

    // 1. 이름 등록까지 마친 슬롯 처리
    _slotDescriptions.forEach((id, info) {
      final subject = _customSubject[id];
      if (subject == null) {
        result[id] = Map<String, String>.from(info);
        return;
      }
      final desc = info['desc'] ?? '';
      final parts = <String>[subject, '역할: ${_catById(id).title}'];
      if (desc.isNotEmpty) parts.add(desc);
      result[id] = {'name': info['name'] ?? subject, 'desc': parts.join(' / ')};
    });

    // 2. 🛡️ 방어 코드: 그림은 그렸는데 "다 그렸어!"를 깜빡한 슬롯도 기본 이름으로 자동 포함
    for (final id in _drawnOrder) {
      final hasDrawing = (_slotPaths[id]?.isNotEmpty ?? false) || (_slotAiDelegated[id] ?? false);
      if (hasDrawing && !result.containsKey(id)) {
        final cat = _catById(id);
        final defaultName = _customSubject[id] ?? cat.title;
        result[id] = {
          'name': defaultName,
          'desc': '$defaultName / 역할: ${cat.title}',
        };
      }
    }

    return result;
  }

// 🎯 [수정] 2000x1600 거대 도화지의 정중앙 영역을 화면에 빈틈없이 꽉 채우는 중앙 포커스 연산
  void _fitCanvasToScreen() {
    final RenderBox? box = _workspaceKey.currentContext?.findRenderObject() as RenderBox?;
    final Size viewportSize = (box != null && box.hasSize) ? box.size : _currentCanvasSize;

    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      _transformCtrl.value = Matrix4.identity();
      return;
    }

    // 도화지 중앙 1100x700 영역이 화면 틀을 100% 꽉 채우도록 지능형 줌인 배율 계산
    final double focusScale = math.max(
      viewportSize.width / 1200,
      viewportSize.height / 800,
    ).clamp(0.6, 1.5);

    // 2000x1600 거대 도화지의 정중앙이 화면 중심에 오도록 오프셋 계산
    final double dx = (viewportSize.width - (_virtualCanvasSize.width * focusScale)) / 2;
    final double dy = (viewportSize.height - (_virtualCanvasSize.height * focusScale)) / 2;

    setState(() {
      _transformCtrl.value = Matrix4.translationValues(dx, dy, 0.0)
        ..scale(focusScale, focusScale, 1.0);
    });
  }

  void _startCustom() {
    if (_isLumiThinking) return;
    _addChild('내가 정할래!');
    setState(() {
      _stage = CreationStage.askCustomWhat;
      _pendingCustomName = null;
    });
    _addLumi('좋아! 무엇을 그리고 싶어?\n말하거나 글로 써줘');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocusNode.requestFocus();
    });
  }

  void _receiveCustomWhat(String subject) {
    _addChild(subject);
    setState(() {
      _pendingCustomName = subject;
      _stage = CreationStage.askCustomRole;
    });
    _addLumi('$subject 정말 멋지다! 😆\n$subject은(는) 이야기에서 어떤 역할이야?');
  }

  Future<void> _assignCustom(String id) async {
    final subject = _pendingCustomName;
    if (subject == null) return;
    final cat = _catById(id);
    _addChild(cat.title);
    _customSubject[id] = subject;
    _slotDescriptions[id] = {'name': subject, 'desc': ''};
    _pendingCustomName = null;
    await _selectCategory(id, fromChip: false, announce: false);
    _addLumi('좋아! ${cat.title} "$subject"을(를) 그려보자 🎨\n다 그리면 "다 그렸어!"를 눌러줘');
  }

  Future<void> _receiveCustomRole(String roleText) async {
    final subject = _pendingCustomName;
    if (subject == null) return;

    final trimmedRole = roleText.trim();
    if (trimmedRole.isEmpty) return;

    // 1. 고유한 커스텀 카테고리 ID 생성 (예: custom_1712345678)
    final customId = 'custom_${DateTime.now().millisecondsSinceEpoch % 1000000}';

    // 2. 아이가 입력한 역할을 이름으로 갖는 새로운 카테고리 객체 생성
    final newCat = StoryCategory(
      id: customId,
      title: trimmedRole,
      fairyPrompt: '좋아! $trimmedRole "$subject"을(를) 멋지게 그려보자 🎨',
      icon: Icons.auto_awesome,
      emoji: '',
      color: const Color(0xFF5E9E4A),
    );

    // 3. 카테고리 목록에 추가하고 바로 캔버스 열기
    setState(() {
      _allCategories.add(newCat);
    });

    await _assignCustom(customId);
  }

  @override
  void initState() {
    super.initState();

    // 1. 애니메이션 컨트롤러 초기화
    _fairyAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _sceneController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();

    _floatingAnim = Tween<double>(begin: -4.0, end: 4.0).animate(
      CurvedAnimation(parent: _fairyAnimController, curve: Curves.easeInOut),
    );

    // 🎯 [핵심] 동화 ID 및 진입 경로 판별
    if (widget.taleId != null || widget.initialStoryData != null) {
      // 1. 보관함에서 진입한 경우: 해당 동화의 ID를 활성화하고 그 동화 그림만 복원
      _activeTaleId = widget.taleId ?? widget.initialStoryData?['tale_id'] ?? 'default_tale';
      _cachedStoryData = widget.initialStoryData;
      _loadPersistedSlotPngs(_activeTaleId); // 👈 해당 동화의 그림들만 로드!
    } else {
      // 2. 메인 화면에서 [나만의 동화 창작하기]로 진입한 경우:
      // 신규 고유 ID 생성 후, 이전 동화의 그림은 단 하나도 로드하지 않고 100% 빈 도화지로 시작!
      _activeTaleId = 'tale_${DateTime.now().millisecondsSinceEpoch}';
    }

    // 도화지 시점 중앙 정렬 및 상황별 요정 루미 인사말
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerCanvasView();
      if (!mounted) return;

      // 보관함에서 줄거리를 들고 온 경우 환영 멘트 분기
      if (widget.initialStoryData != null) {
        _addLumi('이전에 만든 이야기와 그림들을 불러왔어! 🎨\n그림을 수정하거나 자유롭게 더 그려봐');
      } else {
        _addLumi('안녕? 나는 크레용이야\n우리 같이 동화를 만들어보자~\n먼저 뭐부터 그릴래?');
      }
    });
  }

  // 기존 center 함수도 fit 함수로 일치시켜 오프셋 튕김 방지
  void _centerCanvasView() => _fitCanvasToScreen();

  @override
  void dispose() {
    _transformCtrl.dispose();
    _speech.stop();
    _audioPlayer.dispose();
    _fairyAnimController.dispose();
    _sceneController.dispose();
    _chatInputCtrl.dispose();
    _inputFocusNode.dispose();
    _chatScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _speakLumi(String text, {String? directBase64}) async {
    final int currentSession = ++_ttsSessionId;
    try {
      await _audioPlayer.stop();
      if (directBase64 != null && directBase64.isNotEmpty) {
        final bytes = base64Decode(directBase64);
        _ttsCache[text] = bytes;
        if (_ttsSessionId != currentSession) return;
        await _audioPlayer.play(BytesSource(bytes));
        return;
      }
      if (_ttsCache.containsKey(text)) {
        if (_ttsSessionId != currentSession) return;
        await _audioPlayer.play(BytesSource(_ttsCache[text]!));
        return;
      }
      final res = await http.post(
        Uri.parse('$_baseUrl/api/chat/tts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );
      if (_ttsSessionId != currentSession) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final String audioB64 = data['audio_base64'] ?? '';
        if (audioB64.isNotEmpty) {
          final bytes = base64Decode(audioB64);
          _ttsCache[text] = bytes;
          if (_ttsSessionId != currentSession) return;
          await _audioPlayer.play(BytesSource(bytes));
        }
      }
    } catch (e) {
      debugPrint('루미 음성 낭독 실패: $e');
    }
  }

  void _haltAudio() {
    _ttsSessionId++;
    _audioPlayer.stop();
    if (_isListening) {
      _speech.stop();
      _isListening = false;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollCtrl.hasClients) return;
      _chatScrollCtrl.animateTo(
        _chatScrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _addLumi(String text, {String? audioB64}) {
    setState(() => _messages.add(ChatMessage(ChatRole.lumi, text)));
    _scrollToBottom();
    _speakLumi(text, directBase64: audioB64);
  }

  void _addChild(String text) {
    setState(() => _messages.add(ChatMessage(ChatRole.child, text)));
    _scrollToBottom();
  }

  Future<void> _ensureSpeechInitialized() async {
    if (_speechAvailable) return;
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

  Future<void> _toggleVoiceInput() async {
    await _ensureSpeechInitialized();
    if (!mounted) return;
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('마이크 권한을 허용해 줘!')),
      );
      return;
    }
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }
    await _audioPlayer.stop();
    setState(() => _isListening = true);
    await _speech.listen(
      localeId: 'ko_KR',
      onResult: (result) {
        // 이미 최종 결과를 처리한 뒤 들어오는 늦은 콜백은 무시한다.
        if (!_isListening) return;

        final recognized = result.recognizedWords.trim();

        if (result.finalResult) {
          setState(() {
            _isListening = false;
            _chatInputCtrl.clear();
          });
          _speech.stop();

          if (recognized.isNotEmpty) {
            _handleInputSubmit(recognized);
          }
          return;
        }

        setState(() {
          _chatInputCtrl.text = result.recognizedWords;
          _chatInputCtrl.selection = TextSelection.collapsed(
            offset: _chatInputCtrl.text.length,
          );
        });
      },
    );
  }

  void _handleInputSubmit(String raw) {
    final text = raw.trim();
    if (text.isEmpty || _isLumiThinking) return;
    if (_isListening) {
      _speech.stop();
      setState(() => _isListening = false);
    }
    _chatInputCtrl.clear();
    switch (_stage) {
      case CreationStage.askName:
        _receiveName(text);
        break;
      case CreationStage.askDesc:
        _receiveDesc(text);
        break;
      case CreationStage.askCustomWhat:
        _receiveCustomWhat(text);
        break;
      // 👈 [추가!] 직접 타이핑한 역할 처리 분기
      case CreationStage.askCustomRole:
        _receiveCustomRole(text);
      case CreationStage.askStory:
      case CreationStage.askEnding:
        _answerStory(text);
        break;
      default:
        _sendQuestionToLumi(text);
    }
  }

  Future<void> _sendQuestionToLumi(String q) async {
    if (q.isEmpty) return;
    _addChild(q);
    setState(() => _isLumiThinking = true);
    _scrollToBottom();
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/chat/lumi'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'question': q,
          'category_title': currentCat?.title ?? '동화',
        }),
      );
      if (response.statusCode != 200) throw Exception('서버 응답 오류');
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final String replyText = data['reply'] ?? '';
      final String? audioB64 = data['audio_base64'];
      if (!mounted) return;
      setState(() => _isLumiThinking = false);
      _addLumi(replyText, audioB64: audioB64);
    } catch (e) {
      debugPrint('루미 API 통신 오류: $e');
      if (!mounted) return;
      setState(() => _isLumiThinking = false);
      _addLumi('"$q"라니 정말 기발해! 동화 속에서는 무엇이든 마법처럼 가능하니까 자유롭게 그려봐! 🎨');
    }
  }

  // ── 💾 SharedPreferences 키 정규화 및 영구 저장 ──

  // 접두사 'tale_' 중복을 방지하는 정규화 헬퍼
  String _cleanTaleId(String id) => id.replaceFirst(RegExp(r'^tale_'), '');

  // 슬롯별 PNG 이미지를 해당 동화 서랍에 영구 저장
  Future<void> _persistSlotPng(String slotId, Uint8List? pngBytes) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanId = _cleanTaleId(_activeTaleId);
    final key = 'tale_${cleanId}_sketch_png_$slotId';

    if (pngBytes == null) {
      await prefs.remove(key);
      await prefs.remove('tale_tale_${cleanId}_sketch_png_$slotId'); // 구형 중복 키도 청소
    } else {
      await prefs.setString(key, base64Encode(pngBytes));
    }
  }

  // 슬롯 메타데이터를 해당 동화 서랍에 영구 저장
  Future<void> _persistAllMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final cleanId = _cleanTaleId(_activeTaleId);

    await prefs.setString('tale_${cleanId}_drawn_order', jsonEncode(_drawnOrder));
    await prefs.setString('tale_${cleanId}_slot_descriptions', jsonEncode(_slotDescriptions));
    await prefs.setString('tale_${cleanId}_custom_subjects', jsonEncode(_customSubject));

    final customCats = _allCategories.where((c) => c.id.startsWith('custom_')).map((c) => {
      'id': c.id,
      'title': c.title,
      'fairyPrompt': c.fairyPrompt,
      'emoji': c.emoji,
      'color': c.color.value,
    }).toList();
    await prefs.setString('tale_${cleanId}_custom_categories', jsonEncode(customCats));
  }

// 🎯 스마트 4단계 키 매칭을 통한 그림 및 메타데이터 100% 복원
  Future<void> _loadPersistedSlotPngs(String targetTaleId) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanTarget = _cleanTaleId(targetTaleId);

    debugPrint('\n🔍 [에셋 복원 파이프라인 가동] 대상 Tale ID: "$targetTaleId" (정규화 ID: "$cleanTarget")');

    // ── 1. 커스텀 카테고리 복원 ──
    String? customCatsJson = prefs.getString('tale_${cleanTarget}_custom_categories') ??
        prefs.getString('tale_tale_${cleanTarget}_custom_categories');
    if (customCatsJson != null && customCatsJson.isNotEmpty) {
      final List customCats = jsonDecode(customCatsJson);
      for (final raw in customCats) {
        final String id = raw['id'];
        if (!_allCategories.any((c) => c.id == id)) {
          _allCategories.add(StoryCategory(
            id: id,
            title: raw['title'] ?? '친구',
            fairyPrompt: raw['fairyPrompt'] ?? '',
            icon: Icons.auto_awesome,
            emoji: raw['emoji'] ?? '',
            color: Color(raw['color'] ?? 0xFF7E57C2),
          ));
        }
      }
    }

    // ── 2. 슬롯 이름 및 커스텀 주제 복원 ──
    String? descJson = prefs.getString('tale_${cleanTarget}_slot_descriptions') ??
        prefs.getString('tale_tale_${cleanTarget}_slot_descriptions');
    if (descJson != null && descJson.isNotEmpty) {
      final Map<String, dynamic> rawDesc = jsonDecode(descJson);
      rawDesc.forEach((k, v) => _slotDescriptions[k] = Map<String, String>.from(v));
    }

    String? subjectJson = prefs.getString('tale_${cleanTarget}_custom_subjects') ??
        prefs.getString('tale_tale_${cleanTarget}_custom_subjects');
    if (subjectJson != null && subjectJson.isNotEmpty) {
      final Map<String, dynamic> rawSub = jsonDecode(subjectJson);
      rawSub.forEach((k, v) => _customSubject[k] = v.toString());
    }

    // ── 3. 슬롯 순서 복원 ──
    String? orderJson = prefs.getString('tale_${cleanTarget}_drawn_order') ??
        prefs.getString('tale_tale_${cleanTarget}_drawn_order');
    final List<String> loadedOrder = [];
    if (orderJson != null && orderJson.isNotEmpty) {
      loadedOrder.addAll(List<String>.from(jsonDecode(orderJson)));
    }

    // ── 4. 스마트 PNG 그림 키 검색 (4단계 안전망) ──
    final allKeys = prefs.getKeys().toList();
    final matchingKeys = <String>[];

    // 1차: 정상 정규화 키 탐색 (tale_{cleanTarget}_sketch_png_)
    final p1 = 'tale_${cleanTarget}_sketch_png_';
    matchingKeys.addAll(allKeys.where((k) => k.startsWith(p1)));

    // 2차: 구형 이중 접두사 키 탐색 (tale_tale_{cleanTarget}_sketch_png_)
    if (matchingKeys.isEmpty) {
      final p2 = 'tale_tale_${cleanTarget}_sketch_png_';
      matchingKeys.addAll(allKeys.where((k) => k.startsWith(p2)));
    }

    debugPrint('📦 [발견된 그림 키 수]: ${matchingKeys.length}개 -> $matchingKeys');

    // ── 5. PNG 데이터 디코딩 및 메모리 바인딩 ──
    for (final key in matchingKeys) {
      final slotId = key.split('_sketch_png_').last;
      final base64Str = prefs.getString(key);
      if (base64Str != null && base64Str.isNotEmpty) {
        try {
          final bytes = base64Decode(base64Str);
          _slotPngBytes[slotId] = bytes;
          _restoredBasePng[slotId] = bytes; // 👈 캔버스 밑그림 레이어에 직접 바인딩!
          if (!loadedOrder.contains(slotId)) loadedOrder.add(slotId);
        } catch (e) {
          debugPrint('⚠️ Base64 디코딩 실패 ($key): $e');
        }
      }
    }

    // ── 6. 화면 UI 상태 즉시 활성화 ──
    if (loadedOrder.isNotEmpty && mounted) {
      setState(() {
        _drawnOrder
          ..clear()
          ..addAll(loadedOrder);

        // 첫 번째 에셋(짱구)을 기본 선택하고 그리기 모드로 전환
        _currentId = _drawnOrder.first;
        _paths.clear();
        _stage = CreationStage.drawing;
      });

      debugPrint('🎉 [복원 완료] 총 ${_drawnOrder.length}개 에셋 복원 성공! (현재 슬롯: $_currentId)');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitCanvasToScreen();
      });
    } else {
      debugPrint('❌ [복원 실패] 복원할 수 있는 그림 데이터가 없습니다.');
    }
  }

// 🎯 [OpenAI gpt-image-2 & gpt-4o-mini 연동] 512x512 정규화 캡처 및 선 굵기 보정
  Future<Uint8List?> _captureCanvasToPng() async {
    final Uint8List? basePng = _currentId != null ? _restoredBasePng[_currentId] : null;
    final bool hasBasePng = basePng != null;

    // 그은 선도 없고 밑그림도 없으면 null
    if (_paths.isEmpty && !hasBasePng) return null;
    // 🎯 [중복 방지] 새로 그린 선이 전혀 없다면 재귀 크롭을 하지 않고 기존 이미지 원본 그대로 반환!
    if (_paths.isEmpty && hasBasePng) return basePng;

    try {
      // 1. 실제 그림이 존재하는 바운딩 박스 추적
      double minX = double.infinity, minY = double.infinity;
      double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

      for (final p in _paths) {
        if (p.isEraser) continue;
        for (final pt in p.points) {
          if (pt.dx < minX) minX = pt.dx;
          if (pt.dy < minY) minY = pt.dy;
          if (pt.dx > maxX) maxX = pt.dx;
          if (pt.dy > maxY) maxY = pt.dy;
        }
      }

      // 현재 화면 크기에 따른 정중앙 밑그림 오프셋
      const double centerLeft = (2000.0 - 512.0) / 2.0; // 744.0
      const double centerTop = (1600.0 - 512.0) / 2.0;  // 544.0

      if (hasBasePng) {
        minX = math.min(minX, centerLeft);
        minY = math.min(minY, centerTop);
        maxX = math.max(maxX, centerLeft + 512.0);
        maxY = math.max(maxY, centerTop + 512.0);
      }

      if (minX.isInfinite || minY.isInfinite) {
        if (hasBasePng) {
          minX = centerLeft;
          minY = centerTop;
          maxX = centerLeft + 512.0;
          maxY = centerTop + 512.0;
        } else {
          return null;
        }
      }

      // 2. 여백 28px 추가 및 정사각형 크롭 영역 산출
      const double padding = 28.0;
      minX = math.max(0.0, minX - padding);
      minY = math.max(0.0, minY - padding);
      // 🎯 [수정] 2000x1600 도화지 전역에서 선이 잘리지 않도록 virtualCanvasSize 기준으로 제한
      maxX = math.min(_virtualCanvasSize.width, maxX + padding);
      maxY = math.min(_virtualCanvasSize.height, maxY + padding);

      final double width = (maxX - minX).clamp(10.0, _virtualCanvasSize.width);
      final double height = (maxY - minY).clamp(10.0, _virtualCanvasSize.height);
      final double boxSize = math.max(width, height);
      final double cx = (minX + maxX) / 2.0;
      final double cy = (minY + maxY) / 2.0;
      final Rect cropRect = Rect.fromCenter(center: Offset(cx, cy), width: boxSize, height: boxSize);

      // 3. 512x512 오프스크린 캔버스 렌더링
      const double exportSize = 512.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, exportSize, exportSize));

      canvas.saveLayer(const Rect.fromLTWH(0, 0, exportSize, exportSize), Paint());

      final double scale = exportSize / boxSize;
      canvas.scale(scale, scale);
      canvas.translate(-cropRect.left, -cropRect.top);

      // 🖼️ 이전 PNG 밑그림 레이어 병합
      if (hasBasePng) {
        final codec = await ui.instantiateImageCodec(basePng);
        final frame = await codec.getNextFrame();
        canvas.drawImage(frame.image, const Offset(centerLeft, centerTop), Paint());
      }

      // ✏️ 신규 선화 렌더링 + 최소 2.5px 선 굵기 보정
      for (final p in _paths) {
        if (p.points.isEmpty) continue;

        final double effectiveWidth = p.isEraser
            ? p.strokeWidth
            : math.max(p.strokeWidth, 2.5 / scale);

        final paint = Paint()
          ..color = p.isEraser ? const Color(0x00000000) : p.color
          ..strokeWidth = effectiveWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke
          ..blendMode = p.isEraser ? BlendMode.clear : BlendMode.srcOver;

        if (p.points.length == 1) {
          canvas.drawPoints(ui.PointMode.points, [p.points.first], paint);
        } else {
          final drawPath = Path()..moveTo(p.points.first.dx, p.points.first.dy);
          for (int i = 1; i < p.points.length; i++) {
            drawPath.lineTo(p.points[i].dx, p.points[i].dy);
          }
          canvas.drawPath(drawPath, paint);
        }
      }

      canvas.restore();

      final picture = recorder.endRecording();
      final ui.Image img = await picture.toImage(exportSize.toInt(), exportSize.toInt());
      final ByteData? byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e, stack) {
      debugPrint('⚠️ [OpenAI gpt-image-2 파이프라인] PNG 캡처 실패: $e\n$stack');
      return null;
    }
  }

  Future<void> _saveCurrentSlot() async {
    final id = _currentId;
    if (id == null) return;

    // 🎯 1. 화면에 있는 벡터 선화 목록을 슬롯에 100% 온전히 보존 (절대 지우지 않음!)
    _slotPaths[id] = List.from(_paths);

    // 🎯 2. 아이가 그린 선이나 밑그림이 있을 때 백엔드 전달용 PNG 바이트 생성
    if (_paths.isNotEmpty || _restoredBasePng[id] != null) {
      _slotAiDelegated[id] = false;
      final newPng = await _captureCanvasToPng();
      if (newPng != null) {
        _slotPngBytes[id] = newPng;
        // ⚠️ [핵심] 신규 창작 중에는 _restoredBasePng에 덮어쓰지 않고,
        // _paths와 _slotPaths도 비우지 않음! (획 단위 편집 보존)
        await _persistSlotPng(id, newPng);
      }
    } else {
      if (_slotPngBytes[id] != null) {
        await _persistSlotPng(id, _slotPngBytes[id]);
      }
    }

    await _persistAllMetadata();
  }

  Future<void> _selectCategory(String id, {bool fromChip = true, bool announce = true}) async {
    if (_isLumiThinking) return;
    final cat = _catById(id);
    final revisit = _drawnOrder.contains(id);
    if (id != _currentId) await _saveCurrentSlot();
    _haltAudio();
    if (!mounted) return;
    setState(() {
      _currentId = id;
      _paths
        ..clear()
        ..addAll(_slotPaths[id] ?? []);
      _redoStack.clear();
      _isEraser = false;
      _stage = CreationStage.drawing;
      if (!revisit) _drawnOrder.add(id);
    });

    // 🎯 [추가] 슬롯 이동 직후 도화지 시점을 100% 꽉 찬 중앙 포커스로 자동 복구!
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitCanvasToScreen();
    });

    if (fromChip) _addChild(revisit ? '${_labelOf(id)} 고칠래!' : '${cat.title} 그릴래!');
    if (!announce) return;
    if (revisit) {
      _addLumi('좋아! ${_labelOf(id)}을(를) 다시 고쳐보자.\n다 고치면 "다 그렸어!"를 눌러줘 🎨');
    } else {
      _addLumi(cat.fairyPrompt);
    }
  }

  Future<void> _goChoosing({String? childSays, String prefix = ''}) async {
    if (_isLumiThinking) return;
    await _saveCurrentSlot();
    if (!mounted) return;
    setState(() => _stage = CreationStage.choosing);
    // 🎯 [추가] 키보드가 닫히고 choosing 모드로 갈 때 캔버스 시점 자동 맞춤
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitCanvasToScreen();
    });

    if (childSays != null) _addChild(childSays);
    final message = _remainingCategories.isEmpty
        ? '와! 준비한 걸 전부 다 그렸어 🎉\n이제 우리 동화를 만들어볼까?'
        : _heroDrawn
            ? '그래, 그 다음은 뭘 그릴래?\n다 그렸으면 동화를 만들어도 좋아!'
            : '그래, 그 다음은 뭘 그릴래?';
    _addLumi('$prefix$message');
  }

  void _continueDrawing() {
    final id = _currentId;
    if (id == null) return;
    _addChild('${_labelOf(id)} 계속 그릴래!');
    setState(() => _stage = CreationStage.drawing);

    // 🎯 [추가] 그리기 재개 시에도 뷰포트 중앙 맞춤
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitCanvasToScreen();
    });

    _addLumi('좋아, 이어서 그려보자! 🎨');
  }

  void _startNaming() {
    final cat = currentCat;
    if (cat == null || _isLumiThinking) return;
    final hasDrawing = _paths.isNotEmpty || (_restoredBasePng[cat.id] != null) || (_slotPngBytes[cat.id] != null);
    if (!hasDrawing) {
      _addLumi('아직 아무것도 안 그렸어! 먼저 ${cat.title}을(를) 그려줘 🎨');
      return;
    }
    _addChild('다 그렸어!');
    setState(() => _stage = CreationStage.askName);
    final existing = _slotDescriptions[cat.id]?['name'];
    _addLumi(existing != null && existing.isNotEmpty
        ? '정말 멋지게 그렸어!\n이름은 그대로 "$existing"(으)로 할까, 아니면 새 이름을 알려줄래?'
        : '정말 멋지게 그렸어!\n이 ${cat.title}의 이름은 뭐야?');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocusNode.requestFocus();
    });
  }

  void _receiveName(String name, {bool silent = false}) {
    final id = _currentId;
    if (id == null) return;
    if (!silent) _addChild(name);
    _slotDescriptions[id] = {
      'name': name,
      'desc': _slotDescriptions[id]?['desc'] ?? '',
    };
    setState(() => _stage = CreationStage.askDesc);
    _addLumi('"$name"! 멋진 이름이다 😊\n$name은(는) 어떤 특별한 점이나 능력이 있어?');
  }

  Future<void> _receiveDesc(String desc, {bool skip = false}) async {
    final id = _currentId;
    if (id == null) return;
    _addChild(skip ? '없어, 넘어갈래' : desc);
    _slotDescriptions[id] = {
      'name': _slotDescriptions[id]?['name'] ?? _catById(id).title,
      'desc': skip ? (_slotDescriptions[id]?['desc'] ?? '') : desc,
    };
    final prefix = skip ? '알겠어! ' : '알려줘서 고마워! 크레용이 꼭 기억할게\n';
    final moment = _storyMomentAfter(id);
    if (moment == null) {
      await _goChoosing(prefix: prefix);
    } else {
      _askStoryQuestion(moment, prefix: prefix);
    }
  }

  String? _storyMomentAfter(String id) {
    if (id == 'hero' && !_askedMoments.contains(_heroKey)) return _heroKey;
    const characterSlots = {'companion', 'villain'};
    if (characterSlots.contains(id) && !_askedMoments.contains(_meetKey)) {
      _meetWith = id;
      return _meetKey;
    }
    return null;
  }

  String get _heroName => _drawnOrder.contains('hero') ? _labelOf('hero') : '주인공';

  bool _hasBatchim(String word) {
    if (word.isEmpty) return false;
    final code = word.runes.last;
    if (code < 0xAC00 || code > 0xD7A3) return false;
    return (code - 0xAC00) % 28 != 0;
  }

  String _j(String word, String withBatchim, String withoutBatchim) =>
      '$word${_hasBatchim(word) ? withBatchim : withoutBatchim}';

  String _storyQuestionFor(String key) {
    final h = _heroName;
    switch (key) {
      case _heroKey:
        return '${_j(h, '은', '는')} 어떤 친구야?\n어떤 모험을 떠나면 재밌을까? 💭';
      case _meetKey:
        final x = _meetWith == null ? '친구' : _labelOf(_meetWith!);
        if (_meetWith == 'villain') {
          return '앗, ${_j(x, '이', '가')} 나타났어! 😮\n${_j(x, '이', '가')} 무슨 일을 꾸미고 있을까?';
        }
        return '${_j(h, '이랑', '랑')} ${_j(x, '이', '가')} 만나면\n무슨 일이 생길까? 💭';
      default:
        return '이제 동화를 만들 차례야! 📖\n어떤 내용의 동화를 만들고 싶은지 말해줘!';
    }
  }

  List<String> _hintPoolFor(String key) {
    final h = _heroName;
    switch (key) {
      case _heroKey:
        return [
          '${_j(h, '이', '가')} 보물 지도를 발견해',
          '${_j(h, '이', '가')} 하늘을 나는 꿈을 꿔',
          '${_j(h, '이', '가')} 길 잃은 아기 동물을 만나',
          '${_j(h, '이', '가')} 숲속 마법 문을 열어',
          '${h}네 집에 이상한 편지가 와',
          '${_j(h, '이', '가')} 별똥별에 소원을 빌어',
          '${_j(h, '이', '가')} 무지개 끝을 찾아 떠나',
        ];
      case _meetKey:
        final x = _meetWith == null ? '친구' : _labelOf(_meetWith!);
        if (_meetWith == 'villain') {
          return [
            '${_j(x, '이', '가')} 마을의 보물을 숨겨버려',
            '${_j(x, '이', '가')} 사실은 외로웠던 거야',
            '${_j(x, '이', '가')} 온 세상 간식을 다 먹어버려',
            '${_j(x, '이', '가')} 마을에 장난 마법을 걸어',
            '${_j(x, '이', '가')} ${_j(h, '이랑', '랑')} 시합을 하자고 해',
          ];
        }
        return [
          '${_j(x, '이', '가')} 위험한 순간에 ${_j(h, '을', '를')} 구해줘',
          '둘이 같이 비밀 기지를 만들어',
          '${_j(x, '이', '가')} 길을 잃어서 ${_j(h, '이', '가')} 도와줘',
          '둘이 소원 열매를 찾으러 떠나',
          '처음엔 싸웠지만 금방 친해져',
        ];
      default:
        return [
          '${_j(h, '이', '가')} 보물을 찾으러 모험을 떠나',
          '${_j(h, '이', '가')} 친구를 도와주는 이야기',
          '${_j(h, '이', '가')} 마법의 숲에서 신기한 일을 겪어',
          '${_j(h, '이', '가')} 비밀 장소를 발견해',
          '${_j(h, '이', '가')} 어려운 문제를 용기 있게 해결해',
          '${_j(h, '이', '가')} 새로운 친구들을 만나는 이야기',
        ];
    }
  }

  String _noteEmoji(String key) {
    if (key == _heroKey) return _catById('hero').emoji;
    if (key == _meetKey) return _catById(_meetWith ?? 'companion').emoji;
    return '🏁';
  }

  Color _noteColor(String key) {
    if (key == _heroKey) return _catById('hero').color;
    if (key == _meetKey) return _catById(_meetWith ?? 'companion').color;
    return const Color(0xFFFFC93C);
  }

  void _askStoryQuestion(String key, {String prefix = ''}) {
    final question = _storyQuestionFor(key);
    _askedMoments.add(key);
    setState(() {
      _stage = key == _endingKey ? CreationStage.askEnding : CreationStage.askStory;
      _pendingStorySlot = key;
      _pendingStoryQuestion = question;
      _showHints = false;
      _inFollowUp = false;
      _currentHints = [];
    });
    _addLumi('$prefix$question');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocusNode.requestFocus();
    });
  }

  void _askEnding() {
    if (_isLumiThinking) return;
    _askStoryQuestion(_endingKey);
  }

  void _showStoryHints() {
    final key = _pendingStorySlot;
    if (key == null) return;
    final pool = List<String>.from(_hintPoolFor(key))..shuffle(_random);
    _addChild('잘 모르겠어');
    setState(() {
      _showHints = true;
      _currentHints = pool.take(3).toList();
    });
    _addLumi('그럼 이런 건 어때? 🤔\n마음에 드는 걸 골라도 되고,\n다른 생각이 나면 그냥 말해줘!');
  }

  Future<void> _answerStory(String answer, {bool byLumi = false, bool fromHint = false}) async {
    final key = _pendingStorySlot;
    if (key == null) return;
    var finalAnswer = answer;
    if (byLumi) {
      final pool = _hintPoolFor(key);
      finalAnswer = pool[_random.nextInt(pool.length)];
    }
    _addChild(byLumi ? '크레용이 정해줘!' : answer);

    if (_inFollowUp) {
      final prev = _storyNotes[key];
      if (prev != null) {
        _storyNotes[key] = StoryNote(
          slotId: key,
          about: prev.about,
          question: prev.question,
          answer: '${prev.answer} → $finalAnswer',
          byLumi: prev.byLumi,
        );
      }
      await _finishStoryMoment(key, '우와, 정말 멋진 이야기야! 🤩 ');
      return;
    }

    _storyNotes[key] = StoryNote(
      slotId: key,
      about: key == _endingKey ? '이야기 내용' : (key == _heroKey ? _heroName : (_meetWith == null ? '만남' : _labelOf(_meetWith!))),
      question: _pendingStoryQuestion,
      answer: finalAnswer,
      byLumi: byLumi,
    );

    if (!byLumi && !fromHint && key != _endingKey) {
      setState(() {
        _inFollowUp = true;
        _showHints = false;
      });
      _addLumi('"$finalAnswer"(이)라니, 정말 재밌겠다! 😆\n그래서 그 다음엔 어떻게 될까?');
      return;
    }

    final reaction = byLumi ? '크레용은 "$finalAnswer"(이)가 좋을 것 같아! ' : '좋아, "$finalAnswer"! ';
    await _finishStoryMoment(key, reaction);
  }

  Future<void> _finishStoryMoment(String key, String reaction) async {
    setState(() {
      _pendingStorySlot = null;
      _inFollowUp = false;
      _showHints = false;
    });
    if (key == _endingKey) {
      setState(() => _stage = CreationStage.choosing);
      _addLumi('$reaction\n그럼 우리가 정한 이야기로 동화를 만들어볼게');
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) _proceedToStoryReview();
      return;
    }
    await _goChoosing(prefix: '$reaction이야기에 꼭 넣을게 📜\n');
  }

  Future<void> _skipStory() async {
    final key = _pendingStorySlot;
    if (_inFollowUp && key != null) {
      _addChild('이게 다야!');
      await _finishStoryMoment(key, '좋아, 알겠어! ');
      return;
    }
    _addChild(key == _endingKey ? '그림 더 그릴래' : '넘어갈래');
    setState(() {
      _pendingStorySlot = null;
      _showHints = false;
    });
    if (key == _endingKey) {
      setState(() => _stage = CreationStage.choosing);
      _addLumi('좋아, 더 그리고 와도 돼! 다 되면 "동화 만들기"를 눌러줘 😊');
      return;
    }
    await _goChoosing(prefix: '알겠어! ');
  }

  void _removeStoryNote(String id) {
    setState(() => _storyNotes.remove(id));
  }

  List<Map<String, String>> _storyNotesForServer() {
    return _storyNotes.values
        .map((n) => {
              'slot_id': n.slotId,
              'about': n.about,
              'question': n.question,
              'answer': n.answer,
              'decided_by': n.byLumi ? 'lumi' : 'child',
            })
        .toList();
  }

  Future<void> _delegateToAi() async {
    final cat = currentCat;
    if (cat == null || cat.isRequired || _isLumiThinking) return;
    setState(() {
      _paths.clear();
      _redoStack.clear();
      _slotPaths[cat.id] = [];
      _slotPngBytes[cat.id] = null;
      _slotAiDelegated[cat.id] = true;
      _slotDescriptions[cat.id] = {'name': '${_customSubject[cat.id] ?? cat.title} (AI 생성)', 'desc': '요정이 대신 상상해서 그릴 예정'};
    });
    _addChild('크레용이 대신 그려줘!');
    await _goChoosing(prefix: '${cat.title}은(는) 크레용이 마법으로 그려줄게!\n');
  }

  void _clearCanvas() {
    final id = _currentId;
    if (id == null) return;
    setState(() {
      _paths.clear();
      _redoStack.clear();
      _slotPaths[id] = [];
      _slotPngBytes[id] = null;
      _restoredBasePng[id] = null; // 👈 [이 줄 추가!]
      _slotAiDelegated[id] = false;
      _slotDescriptions.remove(id);
    });
  }

  // 🗑️ 카테고리 슬롯 완전 삭제 함수
  Future<void> _deleteCategorySlot(String id) async {
    final cat = _catById(id);

    // 1. 필수 카테고리(주인공)는 삭제 방지
    if (cat.isRequired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('동화의 대장인 주인공은 삭제할 수 없어! 🧒'),
          backgroundColor: Color(0xFFD9604F),
        ),
      );
      return;
    }

    // 2. 실수 방지 확인 다이얼로그
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Color(0xFFFF5252), size: 26),
            SizedBox(width: 8),
            Text('그림 지우기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _deep)),
          ],
        ),
        content: Text(
          '\'${_labelOf(id)}\' 그림을 정말 지울까?\n지우면 처음부터 다시 그려야 해! 😢',
          style: const TextStyle(fontSize: 14, color: Color(0xFF4A3728), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('남겨둘래', style: TextStyle(color: _sub, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5252),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('지우기', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    // 3. 상태 데이터에서 완전 삭제
    setState(() {
      _drawnOrder.remove(id);
      _slotPaths.remove(id);
      _slotPngBytes.remove(id);
      _slotAiDelegated.remove(id);
      _slotDescriptions.remove(id);
      _customSubject.remove(id);
      _storyNotes.remove(id);

      // '내가 정할래'로 추가된 동적 커스텀 슬롯이면 전체 카테고리 목록에서도 제거
      if (id.startsWith('custom_')) {
        _allCategories.removeWhere((c) => c.id == id);
      }

      // 만약 현재 열려있던 슬롯을 지웠다면 선택 해제 및 choosing 단계로 복귀
      if (_currentId == id) {
        _currentId = null;
        _paths.clear();
        _redoStack.clear();
        _stage = CreationStage.choosing;
      }
    });

    // 🎯 [추가] 로컬 디스크에서도 삭제 동기화
    await _persistSlotPng(id, null);
    await _persistAllMetadata();

    _addLumi('\'${cat.title}\' 그림을 지웠어! 다른 걸 골라보자');
  }

  Future<void> _proceedToStoryReview() async {
    if (_isLumiThinking) return;
    await _saveCurrentSlot();
    if (!mounted) return;

    final bool hasHero = (_slotPaths['hero']?.isNotEmpty ?? false) ||
        (_slotPngBytes['hero'] != null) ||
        (_restoredBasePng['hero'] != null);

    if (!hasHero) {
      const warnText = '이야기의 대장이 될 주인공은 꼭 직접 그려줘야 해! 🎨';
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(warnText), backgroundColor: Color(0xFFD9604F)),
      );
      await _selectCategory('hero', fromChip: false, announce: false);
      _addLumi(warnText);
      return;
    }

    if (!_storyNotes.containsKey(_endingKey)) {
      _askEnding();
      return;
    }

    // 이전 줄거리가 있으면 묻지 않고 그대로 이어감 (그림이 바뀐 캐릭터가 나오는 페이지만 미리보기에서 다시 그림)

    _haltAudio();
    if (!mounted) return;

    debugPrint('story_notes: ${jsonEncode(_storyNotesForServer())}');

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoryPreviewScreen(
          assetPngBytes: _slotPngBytes,
          aiDelegated: _slotAiDelegated,
          assetDescriptions: _descriptionsForServer(),
          storyNotes: _storyNotesForServer(), // 🎯 [추가!] 아이와 루미의 대화 기록 전달!
          cachedStoryData: _cachedStoryData,
          taleId: _activeTaleId, // 👈 [추가!] 동화 고유 식별자 전달
        ),
      ),
    );

    if (result is Map<String, dynamic>) {
      setState(() => _cachedStoryData = result);
    }

    _haltAudio();
    if (!mounted) return;
    setState(() => _stage = CreationStage.choosing);
    _addLumi('그림을 더 고치고 싶으면 위에 있는 그림을 눌러봐!\n새로 그리고 싶은 것도 골라줘 😊');
  }

  void _handleSmartBack() {
    if (_stage == CreationStage.askStory || _stage == CreationStage.askEnding) {
      _skipStory();
      return;
    }
    if (_stage == CreationStage.askCustomWhat || _stage == CreationStage.askCustomRole) {
      _goChoosing(childSays: '그만할래!');
      return;
    }
    if (_stage == CreationStage.askName || _stage == CreationStage.askDesc) {
      setState(() => _stage = CreationStage.drawing);
      _addLumi('그래, 더 그려도 좋아! 다 그리면 알려줘 🎨');
      return;
    }
    _showExitConfirmDialog();
  }

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
            Text('동화 만들기 나가기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _deep)),
          ],
        ),
        content: const Text(
          '지금 나가면 정성껏 그린 그림과 이야기가 모두 사라져요.\n정말 나갈까요? 😢',
          style: TextStyle(fontSize: 14, color: Color(0xFF4A3728), height: 1.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _purple),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('계속 그릴래', style: TextStyle(color: _purple, fontWeight: FontWeight.bold)),
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
      _haltAudio();
      Navigator.pop(context);
    }
  }



  static const Color _ink = AppColors.textPrimary;
  static const Color _sub = AppColors.textSecondary;
  static const Color _purpleDark = Color(0xFF457A36);
  static const Color _yellow = AppColors.primary;
  static const Color _green = Color(0xFF6FB043);
  static const Color _cardLine = AppColors.border;
  static const Color _cardEdge = Color(0xFFE6D3AE);

  Color _darken(Color c, [double amount = 0.16]) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
  }

  Color _tint(Color c, [double amount = 0.88]) => Color.lerp(c, Colors.white, amount)!;

  Color _onColor(Color c) => c.computeLuminance() > 0.55 ? _ink : Colors.white;

  BoxDecoration _chunky({
    required Color color,
    Color? edge,
    double radius = 24,
    double depth = 5,
    Color? border,
    double borderWidth = 2.5,
    BoxShape shape = BoxShape.rectangle,
  }) {
    return BoxDecoration(
      color: color,
      shape: shape,
      borderRadius: shape == BoxShape.circle ? null : BorderRadius.circular(radius),
      border: border == null ? null : Border.all(color: border, width: borderWidth),
      boxShadow: [BoxShadow(color: edge ?? _darken(color), offset: Offset(0, depth))],
    );
  }

  BoxDecoration _card({double radius = 30}) =>
      _chunky(color: Colors.white, edge: _cardEdge, radius: radius, depth: 6, border: _cardLine);

  Widget _buildLumiAvatar({required double size, bool ring = false}) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ring ? size * 0.06 : 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: ring ? null : Border.all(color: _cardLine, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), offset: const Offset(0, 3))],
      ),
      child: ClipOval(
        child: Container(
          color: AppColors.secondaryLight,
          padding: EdgeInsets.all(size * 0.06),
          child: Image.asset(_lumiImagePath, fit: BoxFit.contain),
        ),
      ),
    );
  }

  ThemeData _kidsTheme(BuildContext context) {
    final base = Theme.of(context);
    final String? kidsFont = GoogleFonts.poorStory().fontFamily;
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: kidsFont, bodyColor: _ink, displayColor: _ink),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: kidsFont),
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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _handleSmartBack();
          });
        },
        child: Scaffold(
          backgroundColor: const Color(0xFFFFF3DC),
          body: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _KidsScenePainter(_sceneController)),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    _buildTopBar(),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 900;
                          if (wide) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(width: 390, child: _buildChatPanel()),
                                  const SizedBox(width: 20),
                                  Expanded(child: _buildWorkspace()),
                                ],
                              ),
                            );
                          }
                          final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
                          if (keyboardOpen) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                              child: _buildChatPanel(),
                            );
                          }
                          final double chatHeight = (constraints.maxHeight * 0.38).clamp(230.0, 340.0).toDouble();
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                            child: Column(
                              children: [
                                SizedBox(height: chatHeight, child: _buildChatPanel()),
                                const SizedBox(height: 14),
                                Expanded(child: _buildWorkspace()),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final ready = _heroDrawn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        children: [
          _Pressable(
            onTap: _handleSmartBack,
            child: Container(
              width: 48,
              height: 48,
              decoration: _chunky(color: Colors.white, edge: const Color(0xFFE6D3AE), shape: BoxShape.circle, depth: 4),
              child: const Icon(Icons.arrow_back_rounded, size: 26, color: _ink),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '나만의 동화 창작하기',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 26,
                    color: _ink,
                    letterSpacing: -0.3,
                    shadows: [Shadow(color: Colors.white.withValues(alpha: 0.9), offset: const Offset(0, 2))],
                  ),
                ),
                const Text('크레용이랑 이야기하며 그림을 그려요',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: Color(0xFF8A7360))),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _Pressable(
            onTap: _proceedToStoryReview,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: ready
                  ? _chunky(color: _yellow, radius: 30, depth: 5)
                  : _chunky(color: const Color(0xFFF1E3C8), radius: 30, depth: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('📖', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text('이야기 짓기', style: TextStyle(fontSize: 17, color: ready ? _ink : const Color(0xFFBFAE9C))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspace() {
    return Column(
      children: [
        _buildGallery(),
        const SizedBox(height: 14),
        Expanded(child: _buildCanvasArea()),
        const SizedBox(height: 14),
        _buildDrawingDock(),
      ],
    );
  }

  Widget _buildChatPanel() {
    final replies = _isLumiThinking ? <QuickReply>[] : _buildQuickReplies();
    return Container(
      decoration: _card(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Column(
          children: [
            _buildChatHeader(),
            Expanded(
              child: Container(
                color: const Color(0xFFFFFDF7),
                child: ListView(
                  controller: _chatScrollCtrl,
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
                  children: [
                    for (int i = 0; i < _messages.length; i++)
                      _AppearIn(key: ValueKey('msg_$i'), child: _buildMessageBubble(_messages[i])),
                    if (_isLumiThinking) _AppearIn(key: const ValueKey('typing'), child: _buildTypingBubble()),
                    if (replies.isNotEmpty)
                      _AppearIn(
                        key: ValueKey('qr_${_messages.length}_${_stage.name}_${_currentId ?? ''}'),
                        delay: const Duration(milliseconds: 180),
                        child: _buildQuickReplyWrap(replies),
                      ),
                  ],
                ),
              ),
            ),
            _buildInputRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildChatHeader() {
    final cat = currentCat;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: const BoxDecoration(
        color: AppColors.secondaryLight,
        border: Border(bottom: BorderSide(color: Color(0xFFBFDDA5), width: 2)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _floatingAnim,
                builder: (context, child) => Transform.translate(offset: Offset(0, _floatingAnim.value), child: child),
                child: _buildLumiAvatar(size: 50, ring: true),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('크레용', style: AppTextStyles.headingMedium()),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isLumiThinking ? _yellow : AppColors.secondaryDark,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _isLumiThinking
                                  ? '생각하는 중…'
                                  : cat == null
                                      ? '같이 동화 만들자!'
                                      : '${cat.emoji} ${_labelOf(cat.id)} 그리는 중',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, color: Color(0xFF3E6F2E)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _Pressable(
                onTap: () {
                  final last = _messages.lastWhere(
                    (m) => m.role == ChatRole.lumi,
                    orElse: () => ChatMessage(ChatRole.lumi, ''),
                  );
                  if (last.text.isNotEmpty) _speakLumi(last.text);
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: _chunky(color: Colors.white, edge: _purpleDark, shape: BoxShape.circle, depth: 4),
                  child: const Icon(Icons.volume_up_rounded, size: 22, color: _purple),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage m) {
    final isLumi = m.role == ChatRole.lumi;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(isLumi ? 6 : 24),
      topRight: Radius.circular(isLumi ? 24 : 6),
      bottomLeft: const Radius.circular(24),
      bottomRight: const Radius.circular(24),
    );
    final bubble = Flexible(
      child: GestureDetector(
        onTap: isLumi ? () => _speakLumi(m.text) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isLumi ? Colors.white : AppColors.primaryLight,
            borderRadius: radius,
            border: Border.all(color: isLumi ? _cardLine : AppColors.primary, width: 2),
            boxShadow: [BoxShadow(color: isLumi ? _cardEdge : AppColors.primaryDark, offset: const Offset(0, 3))],
          ),
          child: Text(
            m.text,
            style: AppTextStyles.bodyLarge(color: _ink).copyWith(fontSize: 17, height: 1.5),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: isLumi ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: isLumi
            ? [_buildLumiAvatar(size: 36), const SizedBox(width: 8), bubble, const SizedBox(width: 24)]
            : [const SizedBox(width: 56), bubble],
      ),
    );
  }

  Widget _buildTypingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          _buildLumiAvatar(size: 36),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(24),
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              border: Border.all(color: _cardLine, width: 2),
              boxShadow: const [BoxShadow(color: _cardEdge, offset: Offset(0, 3))],
            ),
            child: AnimatedBuilder(
              animation: _fairyAnimController,
              builder: (context, _) {
                final t = _fairyAnimController.value;
                const dots = [Color(0xFFEE8C6E), _yellow, Color(0xFF6FB043)];
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final phase = ((t * 3) - i).clamp(0.0, 1.0);
                    return Transform.translate(
                      offset: Offset(0, -4 * phase),
                      child: Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(color: dots[i], shape: BoxShape.circle),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<QuickReply> _buildQuickReplies() {
    final cat = currentCat;
    switch (_stage) {
      case CreationStage.choosing:
        return [
          for (final c in _remainingCategories)
            QuickReply(
              label: c.isRequired ? '${c.title} (필수)' : c.title,
              emoji: c.emoji,
              color: c.color,
              onTap: () => _selectCategory(c.id),
            ),
          if (_currentId != null)
            QuickReply(label: '${_labelOf(_currentId!)} 계속 그릴래', emoji: '🖍️', onTap: _continueDrawing),
          if (_remainingCategories.isNotEmpty)
            QuickReply(label: '내가 정할래!', emoji: '✏️', color: const Color(0xFFEE8C6E), primary: true, onTap: _startCustom),
          if (_heroDrawn)
            QuickReply(
              label: '동화 만들기',
              emoji: '📖',
              color: _yellow,
              primary: true,
              onTap: () {
                _addChild('이제 동화 만들래!');
                _proceedToStoryReview();
              },
            ),
        ];
      case CreationStage.drawing:
        final hasDrawing = _paths.isNotEmpty || (cat != null && (_restoredBasePng[cat.id] != null || _slotPngBytes[cat.id] != null));
        return [
          QuickReply(label: '다 그렸어!', emoji: '✅', color: _green, primary: true, onTap: hasDrawing ? _startNaming : null),
          QuickReply(label: '어떤 색이 어울릴까?', emoji: '🎨', color: const Color(0xFFEE8C6E), onTap: () => _sendQuestionToLumi('어떤 색이 어울릴까?')),
          QuickReply(
            label: '그리기 너무 어려워!',
            emoji: '🥺',
            color: const Color(0xFF4F93C2),
            onTap: () {
              _addChild('그리기 너무 어려워!');
              _addLumi('완벽하지 않아도 괜찮아! 동그라미랑 네모만 이어 붙여도 멋진 작품이 된단다 🎨');
            },
          ),
          if (cat != null && !cat.isRequired)
            QuickReply(label: '크레용이 대신 그려줘', emoji: '🪄', color: const Color(0xFF5E9E4A), onTap: _delegateToAi),
          if (_remainingCategories.isNotEmpty)
            QuickReply(label: '다른 거 그릴래', emoji: '🔄', color: const Color(0xFFE0A126), onTap: () => _goChoosing(childSays: '다른 거 그릴래!')),
        ];
      case CreationStage.askName:
        final existing = cat == null ? null : _slotDescriptions[cat.id]?['name'];
        return [
          if (existing != null && existing.isNotEmpty)
            QuickReply(label: '"$existing" 그대로 할래', emoji: '👍', color: _green, primary: true, onTap: () => _receiveName(existing))
          else if (cat != null)
            QuickReply(label: '그냥 "${cat.title}"(으)로 할래', emoji: '👍', color: _green, onTap: () => _receiveName(cat.title)),
          QuickReply(label: '더 그릴래', emoji: '🖍️', color: const Color(0xFFE0A126), onTap: _handleSmartBack),
        ];
      case CreationStage.askDesc:
        return [
          QuickReply(label: '없어, 넘어갈래', emoji: '⏭️', color: const Color(0xFF4F93C2), onTap: () => _receiveDesc('', skip: true)),
        ];
      case CreationStage.askCustomWhat:
        return [
          QuickReply(label: '그만할래', emoji: '↩️', color: const Color(0xFFBFAE9C), onTap: _handleSmartBack),
        ];
      case CreationStage.askCustomRole:
        return [
          for (final c in _remainingCategories)
            QuickReply(label: c.title, emoji: c.emoji, color: c.color, onTap: () => _assignCustom(c.id)),
          QuickReply(label: '다시 정할래', emoji: '✏️', color: const Color(0xFFEE8C6E), onTap: () {
            _addChild('다시 정할래!');
            setState(() {
              _pendingCustomName = null;
              _stage = CreationStage.askCustomWhat;
            });
            _addLumi('좋아! 그럼 무엇을 그리고 싶어?');
          }),
        ];
      case CreationStage.askStory:
      case CreationStage.askEnding:
        final key = _pendingStorySlot;
        if (key == null) return [];
        if (_inFollowUp) {
          return [
            QuickReply(label: '이게 다야!', emoji: '🙌', color: _green, primary: true, onTap: _skipStory),
          ];
        }
        if (!_showHints) {
          return [
            QuickReply(label: '잘 모르겠어', emoji: '🤔', color: const Color(0xFFE0A126), onTap: _showStoryHints),
            QuickReply(
              label: key == _endingKey ? '그림 더 그릴래' : '넘어갈래',
              emoji: key == _endingKey ? '🖍️' : '⏭️',
              color: const Color(0xFFBFAE9C),
              onTap: _skipStory,
            ),
          ];
        }
        final accent = _noteColor(key);
        return [
          for (final hint in _currentHints)
            QuickReply(label: hint, emoji: '💡', color: accent, onTap: () => _answerStory(hint, fromHint: true)),
          QuickReply(label: '크레용이 정해줘', emoji: '🎲', color: _purple, primary: true, onTap: () => _answerStory('', byLumi: true)),
        ];
    }
  }

  Widget _buildQuickReplyWrap(List<QuickReply> replies) {
    return Padding(
      padding: const EdgeInsets.only(left: 44, top: 2, bottom: 10),
      child: Wrap(
        spacing: 10,
        runSpacing: 12,
        children: replies.map(_buildQuickReplyChip).toList(),
      ),
    );
  }

  Widget _buildQuickReplyChip(QuickReply r) {
    final enabled = r.onTap != null;
    final accent = r.color ?? _purple;
    final BoxDecoration deco;
    final Color fg;
    if (!enabled) {
      deco = _chunky(color: const Color(0xFFFFF3DC), edge: const Color(0xFFE6D3AE), radius: 30, depth: 4);
      fg = const Color(0xFFBFAE9C);
    } else if (r.primary) {
      deco = _chunky(color: accent, radius: 30, depth: 4);
      fg = _onColor(accent);
    } else {
      deco = _chunky(color: Colors.white, edge: accent, radius: 30, depth: 4, border: accent, borderWidth: 2.5);
      fg = _darken(accent, 0.08);
    }
    return _Pressable(
      onTap: r.onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 9, 18, 9),
        decoration: deco,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (r.emoji != null) ...[
              Text(r.emoji!, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
            ],
            Text(r.label, style: TextStyle(fontSize: 16, color: fg)),
          ],
        ),
      ),
    );
  }

  Widget _buildInputRow() {
    final hint = _isListening
        ? '듣고 있어요! 말해 보세요…'
        : _stage == CreationStage.askName
            ? '이름을 알려줘!'
            : _stage == CreationStage.askCustomWhat
            ? '그리고 싶은 걸 알려줘! (예: 공룡, 우리 집 고양이)'
            : (_stage == CreationStage.askStory || _stage == CreationStage.askEnding)
            ? '내 생각을 말해줘! 💭'
            : _stage == CreationStage.askDesc
                ? '어떤 특별한 점이 있는지 알려줘!'
                : '크레용에게 말해봐!';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFFFDF7),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: _isListening ? const Color(0xFFEE8C6E) : _cardLine, width: 2.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatInputCtrl,
                      focusNode: _inputFocusNode,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(fontSize: 17, color: _ink),
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: TextStyle(fontSize: 16, color: _isListening ? const Color(0xFFEE8C6E) : const Color(0xFFBFAE9C)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.fromLTRB(18, 13, 8, 13),
                      ),
                    ),
                  ),
                  Padding(padding: const EdgeInsets.only(right: 5), child: _buildMicButton()),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _Pressable(
            onTap: _isLumiThinking ? null : () => _handleInputSubmit(_chatInputCtrl.text),
            child: Container(
              width: 52,
              height: 52,
              decoration: _chunky(color: _purple, edge: _purpleDark, shape: BoxShape.circle, depth: 4),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMicButton() {
    return _Pressable(
      onTap: _toggleVoiceInput,
      child: AnimatedBuilder(
        animation: _fairyAnimController,
        builder: (context, child) {
          final pulse = _isListening ? _fairyAnimController.value : 0.0;
          return Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isListening ? const Color(0xFFEE8C6E) : _tint(_purple, 0.85),
              boxShadow: _isListening
                  ? [BoxShadow(color: const Color(0xFFEE8C6E).withValues(alpha: 0.35), blurRadius: 6 + 10 * pulse, spreadRadius: 3 * pulse)]
                  : [],
            ),
            child: child,
          );
        },
        child: Icon(
          _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
          color: _isListening ? Colors.white : _purple,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildGallery() {
    final total = _allCategories.length;
    final count = _drawnOrder.length;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      padding: EdgeInsets.fromLTRB(16, 10, 14, _isGalleryCollapsed ? 10 : 14),
      decoration: _card(radius: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 상단 요약 바 (진행도 + 메모 + 접기/펼치기 토글) ──
          Row(
            children: [
              const Text('🖼️', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              const Text('내 그림 모음', style: TextStyle(fontSize: 17, color: _ink)),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 14,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3DC),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: LayoutBuilder(
                    builder: (context, c) => Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutBack,
                        width: count == 0 ? 0 : (c.maxWidth * (count / total)),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFF8C03C), Color(0xFFE0A126)]),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('$count / $total', style: const TextStyle(fontSize: 14, color: Color(0xFFE08A00), fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              _buildStoryNotesChip(),
              const SizedBox(width: 6),

              // 🔼 [신규 추가] 갤러리 접기/펼치기 토글 버튼
              _Pressable(
                onTap: () {
                  setState(() => _isGalleryCollapsed = !_isGalleryCollapsed);
                  // 갤러리가 접히거나 펼쳐진 직후 캔버스 뷰포트 크기에 맞춰 도화지 자동 재배치
                  WidgetsBinding.instance.addPostFrameCallback((_) => _fitCanvasToScreen());
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3DC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isGalleryCollapsed ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                        size: 18,
                        color: _purple,
                      ),
                      Text(
                        _isGalleryCollapsed ? '펼치기' : '접기',
                        style: const TextStyle(fontSize: 12, color: _purple, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── 슬롯 목록 (접혔을 때는 완전히 숨겨져 캔버스 공간 확보) ──
          if (!_isGalleryCollapsed) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 96,
              child: Row(
                children: [
                  Expanded(
                    child: _drawnOrder.isEmpty
                        ? Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEA),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFFE7A3), width: 2),
                      ),
                      child: const Text('그린 그림이 여기에 모여요\n눌러서 언제든 다시 고칠 수 있어!',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Color(0xFFB88A1E), height: 1.4)),
                    )
                        : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(bottom: 5),
                      itemCount: _drawnOrder.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) =>
                          _AppearIn(key: ValueKey('slot_${_drawnOrder[index]}'), child: _buildSlotItem(_drawnOrder[index])),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildAddSlotButton(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }


  Widget _buildStoryNotesChip() {
    final count = _storyNotes.length;
    return _Pressable(
      onTap: _showStoryNotes,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
        decoration: _chunky(
          color: count > 0 ? const Color(0xFFFFF4D6) : const Color(0xFFFFF3DC),
          edge: count > 0 ? const Color(0xFFF2C94C) : _cardEdge,
          radius: 16,
          depth: 3,
          border: count > 0 ? const Color(0xFFF2C94C) : _cardLine,
          borderWidth: 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📜', style: TextStyle(fontSize: 15)),
            const SizedBox(width: 4),
            Text('이야기 메모 $count', style: TextStyle(fontSize: 13, color: count > 0 ? const Color(0xFFB07A00) : _sub)),
          ],
        ),
      ),
    );
  }

  void _showStoryNotes() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Theme(
        data: _kidsTheme(context),
        child: StatefulBuilder(
          builder: (ctx, setSheet) {
            final notes = _storyNotes.values.toList();
            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: _card(radius: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(width: 44, height: 5, decoration: BoxDecoration(color: _cardLine, borderRadius: BorderRadius.circular(3))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 16, 22, 6),
                    child: Row(
                      children: [
                        const Text('📜', style: TextStyle(fontSize: 24)),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('우리가 정한 이야기', style: TextStyle(fontSize: 22, color: _ink))),
                        _Pressable(
                          onTap: () => Navigator.pop(sheetCtx),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: _chunky(color: const Color(0xFFFFF3DC), edge: _cardEdge, shape: BoxShape.circle, depth: 3),
                            child: const Icon(Icons.close_rounded, color: _sub),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 22),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('크레용이랑 이야기하면서 정한 내용이 동화에 들어가요!', style: TextStyle(fontSize: 14, color: _sub)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (notes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(22, 20, 22, 36),
                      child: Text('아직 정한 이야기가 없어요.\n그림을 완성하면 크레용이 물어볼 거야',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: _sub, height: 1.5)),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                        itemCount: notes.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final n = notes[i];
                          final color = _noteColor(n.slotId);
                          final emoji = _noteEmoji(n.slotId);
                          return Container(
                            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                            decoration: _chunky(color: _tint(color, 0.88), edge: _tint(color, 0.55), radius: 20, depth: 4, border: _tint(color, 0.55), borderWidth: 2),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(n.question, style: const TextStyle(fontSize: 13, color: _sub)),
                                      const SizedBox(height: 3),
                                      Text(n.answer, style: TextStyle(fontSize: 18, color: _darken(color, 0.12))),
                                      if (n.byLumi)
                                        const Padding(
                                          padding: EdgeInsets.only(top: 2),
                                          child: Text('🎲 크레용이 골랐어요', style: TextStyle(fontSize: 12, color: _sub)),
                                        ),
                                    ],
                                  ),
                                ),
                                _Pressable(
                                  onTap: () {
                                    _removeStoryNote(n.slotId);
                                    setSheet(() {});
                                  },
                                  child: const SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Icon(Icons.close_rounded, size: 20, color: Color(0xFFBFAE9C)),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSlotItem(String id) {
    final cat = _catById(id);
    final isSelected = _currentId == id;
    final isAi = _slotAiDelegated[id] ?? false;
    final paths = isSelected ? _paths : (_slotPaths[id] ?? []);
    final pngBytes = _slotPngBytes[id]; // 👈 [추가] 복원된 PNG 바이트 참조
    final hasDrawing = paths.isNotEmpty || pngBytes != null; // 👈 [수정] 바이트 존재 여부 포함
    final named = _slotDescriptions[id]?['name']?.isNotEmpty == true;

    return _Pressable(
      onTap: () {
        if (isSelected) {
          if (_stage == CreationStage.choosing) _continueDrawing();
          return;
        }
        _selectCategory(id, fromChip: false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 84,
        padding: const EdgeInsets.all(5),
        decoration: _chunky(
          color: isSelected ? _tint(cat.color, 0.82) : Colors.white,
          edge: isSelected ? _darken(cat.color, 0.05) : _cardEdge,
          radius: 20,
          depth: 4,
          border: isSelected ? cat.color : _cardLine,
          borderWidth: isSelected ? 3 : 2.5,
        ),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(color: _tint(cat.color, 0.92), borderRadius: BorderRadius.circular(14)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: isAi
                          ? const Center(child: Text('🪄', style: TextStyle(fontSize: 26)))
                          // 🎯 [수정] 선 좌표가 있으면 Painter로, 선 좌표가 없고 복원된 PNG가 있으면 Image.memory로 표시
                          : paths.isNotEmpty
                              ? Container(color: Colors.white, child: CustomPaint(painter: MiniThumbnailPainter(paths), size: Size.infinite))
                              : pngBytes != null
                                  ? Container(
                                      color: Colors.white,
                                      padding: const EdgeInsets.all(4),
                                      child: Image.memory(pngBytes, fit: BoxFit.contain),
                                    )
                                  : Center(child: Text(cat.emoji, style: const TextStyle(fontSize: 26))),
                    ),
                  ),
                  if (named || isAi)
                    Positioned(
                      top: -6,
                      right: -6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: _green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                        ),
                        child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
                      ),
                    ),
                  // 🗑️ [추가!] 슬롯 삭제 버튼 (좌측 상단 - 주인공 제외)
                  if (!cat.isRequired)
                    Positioned(
                      top: -6,
                      left: -6,
                      child: GestureDetector(
                        onTap: () => _deleteCategorySlot(id),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF5252),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.close_rounded, size: 13, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _labelOf(id),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: isSelected ? _darken(cat.color, 0.1) : _sub),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddSlotButton() {
    final enabled = _remainingCategories.isNotEmpty && _stage != CreationStage.choosing;
    return _Pressable(
      onTap: enabled ? () => _goChoosing(childSays: '다른 거 그릴래!') : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1 : 0.45,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: CustomPaint(
            painter: _DashedRRectPainter(color: _purple.withValues(alpha: 0.55), radius: 20),
            child: SizedBox(
              width: 74,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: _chunky(color: _purple, edge: _purpleDark, shape: BoxShape.circle, depth: 3),
                    child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(height: 6),
                  const Text('새로 그리기', style: TextStyle(fontSize: 12, color: _purple)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCanvasArea() {
    final cat = currentCat;
    final isAi = cat != null && (_slotAiDelegated[cat.id] ?? false);

    return Container(
      key: _workspaceKey, // 👈 [추가 1] 화면 크기 자동 측정을 위해 키 연결
      decoration: _card(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: cat == null
            ? _buildCanvasPlaceholder()
            : LayoutBuilder(
          builder: (context, constraints) {
            // 🎯 현재 기기 화면의 카드 크기를 100% 그대로 도화지 크기로 동기화
            final canvasWidth = constraints.maxWidth;
            final canvasHeight = constraints.maxHeight;
            _currentCanvasSize = Size(canvasWidth, canvasHeight);
            final bool hasCanvasDrawing = _paths.isNotEmpty ||
                (_currentId != null && (_restoredBasePng[_currentId] != null || _slotPngBytes[_currentId] != null));

            return Stack(
              children: [
                // ── 🌐 작업대(Desk) & 100% 꽉 찬 인터랙티브 도화지 ──
                Container(
                  color: const Color(0xFFFFF3DC), // 줌아웃 시 드러나는 작업대 배경색
                  child: InteractiveViewer(
                    transformationController: _transformCtrl,
                    constrained: false, // 👈 [추가 2] 화면 크기로 강제 압축되는 현상 차단!
                    panEnabled: _isPanMode,
                    scaleEnabled: _isPanMode,
                    minScale: 0.2, // 줌아웃 시 도화지 전체 조망 가능
                    maxScale: 3.5, // 줌인 시 세밀한 묘사 가능
                    boundaryMargin: const EdgeInsets.all(500),
                    child: Container(
                      width: _virtualCanvasSize.width,  // 👈 [수정 3] 진짜 2000 적용!
                      height: _virtualCanvasSize.height, // 👈 [수정 3] 진짜 1600 적용!
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        // 🎯 [경계선] 도화지 가장자리에 둘러진 뚜렷한 보라색 외곽선 & 입체 그림자
                        border: Border.all(color: const Color(0xFF5E9E4A), width: 3.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4A3728).withOpacity(0.16),
                            blurRadius: 24,
                            spreadRadius: 3,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Stack(
                          children: [
                            // 1. 도화지 배경 도트 그리드 (화면 끝까지 꽉 참!)
                            const Positioned.fill(child: CustomPaint(painter: _DotGridPainter())),

                            // 2. 🖼️ 로컬에 영구 보존된 원본 밑그림 레이어 (정중앙 512x512)
                            if (_currentId != null && _restoredBasePng[_currentId] != null)
                              Positioned.fill(
                                child: Center(
                                  child: Image.memory(
                                    _restoredBasePng[_currentId]!,
                                    fit: BoxFit.contain,
                                    width: 512,
                                    height: 512,
                                  ),
                                ),
                              ),

                            // 3. ✏️ 화면 전역 펜/지우개 드로잉 레이어
                            RepaintBoundary(
                              key: _canvasKey,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: _isPanMode
                                    ? null
                                    : (details) {
                                  setState(() {
                                    if (isAi) _slotAiDelegated[cat.id] = false;
                                    if (_stage == CreationStage.choosing) _stage = CreationStage.drawing;
                                    _redoStack.clear();
                                    _currentPath = DrawingPath(
                                      color: _selectedColor,
                                      strokeWidth: _currentStrokeWidth,
                                      isEraser: _isEraser,
                                      points: [details.localPosition],
                                    );
                                    _paths.add(_currentPath!);
                                  });
                                },
                                onPanUpdate: _isPanMode
                                    ? null
                                    : (details) {
                                  setState(() => _currentPath?.points.add(details.localPosition));
                                },
                                onPanEnd: _isPanMode ? null : (_) => _currentPath = null,
                                child: CustomPaint(
                                  painter: TransparentDrawingPainter(_paths),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── AI 위임 안내 ──
                if (isAi)
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                        decoration: _chunky(color: Colors.white, edge: _cardEdge, radius: 26, depth: 5, border: _cardLine),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🪄', style: TextStyle(fontSize: 44)),
                            const SizedBox(height: 10),
                            Text('크레용이 ${cat.title}을(를) 대신 그려줄 거야!', style: const TextStyle(fontSize: 18, color: _ink)),
                            const SizedBox(height: 4),
                            const Text('직접 그리고 싶다면 바로 그려 봐 🎨', style: TextStyle(fontSize: 14, color: _sub)),
                          ],
                        ),
                      ),
                    ),
                  )
                else if (!hasCanvasDrawing)
                  IgnorePointer(
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _floatingAnim,
                        builder: (context, child) => Transform.translate(offset: Offset(0, _floatingAnim.value), child: child),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 104,
                              height: 104,
                              alignment: Alignment.center,
                              decoration: _chunky(color: _tint(cat.color, 0.85), edge: _tint(cat.color, 0.6), shape: BoxShape.circle, depth: 5),
                              child: Text(cat.emoji, style: const TextStyle(fontSize: 50)),
                            ),
                            const SizedBox(height: 16),
                            Text('${_customSubject[cat.id] ?? cat.title}을(를) 자유롭게 그려봐!', style: TextStyle(fontSize: 22, color: _darken(cat.color, 0.05))),
                            const SizedBox(height: 4),
                            const Text('손가락이나 펜으로 쓱쓱 ✏️ (보라색 테두리 안쪽에 그려줘!)', style: TextStyle(fontSize: 15, color: _sub)),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ── 상단 카테고리 태그 ──
                Positioned(
                  top: 14,
                  left: 14,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 7, 16, 7),
                    decoration: _chunky(color: cat.color, radius: 20, depth: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(cat.emoji, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Text(_labelOf(cat.id), style: TextStyle(fontSize: 16, color: _onColor(cat.color))),
                        if (cat.isRequired) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
                            child: Text('필수', style: TextStyle(fontSize: 12, color: _onColor(cat.color))),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // ── 우상단 툴바 (실행취소 / 다시실행 / 🎯 화면 맞춤 / 전체삭제) ──
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    decoration: _chunky(color: Colors.white, edge: _cardEdge, radius: 24, depth: 4, border: _cardLine, borderWidth: 2),
                    child: Row(
                      children: [
                        _canvasIconButton(Icons.undo_rounded, _paths.isEmpty ? null : () => setState(() => _redoStack.add(_paths.removeLast()))),
                        _canvasIconButton(Icons.redo_rounded, _redoStack.isEmpty ? null : () => setState(() => _paths.add(_redoStack.removeLast()))),
                        // 🎯 누르면 즉시 화면 100% 꽉 찬 상태로 복귀
                        _canvasIconButton(Icons.fit_screen_rounded, _fitCanvasToScreen),
                        Container(width: 2, height: 22, color: _cardLine, margin: const EdgeInsets.symmetric(horizontal: 2)),
                        _canvasIconButton(Icons.delete_rounded, _paths.isEmpty ? null : _clearCanvas, danger: true),
                      ],
                    ),
                  ),
                ),

                // ── 다 그렸어! 완료 버튼 ──
                if (_stage == CreationStage.drawing)
                  Positioned(
                    bottom: 18,
                    right: 18,
                    child: _Pressable(
                      // 🎯 [수정] 새로 그은 선이 있거나, 복원된 밑그림이 있으면 바로 완료 가능!
                      onTap: hasCanvasDrawing ? _startNaming : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                        decoration: hasCanvasDrawing
                            ? _chunky(color: _green, radius: 30, depth: 5)
                            : _chunky(color: const Color(0xFFF1E3C8), radius: 30, depth: 5),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_rounded,
                              size: 22,
                              color: hasCanvasDrawing ? Colors.white : const Color(0xFFBFAE9C),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '다 그렸어!',
                              style: TextStyle(
                                fontSize: 18,
                                color: hasCanvasDrawing ? Colors.white : const Color(0xFFBFAE9C),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCanvasPlaceholder() {
    return Stack(
      children: [
        const Positioned.fill(child: CustomPaint(painter: _DotGridPainter())),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _floatingAnim,
                builder: (context, child) => Transform.translate(offset: Offset(0, _floatingAnim.value * 1.5), child: child),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: _chunky(color: _tint(_purple, 0.82), edge: _tint(_purple, 0.6), shape: BoxShape.circle, depth: 6),
                  child: _buildLumiAvatar(size: 104, ring: true),
                ),
              ),
              const SizedBox(height: 20),
              const Text('무엇을 그려볼까?', style: TextStyle(fontSize: 26, color: _ink)),
              const SizedBox(height: 6),
              const Text('크레용의 말풍선 아래 버튼을 골라줘!', style: TextStyle(fontSize: 16, color: _sub)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _canvasIconButton(IconData icon, VoidCallback? onTap, {bool danger = false}) {
    final color = onTap == null ? const Color(0xFFE6D3AE) : (danger ? const Color(0xFFEE8C6E) : _ink);
    return _Pressable(
      onTap: onTap,
      child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 22, color: color)),
    );
  }

  Widget _buildDrawingDock() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: _card(radius: 36),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _toolToggle(),
            _dockDivider(),
            ...List.generate(3, (i) => _sizeDot(i)),
            _dockDivider(),
            ..._colorPalette.map(_colorDot),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }

  Widget _dockDivider() {
    return Container(width: 2, height: 30, margin: const EdgeInsets.symmetric(horizontal: 10), color: _cardLine);
  }

  Widget _toolToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFFFFF3DC), borderRadius: BorderRadius.circular(24)),
      child: Row(
        children: [
          _toolSegment('🖍️', '펜', !_isEraser && !_isPanMode, () {
            setState(() {
              _isEraser = false;
              _isPanMode = false;
            });
          }),
          _toolSegment('🧽', '지우개', _isEraser && !_isPanMode, () {
            setState(() {
              _isEraser = true;
              _isPanMode = false;
            });
          }),
          _toolSegment('✋', '이동', _isPanMode, () {
            setState(() => _isPanMode = true);
          }),
        ],
      ),
    );
  }

  Widget _toolSegment(String emoji, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: active
            ? _chunky(color: _purple, edge: _purpleDark, radius: 20, depth: 3)
            : const BoxDecoration(color: Colors.transparent),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 15, color: active ? Colors.white : _sub)),
          ],
        ),
      ),
    );
  }

  Widget _sizeDot(int level) {
    final selected = (_isEraser ? _eraserLevel : _penLevel) == level;
    final double dot = [8.0, 14.0, 21.0][level];
    return _Pressable(
      onTap: () => setState(() => _isEraser ? _eraserLevel = level : _penLevel = level),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? _tint(_purple, 0.86) : Colors.transparent,
          border: Border.all(color: selected ? _purple : Colors.transparent, width: 2.5),
        ),
        child: Container(
          width: dot,
          height: dot,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isEraser ? const Color(0xFFE6D3AE) : _selectedColor,
          ),
        ),
      ),
    );
  }

  Widget _colorDot(Color color) {
    final isSelected = _selectedColor == color && !_isEraser;
    return _Pressable(
      onTap: () => setState(() {
        _selectedColor = color;
        _isEraser = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        width: isSelected ? 40 : 32,
        height: isSelected ? 40 : 32,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: isSelected ? 3.5 : 2.5),
          boxShadow: [
            BoxShadow(color: _darken(color, 0.18), offset: Offset(0, isSelected ? 4 : 3)),
            if (isSelected) BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 10),
          ],
        ),
        child: isSelected ? Icon(Icons.check_rounded, size: 18, color: _onColor(color)) : null,
      ),
    );
  }
}

class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Pressable({required this.child, this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _down ? 3 : 0, 0),
          child: AnimatedScale(
            scale: _down ? 0.97 : 1.0,
            duration: const Duration(milliseconds: 90),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _AppearIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _AppearIn({super.key, required this.child, this.delay = Duration.zero});

  @override
  State<_AppearIn> createState() => _AppearInState();
}

class _AppearInState extends State<_AppearIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (context, child) {
        final v = _a.value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - v) * 16),
            child: Transform.scale(scale: 0.92 + 0.08 * v, alignment: Alignment.bottomLeft, child: child),
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _KidsScenePainter extends CustomPainter {
  final Animation<double> anim;
  _KidsScenePainter(this.anim) : super(repaint: anim);

  static const _cloudX = [0.06, 0.38, 0.70, 0.22, 0.88];
  static const _cloudY = [0.07, 0.15, 0.05, 0.30, 0.24];
  static const _cloudS = [1.0, 0.8, 0.65, 0.6, 0.75];
  static const _cloudV = [1.0, 0.7, 1.3, 0.9, 0.6];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE9A8), Color(0xFFFFF3DC), Color(0xFFFFF9EE)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    final sunCenter = Offset(w * 0.9, h * 0.09);
    canvas.drawCircle(sunCenter, 80, Paint()..color = const Color(0xFFFFF3B0).withValues(alpha: 0.45));
    canvas.drawCircle(sunCenter, 58, Paint()..color = const Color(0xFFFFE680).withValues(alpha: 0.7));
    canvas.drawCircle(sunCenter, 42, Paint()..color = const Color(0xFFFFD93D));

    for (int i = 0; i < _cloudX.length; i++) {
      final t = (_cloudX[i] + anim.value * 0.25 * _cloudV[i]) % 1.25 - 0.12;
      _drawCloud(canvas, Offset(t * w, _cloudY[i] * h), _cloudS[i] * (w < 700 ? 0.7 : 1.0));
    }

    final back = Path()
      ..moveTo(0, h * 0.80)
      ..quadraticBezierTo(w * 0.22, h * 0.68, w * 0.48, h * 0.79)
      ..quadraticBezierTo(w * 0.76, h * 0.90, w, h * 0.74)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(back, Paint()..color = const Color(0xFFA8E07A));

    final front = Path()
      ..moveTo(0, h * 0.90)
      ..quadraticBezierTo(w * 0.30, h * 0.80, w * 0.62, h * 0.90)
      ..quadraticBezierTo(w * 0.86, h * 0.97, w, h * 0.87)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(front, Paint()..color = const Color(0xFF7DCB5A));

    const flowers = [
      [0.08, 0.95, 0xFFFFFFFF],
      [0.16, 0.92, 0xFFFF8FC8],
      [0.42, 0.93, 0xFFFFE066],
      [0.55, 0.96, 0xFFFFFFFF],
      [0.74, 0.97, 0xFFFF8FC8],
      [0.93, 0.92, 0xFFFFE066],
    ];
    for (final f in flowers) {
      final c = Offset((f[0] as double) * w, (f[1] as double) * h);
      final petal = Paint()..color = Color(f[2] as int);
      for (int k = 0; k < 5; k++) {
        final a = k * 1.2566;
        canvas.drawCircle(c + Offset(5 * math.cos(a), 5 * math.sin(a)), 4, petal);
      }
      canvas.drawCircle(c, 3, Paint()..color = const Color(0xFFFFB300));
    }
  }

  void _drawCloud(Canvas canvas, Offset c, double s) {
    final shadow = Paint()..color = const Color(0xFF9FD3F5).withValues(alpha: 0.6);
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.95);
    void blob(Paint p, Offset o) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: c + o + Offset(0, 14 * s), width: 120 * s, height: 34 * s), Radius.circular(17 * s)),
        p,
      );
      canvas.drawCircle(c + o + Offset(-30 * s, 6 * s), 22 * s, p);
      canvas.drawCircle(c + o + Offset(4 * s, -6 * s), 30 * s, p);
      canvas.drawCircle(c + o + Offset(34 * s, 6 * s), 20 * s, p);
    }

    blob(shadow, Offset(0, 5 * s));
    blob(paint, Offset.zero);
  }

  @override
  bool shouldRepaint(covariant _KidsScenePainter oldDelegate) => false;
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFF1E3C8);
    const gap = 26.0;
    for (double y = gap / 2; y < size.height; y += gap) {
      for (double x = gap / 2; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), 1.6, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedRRectPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect.deflate(1.5));
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 7), paint);
        d += 13;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) => oldDelegate.color != color;
}

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
      final drawPath = Path()..moveTo(path.points.first.dx, path.points.first.dy);
      if (path.points.length == 1) {
        drawPath.lineTo(path.points.first.dx + 0.1, path.points.first.dy);
      }
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
      if (p.isEraser) continue;
      for (final pt in p.points) {
        if (pt.dx < minX) minX = pt.dx;
        if (pt.dx > maxX) maxX = pt.dx;
        if (pt.dy < minY) minY = pt.dy;
        if (pt.dy > maxY) maxY = pt.dy;
      }
    }
    if (minX == double.infinity) return;
    final double drawingWidth = (maxX - minX) < 1.0 ? 1.0 : (maxX - minX);
    final double drawingHeight = (maxY - minY) < 1.0 ? 1.0 : (maxY - minY);

    final scaleX = (size.width - 10) / drawingWidth;
    final scaleY = (size.height - 10) / drawingHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(
      (size.width - drawingWidth * scale) / 2 - minX * scale,
      (size.height - drawingHeight * scale) / 2 - minY * scale,
    );
    canvas.scale(scale);
    canvas.saveLayer(Rect.fromLTWH(minX - 100, minY - 100, drawingWidth + 200, drawingHeight + 200), Paint());
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
      }
      final drawPath = Path()..moveTo(path.points.first.dx, path.points.first.dy);
      for (int i = 1; i < path.points.length; i++) {
        drawPath.lineTo(path.points[i].dx, path.points[i].dy);
      }
      canvas.drawPath(drawPath, paint);
    }
    canvas.restore();
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