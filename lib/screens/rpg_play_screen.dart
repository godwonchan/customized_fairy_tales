import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/rpg_models.dart';
import '../providers/rpg_game_provider.dart';
import '../providers/inventory_provider.dart';
import '../widgets/inventory_bar.dart';
import 'rpg_npc_chat_screen.dart';
import 'rpg_ending_screen.dart';

// ===== 공통 라벤더 팔레트 (앱 전체와 통일) =====
const kBg = Color(0xFFF8F4FF);
const kPrimary = Color(0xFF7E57C2);
const kPrimaryLight = Color(0xFF9575CD);
const kPill = Color(0xFFEDE7F6);
const kInk = Color(0xFF3D2C8D);

class RpgPlayScreen extends StatelessWidget {
  final int storyId;
  final String storyTitle;
  final String playerName;
  final String assetHint;
  final int maxTurns;
  final Uint8List? characterSprite;

  const RpgPlayScreen({
    super.key,
    required this.storyId,
    required this.storyTitle,
    this.playerName = '주인공',
    this.assetHint = '',
    this.maxTurns = 6,
    this.characterSprite,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => RpgGameProvider()
            ..startGame(
              storyId: storyId,
              playerName: playerName,
              assetHint: assetHint,
              maxTurns: maxTurns,
            ),
        ),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
      ],
      child: _RpgPlayView(
        storyTitle: storyTitle,
        characterSprite: characterSprite,
      ),
    );
  }
}

class _RpgPlayView extends StatefulWidget {
  final String storyTitle;
  final Uint8List? characterSprite;
  const _RpgPlayView({required this.storyTitle, this.characterSprite});

  @override
  State<_RpgPlayView> createState() => _RpgPlayViewState();
}

class _RpgPlayViewState extends State<_RpgPlayView> {
  final _freeCtrl = TextEditingController();
  bool _navigatedToEnding = false;

  @override
  void dispose() {
    _freeCtrl.dispose();
    super.dispose();
  }

  void _maybeGoEnding(RpgGameProvider game) {
    if (game.hasEnding && !_navigatedToEnding) {
      _navigatedToEnding = true;
      final itemHints = context
          .read<InventoryProvider>()
          .items
          .map((e) => '${e.name} (${e.typeLabel})')
          .toList();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RpgEndingScreen(
              ending: game.ending!,
              itemHints: itemHints,
            ),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RpgGameProvider>(
      builder: (context, game, _) {
        _maybeGoEnding(game);
        return Scaffold(
          backgroundColor: kBg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            title: Text(widget.storyTitle,
                style: const TextStyle(
                    fontSize: 18, color: kInk, fontWeight: FontWeight.w700)),
            iconTheme: const IconThemeData(color: kPrimary),
            actions: [
              IconButton(
                tooltip: '등장인물과 대화',
                icon: const Icon(Icons.chat_bubble_outline),
                onPressed: game.playthroughId == null
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RpgNpcChatScreen(
                              playthroughId: game.playthroughId!,
                            ),
                          ),
                        ),
              ),
            ],
          ),
          body: Stack(
            children: [
              Positioned(
                top: -60,
                right: -60,
                child: _circle(200, kPrimaryLight.withOpacity(0.08)),
              ),
              Positioned(
                bottom: -90,
                left: -50,
                child: _circle(260, const Color(0xFFEC407A).withOpacity(0.05)),
              ),
              SafeArea(
                child: Column(
                  children: [
                    _statsBar(game.stats, game.lastChanges),
                    Expanded(child: _narrative(game)),
                    _bottomArea(game),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _circle(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );

  BoxDecoration get _cardDeco => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: kPrimary.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      );

  Widget _statsBar(RpgStats s, Map<String, int> changes) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: _cardDeco,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          if (widget.characterSprite != null)
            Container(
              width: 42,
              height: 42,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kPill,
                border: Border.all(color: kPrimaryLight, width: 2),
              ),
              child: Image.memory(widget.characterSprite!, fit: BoxFit.cover),
            ),
          _statBadge('Lv', s.level, const Color(0xFFF5A623), null),
          _statBadge('용기', s.courage, const Color(0xFFE5689B), changes['courage']),
          _statBadge('지혜', s.wisdom, const Color(0xFF5B8DEF), changes['wisdom']),
          _statBadge('친절', s.kindness, const Color(0xFF4CAF82), changes['kindness']),
        ],
      ),
    );
  }

  Widget _statBadge(String label, int value, Color color, int? delta) {
    final bumped = delta != null && delta > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              key: ValueKey('$label$value'),
              tween: Tween(begin: bumped ? 1.6 : 1.0, end: 1.0),
              duration: const Duration(milliseconds: 500),
              curve: Curves.elasticOut,
              builder: (_, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Text(
                '$value',
                style: const TextStyle(
                  color: kInk,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (bumped)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Text('+$delta',
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _narrative(RpgGameProvider game) {
    if (game.isLoading && game.narrative.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: kPrimary),
            SizedBox(height: 16),
            Text('이야기를 짓는 중...',
                style: TextStyle(color: kPrimary, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (game.error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFDECEF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(game.error!,
                  style: const TextStyle(
                      color: Color(0xFFD5567B), fontSize: 13)),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: _cardDeco,
            child: _TypingText(
              key: ValueKey(game.narrative),
              text: game.narrative,
              style: const TextStyle(
                color: Color(0xFF4A4466),
                fontSize: 17,
                height: 1.75,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomArea(RpgGameProvider game) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const InventoryBar(),
          const SizedBox(height: 8),
          if (game.isLoading && game.narrative.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(
                  color: kPrimary, backgroundColor: kPill, minHeight: 3),
            ),
          TweenAnimationBuilder<double>(
            key: ValueKey('choices_${game.narrative.hashCode}'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOut,
            builder: (_, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 16),
                child: child,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children:
                  game.choices.map((c) => _choiceButton(game, c)).toList(),
            ),
          ),
          const SizedBox(height: 6),
          _freeInput(game),
        ],
      ),
    );
  }

  Widget _choiceButton(RpgGameProvider game, RpgChoice c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: game.isLoading ? null : () => game.choose(c.id),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kPrimaryLight.withOpacity(0.45)),
              boxShadow: [
                BoxShadow(
                    color: kPrimary.withOpacity(0.07),
                    blurRadius: 10,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                      color: kPill, shape: BoxShape.circle),
                  child: const Icon(Icons.chevron_right,
                      size: 18, color: kPrimary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    c.text,
                    style: const TextStyle(
                        color: kInk,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _freeInput(RpgGameProvider game) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _freeCtrl,
            enabled: !game.isLoading,
            style: const TextStyle(color: kInk),
            decoration: InputDecoration(
              hintText: '직접 행동을 입력해도 돼요',
              hintStyle: const TextStyle(color: Color(0xFFB6ABD6)),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: kPrimaryLight.withOpacity(0.4)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: kPrimaryLight.withOpacity(0.4)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kPrimary, width: 1.5),
              ),
            ),
            onSubmitted: (_) => _submitFree(game),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: const BoxDecoration(color: kPrimary, shape: BoxShape.circle),
          child: IconButton(
            icon: const Icon(Icons.send_rounded, color: Colors.white),
            onPressed: game.isLoading ? null : () => _submitFree(game),
          ),
        ),
      ],
    );
  }

  void _submitFree(RpgGameProvider game) {
    final text = _freeCtrl.text;
    if (text.trim().isEmpty) return;
    _freeCtrl.clear();
    game.submitFreeText(text);
  }
}

class _TypingText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _TypingText({super.key, required this.text, required this.style});

  @override
  State<_TypingText> createState() => _TypingTextState();
}

class _TypingTextState extends State<_TypingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    final ms = (widget.text.length * 22).clamp(400, 6000);
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: ms))
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _c.value = 1.0,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final n = (widget.text.length * _c.value)
              .round()
              .clamp(0, widget.text.length);
          return Text(widget.text.substring(0, n), style: widget.style);
        },
      ),
    );
  }
}
