import 'package:flutter/material.dart';
import 'drawing_guide_screen.dart';

class StoryCreationScreen extends StatefulWidget {
  const StoryCreationScreen({super.key});

  @override
  State<StoryCreationScreen> createState() => _StoryCreationScreenState();
}

class _StoryCreationScreenState extends State<StoryCreationScreen>
    with TickerProviderStateMixin {
  final TextEditingController _characterController = TextEditingController();
  final TextEditingController _backgroundController = TextEditingController();

  late AnimationController _bounceController;
  late AnimationController _wiggleController;
  late AnimationController _starController;
  late Animation<double> _bounceAnim;
  late Animation<double> _wiggleAnim;
  late Animation<double> _starAnim;

  int? _selectedCharIdx;
  int? _selectedBgIdx;

  final List<Map<String, dynamic>> _characterSuggestions = [
    {'label': '용감한 토끼', 'icon': '🐰', 'bg': const Color(0xFFEDE7F6), 'border': const Color(0xFF7E57C2)},
    {'label': '마법사 고양이', 'icon': '🐱', 'bg': const Color(0xFFE8EAF6), 'border': const Color(0xFF5C6BC0)},
    {'label': '작은 용', 'icon': '🐲', 'bg': const Color(0xFFE8F5E9), 'border': const Color(0xFF66BB6A)},
    {'label': '씩씩한 공주', 'icon': '👸', 'bg': const Color(0xFFFFF8E1), 'border': const Color(0xFFFFCA28)},
    {'label': '우주 소년', 'icon': '🚀', 'bg': const Color(0xFFE3F2FD), 'border': const Color(0xFF42A5F5)},
    {'label': '숲의 요정', 'icon': '🧚', 'bg': const Color(0xFFE8F5E9), 'border': const Color(0xFF4CAF50)},
  ];

  final List<Map<String, dynamic>> _backgroundSuggestions = [
    {'label': '마법의 숲', 'icon': '🌳', 'bg': const Color(0xFFE8F5E9), 'border': const Color(0xFF66BB6A)},
    {'label': '별빛 하늘', 'icon': '🌟', 'bg': const Color(0xFFEDE7F6), 'border': const Color(0xFF9575CD)},
    {'label': '바다 속', 'icon': '🐠', 'bg': const Color(0xFFE3F2FD), 'border': const Color(0xFF42A5F5)},
    {'label': '구름 왕국', 'icon': '☁️', 'bg': const Color(0xFFE8EAF6), 'border': const Color(0xFF5C6BC0)},
    {'label': '동화 성', 'icon': '🏰', 'bg': const Color(0xFFFFF8E1), 'border': const Color(0xFFFFCA28)},
    {'label': '꽃밭', 'icon': '🌸', 'bg': const Color(0xFFFCE4EC), 'border': const Color(0xFFF48FB1)},
  ];

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
    _wiggleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(reverse: true);
    _starController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

    _bounceAnim = Tween<double>(begin: 0, end: -10)
        .animate(CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut));
    _wiggleAnim = Tween<double>(begin: -5, end: 5)
        .animate(CurvedAnimation(parent: _wiggleController, curve: Curves.easeInOut));
    _starAnim = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _starController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _wiggleController.dispose();
    _starController.dispose();
    _characterController.dispose();
    _backgroundController.dispose();
    super.dispose();
  }

  bool get _canProceed =>
      _characterController.text.trim().isNotEmpty &&
      _backgroundController.text.trim().isNotEmpty;

  void _proceed() {
    if (!_canProceed) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, animation, __) => DrawingGuideScreen(
          character: _characterController.text.trim(),
          background: _backgroundController.text.trim(),
        ),
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: FadeTransition(opacity: animation, child: child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 배경
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A0050), Color(0xFF2D1B69), Color(0xFF1A237E), Color(0xFF283593)],
                stops: [0.0, 0.35, 0.65, 1.0],
              ),
            ),
          ),
          // 장식 버블
          Positioned(top: -60, right: -40,
            child: Container(width: 220, height: 220,
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF7C4DFF).withOpacity(0.12)))),
          Positioned(top: 200, left: -50,
            child: Container(width: 160, height: 160,
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF3949AB).withOpacity(0.15)))),
          Positioned(bottom: 100, right: -20,
            child: Container(width: 140, height: 140,
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF1565C0).withOpacity(0.12)))),
          // 별 장식
          _floatingDecor('⭐', top: 70, left: 40, size: 22),
          _floatingDecor('✨', top: 150, right: 60, size: 18),
          _floatingDecor('🌟', top: 240, left: 110, size: 20),
          _floatingDecor('💫', top: 100, right: 170, size: 16),
          // 메인
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    child: Column(
                      children: [
                        _buildHero(),
                        const SizedBox(height: 20),
                        _buildProgressDots(),
                        const SizedBox(height: 20),
                        _buildSection(
                          icon: '🦸',
                          color: const Color(0xFF9575CD),
                          title: '주인공을 골라봐요!',
                          subtitle: '이야기를 이끌어갈 캐릭터를 선택하세요',
                          controller: _characterController,
                          hint: '직접 입력하거나 아래에서 골라봐요',
                          suggestions: _characterSuggestions,
                          selectedIdx: _selectedCharIdx,
                          onTap: (i) => setState(() {
                            _selectedCharIdx = i;
                            _characterController.text = _characterSuggestions[i]['label'];
                          }),
                        ),
                        const SizedBox(height: 16),
                        _buildSection(
                          icon: '🗺️',
                          color: const Color(0xFF64B5F6),
                          title: '배경을 골라봐요!',
                          subtitle: '어디서 이야기가 펼쳐질지 선택하세요',
                          controller: _backgroundController,
                          hint: '직접 입력하거나 아래에서 골라봐요',
                          suggestions: _backgroundSuggestions,
                          selectedIdx: _selectedBgIdx,
                          onTap: (i) => setState(() {
                            _selectedBgIdx = i;
                            _backgroundController.text = _backgroundSuggestions[i]['label'];
                          }),
                        ),
                        const SizedBox(height: 28),
                        _buildStartButton(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _floatingDecor(String emoji, {double? top, double? left, double? right, required double size}) {
    return Positioned(
      top: top, left: left, right: right,
      child: AnimatedBuilder(
        animation: _starAnim,
        builder: (_, __) => Opacity(
          opacity: _starAnim.value * 0.6,
          child: Transform.translate(
            offset: Offset(_wiggleAnim.value * 0.4, _bounceAnim.value * 0.3),
            child: Text(emoji, style: TextStyle(fontSize: size)),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.25)),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.white),
            ),
          ),
          const SizedBox(width: 14),
          const Text('나만의 동화 만들기',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFFD54F), Color(0xFFFFB300)]),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [BoxShadow(color: const Color(0xFFFFB300).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_fix_high_rounded, size: 16, color: Color(0xFF4A148C)),
                SizedBox(width: 6),
                Text('AI 창작', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF4A148C))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return AnimatedBuilder(
      animation: _bounceAnim,
      builder: (_, child) => Transform.translate(offset: Offset(0, _bounceAnim.value * 0.5), child: child),
      child: Container(
        margin: const EdgeInsets.only(top: 18),
        padding: const EdgeInsets.fromLTRB(24, 24, 20, 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withOpacity(0.18), Colors.white.withOpacity(0.08)],
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
          boxShadow: [BoxShadow(color: const Color(0xFF7C4DFF).withOpacity(0.3), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD54F).withOpacity(0.25),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFFD54F).withOpacity(0.6)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('⭐', style: TextStyle(fontSize: 13)),
                        SizedBox(width: 5),
                        Text('세상에 단 하나뿐인 이야기',
                            style: TextStyle(fontSize: 13, color: Color(0xFFFFD54F), fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('어떤 동화를\n만들까요?',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white, height: 1.25)),
                  const SizedBox(height: 10),
                  Text('캐릭터와 배경을 고르면\nAI가 동화를 만들어줘요!',
                      style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.85), height: 1.6)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedBuilder(
              animation: _bounceAnim,
              builder: (_, __) => Transform.translate(
                offset: Offset(_wiggleAnim.value * 0.2, _bounceAnim.value * 0.4),
                child: const Text('🧙', style: TextStyle(fontSize: 72)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressDots() {
    final steps = ['캐릭터', '배경', '그리기', '완성'];
    final done = [
      _characterController.text.isNotEmpty,
      _backgroundController.text.isNotEmpty,
      false, false,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            return Container(width: 28, height: 3,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: done[i ~/ 2] ? const Color(0xFFFFD54F) : Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ));
          }
          final idx = i ~/ 2;
          final isActive = idx == 0 || (idx == 1 && _characterController.text.isNotEmpty);
          return Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isActive || done[idx]
                      ? const LinearGradient(colors: [Color(0xFFFFD54F), Color(0xFFFFB300)])
                      : null,
                  color: isActive || done[idx] ? null : Colors.white.withOpacity(0.15),
                  boxShadow: isActive || done[idx]
                      ? [BoxShadow(color: const Color(0xFFFFB300).withOpacity(0.5), blurRadius: 10)]
                      : null,
                ),
                child: Center(
                  child: done[idx]
                      ? const Icon(Icons.check_rounded, color: Color(0xFF4A148C), size: 20)
                      : Text('${idx + 1}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                            color: isActive ? const Color(0xFF4A148C) : Colors.white.withOpacity(0.5))),
                ),
              ),
              const SizedBox(height: 5),
              Text(steps[idx], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: isActive || done[idx] ? const Color(0xFFFFD54F) : Colors.white.withOpacity(0.4))),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildSection({
    required String icon,
    required Color color,
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required String hint,
    required List<Map<String, dynamic>> suggestions,
    required int? selectedIdx,
    required Function(int) onTap,
  }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (_, __, ___) {
        final hasValue = controller.text.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: hasValue ? Colors.white.withOpacity(0.16) : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: hasValue ? color.withOpacity(0.7) : Colors.white.withOpacity(0.2),
              width: hasValue ? 2 : 1,
            ),
            boxShadow: hasValue
                ? [BoxShadow(color: color.withOpacity(0.2), blurRadius: 16, offset: const Offset(0, 6))]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더
                Row(
                  children: [
                    Container(
                      width: 54, height: 54,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
                      ),
                      child: Center(child: Text(icon, style: const TextStyle(fontSize: 28))),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
                          const SizedBox(height: 3),
                          Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.6))),
                        ],
                      ),
                    ),
                    if (hasValue)
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFFFD54F), Color(0xFFFFB300)]),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: const Color(0xFFFFB300).withOpacity(0.5), blurRadius: 8)],
                        ),
                        child: const Icon(Icons.check_rounded, color: Color(0xFF4A148C), size: 20),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                // 칩 버튼들
                Wrap(
                  spacing: 10, runSpacing: 10,
                  children: List.generate(suggestions.length, (i) {
                    final s = suggestions[i];
                    final isSel = selectedIdx == i;
                    final chipColor = s['border'] as Color;
                    return GestureDetector(
                      onTap: () => onTap(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSel ? chipColor.withOpacity(0.9) : Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(
                            color: isSel ? Colors.transparent : chipColor.withOpacity(0.6),
                            width: 1.5,
                          ),
                          boxShadow: isSel
                              ? [BoxShadow(color: chipColor.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(s['icon'], style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 8),
                            Text(s['label'],
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: isSel ? Colors.white : Colors.white.withOpacity(0.85))),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 14),
                // 직접 입력창
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withOpacity(0.4), width: 1.5),
                  ),
                  child: TextField(
                    controller: controller,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.4)),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                      prefixIcon: Icon(Icons.edit_rounded, size: 20, color: color.withOpacity(0.7)),
                      suffixIcon: controller.text.isNotEmpty
                          ? GestureDetector(
                              onTap: () => setState(() { controller.clear(); }),
                              child: Icon(Icons.cancel_rounded, color: Colors.white.withOpacity(0.4), size: 20),
                            )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStartButton() {
    return AnimatedBuilder(
      animation: _bounceAnim,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, _canProceed ? _bounceAnim.value * 0.25 : 0),
        child: child,
      ),
      child: GestureDetector(
        onTap: _proceed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          height: 72,
          decoration: BoxDecoration(
            gradient: _canProceed
                ? const LinearGradient(
                    colors: [Color(0xFFFFE57F), Color(0xFFFFD740), Color(0xFFFFAB00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : LinearGradient(colors: [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.05)]),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _canProceed ? Colors.transparent : Colors.white.withOpacity(0.2),
            ),
            boxShadow: _canProceed
                ? [
                    BoxShadow(color: const Color(0xFFFFD740).withOpacity(0.5), blurRadius: 24, offset: const Offset(0, 10)),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_canProceed) const Text('🎨', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 8),
              Text(
                _canProceed ? '그림 그리러 가기!' : '캐릭터와 배경을 골라봐요 😊',
                style: TextStyle(
                    fontSize: _canProceed ? 20 : 16,
                    fontWeight: FontWeight.w900,
                    color: _canProceed ? const Color(0xFF4A148C) : Colors.white.withOpacity(0.4)),
              ),
              if (_canProceed) ...[
                const SizedBox(width: 8),
                const Text('🚀', style: TextStyle(fontSize: 28)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}