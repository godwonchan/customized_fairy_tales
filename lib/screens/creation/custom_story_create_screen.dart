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
  const CustomStoryCreateScreen({super.key});

  @override
  State<CustomStoryCreateScreen> createState() => _CustomStoryCreateScreenState();
}

class _CustomStoryCreateScreenState extends State<CustomStoryCreateScreen>
    with TickerProviderStateMixin {
  static const String _lumiImagePath = 'assets/images/lumi.jpg';
  static const String _baseUrl = 'http://localhost:8000';
  static const Color _purple = Color(0xFF7C4DFF);
  static const Color _deep = Color(0xFF2B2A4C);

  final List<StoryCategory> _allCategories = const [
    StoryCategory(id: 'hero', title: '주인공', fairyPrompt: '좋아! 우리 멋진 모험을 이끌어갈 주인공을 그려줘 ✨\n사람, 동물, 로봇… 뭐든지 괜찮아!', icon: Icons.person_pin, emoji: '🧒', color: Color(0xFF7E57C2), isRequired: true),
    StoryCategory(id: 'companion', title: '단짝 친구', fairyPrompt: '주인공 곁을 지켜줄 든든한 단짝 친구나 귀여운 동물 친구를 그려볼까?', icon: Icons.pets, emoji: '🐶', color: Color(0xFF26A69A)),
    StoryCategory(id: 'item', title: '마법 도구', fairyPrompt: '위험한 순간에 힘을 발휘할 신비한 마법 지팡이나 특별한 도구를 그려줘!', icon: Icons.auto_awesome, emoji: '🪄', color: Color(0xFFAB47BC)),
    StoryCategory(id: 'place', title: '비밀 장소', fairyPrompt: '모험이 펼쳐질 장소를 그려줘! 우리 집, 마법의 성, 신비한 숲도 좋아.', icon: Icons.castle, emoji: '🏰', color: Color(0xFF42A5F5)),
    StoryCategory(id: 'vehicle', title: '특별한 탈것', fairyPrompt: '하늘을 나는 양탄자, 우주선, 구름 자전거처럼 신나는 탈것을 그려볼래?', icon: Icons.rocket_launch, emoji: '🚀', color: Color(0xFFFF7043)),
    StoryCategory(id: 'villain', title: '엉뚱한 악당', fairyPrompt: '이야기를 더 흥미진진하게 만들 귀여운 장난꾸러기 악당을 그려보자!', icon: Icons.mood_bad, emoji: '😈', color: Color(0xFF5C6BC0)),
    StoryCategory(id: 'food', title: '좋아하는 간식', fairyPrompt: '먹으면 힘이 솟아나는 달콤한 케이크나 마법 열매를 그려보는 건 어때?', icon: Icons.icecream, emoji: '🍰', color: Color(0xFFEC407A)),
    StoryCategory(id: 'treasure', title: '숨겨진 보물', fairyPrompt: '모험의 끝에서 발견할 반짝이는 보물 상자나 비밀 열쇠를 그려보자!', icon: Icons.vpn_key, emoji: '💎', color: Color(0xFFFFA000)),
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

  final Map<String, List<DrawingPath>> _slotPaths = {};
  final Map<String, bool> _slotAiDelegated = {};
  final Map<String, Uint8List?> _slotPngBytes = {};
  final Map<String, Map<String, String>> _slotDescriptions = {};

  final List<DrawingPath> _paths = [];
  final List<DrawingPath> _redoStack = [];
  DrawingPath? _currentPath;
  Color _selectedColor = const Color(0xFF2B2A4C);
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
    Color(0xFF2B2A4C),
    Color(0xFFFF4D4D),
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

  bool get _heroDrawn =>
      (_currentId == 'hero' && _paths.isNotEmpty) || (_currentId != 'hero' && (_slotPaths['hero']?.isNotEmpty ?? false));

  String _labelOf(String id) {
    final name = _slotDescriptions[id]?['name'];
    if (name != null && name.isNotEmpty) return name;
    return _customSubject[id] ?? _catById(id).title;
  }

  Map<String, Map<String, String>> _descriptionsForServer() {
    final result = <String, Map<String, String>>{};
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
    _customSubject.forEach((id, subject) {
      final hasDrawing = (_slotPaths[id]?.isNotEmpty ?? false) || (_slotAiDelegated[id] ?? false);
      if (hasDrawing) {
        result.putIfAbsent(id, () => {'name': subject, 'desc': '$subject / 역할: ${_catById(id).title}'});
      }
    });
    return result;
  }

  void _startCustom() {
    if (_isLumiThinking) return;
    _addChild('내가 정할래!');
    setState(() {
      _stage = CreationStage.askCustomWhat;
      _pendingCustomName = null;
    });
    _addLumi('좋아! 무엇을 그리고 싶어?\n말하거나 글로 써줘 ✨');
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

  @override
  void initState() {
    super.initState();
    _fairyAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _sceneController = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
    _floatingAnim = Tween<double>(begin: -4.0, end: 4.0).animate(
      CurvedAnimation(parent: _fairyAnimController, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _addLumi('안녕? 나는 이야기 요정 루미야 ✨\n우리 같이 동화를 만들어보자~\n먼저 뭐부터 그릴래?');
    });
  }

  @override
  void dispose() {
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
        setState(() => _chatInputCtrl.text = result.recognizedWords);
        if (result.finalResult) {
          setState(() => _isListening = false);
          if (result.recognizedWords.trim().isNotEmpty) {
            _handleInputSubmit(result.recognizedWords);
          }
        }
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
      _addLumi('"$q"라니 정말 기발해! 동화 속에서는 무엇이든 마법처럼 가능하니까 자유롭게 그려봐! 🎨✨');
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

  Future<void> _saveCurrentSlot() async {
    final id = _currentId;
    if (id == null) return;
    _slotPaths[id] = List.from(_paths);
    if (_paths.isNotEmpty) {
      _slotAiDelegated[id] = false;
      _slotPngBytes[id] = await _captureCanvasToPng();
    } else if (!(_slotAiDelegated[id] ?? false)) {
      _slotPngBytes[id] = null;
    }
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
    _addLumi('좋아, 이어서 그려보자! 🎨');
  }

  void _startNaming() {
    final cat = currentCat;
    if (cat == null || _isLumiThinking) return;
    if (_paths.isEmpty) {
      _addLumi('아직 아무것도 안 그렸어! 먼저 ${cat.title}을(를) 그려줘 🎨');
      return;
    }
    _addChild('다 그렸어!');
    setState(() => _stage = CreationStage.askName);
    final existing = _slotDescriptions[cat.id]?['name'];
    _addLumi(existing != null && existing.isNotEmpty
        ? '정말 멋지게 그렸어! ✨\n이름은 그대로 "$existing"(으)로 할까, 아니면 새 이름을 알려줄래?'
        : '정말 멋지게 그렸어! ✨\n이 ${cat.title}의 이름은 뭐야?');
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
    final prefix = skip ? '알겠어! ' : '알려줘서 고마워! 루미가 꼭 기억할게 ✨\n';
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
        return '이제 동화를 만들 차례야! 📖\n이야기는 어떻게 끝나면 좋을까?';
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
          '다 같이 신나는 축제를 열어',
          '모두 사이좋은 친구가 돼',
          '무사히 집으로 돌아와',
          '깜짝 반전이 일어나',
          '새로운 모험이 또 시작돼',
          '${_j(h, '이', '가')} 소원을 이뤄',
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
    _addChild(byLumi ? '루미가 정해줘!' : answer);

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
      about: key == _endingKey ? '결말' : (key == _heroKey ? _heroName : (_meetWith == null ? '만남' : _labelOf(_meetWith!))),
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

    final reaction = byLumi ? '루미는 "$finalAnswer"(이)가 좋을 것 같아! ' : '좋아, "$finalAnswer"! ';
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
      _addLumi('$reaction\n그럼 우리가 정한 이야기로 동화를 만들어볼게 ✨');
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
    _addChild('루미가 대신 그려줘!');
    await _goChoosing(prefix: '${cat.title}은(는) 루미가 마법으로 그려줄게! ✨\n');
  }

  void _clearCanvas() {
    final id = _currentId;
    if (id == null) return;
    setState(() {
      _paths.clear();
      _redoStack.clear();
      _slotPaths[id] = [];
      _slotPngBytes[id] = null;
      _slotAiDelegated[id] = false;
      _slotDescriptions.remove(id);
    });
  }

  Future<void> _proceedToStoryReview() async {
    if (_isLumiThinking) return;
    await _saveCurrentSlot();
    if (!mounted) return;

    if (!(_slotPaths['hero']?.isNotEmpty ?? false)) {
      const warnText = '이야기의 대장이 될 주인공은 꼭 직접 그려줘야 해! 🎨';
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(warnText), backgroundColor: Color(0xFFE53935)),
      );
      await _selectCategory('hero', fromChip: false, announce: false);
      _addLumi(warnText);
      return;
    }

    if (!_storyNotes.containsKey(_endingKey)) {
      _askEnding();
      return;
    }

    if (_cachedStoryData != null) {
      final String? action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.auto_stories_rounded, color: _purple, size: 26),
              SizedBox(width: 8),
              Text('이야기 만들기 선택', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _deep)),
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
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'new_story'),
                  icon: const Icon(Icons.refresh_rounded, size: 18, color: _purple),
                  label: const Text('줄거리도 완전히 새로 만들래', style: TextStyle(color: _purple, fontWeight: FontWeight.bold)),
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

      if (action == null) return;

      if (action == 'keep_story') {
        final updatedStoryData = Map<String, dynamic>.from(_cachedStoryData!);
        final List updatedPages = List.from(updatedStoryData['pages'] ?? []);
        for (int i = 0; i < updatedPages.length; i++) {
          final pageInfo = Map<String, dynamic>.from(updatedPages[i]);
          pageInfo['prompt'] = '';
          updatedPages[i] = pageInfo;
        }
        updatedStoryData['pages'] = updatedPages;
        _cachedStoryData = updatedStoryData;
      } else if (action == 'new_story') {
        _cachedStoryData = null;
      }
    }

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
          cachedStoryData: _cachedStoryData,
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



  static const Color _ink = Color(0xFF2B2A4C);
  static const Color _sub = Color(0xFF8A86A8);
  static const Color _purpleDark = Color(0xFF5B2FE0);
  static const Color _yellow = Color(0xFFFFC93C);
  static const Color _green = Color(0xFF58CC02);
  static const Color _cardLine = Color(0xFFEAE6F8);
  static const Color _cardEdge = Color(0xFFDCD5F3);

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
        child: Image.asset(
          _lumiImagePath,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) => Container(
            color: _purple,
            child: Icon(Icons.face_retouching_natural, color: Colors.white, size: size * 0.55),
          ),
        ),
      ),
    );
  }

  ThemeData _kidsTheme(BuildContext context) {
    final base = Theme.of(context);
    final String? kidsFont = GoogleFonts.jua().fontFamily;
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
          backgroundColor: const Color(0xFFB8E6FF),
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
              decoration: _chunky(color: Colors.white, edge: const Color(0xFF9FCDEB), shape: BoxShape.circle, depth: 4),
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
                const Text('루미랑 이야기하며 그림을 그려요 ✨',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: Color(0xFF4A6A8A))),
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
                  : _chunky(color: const Color(0xFFE6E2EF), radius: 30, depth: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('📖', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text('이야기 짓기', style: TextStyle(fontSize: 17, color: ready ? _ink : const Color(0xFFA9A3BC))),
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
                color: const Color(0xFFF8F6FF),
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
      color: _purple,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(right: 60, top: -6, child: Text('✦', style: TextStyle(fontSize: 18, color: Colors.white.withValues(alpha: 0.35)))),
          Positioned(right: 96, bottom: -8, child: Text('✦', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.3)))),
          Positioned(left: 150, top: -4, child: Text('✦', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.3)))),
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
                    const Text('요정 루미', style: TextStyle(fontSize: 20, color: Colors.white)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isLumiThinking ? _yellow : const Color(0xFF7CFF8A),
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
                              style: const TextStyle(fontSize: 13, color: Colors.white),
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
            color: isLumi ? Colors.white : _purple,
            borderRadius: radius,
            border: isLumi ? Border.all(color: _cardLine, width: 2) : null,
            boxShadow: [BoxShadow(color: isLumi ? _cardEdge : _purpleDark, offset: const Offset(0, 3))],
          ),
          child: Text(
            m.text,
            style: TextStyle(fontSize: 17, height: 1.45, color: isLumi ? _ink : Colors.white),
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
                const dots = [Color(0xFFFF6FB5), _yellow, Color(0xFF4D96FF)];
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
            QuickReply(label: '내가 정할래!', emoji: '✏️', color: const Color(0xFFFF6FB5), primary: true, onTap: _startCustom),
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
        return [
          QuickReply(label: '다 그렸어!', emoji: '✅', color: _green, primary: true, onTap: _paths.isNotEmpty ? _startNaming : null),
          QuickReply(label: '어떤 색이 어울릴까?', emoji: '🎨', color: const Color(0xFFFF6FB5), onTap: () => _sendQuestionToLumi('어떤 색이 어울릴까?')),
          QuickReply(
            label: '그리기 너무 어려워!',
            emoji: '🥺',
            color: const Color(0xFF4D96FF),
            onTap: () {
              _addChild('그리기 너무 어려워!');
              _addLumi('완벽하지 않아도 괜찮아! 동그라미랑 네모만 이어 붙여도 멋진 작품이 된단다 🎨');
            },
          ),
          if (cat != null && !cat.isRequired)
            QuickReply(label: '루미가 대신 그려줘', emoji: '🪄', color: const Color(0xFF9B5DE5), onTap: _delegateToAi),
          if (_remainingCategories.isNotEmpty)
            QuickReply(label: '다른 거 그릴래', emoji: '🔄', color: const Color(0xFFFF9F1C), onTap: () => _goChoosing(childSays: '다른 거 그릴래!')),
        ];
      case CreationStage.askName:
        final existing = cat == null ? null : _slotDescriptions[cat.id]?['name'];
        return [
          if (existing != null && existing.isNotEmpty)
            QuickReply(label: '"$existing" 그대로 할래', emoji: '👍', color: _green, primary: true, onTap: () => _receiveName(existing))
          else if (cat != null)
            QuickReply(label: '그냥 "${cat.title}"(으)로 할래', emoji: '👍', color: _green, onTap: () => _receiveName(cat.title)),
          QuickReply(label: '더 그릴래', emoji: '🖍️', color: const Color(0xFFFF9F1C), onTap: _handleSmartBack),
        ];
      case CreationStage.askDesc:
        return [
          QuickReply(label: '없어, 넘어갈래', emoji: '⏭️', color: const Color(0xFF4D96FF), onTap: () => _receiveDesc('', skip: true)),
        ];
      case CreationStage.askCustomWhat:
        return [
          QuickReply(label: '그만할래', emoji: '↩️', color: const Color(0xFF9E9E9E), onTap: _handleSmartBack),
        ];
      case CreationStage.askCustomRole:
        return [
          for (final c in _remainingCategories)
            QuickReply(label: c.title, emoji: c.emoji, color: c.color, onTap: () => _assignCustom(c.id)),
          QuickReply(label: '다시 정할래', emoji: '✏️', color: const Color(0xFFFF6FB5), onTap: () {
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
            QuickReply(label: '잘 모르겠어', emoji: '🤔', color: const Color(0xFFFF9F1C), onTap: _showStoryHints),
            QuickReply(
              label: key == _endingKey ? '그림 더 그릴래' : '넘어갈래',
              emoji: key == _endingKey ? '🖍️' : '⏭️',
              color: const Color(0xFF9E9E9E),
              onTap: _skipStory,
            ),
          ];
        }
        final accent = _noteColor(key);
        return [
          for (final hint in _currentHints)
            QuickReply(label: hint, emoji: '💡', color: accent, onTap: () => _answerStory(hint, fromHint: true)),
          QuickReply(label: '루미가 정해줘', emoji: '🎲', color: _purple, primary: true, onTap: () => _answerStory('', byLumi: true)),
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
      deco = _chunky(color: const Color(0xFFF0EDF6), edge: const Color(0xFFDCD7E6), radius: 30, depth: 4);
      fg = const Color(0xFFB5AEC4);
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
                : '루미에게 말해봐!';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF6F4FC),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: _isListening ? const Color(0xFFFF4D4D) : _cardLine, width: 2.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatInputCtrl,
                      focusNode: _inputFocusNode,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _handleInputSubmit,
                      style: const TextStyle(fontSize: 17, color: _ink),
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: TextStyle(fontSize: 16, color: _isListening ? const Color(0xFFFF4D4D) : const Color(0xFFB0AAC6)),
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
              color: _isListening ? const Color(0xFFFF4D4D) : _tint(_purple, 0.85),
              boxShadow: _isListening
                  ? [BoxShadow(color: const Color(0xFFFF4D4D).withValues(alpha: 0.35), blurRadius: 6 + 10 * pulse, spreadRadius: 3 * pulse)]
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 14),
      decoration: _card(radius: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🖼️', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              const Text('내 그림 모음', style: TextStyle(fontSize: 18, color: _ink)),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 16,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: const Color(0xFFF1EEF8), borderRadius: BorderRadius.circular(10)),
                  child: LayoutBuilder(
                    builder: (context, c) => Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutBack,
                        width: count == 0 ? 0 : c.maxWidth * count / total,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFFFD93D), Color(0xFFFF9F1C)]),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text('⭐', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 4),
              Text('$count / $total', style: const TextStyle(fontSize: 15, color: Color(0xFFE08A00))),
              const SizedBox(width: 10),
              _buildStoryNotesChip(),
            ],
          ),
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
                          child: const Text('그린 그림이 여기에 모여요 ✨\n눌러서 언제든 다시 고칠 수 있어!',
                              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Color(0xFFB88A1E), height: 1.5)),
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
          color: count > 0 ? const Color(0xFFFFF4D6) : const Color(0xFFF1EEF8),
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
                            decoration: _chunky(color: const Color(0xFFF1EEF8), edge: _cardEdge, shape: BoxShape.circle, depth: 3),
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
                      child: Text('루미랑 이야기하면서 정한 내용이 동화에 들어가요!', style: TextStyle(fontSize: 14, color: _sub)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (notes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(22, 20, 22, 36),
                      child: Text('아직 정한 이야기가 없어요.\n그림을 완성하면 루미가 물어볼 거야 ✨',
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
                                          child: Text('🎲 루미가 골랐어요', style: TextStyle(fontSize: 12, color: _sub)),
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
                                    child: Icon(Icons.close_rounded, size: 20, color: Color(0xFFB0AAC0)),
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
    final hasDrawing = paths.isNotEmpty;
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
                          : hasDrawing
                              ? Container(color: Colors.white, child: CustomPaint(painter: MiniThumbnailPainter(paths), size: Size.infinite))
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
      decoration: _card(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: cat == null
            ? _buildCanvasPlaceholder()
            : Stack(
                children: [
                  const Positioned.fill(child: CustomPaint(painter: _DotGridPainter())),
                  RepaintBoundary(
                    key: _canvasKey,
                    child: GestureDetector(
                      onPanStart: (details) {
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
                      onPanUpdate: (details) {
                        setState(() => _currentPath?.points.add(details.localPosition));
                      },
                      onPanEnd: (_) => _currentPath = null,
                      child: CustomPaint(
                        painter: TransparentDrawingPainter(_paths),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
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
                              Text('루미가 ${cat.title}을(를) 대신 그려줄 거야!', style: const TextStyle(fontSize: 18, color: _ink)),
                              const SizedBox(height: 4),
                              const Text('직접 그리고 싶다면 바로 그려 봐 🎨', style: TextStyle(fontSize: 14, color: _sub)),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (_paths.isEmpty)
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
                              const Text('손가락이나 펜으로 쓱쓱 ✏️', style: TextStyle(fontSize: 15, color: _sub)),
                            ],
                          ),
                        ),
                      ),
                    ),
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
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
                              child: Text('필수', style: TextStyle(fontSize: 12, color: _onColor(cat.color))),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
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
                          Container(width: 2, height: 22, color: _cardLine, margin: const EdgeInsets.symmetric(horizontal: 2)),
                          _canvasIconButton(Icons.delete_rounded, _paths.isEmpty ? null : _clearCanvas, danger: true),
                        ],
                      ),
                    ),
                  ),
                  if (_stage == CreationStage.drawing)
                    Positioned(
                      bottom: 18,
                      right: 18,
                      child: _Pressable(
                        onTap: _paths.isNotEmpty ? _startNaming : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                          decoration: _paths.isNotEmpty
                              ? _chunky(color: _green, radius: 30, depth: 5)
                              : _chunky(color: const Color(0xFFE6E2EF), radius: 30, depth: 5),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_rounded, size: 22, color: _paths.isNotEmpty ? Colors.white : const Color(0xFFB0AAC0)),
                              const SizedBox(width: 6),
                              Text('다 그렸어!', style: TextStyle(fontSize: 18, color: _paths.isNotEmpty ? Colors.white : const Color(0xFFB0AAC0))),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
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
              const Text('루미의 말풍선 아래 버튼을 골라줘!', style: TextStyle(fontSize: 16, color: _sub)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _canvasIconButton(IconData icon, VoidCallback? onTap, {bool danger = false}) {
    final color = onTap == null ? const Color(0xFFD5CFE2) : (danger ? const Color(0xFFFF4D4D) : _ink);
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
      decoration: BoxDecoration(color: const Color(0xFFF1EEF8), borderRadius: BorderRadius.circular(24)),
      child: Row(
        children: [
          _toolSegment('🖍️', '펜', !_isEraser, () => setState(() => _isEraser = false)),
          _toolSegment('🧽', '지우개', _isEraser, () => setState(() => _isEraser = true)),
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
            color: _isEraser ? const Color(0xFFCFC8DD) : _selectedColor,
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
          colors: [Color(0xFF7CCBFF), Color(0xFFB8E6FF), Color(0xFFE8F8FF)],
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
    final paint = Paint()..color = const Color(0xFFEDE9F7);
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