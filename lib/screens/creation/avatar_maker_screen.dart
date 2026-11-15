// lib/screens/creation/avatar_maker_screen.dart
// 나를 닮은 주인공 만들기: 글을 몰라도 그림 버튼만 눌러 주인공을 꾸민다.
// - 캐릭터는 투명 PNG 조각(512×512, assets/donghwarang/avatar/layers)을 정해진 순서로 겹쳐 그린다.
//   뒷머리 → 몸(피부) → 옷 → 얼굴 → 눈 → 앞머리 → 장식. 모든 조각이 같은 정사각형 좌표를 쓴다.
// - 고를 때마다 캐릭터가 바로 바뀐다 (그림 생성 AI를 쓰지 않아 기다림·비용이 없음)
// - "사진으로 닮게"를 누르면 사진에서 머리 모양·머리색·피부 톤·안경만 읽어 처음 모습을 맞춰 준다
//   (사진은 서버에 저장하지 않고, 그림으로 바꾸지도 않는다)
// - 완성하면 PNG 로 만들어 창작 화면의 주인공 그림 자리에 넣는다
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../config/app_config.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dh_ui.dart';

/// 꾸미기 결과 (창작 화면으로 돌려주는 값)
class AvatarResult {
  final Uint8List png; // 투명 배경 512x512
  final String description; // 동화 만들 때 참고할 생김새 설명
  const AvatarResult(this.png, this.description);
}

/// 캐릭터 생김새 (모든 값은 보기 번호)
class AvatarConfig {
  final int skin; // 0 peach, 1 warm, 2 tan, 3 deep
  final int faceShape; // 0 동그란 얼굴, 1 갸름한 얼굴
  final int hairStyle; // 0 짧은 머리, 1 단발, 2 긴 머리, 3 양갈래, 4 올림머리, 5 곱슬
  final int hairColor; // 0 검정, 1 갈색(조각 원래 색), 2 밝은 갈색, 3 노랑, 4 빨강, 5 분홍
  final int eyes; // 0 동그란 눈, 1 웃는 눈, 2 반짝 눈
  final int outfit; // 0 파랑, 1 분홍, 2 민트, 3 노랑
  final int accessory; // 0 없음, 1 안경, 2 리본, 3 왕관

  const AvatarConfig({
    this.skin = 0,
    this.faceShape = 0,
    this.hairStyle = 1,
    this.hairColor = 1,
    this.eyes = 0,
    this.outfit = 0,
    this.accessory = 0,
  });

  static const List<String> skinNames = ['peach', 'warm', 'tan', 'deep'];
  static const List<String> faceNames = ['round', 'oval'];
  static const List<String> eyeNames = ['round', 'smile', 'sparkle'];
  static const List<String> outfitNames = ['blue', 'pink', 'mint', 'yellow'];
  static const List<Color> hairColors = [
    Color(0xFF3A2E2A),
    Color(0xFF72432A),
    Color(0xFFB9783F),
    Color(0xFFF2C94C),
    Color(0xFFD9573F),
    Color(0xFFFF8FC8),
  ];
  static const int hairStyleCount = 6;
  static const int accessoryCount = 4;

  AvatarConfig copyWith({int? skin, int? faceShape, int? hairStyle, int? hairColor, int? eyes, int? outfit, int? accessory}) {
    return AvatarConfig(
      skin: skin ?? this.skin,
      faceShape: faceShape ?? this.faceShape,
      hairStyle: hairStyle ?? this.hairStyle,
      hairColor: hairColor ?? this.hairColor,
      eyes: eyes ?? this.eyes,
      outfit: outfit ?? this.outfit,
      accessory: accessory ?? this.accessory,
    );
  }

  bool sameAs(AvatarConfig o) =>
      skin == o.skin &&
      faceShape == o.faceShape &&
      hairStyle == o.hairStyle &&
      hairColor == o.hairColor &&
      eyes == o.eyes &&
      outfit == o.outfit &&
      accessory == o.accessory;

  /// 겹쳐 그릴 조각 이름 (그리는 순서대로). 머리 조각은 hairColor 로 물들인다.
  List<String> get layerNames => [
        'hair_${hairStyle % hairStyleCount + 1}_back',
        'skin_${skinNames[skin % 4]}',
        'outfit_${outfitNames[outfit % 4]}',
        'face_${faceNames[faceShape % 2]}_${skinNames[skin % 4]}',
        'eyes_${eyeNames[eyes % 3]}',
        'hair_${hairStyle % hairStyleCount + 1}_front',
        if (accessory == 2) 'accessory_bow',
        if (accessory == 3) 'accessory_crown',
      ];

  String describe() {
    const hairColorNames = ['검은', '갈색', '밝은 갈색', '노란', '빨간', '분홍'];
    const hairStyleNames = ['짧은 머리', '단발머리', '긴 머리', '양갈래 머리', '위로 묶은 머리', '곱슬머리'];
    const outfitColorNames = ['파란', '분홍', '민트색', '노란'];
    const accessoryNames = ['', '동그란 안경', '분홍 리본', '금빛 왕관'];
    final parts = <String>[
      '${hairColorNames[hairColor % 6]} ${hairStyleNames[hairStyle % 6]}',
      '${outfitColorNames[outfit % 4]} 옷',
      if (accessory > 0 && accessory < accessoryNames.length) accessoryNames[accessory],
    ];
    return '아이를 닮게 꾸민 주인공 (${parts.join(', ')})';
  }
}

/// 조각 PNG 를 한 번만 읽어 두는 보관소 (미리보기·보기 카드·PNG 내보내기가 함께 씀)
class AvatarLayers {
  static final Map<String, ui.Image> _images = {};
  static Future<void>? _loading;
  static bool get ready => _images.length >= _all.length;

  static final List<String> _all = [
    for (int h = 1; h <= 6; h++) ...['hair_${h}_back', 'hair_${h}_front'],
    for (final t in AvatarConfig.skinNames) ...['skin_$t', 'face_round_$t', 'face_oval_$t'],
    for (final o in AvatarConfig.outfitNames) 'outfit_$o',
    for (final e in AvatarConfig.eyeNames) 'eyes_$e',
    'accessory_bow',
    'accessory_crown',
  ];

  static Future<void> load() => _loading ??= _loadAll();

  static Future<void> _loadAll() async {
    await Future.wait(_all.map((name) async {
      final data = await rootBundle.load(dhLayer(name));
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      _images[name] = (await codec.getNextFrame()).image;
    }));
  }

  static ui.Image? of(String name) => _images[name];
}

// 머리 조각(갈색)을 다른 머리색으로 물들이는 필터: 밝기는 살리고 색만 바꿔 테두리 선이 남는다
ColorFilter? _hairTint(int hairColor) {
  if (hairColor % 6 == 1) return null; // 조각 원래 색
  final c = AvatarConfig.hairColors[hairColor % 6];
  const k = 1 / 0.307; // 조각의 가운데 밝기가 고른 색이 되도록
  final r = c.r * k, g = c.g * k, b = c.b * k;
  return ColorFilter.matrix(<double>[
    0.299 * r, 0.587 * r, 0.114 * r, 0, 0,
    0.299 * g, 0.587 * g, 0.114 * g, 0, 0,
    0.299 * b, 0.587 * b, 0.114 * b, 0, 0,
    0, 0, 0, 1, 0,
  ]);
}

/// 캐릭터를 그린다 (화면 미리보기·보기 카드·PNG 내보내기가 모두 이 함수를 씀). 조각을 다 읽기 전에는 아무것도 그리지 않는다.
void paintAvatar(Canvas canvas, Size size, AvatarConfig c) {
  if (!AvatarLayers.ready) return;
  final double side = math.min(size.width, size.height);
  final dst = Rect.fromLTWH((size.width - side) / 2, (size.height - side) / 2, side, side);
  const src = Rect.fromLTWH(0, 0, 512, 512);
  final tint = _hairTint(c.hairColor);

  for (final name in c.layerNames) {
    final image = AvatarLayers.of(name);
    if (image == null) continue;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (tint != null && name.startsWith('hair_')) paint.colorFilter = tint;
    canvas.drawImageRect(image, src, dst, paint);
  }

  // 안경은 조각 그림이 없어 눈 위치(조각 좌표 215·297, 196)에 맞춰 직접 그린다
  if (c.accessory == 1) {
    final double s = side / 512;
    Offset at(double x, double y) => dst.topLeft + Offset(x * s, y * s);
    final rim = Paint()
      ..color = const Color(0xFF5A3A22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 * s
      ..strokeCap = StrokeCap.round;
    final glass = Paint()..color = Colors.white.withValues(alpha: 0.28);
    for (final x in [215.5, 297.5]) {
      canvas.drawCircle(at(x, 196), 30 * s, glass);
      canvas.drawCircle(at(x, 196), 30 * s, rim);
    }
    canvas.drawLine(at(245.5, 194), at(267.5, 194), rim);
  }
}

/// 캐릭터를 투명 배경 PNG 로 만든다 (창작 화면의 다른 그림과 같은 512x512)
Future<Uint8List> renderAvatarPng(AvatarConfig config, {int size = 512}) async {
  await AvatarLayers.load();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));
  paintAvatar(canvas, Size(size.toDouble(), size.toDouble()), config);
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

class AvatarPainter extends CustomPainter {
  final AvatarConfig config;
  final bool ready;
  AvatarPainter(this.config) : ready = AvatarLayers.ready;

  @override
  void paint(Canvas canvas, Size size) => paintAvatar(canvas, size, config);

  @override
  bool shouldRepaint(AvatarPainter oldDelegate) => oldDelegate.ready != ready || !oldDelegate.config.sameAs(config);
}

// 꾸밀 수 있는 부분 하나 (탭 하나)
class _Part {
  final String icon; // assets/donghwarang/icons
  final String label; // 접근성 이름
  final int count;
  final int Function(AvatarConfig) get;
  final AvatarConfig Function(AvatarConfig, int) set;
  const _Part(this.icon, this.label, this.count, this.get, this.set);
}

class AvatarMakerScreen extends StatefulWidget {
  const AvatarMakerScreen({super.key});

  @override
  State<AvatarMakerScreen> createState() => _AvatarMakerScreenState();
}

class _AvatarMakerScreenState extends State<AvatarMakerScreen> with SingleTickerProviderStateMixin {
  static String get _baseUrl => AppConfig.serverUrl;

  AvatarConfig _config = const AvatarConfig(); // 시안의 기본 모습: 갈색 단발, 파란 옷
  int _tab = 1; // 처음에는 머리 모양부터
  bool _analyzing = false;
  bool _finishing = false;

  final math.Random _random = math.Random();
  final AudioPlayer _audioPlayer = AudioPlayer();
  late final AnimationController _floatController =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);

  static final List<_Part> _parts = [
    _Part('face', '얼굴', 4, (c) => c.skin, (c, i) => c.copyWith(skin: i)),
    _Part('hair', '머리 모양', AvatarConfig.hairStyleCount, (c) => c.hairStyle, (c, i) => c.copyWith(hairStyle: i)),
    _Part('palette', '머리 색', AvatarConfig.hairColors.length, (c) => c.hairColor, (c, i) => c.copyWith(hairColor: i)),
    _Part('eyes', '눈', 3, (c) => c.eyes, (c, i) => c.copyWith(eyes: i)),
    _Part('clothes', '옷', 4, (c) => c.outfit, (c, i) => c.copyWith(outfit: i)),
    _Part('crown', '꾸미기', AvatarConfig.accessoryCount, (c) => c.accessory, (c, i) => c.copyWith(accessory: i)),
  ];

  @override
  void initState() {
    super.initState();
    AvatarLayers.load().then((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speak('나를 닮은 주인공을 만들어 보자! 마음에 드는 그림을 눌러 봐.');
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _floatController.dispose();
    super.dispose();
  }

  // 크레용 목소리로 안내 (서버가 꺼져 있으면 조용히 넘어감)
  Future<void> _speak(String text) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/api/chat/tts'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted || res.statusCode != 200) return;
      final String audioB64 = jsonDecode(utf8.decode(res.bodyBytes))['audio_base64'] ?? '';
      if (audioB64.isEmpty) return;
      await _audioPlayer.stop();
      await _audioPlayer.play(BytesSource(base64Decode(audioB64)));
    } catch (e) {
      debugPrint('꾸미기 안내 음성 실패 (무시): $e');
    }
  }

  void _showMessage(String text, {String image = CrayongImages.wink}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Image.asset(image, width: 30, height: 30),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: AppTextStyles.labelLarge(color: Colors.white))),
          ],
        ),
      ),
    );
  }

  void _randomize() {
    setState(() {
      _config = AvatarConfig(
        skin: _random.nextInt(4),
        hairStyle: _random.nextInt(AvatarConfig.hairStyleCount),
        hairColor: _random.nextInt(AvatarConfig.hairColors.length),
        eyes: _random.nextInt(3),
        outfit: _random.nextInt(4),
        accessory: _random.nextInt(AvatarConfig.accessoryCount),
      );
    });
  }

  // 📷 사진으로 닮게: 보호자 동의 → 사진 → 서버가 특징만 읽음 → 처음 모습에 반영
  Future<void> _matchFromPhoto() async {
    if (_analyzing) return;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(CrayongImages.wink, height: 96),
                const SizedBox(height: 10),
                Text('사진을 찍을까요?', style: AppTextStyles.headingMedium()),
                const SizedBox(height: 8),
                Text(
                  '보호자와 함께 봐 주세요.\n사진은 머리 모양·머리색·안경처럼 닮은 점을 찾는 데만 쓰고, 저장하지 않아요.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium(color: AppColors.textPrimary),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.border, width: 2)),
                        child: const Text('안 찍을래요'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('찍을래요')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (agreed != true || !mounted) return;

    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 640,
        maxHeight: 640,
        imageQuality: 80,
      );
      if (photo == null || !mounted) return;
      setState(() => _analyzing = true);
      final bytes = await photo.readAsBytes();
      final res = await http
          .post(
            Uri.parse('$_baseUrl/api/avatar/features'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'image_base64': base64Encode(bytes)}),
          )
          .timeout(const Duration(seconds: 40));
      if (!mounted) return;
      if (res.statusCode != 200) throw Exception('서버 응답 ${res.statusCode}');
      final Map<String, dynamic> f = jsonDecode(utf8.decode(res.bodyBytes));
      int pick(String key, int count, int fallback) {
        final v = f[key];
        return v is int && v >= 0 && v < count ? v : fallback;
      }

      setState(() {
        _config = _config.copyWith(
          skin: pick('skin', 4, _config.skin),
          hairStyle: pick('hair_style', AvatarConfig.hairStyleCount, _config.hairStyle),
          hairColor: pick('hair_color', AvatarConfig.hairColors.length, _config.hairColor),
          accessory: f['glasses'] == true ? 1 : (_config.accessory == 1 ? 0 : _config.accessory),
        );
      });
      _speak('짜잔! 너랑 닮았지? 마음에 안 드는 곳은 눌러서 바꿔 봐.');
    } catch (e) {
      debugPrint('사진으로 닮게 실패: $e');
      if (mounted) _showMessage('사진에서 닮은 점을 못 찾았어요. 직접 골라 볼까요?', image: CrayongImages.surprised);
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      await _audioPlayer.stop();
      final png = await renderAvatarPng(_config);
      if (!mounted) return;
      Navigator.pop(context, AvatarResult(png, _config.describe()));
    } catch (e) {
      debugPrint('캐릭터 그림 만들기 실패: $e');
      if (mounted) {
        setState(() => _finishing = false);
        _showMessage('주인공을 못 만들었어요. 다시 눌러 줄래요?', image: CrayongImages.surprised);
      }
    }
  }

  // ── 시안 크기(1586×992) 좌표에 홈 톤의 판·버튼·카드를 직접 그린다 ──
  static const List<double> _tabX = [727, 872, 1017, 1160, 1302, 1447]; // 탭 동그라미 가운데 (y 는 205)
  static const List<List<double>> _cardCols = [[641, 850], [866, 1077], [1092, 1298], [1316, 1527]];
  static const List<List<double>> _cardRows = [[335, 556], [578, 802]];

  Rect _cardRect(int i) {
    final c = _cardCols[i % 4], r = _cardRows[(i ~/ 4) % 2];
    return Rect.fromLTRB(c[0] - 4, r[0] - 4, c[1] + 4, r[1] + 6);
  }

  @override
  Widget build(BuildContext context) {
    final part = _parts[_tab];
    final selected = part.get(_config);
    return ToyScaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: DhMeadow()),
          Positioned.fill(
            child: DhDesignCanvas(
              children: [
                // 바탕 판: 왼쪽 미리보기 판, 오른쪽 고르기 판
                Positioned.fromRect(rect: const Rect.fromLTRB(40, 150, 596, 932), child: Container(decoration: dhFrame('paper_panel'))),
                Positioned.fromRect(rect: const Rect.fromLTRB(612, 122, 1560, 842), child: Container(decoration: dhFrame('paper_panel'))),

                // 위쪽: 뒤로, 제목, 다 됐어
                Positioned.fromRect(
                  rect: const Rect.fromLTRB(30, 34, 118, 122),
                  child: Container(
                    decoration: dhFrame('button_cream').copyWith(borderRadius: BorderRadius.circular(44)),
                    child: const Icon(Icons.arrow_back_rounded, size: 50, color: dhBrown),
                  ),
                ),
                Positioned(left: 146, top: 44, child: Text('나를 닮은 주인공', style: dhText(58))),
                Positioned.fromRect(
                  rect: const Rect.fromLTRB(1282, 36, 1562, 118),
                  child: Container(
                    decoration: dhFrame('button_yellow').copyWith(borderRadius: BorderRadius.circular(42)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_rounded, size: 46, color: Color(0xFF7A3B1E)),
                        const SizedBox(width: 8),
                        Text('다 됐어!', style: dhText(42, color: const Color(0xFF7A3B1E))),
                      ],
                    ),
                  ),
                ),

                // 아래쪽: 사진으로 닮게, 아무거나
                Positioned.fromRect(
                  rect: const Rect.fromLTRB(62, 812, 344, 896),
                  child: Container(
                    decoration: dhFrame('button_blue').copyWith(borderRadius: BorderRadius.circular(42)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.photo_camera_rounded, size: 40, color: dhBrown),
                        const SizedBox(width: 8),
                        Text('사진으로 닮게', style: dhText(30)),
                      ],
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: const Rect.fromLTRB(360, 812, 574, 896),
                  child: Container(
                    decoration: dhFrame('button_cream').copyWith(borderRadius: BorderRadius.circular(42)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.casino_rounded, size: 40, color: dhBrown),
                        const SizedBox(width: 8),
                        Text('아무거나', style: dhText(30)),
                      ],
                    ),
                  ),
                ),

                // 왼쪽 큰 미리보기: 연노랑 판 위에 지금 조합을 그림
                Positioned.fromRect(
                  rect: const Rect.fromLTRB(92, 205, 548, 792),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE9A0),
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 4),
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: const Rect.fromLTWH(0, 160, 640, 640),
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _floatController,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(0, -6 * Curves.easeInOut.transform(_floatController.value)),
                        child: child,
                      ),
                      child: CustomPaint(painter: AvatarPainter(_config)),
                    ),
                  ),
                ),
                if (_analyzing)
                  DhPatch(
                    const Rect.fromLTRB(92, 205, 548, 792),
                    const Color(0xF2FFE9A8),
                    radius: 40,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(CrayongImages.main, height: 170),
                        const SizedBox(height: 18),
                        const SizedBox(
                          width: 220,
                          child: LinearProgressIndicator(minHeight: 9, borderRadius: BorderRadius.all(Radius.circular(5))),
                        ),
                        const SizedBox(height: 16),
                        Text('닮은 점을 찾고 있어…', style: dhText(36)),
                      ],
                    ),
                  ),

                // 꾸밀 곳 탭: 고른 탭은 노란 동그라미
                for (int i = 0; i < _parts.length; i++)
                    Positioned.fromRect(
                      rect: Rect.fromCircle(center: Offset(_tabX[i], 205), radius: 59),
                      child: IgnorePointer(
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _tab ? const Color(0xFFFFCB3D) : const Color(0xFFFFF0DA),
                            border: Border.all(color: i == _tab ? const Color(0xFFE3A520) : const Color(0xFFE3C79E), width: 4),
                          ),
                          child: DhIcon(_parts[i].icon, size: 74),
                        ),
                      ),
                    ),
                for (int i = 0; i < _parts.length; i++)
                  DhHit(Rect.fromCircle(center: Offset(_tabX[i], 205), radius: 62), _parts[i].label, () => setState(() => _tab = i), radius: 62),

                // 보기 카드
                for (int i = 0; i < part.count && i < 8; i++)
                  Positioned.fromRect(
                    rect: _cardRect(i).deflate(3),
                    child: IgnorePointer(
                      child: Container(
                        decoration: dhFrame(i == selected ? 'slot_selected' : 'gallery_slot', scale: 2),
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 14),
                        child: Stack(
                          children: [
                            Positioned.fill(child: CustomPaint(painter: AvatarPainter(part.set(_config, i)))),
                            if (i == selected) const Positioned(top: 2, right: 2, child: DhIcon('check_green', size: 50)),
                          ],
                        ),
                      ),
                    ),
                  ),
                for (int i = 0; i < part.count && i < 8; i++)
                  DhHit(
                    _cardRect(i),
                    '${part.label} ${i + 1}번${i == selected ? ', 선택됨' : ''}',
                    () => setState(() => _config = part.set(_config, i)),
                    radius: 30,
                  ),

                // 누르는 자리들
                DhHit(const Rect.fromLTRB(22, 30, 125, 120), '뒤로 가기', () => Navigator.pop(context), radius: 48),
                DhHit(const Rect.fromLTRB(1275, 30, 1572, 126), '다 됐어, 주인공 완성', _finishing ? null : _finish, radius: 48),
                DhHit(const Rect.fromLTRB(55, 803, 348, 902), '사진으로 닮게', _analyzing ? null : _matchFromPhoto, radius: 46),
                DhHit(const Rect.fromLTRB(352, 803, 577, 902), '아무거나', _analyzing ? null : _randomize, radius: 46),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
