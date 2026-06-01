import 'package:flutter/material.dart';
import 'fairy_tale_list_screen.dart';
import 'my_stories_screen.dart';
import 'settings_screen.dart';
import 'package:flutter/services.dart' show rootBundle;
// ═══════════════════════════════════════════════════════════════
//  앱 전체 감싸는 메인 구조 (사이드바 + 콘텐츠)
// ═══════════════════════════════════════════════════════════════

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const HomeScreen(),
    const FairyTaleListScreen(),
    const MyStoriesScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      body: Row(
        children: [
          _buildSidebar(isTablet),
          Expanded(child: _pages[_selectedIndex]),
        ],
      ),
    );
  }

  Widget _buildSidebar(bool isTablet) {
    final items = [
      {'icon': Icons.home_rounded, 'label': '홈'},
      {'icon': Icons.menu_book_rounded, 'label': '동화 목록'},
      {'icon': Icons.auto_stories_rounded, 'label': '내 이야기'},
      {'icon': Icons.settings_rounded, 'label': '설정'},
    ];

    return Container(
      width: isTablet ? 80 : 64,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF9575CD), Color(0xFF7E57C2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.auto_stories,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(height: 32),
            ...items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isSelected = _selectedIndex == index;

              return GestureDetector(
                onTap: () => setState(() => _selectedIndex = index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFEDE7F6)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        item['icon'] as IconData,
                        size: 24,
                        color: isSelected
                            ? const Color(0xFF7E57C2)
                            : Colors.grey[400],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item['label'] as String,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected
                              ? const Color(0xFF7E57C2)
                              : Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  홈 화면
// ═══════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFEDE7F6),
                Color(0xFFF8F4FF),
                Color(0xFFE8EAF6),
              ],
            ),
          ),
        ),
        Positioned(
          top: -60,
          right: -60,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF9575CD).withOpacity(0.08),
            ),
          ),
        ),
        Positioned(
          bottom: -80,
          left: -40,
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFEC407A).withOpacity(0.06),
            ),
          ),
        ),
        SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Padding(
                padding: EdgeInsets.all(isTablet ? 32 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopBar(isTablet),
                    const SizedBox(height: 32),
                    Expanded(
                      child: isTablet
                          ? _buildTabletLayout()
                          : _buildPhoneLayout(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(bool isTablet) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '안녕! 👋',
              style: TextStyle(
                fontSize: isTablet ? 16 : 14,
                color: const Color(0xFF7E57C2),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '오늘은 어떤 이야기를\n만들까? ✨',
              style: TextStyle(
                fontSize: isTablet ? 28 : 22,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF3D2C8D),
                height: 1.3,
              ),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE7F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.emoji_nature,
                  size: 18,
                  color: Color(0xFF7E57C2),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '토끼마을',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3D2C8D),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: Color(0xFF7E57C2),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabletLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSearchBar(),
              const SizedBox(height: 28),
              _buildMenuCards(),
            ],
          ),
        ),
        const SizedBox(width: 32),
        Expanded(flex: 5, child: _buildHeroImage()),
      ],
    );
  }

  Widget _buildPhoneLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildSearchBar(),
          const SizedBox(height: 24),
          _buildMenuCards(),
          const SizedBox(height: 24),
          _buildHeroImage(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: '동화를 검색해보세요',
          hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
          prefixIcon: Icon(Icons.search, color: Colors.grey[400], size: 22),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildMenuCards() {
    final cards = [
      {
        'icon': Icons.menu_book_rounded,
        'iconColor': const Color(0xFF7E57C2),
        'bgColor': const Color(0xFFEDE7F6),
        'title': '동화 읽기',
        'desc': '재미있는 동화를\n읽어보아요!',
        'cardColor': Colors.white,
        'onTap': () => _navigateToTaleList(),
      },
      {
        'icon': Icons.edit_rounded,
        'iconColor': const Color(0xFFEC407A),
        'bgColor': const Color(0xFFFCE4EC),
        'title': '이야기 바꾸기',
        'desc': '내가 원하는 대로\n이야기를 바꿔봐요!',
        'cardColor': Colors.white,
        'onTap': () => _navigateToTaleList(),
      },
      {
        'icon': Icons.star_rounded,
        'iconColor': const Color(0xFFFF8F00),
        'bgColor': const Color(0xFFFFF8E1),
        'title': '내 이야기 보기',
        'desc': '내가 만든 이야기를\n다시 볼 수 있어요!',
        'cardColor': Colors.white,
        'onTap': () => _navigateToMyStories(),
      },
    ];

    final isTablet = MediaQuery.of(context).size.width >= 600;

    return isTablet
        ? Row(
            children: cards
                .map(
                  (card) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _buildMenuCard(card),
                    ),
                  ),
                )
                .toList(),
          )
        : Column(
            children: cards
                .map(
                  (card) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildMenuCard(card),
                  ),
                )
                .toList(),
          );
  }

  Widget _buildMenuCard(Map<String, dynamic> card) {
    return GestureDetector(
      onTap: card['onTap'] as VoidCallback,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: card['cardColor'] as Color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: card['bgColor'] as Color,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                card['icon'] as IconData,
                color: card['iconColor'] as Color,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              card['title'] as String,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3D2C8D),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              card['desc'] as String,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: card['bgColor'] as Color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.arrow_forward,
                color: card['iconColor'] as Color,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroImage() {
    return Container(
      height: 280,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD1C4E9), Color(0xFFB39DDB)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 20,
            right: 20,
            child: Icon(
              Icons.auto_awesome,
              size: 30,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
          Positioned(
            bottom: 30,
            left: 20,
            child: Icon(
              Icons.star,
              size: 20,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.auto_stories,
                  size: 80,
                  color: Colors.white.withOpacity(0.7),
                ),
                const SizedBox(height: 12),
                Text(
                  '새로운 이야기가 기다려요!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToTaleList() {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, animation, _) => const FairyTaleListScreen(),
        transitionsBuilder: (_, animation, _, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
      ),
    );
  }

  void _navigateToMyStories() {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, animation, _) => const MyStoriesScreen(),
        transitionsBuilder: (_, animation, _, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
      ),
    );
  }
}

