import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../models/rpg_models.dart';
import '../services/rpg_api_service.dart';

const _kBg = Color(0xFFF8F4FF);
const _kPrimary = Color(0xFF7E57C2);
const _kPrimaryLight = Color(0xFF9575CD);
const _kInk = Color(0xFF3D2C8D);

class RpgEndingScreen extends StatelessWidget {
  final RpgEndingData ending;
  final List<String> itemHints;

  const RpgEndingScreen({
    super.key,
    required this.ending,
    this.itemHints = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = _endingTheme(ending.endingType);
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          Positioned(
            top: -70,
            right: -70,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kPrimaryLight.withOpacity(0.08)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 720;
                  if (wide) {
                    final comicSize =
                        min(c.maxHeight, min(c.maxWidth * 0.46, 560.0));
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                            width: comicSize,
                            height: comicSize,
                            child: _comicCard()),
                        const SizedBox(width: 24),
                        Expanded(
                          child: SizedBox(
                            height: c.maxHeight,
                            child: _infoColumn(context, theme),
                          ),
                        ),
                      ],
                    );
                  }
                  final comicSize = min(c.maxHeight * 0.4, c.maxWidth);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                          width: comicSize,
                          height: comicSize,
                          child: _comicCard()),
                      const SizedBox(height: 16),
                      Expanded(child: _infoColumn(context, theme)),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoColumn(BuildContext context, _EndingTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      children: [
        Text(
          ending.title,
          style: TextStyle(
              color: theme.color, fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _card(
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Text(
                  ending.narrative,
                  style: const TextStyle(
                      color: Color(0xFF4A4466), fontSize: 16, height: 1.7),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _card(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: _finalStats(ending.stats),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('처음으로',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _comicCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: _kPrimary.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _FinalComic(
        playthroughId: ending.playthroughId,
        itemHints: itemHints,
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: _kPrimary.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _finalStats(RpgStats s) {
    Widget item(String label, int value, Color color) => Column(
          children: [
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(value.toString(),
                style: const TextStyle(
                    color: _kInk, fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        item('용기', s.courage, const Color(0xFFE5689B)),
        item('지혜', s.wisdom, const Color(0xFF5B8DEF)),
        item('친절', s.kindness, const Color(0xFF4CAF82)),
        item('Lv', s.level, const Color(0xFFF5A623)),
      ],
    );
  }

  _EndingTheme _endingTheme(String type) {
    switch (type) {
      case 'kind':
        return const _EndingTheme(Color(0xFF4CAF82));
      case 'brave':
        return const _EndingTheme(Color(0xFFE5689B));
      case 'wise':
        return const _EndingTheme(Color(0xFF5B8DEF));
      case 'balanced':
        return const _EndingTheme(Color(0xFFF5A623));
      default:
        return const _EndingTheme(_kPrimary);
    }
  }
}

class _EndingTheme {
  final Color color;
  const _EndingTheme(this.color);
}

class _FinalComic extends StatefulWidget {
  final int playthroughId;
  final List<String> itemHints;
  const _FinalComic({required this.playthroughId, this.itemHints = const []});

  @override
  State<_FinalComic> createState() => _FinalComicState();
}

class _FinalComicState extends State<_FinalComic> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _failed = false);
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final b = await RpgApiService.fetchFinalComic(
          playthroughId: widget.playthroughId,
          itemHints: widget.itemHints,
        );
        if (mounted) setState(() => _bytes = b);
        return;
      } catch (_) {
        if (attempt < 2) {
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
        }
      }
    }
    if (mounted) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
      );
    }
    return GestureDetector(
      onTap: _failed ? _load : null,
      child: Container(
        color: const Color(0xFFF3EFFA),
        alignment: Alignment.center,
        child: _failed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.refresh, color: _kPrimaryLight, size: 36),
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('그림을 못 만들었어요 — 탭하면 다시 시도',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: _kPrimaryLight, fontSize: 12)),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: _kPrimary),
                  ),
                  SizedBox(height: 14),
                  Text('동화 4컷을 그리는 중...',
                      style: TextStyle(color: _kPrimary, fontSize: 13)),
                ],
              ),
      ),
    );
  }
}
