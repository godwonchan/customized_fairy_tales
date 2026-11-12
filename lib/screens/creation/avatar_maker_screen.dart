// lib/screens/creation/avatar_maker_screen.dart
// 나를 닮은 주인공 만들기: 글을 몰라도 그림 버튼만 눌러 주인공을 꾸민다.
// - 고를 때마다 캐릭터가 바로 바뀐다 (그림 생성 AI를 쓰지 않아 기다림·비용이 없음)
// - "사진으로 닮게"를 누르면 사진에서 머리 모양·머리색·안경 같은 특징만 읽어 처음 모습을 맞춰 준다
//   (사진은 서버에 저장하지 않고, 그림으로 바꾸지도 않는다)
// - 완성하면 PNG 로 만들어 창작 화면의 주인공 그림 자리에 넣는다
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../config/app_config.dart';
import '../../theme/app_theme.dart';
import '../../widgets/crayong_widgets.dart';

/// 꾸미기 결과 (창작 화면으로 돌려주는 값)
class AvatarResult {
  final Uint8List png; // 투명 배경 512x512
  final String description; // 동화 만들 때 참고할 생김새 설명
  const AvatarResult(this.png, this.description);
}

/// 캐릭터 생김새 (모든 값은 보기 번호)
class AvatarConfig {
  final int skin;
  final int hairStyle;
  final int hairColor;
  final int eyes;
  final int outfit;
  final int accessory;

  const AvatarConfig({
    this.skin = 0,
    this.hairStyle = 0,
    this.hairColor = 0,
    this.eyes = 0,
    this.outfit = 0,
    this.accessory = 0,
  });

  static const List<Color> skins = [Color(0xFFFFE3CC), Color(0xFFF8CFA6), Color(0xFFE2AA7A), Color(0xFFA8704A)];
  static const List<Color> hairColors = [
    Color(0xFF2B2320),
    Color(0xFF6B4226),
    Color(0xFFB9783F),
    Color(0xFFF2C94C),
    Color(0xFFD9573F),
    Color(0xFFFF8FC8),
  ];
  static const List<Color> outfitColors = [Color(0xFF4D96FF), Color(0xFFFF6B6B), Color(0xFF6BCB77), Color(0xFFFFC93C)];

  static const int hairStyleCount = 6; // 짧은 머리, 단발, 긴 머리, 양갈래, 똥머리, 곱슬
  static const int eyesCount = 3; // 동그란 눈, 웃는 눈, 반짝 눈
  static const int outfitCount = 8; // 티셔츠 4색 + 원피스 4색
  static const int accessoryCount = 5; // 없음, 안경, 리본, 왕관, 모자

  AvatarConfig copyWith({int? skin, int? hairStyle, int? hairColor, int? eyes, int? outfit, int? accessory}) {
    return AvatarConfig(
      skin: skin ?? this.skin,
      hairStyle: hairStyle ?? this.hairStyle,
      hairColor: hairColor ?? this.hairColor,
      eyes: eyes ?? this.eyes,
      outfit: outfit ?? this.outfit,
      accessory: accessory ?? this.accessory,
    );
  }

  String describe() {
    const hairColorNames = ['검은', '갈색', '밝은 갈색', '노란', '빨간', '분홍'];
    const hairStyleNames = ['짧은 머리', '단발머리', '긴 머리', '양갈래 머리', '위로 묶은 머리', '곱슬머리'];
    const outfitColorNames = ['파란', '빨간', '초록', '노란'];
    const accessoryNames = ['', '동그란 안경', '빨간 리본', '금빛 왕관', '털모자'];
    final parts = <String>[
      '${hairColorNames[hairColor]} ${hairStyleNames[hairStyle]}',
      '${outfitColorNames[outfit % 4]} ${outfit < 4 ? '티셔츠' : '원피스'}',
      if (accessory > 0) accessoryNames[accessory],
    ];
    return '아이를 닮게 꾸민 주인공 (${parts.join(', ')})';
  }
}

const Color _outline = Color(0xFF4A3728);

/// 512x512 기준으로 캐릭터를 그린다 (화면 미리보기·보기 버튼·PNG 내보내기가 모두 이 함수를 씀)
void paintAvatar(Canvas canvas, Size size, AvatarConfig c) {
  final double s = math.min(size.width, size.height) / 512;
  canvas.save();
  canvas.translate((size.width - 512 * s) / 2, (size.height - 512 * s) / 2);
  canvas.scale(s);

  final skin = AvatarConfig.skins[c.skin % AvatarConfig.skins.length];
  final hair = AvatarConfig.hairColors[c.hairColor % AvatarConfig.hairColors.length];
  final cloth = AvatarConfig.outfitColors[c.outfit % 4];
  final bool dress = c.outfit >= 4;

  Paint fill(Color color) => Paint()..color = color;
  Paint line([double w = 6]) => Paint()
    ..color = _outline
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  Paint limb(Color color, double w) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round;

  const head = Offset(256, 200);
  const double r = 105;

  // 1. 뒷머리 (얼굴 뒤에 깔리는 부분)
  void backShape(Path p) {
    canvas.drawPath(p, fill(hair));
    canvas.drawPath(p, line(5));
  }

  if (c.hairStyle == 1) {
    backShape(Path()..addRRect(RRect.fromLTRBR(138, 190, 374, 330, const Radius.circular(46))));
  } else if (c.hairStyle == 2) {
    backShape(Path()..addRRect(RRect.fromLTRBR(134, 190, 378, 420, const Radius.circular(50))));
  } else if (c.hairStyle == 3) {
    for (final x in [122.0, 390.0]) {
      backShape(Path()..addOval(Rect.fromCenter(center: Offset(x, 262), width: 78, height: 104)));
      canvas.drawCircle(Offset(x < 256 ? 146 : 366, 214), 12, fill(const Color(0xFFFF6B6B)));
    }
  } else if (c.hairStyle == 4) {
    backShape(Path()..addOval(Rect.fromCircle(center: const Offset(256, 82), radius: 44)));
  } else if (c.hairStyle == 5) {
    for (int i = 0; i <= 8; i++) {
      final a = math.pi + (math.pi * i / 8);
      final p = head + Offset(math.cos(a) * (r + 6), math.sin(a) * (r + 6));
      backShape(Path()..addOval(Rect.fromCircle(center: p, radius: 36)));
    }
    for (final x in [150.0, 362.0]) {
      backShape(Path()..addOval(Rect.fromCircle(center: Offset(x, 236), radius: 34)));
    }
  }

  // 2. 다리와 신발
  for (final x in [228.0, 284.0]) {
    canvas.drawLine(Offset(x, 396), Offset(x, 458), limb(_outline, 34));
    canvas.drawLine(Offset(x, 396), Offset(x, 458), limb(skin, 24));
    final shoe = Rect.fromCenter(center: Offset(x < 256 ? x - 8 : x + 8, 470), width: 56, height: 28);
    canvas.drawOval(shoe, fill(const Color(0xFF8D6E63)));
    canvas.drawOval(shoe, line(5));
  }

  // 3. 팔
  for (final pair in [
    [const Offset(196, 326), const Offset(142, 384)],
    [const Offset(316, 326), const Offset(370, 384)],
  ]) {
    canvas.drawLine(pair[0], pair[1], limb(_outline, 34));
    canvas.drawLine(pair[0], pair[1], limb(skin, 24));
  }

  // 4. 옷
  final Path body;
  if (dress) {
    body = Path()
      ..moveTo(204, 292)
      ..lineTo(308, 292)
      ..lineTo(352, 414)
      ..lineTo(160, 414)
      ..close();
  } else {
    body = Path()..addRRect(RRect.fromLTRBR(188, 292, 324, 408, const Radius.circular(30)));
  }
  canvas.drawPath(body, fill(cloth));
  canvas.drawPath(body, line());
  if (!dress) {
    // 티셔츠 가운데 작은 별
    canvas.drawCircle(const Offset(256, 352), 13, fill(Colors.white.withValues(alpha: 0.85)));
  }

  // 5. 귀와 얼굴
  for (final x in [156.0, 356.0]) {
    canvas.drawCircle(Offset(x, 212), 20, fill(skin));
    canvas.drawCircle(Offset(x, 212), 20, line(5));
  }
  canvas.drawCircle(head, r, fill(skin));
  canvas.drawCircle(head, r, line());

  // 6. 앞머리 (머리 전체에서 얼굴이 보이는 구멍을 뺀 모양)
  final hairCap = Path.combine(
    PathOperation.difference,
    Path()..addOval(Rect.fromCircle(center: head, radius: r + 10)),
    Path()..addOval(Rect.fromCenter(center: const Offset(256, 238), width: r * 1.7, height: r * 1.86)),
  );
  final double sideLimit = c.hairStyle == 0 || c.hairStyle == 4 ? 196 : 226; // 옆머리가 내려오는 높이
  final front = Path.combine(
    PathOperation.intersect,
    hairCap,
    Path()..addRect(Rect.fromLTRB(0, 0, 512, sideLimit)),
  );
  canvas.drawPath(front, fill(hair));
  canvas.drawPath(front, line(5));

  // 7. 눈·볼·입
  const eyeL = Offset(218, 216);
  const eyeR = Offset(294, 216);
  if (c.eyes == 1) {
    for (final e in [eyeL, eyeR]) {
      canvas.drawArc(Rect.fromCenter(center: e + const Offset(0, 6), width: 34, height: 28), math.pi, math.pi, false, line(6));
    }
  } else {
    final double er = c.eyes == 2 ? 16 : 11;
    for (final e in [eyeL, eyeR]) {
      canvas.drawCircle(e, er, fill(_outline));
      canvas.drawCircle(e + Offset(-er * 0.3, -er * 0.35), er * 0.36, fill(Colors.white));
      if (c.eyes == 2) canvas.drawCircle(e + Offset(er * 0.35, er * 0.3), er * 0.2, fill(Colors.white));
    }
  }
  for (final x in [194.0, 318.0]) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, 250), width: 36, height: 22),
      fill(const Color(0xFFFF8A80).withValues(alpha: 0.55)),
    );
  }
  canvas.drawArc(Rect.fromCenter(center: const Offset(256, 248), width: 58, height: 44), math.pi * 0.15, math.pi * 0.7, false, line(6));

  // 8. 꾸미기 소품
  if (c.accessory == 1) {
    for (final e in [eyeL, eyeR]) {
      canvas.drawCircle(e, 28, fill(Colors.white.withValues(alpha: 0.25)));
      canvas.drawCircle(e, 28, line(6));
    }
    canvas.drawLine(eyeL + const Offset(28, 0), eyeR - const Offset(28, 0), line(6));
  } else if (c.accessory == 2) {
    const center = Offset(338, 118);
    final bow = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx - 46, center.dy - 30)
      ..lineTo(center.dx - 46, center.dy + 30)
      ..close()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx + 46, center.dy - 30)
      ..lineTo(center.dx + 46, center.dy + 30)
      ..close();
    canvas.drawPath(bow, fill(const Color(0xFFFF5C7A)));
    canvas.drawPath(bow, line(5));
    canvas.drawCircle(center, 13, fill(const Color(0xFFFF5C7A)));
    canvas.drawCircle(center, 13, line(5));
  } else if (c.accessory == 3) {
    final crown = Path()
      ..moveTo(196, 108)
      ..lineTo(206, 44)
      ..lineTo(236, 82)
      ..lineTo(256, 34)
      ..lineTo(276, 82)
      ..lineTo(306, 44)
      ..lineTo(316, 108)
      ..close();
    canvas.drawPath(crown, fill(const Color(0xFFFFD93D)));
    canvas.drawPath(crown, line(5));
    for (final x in [226.0, 256.0, 286.0]) {
      canvas.drawCircle(Offset(x, 94), 6, fill(const Color(0xFFFF6B6B)));
    }
  } else if (c.accessory == 4) {
    final cap = Path.combine(
      PathOperation.intersect,
      Path()..addOval(Rect.fromCircle(center: const Offset(256, 150), radius: r + 14)),
      Path()..addRect(const Rect.fromLTRB(0, 0, 512, 132)),
    );
    canvas.drawPath(cap, fill(const Color(0xFF4F93C2)));
    canvas.drawPath(cap, line(5));
    final band = RRect.fromLTRBR(134, 116, 378, 148, const Radius.circular(16));
    canvas.drawRRect(band, fill(const Color(0xFFE8F1F8)));
    canvas.drawRRect(band, line(5));
    canvas.drawCircle(const Offset(256, 24), 20, fill(const Color(0xFFE8F1F8)));
    canvas.drawCircle(const Offset(256, 24), 20, line(5));
  }

  canvas.restore();
}

/// 캐릭터를 투명 배경 PNG 로 만든다 (창작 화면의 다른 그림과 같은 512x512)
Future<Uint8List> renderAvatarPng(AvatarConfig config, {int size = 512}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));
  paintAvatar(canvas, Size(size.toDouble(), size.toDouble()), config);
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

class AvatarPainter extends CustomPainter {
  final AvatarConfig config;
  const AvatarPainter(this.config);

  @override
  void paint(Canvas canvas, Size size) => paintAvatar(canvas, size, config);

  @override
  bool shouldRepaint(AvatarPainter oldDelegate) =>
      oldDelegate.config.skin != config.skin ||
      oldDelegate.config.hairStyle != config.hairStyle ||
      oldDelegate.config.hairColor != config.hairColor ||
      oldDelegate.config.eyes != config.eyes ||
      oldDelegate.config.outfit != config.outfit ||
      oldDelegate.config.accessory != config.accessory;
}

// 꾸밀 수 있는 부분 하나 (탭 하나)
class _Part {
  final String emoji;
  final int count;
  final int Function(AvatarConfig) get;
  final AvatarConfig Function(AvatarConfig, int) set;
  const _Part(this.emoji, this.count, this.get, this.set);
}

class AvatarMakerScreen extends StatefulWidget {
  const AvatarMakerScreen({super.key});

  @override
  State<AvatarMakerScreen> createState() => _AvatarMakerScreenState();
}

class _AvatarMakerScreenState extends State<AvatarMakerScreen> with SingleTickerProviderStateMixin {
  static String get _baseUrl => AppConfig.serverUrl;

  AvatarConfig _config = const AvatarConfig(hairStyle: 1, hairColor: 1);
  int _tab = 1; // 처음에는 머리 모양부터
  bool _analyzing = false;
  bool _finishing = false;

  final math.Random _random = math.Random();
  final AudioPlayer _audioPlayer = AudioPlayer();
  late final AnimationController _floatController =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);

  static final List<_Part> _parts = [
    _Part('🙂', AvatarConfig.skins.length, (c) => c.skin, (c, i) => c.copyWith(skin: i)),
    _Part('💇', AvatarConfig.hairStyleCount, (c) => c.hairStyle, (c, i) => c.copyWith(hairStyle: i)),
    _Part('🎨', AvatarConfig.hairColors.length, (c) => c.hairColor, (c, i) => c.copyWith(hairColor: i)),
    _Part('👀', AvatarConfig.eyesCount, (c) => c.eyes, (c, i) => c.copyWith(eyes: i)),
    _Part('👕', AvatarConfig.outfitCount, (c) => c.outfit, (c, i) => c.copyWith(outfit: i)),
    _Part('👑', AvatarConfig.accessoryCount, (c) => c.accessory, (c, i) => c.copyWith(accessory: i)),
  ];

  @override
  void initState() {
    super.initState();
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
        skin: _random.nextInt(AvatarConfig.skins.length),
        hairStyle: _random.nextInt(AvatarConfig.hairStyleCount),
        hairColor: _random.nextInt(AvatarConfig.hairColors.length),
        eyes: _random.nextInt(AvatarConfig.eyesCount),
        outfit: _random.nextInt(AvatarConfig.outfitCount),
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
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('찍을래요'),
                      ),
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
          skin: pick('skin', AvatarConfig.skins.length, _config.skin),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 700) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 4, child: _buildPreview()),
                          const SizedBox(width: 18),
                          Expanded(flex: 6, child: _buildOptions(columns: 4)),
                        ],
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                    child: Column(
                      children: [
                        SizedBox(height: constraints.maxHeight * 0.42, child: _buildPreview()),
                        const SizedBox(height: 12),
                        Expanded(child: _buildOptions(columns: 3)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          RoundIconButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Text('나를 닮은 주인공 만들기', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.headingLarge()),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _finishing ? null : _finish,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 26),
              decoration: AppDecorations.sticker(
                color: AppColors.secondaryDark,
                shadowColor: const Color(0xFF457A36),
                radius: 28,
                depth: 5,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_rounded, color: Colors.white, size: 28),
                  const SizedBox(width: 8),
                  Text('다 됐어!', style: AppTextStyles.button(color: Colors.white).copyWith(fontSize: 24)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      decoration: AppDecorations.card(radius: 30, color: AppColors.primaryLight),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _floatController,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(0, -6 * Curves.easeInOut.transform(_floatController.value)),
                      child: child,
                    ),
                    child: CustomPaint(painter: AvatarPainter(_config)),
                  ),
                ),
                if (_analyzing)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(CrayongImages.drawing, height: 100),
                          const SizedBox(height: 12),
                          const SizedBox(
                            width: 140,
                            child: LinearProgressIndicator(minHeight: 6, borderRadius: BorderRadius.all(Radius.circular(3))),
                          ),
                          const SizedBox(height: 10),
                          Text('닮은 점을 찾고 있어…', style: AppTextStyles.headingSmall()),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _previewButton(icon: Icons.photo_camera_rounded, label: '사진으로 닮게', onTap: _matchFromPhoto),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _previewButton(icon: Icons.casino_rounded, label: '아무거나', onTap: _randomize),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: _analyzing ? null : onTap,
      child: Container(
        height: 58,
        alignment: Alignment.center,
        decoration: AppDecorations.sticker(color: AppColors.surface, shadowColor: AppColors.border, radius: 20, depth: 4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 26, color: AppColors.primaryText),
                const SizedBox(width: 6),
                Text(label, style: AppTextStyles.button().copyWith(fontSize: 19)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptions({required int columns}) {
    final part = _parts[_tab];
    final selected = part.get(_config);
    return Container(
      decoration: AppDecorations.card(radius: 30),
      child: Column(
        children: [
          // 꾸밀 곳 고르기: 글자 없이 그림 버튼만
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (int i = 0; i < _parts.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _tab = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 66,
                      height: 66,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _tab == i ? AppColors.primary : AppColors.surfaceVariant,
                        shape: BoxShape.circle,
                        border: Border.all(color: _tab == i ? AppColors.primaryDark : AppColors.border, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: _tab == i ? AppColors.primaryDark : AppColors.border,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(_parts[i].emoji, style: const TextStyle(fontSize: 32)),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 14,
                mainAxisSpacing: 16,
                childAspectRatio: 0.92,
              ),
              itemCount: part.count,
              itemBuilder: (context, i) {
                final isSelected = i == selected;
                return GestureDetector(
                  onTap: () => setState(() => _config = part.set(_config, i)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primaryLight : AppColors.inputFill,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: isSelected ? 4 : 2),
                      boxShadow: [
                        BoxShadow(color: isSelected ? AppColors.primaryDark : AppColors.border, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(child: CustomPaint(painter: AvatarPainter(part.set(_config, i)))),
                        if (isSelected)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: const BoxDecoration(color: AppColors.secondaryDark, shape: BoxShape.circle),
                              child: const Icon(Icons.check_rounded, size: 20, color: Colors.white),
                            ),
                          ),
                      ],
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
}
