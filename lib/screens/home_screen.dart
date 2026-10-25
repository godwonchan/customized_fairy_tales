import 'package:flutter/material.dart';
import 'fairy_tale_list_screen.dart';
import 'my_stories_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'creation/custom_story_create_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const _tabs = [
    {'icon': Icons.home_rounded, 'label': '홈'},
    {'icon': Icons.menu_book_rounded, 'label': '동화 목록'},
    {'icon': Icons.auto_stories_rounded, 'label': '내 이야기'},
    {'icon': Icons.settings_rounded, 'label': '설정'},
  ];

  void _selectTab(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onTabChange: _selectTab),
      const FairyTaleListScreen(),
      const MyStoriesScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Expanded(
            child: pages[_selectedIndex],
          ),
          _buildDock(),
        ],
      ),
    );
  }

  Widget _buildDock() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: AppDecorations.card(radius: 26),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_tabs.length, (index) {
                final tab = _tabs[index];
                final isSelected = _selectedIndex == index;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _selectTab(index),
                    behavior: HitTestBehavior.opaque,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 44,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.primaryLight : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              tab['icon'] as IconData,
                              size: 24,
                              color: isSelected ? AppColors.textPrimary : AppColors.textHint,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tab['label'] as String,
                            style: AppTextStyles.labelSmall(
                              color: isSelected ? AppColors.textPrimary : AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onTabChange});

  final ValueChanged<int>? onTabChange;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  final TextEditingController _searchController = TextEditingController();

  String _nickname = '동화친구';

  @override
  void initState() {
    super.initState();
    _loadNickname();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();
  }

  Future<void> _loadNickname() async {
    final info = await ApiService.getUserInfo();
    if (!mounted) return;
    setState(() {
      _nickname = info['nickname'] ?? '동화친구';
    });
  }

  Future<void> _openProfile() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
    if (result == true) {
      _loadNickname();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String get _todayLabel {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final now = DateTime.now();
    return '${now.month}월 ${now.day}일 ${weekdays[now.weekday - 1]}요일';
  }

  void _goToTab(int index) {
    if (widget.onTabChange != null) {
      widget.onTabChange!(index);
      return;
    }
    final page = index == 1 ? const FairyTaleListScreen() : const MyStoriesScreen();
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _navigateToStoryCreation() {
    Navigator.push(context, PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, animation, __) => const CustomStoryCreateScreen(),
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: FadeTransition(opacity: animation, child: child),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 0, 8),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: _buildTopBar(),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final heroWidth = (constraints.maxWidth * 0.36).clamp(330.0, 480.0);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: heroWidth, child: _buildHero()),
                          Expanded(child: _buildCardRow()),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        Text('동화랑', style: AppTextStyles.headingLarge()),
        const SizedBox(width: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.secondaryLight,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.eco_rounded, size: 16, color: AppColors.secondaryDark),
              const SizedBox(width: 6),
              Text('$_nickname님, 안녕하세요', style: AppTextStyles.labelMedium(color: const Color(0xFF3E6F2E))),
            ],
          ),
        ),
        const Spacer(),
        Text(_todayLabel, style: AppTextStyles.labelMedium()),
        const SizedBox(width: 14),
        SizedBox(
          width: 220,
          height: 40,
          child: TextField(
            controller: _searchController,
            enableSuggestions: false,
            autocorrect: false,
            style: AppTextStyles.bodyMedium(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: '동화 찾기',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: AppColors.border, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: AppColors.border, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: AppColors.primary, width: 2),
              ),
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) _goToTab(1);
            },
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _openProfile,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.face_rounded, size: 24, color: AppColors.primaryText),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHero() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final w = constraints.maxWidth;
        final crayongHeight = (h * 0.72).clamp(200.0, 400.0);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -60,
              top: h * 0.04,
              child: Container(
                width: w + 30,
                height: h * 0.94,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(160),
                    topRight: Radius.circular(200),
                    bottomLeft: Radius.circular(150),
                    bottomRight: Radius.circular(180),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 4,
              top: h * 0.02,
              child: _SpeechBubble(text: '$_nickname님,\n오늘은 어떤 이야기를\n만들어 볼까?'),
            ),
            Positioned(
              right: 0,
              top: h * 0.2,
              child: _FloatingCrayong(image: CrayongImages.main, height: crayongHeight),
            ),
            Positioned(
              left: 20,
              bottom: h * 0.06,
              child: _StartButton(onTap: _navigateToStoryCreation),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCardRow() {
    final cards = <_TallCardData>[
      _TallCardData(
        label: '오늘의 추천',
        title: '빨간\n망토 소녀',
        background: AppColors.surface,
        shadow: AppColors.border,
        labelColor: AppColors.accentDark,
        bordered: true,
        picture: 'assets/girl_wolf.png',
        onTap: () => _goToTab(1),
      ),
      _TallCardData(
        label: '원래 동화를',
        title: '동화\n바꾸기',
        background: AppColors.primaryLight,
        shadow: const Color(0xFFF2D27A),
        labelColor: AppColors.primaryText,
        crayong: CrayongImages.proud,
        onTap: () => _goToTab(1),
      ),
      _TallCardData(
        label: '읽던 동화',
        title: '이어서\n읽기',
        background: AppColors.secondaryLight,
        shadow: const Color(0xFFBFDDA5),
        labelColor: AppColors.secondaryDark,
        crayong: CrayongImages.lying,
        onTap: () => _goToTab(1),
      ),
      _TallCardData(
        label: '좋아하는 동화',
        title: '즐겨\n찾기',
        background: AppColors.accentLight,
        shadow: const Color(0xFFF1D6CA),
        labelColor: AppColors.accentDark,
        crayong: CrayongImages.celebrate,
        onTap: () => _goToTab(2),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 16.0;
        const padH = 24.0;
        const minWidth = 150.0;
        final cardHeight = (constraints.maxHeight - 40).clamp(260.0, 460.0);
        final fitWidth = (constraints.maxWidth - padH * 2 - gap * (cards.length - 1)) / cards.length;
        final cardWidth = fitWidth.clamp(minWidth, cardHeight * 0.62);

        if (fitWidth < minWidth) {
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(padH, 16, padH, 24),
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: gap),
            itemBuilder: (context, i) => Center(
              child: _TallCard(data: cards[i], width: minWidth, height: cardHeight),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(padH, 16, padH, 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final card in cards)
                _TallCard(data: card, width: cardWidth, height: cardHeight),
            ],
          ),
        );
      },
    );
  }
}

class _TallCardData {
  final String label;
  final String title;
  final Color background;
  final Color shadow;
  final Color labelColor;
  final bool bordered;
  final String? picture;
  final String? crayong;
  final VoidCallback onTap;

  const _TallCardData({
    required this.label,
    required this.title,
    required this.background,
    required this.shadow,
    required this.labelColor,
    required this.onTap,
    this.bordered = false,
    this.picture,
    this.crayong,
  });
}

class _TallCard extends StatefulWidget {
  final _TallCardData data;
  final double width;
  final double height;

  const _TallCard({required this.data, required this.width, required this.height});

  @override
  State<_TallCard> createState() => _TallCardState();
}

class _TallCardState extends State<_TallCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final radius = widget.width / 2;
    const depth = 6.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: d.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          transform: Matrix4.translationValues(0, _pressed ? depth : 0, 0),
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: d.background,
            borderRadius: BorderRadius.circular(radius),
            border: d.bordered ? Border.all(color: AppColors.border, width: 2) : null,
            boxShadow: [
              BoxShadow(
                color: d.shadow,
                blurRadius: 0,
                offset: Offset(0, _pressed ? 0 : depth),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(14, widget.width * 0.16, 14, widget.width * 0.2),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: d.picture != null
                        ? AspectRatio(
                            aspectRatio: 1,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(radius * 0.6),
                              child: Image.asset(d.picture!, fit: BoxFit.cover),
                            ),
                          )
                        : Image.asset(d.crayong!, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 10),
                Text(d.label, style: AppTextStyles.labelSmall(color: d.labelColor)),
                const SizedBox(height: 2),
                Text(
                  d.title,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headingLarge().copyWith(height: 1.15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  final String text;

  const _SpeechBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 250),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 2),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomRight: Radius.circular(18),
          bottomLeft: Radius.circular(4),
        ),
      ),
      child: Text(text, style: AppTextStyles.headingSmall().copyWith(fontSize: 20, height: 1.3)),
    );
  }
}

class _StartButton extends StatefulWidget {
  final VoidCallback onTap;

  const _StartButton({required this.onTap});

  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 140.0;
    const depth = 6.0;
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        final scale = 1 + 0.04 * Curves.easeInOut.transform(_controller.value);
        return Transform.scale(scale: _pressed ? 0.97 : scale, child: child);
      },
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                width: size,
                height: size,
                transform: Matrix4.translationValues(0, _pressed ? depth : 0, 0),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryDark,
                      blurRadius: 0,
                      offset: Offset(0, _pressed ? 0 : depth),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.brush_rounded, size: 34, color: AppColors.onPrimary),
                    Text('시작', style: AppTextStyles.display(color: AppColors.onPrimary).copyWith(height: 1.1)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text('새 동화 만들기', style: AppTextStyles.labelLarge()),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingCrayong extends StatefulWidget {
  final String image;
  final double height;

  const _FloatingCrayong({required this.image, required this.height});

  @override
  State<_FloatingCrayong> createState() => _FloatingCrayongState();
}

class _FloatingCrayongState extends State<_FloatingCrayong>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Transform.translate(
          offset: Offset(0, -10 * t),
          child: Transform.rotate(angle: (t - 0.5) * 0.06, child: child),
        );
      },
      child: Image.asset(widget.image, height: widget.height, fit: BoxFit.contain),
    );
  }
}