import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../services/api_service.dart';
import 'rpg_play_screen.dart'; // kBg, kPrimary, kPrimaryLight, kPill, kInk

class RpgDrawScreen extends StatefulWidget {
  final int storyId;
  final String storyTitle;
  final String playerName;
  final String assetHint;
  final int maxTurns;

  const RpgDrawScreen({
    super.key,
    required this.storyId,
    required this.storyTitle,
    this.playerName = '주인공',
    this.assetHint = '',
    this.maxTurns = 6,
  });

  @override
  State<RpgDrawScreen> createState() => _RpgDrawScreenState();
}

class _RpgDrawScreenState extends State<RpgDrawScreen> {
  final GlobalKey _boundaryKey = GlobalKey();

  // 탭별로 그림을 따로 보관 (공유 X)
  final Map<String, List<Offset?>> _pointsByType = {};

  bool _drawing = false;
  String _assetType = '캐릭터';
  bool _loading = false;

  final _types = const ['캐릭터', '무기', '동물', '아이템', '배경'];

  // 현재 선택된 탭의 그림 리스트
  List<Offset?> get _points =>
      _pointsByType.putIfAbsent(_assetType, () => <Offset?>[]);

  void _add(Offset p) => setState(() => _points.add(p));
  void _end() => setState(() => _points.add(null));
  void _clear() => setState(() => _points.clear());

  bool get _currentHasDrawing => _points.any((e) => e != null);

  Future<Uint8List?> _capture() async {
    final boundary =
        _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<Uint8List?> _fetchSprite(String desc, String type) async {
    final resp = await http.post(
      Uri.parse('${ApiService.baseUrl}/rpg/sprite'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'description': desc, 'asset_type': type}),
    );
    if (resp.statusCode != 200) return null;
    return resp.bodyBytes;
  }

  void _goPlay(String assetHint, Uint8List? sprite) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RpgPlayScreen(
          storyId: widget.storyId,
          storyTitle: widget.storyTitle,
          playerName: widget.playerName,
          assetHint: assetHint,
          maxTurns: widget.maxTurns,
          characterSprite: sprite,
        ),
      ),
    );
  }

  Future<void> _complete() async {
    if (!_currentHasDrawing) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("먼저 '$_assetType'을(를) 그려주세요!")),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final png = await _capture();
      if (png == null) throw Exception('이미지 캡처 실패');

      final uri = Uri.parse('${ApiService.baseUrl}/rpg/describe');
      final req = http.MultipartRequest('POST', uri)
        ..fields['asset_type'] = _assetType
        ..files.add(http.MultipartFile.fromBytes(
          'sketch_file',
          png,
          filename: 'sketch.png',
          contentType: MediaType('image', 'png'),
        ));
      final streamed = await req.send();
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode != 200) throw Exception(resp.body);
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final desc = (data['description'] ?? '').toString();

      Uint8List? sprite;
      try {
        sprite = await _fetchSprite(desc, _assetType);
      } catch (_) {}

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('내 $_assetType 완성!',
              style: const TextStyle(color: kInk, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sprite != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(sprite, height: 160),
                ),
              const SizedBox(height: 12),
              Text('"$desc"',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF6E6690))),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('동화 시작'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      _goPlay(desc, sprite);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('분석 실패: $e')),
        );
      }
    }
  }

  Widget _circle(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: kPrimary,
        title: Text('${widget.storyTitle} — 내 요소 그리기',
            style: const TextStyle(
                fontSize: 16, color: kInk, fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: _loading ? null : () => _goPlay('', null),
            child: const Text('건너뛰기',
                style: TextStyle(color: kPrimary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned(
              top: -60,
              right: -60,
              child: _circle(200, kPrimaryLight.withOpacity(0.08))),
          Positioned(
              bottom: -90,
              left: -50,
              child: _circle(260, const Color(0xFFEC407A).withOpacity(0.05))),
          SafeArea(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('동화에 넣을 나만의 요소를 그려보세요 ✏️',
                      style: TextStyle(color: Color(0xFF8B82A8), fontSize: 14)),
                ),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: _types.map((t) {
                      final sel = t == _assetType;
                      final drawn =
                          (_pointsByType[t]?.any((e) => e != null)) ?? false;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          avatar: drawn && !sel
                              ? const Icon(Icons.brush,
                                  size: 15, color: kPrimary)
                              : null,
                          label: Text(t),
                          selected: sel,
                          onSelected: (_) => setState(() => _assetType = t),
                          selectedColor: kPrimary,
                          backgroundColor: kPill,
                          labelStyle: TextStyle(
                              color: sel ? Colors.white : kInk,
                              fontWeight: FontWeight.w600),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: RepaintBoundary(
                            key: _boundaryKey,
                            child: Container(
                              color: Colors.white,
                              child: Listener(
                                onPointerDown: (e) {
                                  _drawing = true;
                                  _add(e.localPosition);
                                },
                                onPointerMove: (e) {
                                  if (_drawing) _add(e.localPosition);
                                },
                                onPointerUp: (_) {
                                  _drawing = false;
                                  _end();
                                },
                                onPointerCancel: (_) {
                                  _drawing = false;
                                  _end();
                                },
                                child: CustomPaint(
                                  painter: _SketchPainter(_points),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // 현재 어떤 탭을 그리는 중인지 표시
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: kPill,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('$_assetType 그리는 중',
                                style: const TextStyle(
                                    color: kPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _clear,
                        icon: const Icon(Icons.refresh, color: kPrimary),
                        label: const Text('지우기',
                            style: TextStyle(
                                color: kPrimary, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: kPrimary),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _complete,
                          icon: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.auto_awesome),
                          label:
                              Text(_loading ? 'AI가 만드는 중...' : '완성! 동화 시작'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
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
}

class _SketchPainter extends CustomPainter {
  final List<Offset?> points;
  _SketchPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF3D2C8D)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (a != null && b != null) canvas.drawLine(a, b, p);
    }
  }

  @override
  bool shouldRepaint(_SketchPainter old) => true;
}
