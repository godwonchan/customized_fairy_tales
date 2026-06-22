import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/rpg_inventory_item.dart';

const _kPrimary = Color(0xFF7E57C2);
const _kPrimaryLight = Color(0xFF9575CD);
const _kPill = Color(0xFFEDE7F6);
const _kInk = Color(0xFF3D2C8D);

class ItemDrawDialog extends StatefulWidget {
  const ItemDrawDialog({super.key});

  @override
  State<ItemDrawDialog> createState() => _ItemDrawDialogState();
}

class _ItemDrawDialogState extends State<ItemDrawDialog> {
  final _canvasKey = GlobalKey();
  final _nameCtrl = TextEditingController();
  final List<_Stroke> _strokes = [];
  _Stroke? _current;

  Color _color = const Color(0xFF3D2C8D);
  ItemType _type = ItemType.item;
  bool _saving = false;

  static const _palette = <Color>[
    Color(0xFF3D2C8D),
    Color(0xFFE5689B),
    Color(0xFF5B8DEF),
    Color(0xFFF5A623),
    Color(0xFF4CAF82),
    Color(0xFFB07D4F),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _start(Offset p) {
    setState(() {
      _current = _Stroke(_color, [p]);
      _strokes.add(_current!);
    });
  }

  void _move(Offset p) {
    if (_current == null) return;
    setState(() => _current!.points.add(p));
  }

  void _end() => _current = null;

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
  }

  void _clearAll() => setState(() => _strokes.clear());

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('이름을 입력해 주세요');
      return;
    }
    if (_strokes.isEmpty) {
      _snack('그림을 그려 주세요');
      return;
    }
    setState(() => _saving = true);
    try {
      final boundary = _canvasKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data!.buffer.asUint8List();
      if (!mounted) return;
      Navigator.pop(
        context,
        InventoryItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: name,
          imageBytes: bytes,
          type: _type,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('저장 실패: $e');
      }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '아이템 그리기',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _kInk, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Listener(
                    onPointerDown: (e) => _start(e.localPosition),
                    onPointerMove: (e) => _move(e.localPosition),
                    onPointerUp: (e) => _end(),
                    child: RepaintBoundary(
                      key: _canvasKey,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                              color: _kPrimaryLight.withOpacity(0.35)),
                        ),
                        child: CustomPaint(
                          painter: _DrawPainter(_strokes),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final c in _palette) _colorDot(c),
                  const Spacer(),
                  IconButton(
                    tooltip: '되돌리기',
                    icon: const Icon(Icons.undo, color: _kPrimary),
                    onPressed: _undo,
                  ),
                  IconButton(
                    tooltip: '전체 지우기',
                    icon: const Icon(Icons.delete_outline, color: _kPrimary),
                    onPressed: _clearAll,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  _typeChip(ItemType.weapon, '⚔️ 무기'),
                  _typeChip(ItemType.item, '🎒 아이템'),
                  _typeChip(ItemType.animal, '🐾 동물'),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: _kInk),
                decoration: InputDecoration(
                  hintText: '이름 (예: 빛나는 검)',
                  hintStyle: const TextStyle(color: Color(0xFFB6ABD6)),
                  filled: true,
                  fillColor: _kPill,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('취소',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('가방에 넣기',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorDot(Color c) {
    final sel = _color == c;
    return GestureDetector(
      onTap: () => setState(() => _color = c),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(
            color: sel ? _kPrimary : Colors.transparent,
            width: sel ? 3 : 0,
          ),
        ),
      ),
    );
  }

  Widget _typeChip(ItemType t, String label) {
    final sel = _type == t;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => setState(() => _type = t),
      labelStyle: TextStyle(
          color: sel ? Colors.white : _kInk, fontWeight: FontWeight.w600),
      backgroundColor: _kPill,
      selectedColor: _kPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}

class _Stroke {
  final Color color;
  final List<Offset> points;
  _Stroke(this.color, this.points);
}

class _DrawPainter extends CustomPainter {
  final List<_Stroke> strokes;
  _DrawPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (s.points.length == 1) {
        canvas.drawPoints(ui.PointMode.points, s.points, paint);
      } else {
        for (var i = 0; i < s.points.length - 1; i++) {
          canvas.drawLine(s.points[i], s.points[i + 1], paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_DrawPainter old) => true;
}
