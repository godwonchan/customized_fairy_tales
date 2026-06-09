import 'package:flutter/material.dart';
import 'fairy_tale_list_screen.dart';
import 'my_stories_screen.dart';
import 'settings_screen.dart';

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
    return Scaffold(
      backgroundColor: const Color(0xFFF0EEFF),
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(child: _pages[_selectedIndex]),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    final items = [
      {'icon': Icons.home_rounded, 'label': '홈'},
      {'icon': Icons.menu_book_rounded, 'label': '동화 목록'},
      {'icon': Icons.star_rounded, 'label': '내 이야기'},
      {'icon': Icons.settings_rounded, 'label': '설정'},
    ];

    return Container(
      width: 90,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9575CD).withOpacity(0.12),
            blurRadius: 20,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Column(
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFB39DDB), Color(0xFF7E57C2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF9575CD).withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.auto_stories, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 6),
                const Text('동화랑',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF5E35B1))),
              ],
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
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFEDE7F6) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Icon(item['icon'] as IconData, size: 26,
                          color: isSelected ? const Color(0xFF7E57C2) : Colors.grey[350]),
                      const SizedBox(height: 4),
                      Text(item['label'] as String,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                            color: isSelected ? const Color(0xFF7E57C2) : Colors.grey[400],
                          )),
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
  final TextEditingController _searchController = TextEditingController();

  final List<Map<String, dynamic>> _recentStories = [
    {'title': '잭과 콩나무', 'date': '2024.05.20', 'color': const Color(0xFF81C784), 'icon': Icons.eco_rounded},
    {'title': '인어공주', 'date': '2024.05.18', 'color': const Color(0xFF64B5F6), 'icon': Icons.waves_rounded},
    {'title': '아기 돼지 삼형제', 'date': '2024.05.15', 'color': const Color(0xFFFFB74D), 'icon': Icons.home_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFE8E0FF), Color(0xFFF5F0FF), Color(0xFFEDF5FF)],
            ),
          ),
        ),
        Positioned(top: -80, right: 100,
          child: Container(width: 280, height: 280,
            decoration: BoxDecoration(shape: BoxShape.circle,
                color: const Color(0xFFB39DDB).withOpacity(0.15)))),
        Positioned(bottom: -60, left: 80,
          child: Container(width: 200, height: 200,
            decoration: BoxDecoration(shape: BoxShape.circle,
                color: const Color(0xFF80CBC4).withOpacity(0.12)))),
        SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: Column(
                  children: [
                    _buildTopBar(),
                    const SizedBox(height: 20),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 62,
                            child: Column(
                              children: [
                                Expanded(flex: 3, child: _buildHeroBanner()),
                                const SizedBox(height: 16),
                                Expanded(flex: 2, child: _buildMenuCards()),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          SizedBox(
                            width: 260,
                            child: Column(
                              children: [
                                Expanded(flex: 3, child: _buildRecommendCard()),
                                const SizedBox(height: 16),
                                Expanded(flex: 2, child: _buildRecentStoriesCard()),
                              ],
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildTopBar() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [BoxShadow(color: const Color(0xFF9575CD).withOpacity(0.12), blurRadius: 16, offset: const Offset(0, 4))],
            ),
            child: TextField(
              controller: _searchController,
              enableSuggestions: false,
              autocorrect: false,
              style: const TextStyle(fontSize: 14, color: Color(0xFF3D2C8D)),
              decoration: InputDecoration(
                hintText: '읽고 싶은 동화를 검색해보세요 ✨',
                hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF9575CD), size: 22),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (_, value, __) => value.text.isNotEmpty
                      ? GestureDetector(onTap: () => _searchController.clear(),
                          child: Icon(Icons.cancel_rounded, color: Colors.grey[400], size: 20))
                      : const SizedBox.shrink(),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onSubmitted: (value) { if (value.trim().isNotEmpty) _navigateToTaleList(); },
            ),
          ),
        ),
        const SizedBox(width: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              Container(width: 36, height: 36,
                decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFE0B2), width: 1.5)),
                child: const Icon(Icons.face_rounded, size: 22, color: Color(0xFFFF8F00))),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('안녕하세요!', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                  const Row(children: [
                    Text('동화친구님', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF3D2C8D))),
                    SizedBox(width: 4),
                    Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFB300)),
                  ]),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF2D1B6B), Color(0xFF5C3A9E)],
        ),
        boxShadow: [BoxShadow(color: const Color(0xFF5E35B1).withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(right: 0, top: 0, bottom: 0, left: 0,
              child: Align(alignment: Alignment.centerRight,
                child: Image.asset('assets/background.png', fit: BoxFit.contain, alignment: Alignment.centerRight))),
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2D1B6B), Color(0xFF2D1B6B), Colors.transparent],
                    begin: Alignment.centerLeft, end: Alignment.centerRight,
                    stops: [0.0, 0.35, 0.65],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 0, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('나만의 이야기를\n만들어볼까요?',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white, height: 1.35)),
                  const SizedBox(height: 10),
                  Text('상상력을 더해 세상에 하나뿐인\n동화를 만들어보세요!',
                      style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.75), height: 1.6)),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: () => _navigateToTaleList(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFFFB300), Color(0xFFFF8F00)]),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [BoxShadow(color: const Color(0xFFFF8F00).withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('이야기 만들기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                        SizedBox(width: 8),
                        Icon(Icons.auto_fix_high_rounded, size: 16, color: Colors.white),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 메뉴 카드 3개: 가로형 레이아웃 ───
  Widget _buildMenuCards() {
    final cards = [
      {
        'image': 'assets/book01.png',
        'bgGradient': const LinearGradient(colors: [Color(0xFFF3EEFF), Color(0xFFE8DCFF)]),
        'title': '동화 목록',
        'desc': '다양한 동화를\n읽어보아요',
        'btnColor': const Color(0xFF7E57C2),
        'titleColor': const Color(0xFF5E35B1),
        'onTap': _navigateToTaleList,
      },
      {
        'image': 'assets/posion01.png',
        'bgGradient': const LinearGradient(colors: [Color(0xFFFFF0F5), Color(0xFFFFDDEC)]),
        'title': '내 이야기',
        'desc': '내가 만든 이야기를\n확인해봐요',
        'btnColor': const Color(0xFFEC407A),
        'titleColor': const Color(0xFFAD1457),
        'onTap': _navigateToMyStories,
      },
      {
        'image': 'assets/star01.png',
        'bgGradient': const LinearGradient(colors: [Color(0xFFFFFBF0), Color(0xFFFFF3CC)]),
        'title': '즐겨찾기',
        'desc': '좋아하는 동화를\n모아보아요',
        'btnColor': const Color(0xFFFF8F00),
        'titleColor': const Color(0xFFE65100),
        'onTap': () {},
      },
    ];

    return Row(
      children: List.generate(cards.length, (i) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < cards.length - 1 ? 14 : 0),
            child: _buildMenuCard(cards[i]),
          ),
        );
      }),
    );
  }

  Widget _buildMenuCard(Map<String, dynamic> card) {
    return Container(
      decoration: BoxDecoration(
        gradient: card['bgGradient'] as LinearGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (card['btnColor'] as Color).withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: card['onTap'] as VoidCallback,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ 상단: 이미지(왼쪽) + 제목/설명(오른쪽) 가로 배치
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 이미지 크게
                    Image.asset(
                      card['image'] as String,
                      width: 110,
                      height: 110,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 12),
                    // 제목 + 설명
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card['title'] as String,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: card['titleColor'] as Color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            card['desc'] as String,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // ✅ 하단 오른쪽 화살표 버튼
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: card['btnColor'] as Color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (card['btnColor'] as Color).withOpacity(0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.favorite_rounded, size: 16, color: Color(0xFFEC407A)),
                const SizedBox(width: 6),
                const Text('오늘의 추천 동화',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF3D2C8D))),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset('assets/girl_wolf.png', fit: BoxFit.cover, width: double.infinity),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('빨간 망토 소녀',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF3D2C8D))),
                      const SizedBox(height: 4),
                      Text('용감한 소녀가 숲 속에서\n만난 특별한 모험 이야기',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500], height: 1.5)),
                    ],
                  ),
                ),
                Container(
                  width: 36, height: 36,
                  decoration: const BoxDecoration(color: Color(0xFFFCE4EC), shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFFEC407A)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentStoriesCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDE7),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, size: 16, color: Color(0xFFFF8F00)),
                const SizedBox(width: 6),
                const Text('최근 읽은 동화',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF3D2C8D))),
                const Spacer(),
                Icon(Icons.flutter_dash, size: 20, color: const Color(0xFF29B6F6).withOpacity(0.8)),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFFFF9C4)),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _recentStories.map((s) => _buildRecentStoryItem(s)).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('더보기', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                const SizedBox(width: 2),
                Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.grey[600]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentStoryItem(Map<String, dynamic> story) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: (story['color'] as Color).withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(story['icon'] as IconData, size: 20, color: story['color'] as Color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(story['title'] as String,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3D2C8D))),
                Text(story['date'] as String, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey[400]),
        ],
      ),
    );
  }

  void _navigateToTaleList() {
    Navigator.push(context, PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, animation, __) => const FairyTaleListScreen(),
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: FadeTransition(opacity: animation, child: child),
      ),
    ));
  }

  void _navigateToMyStories() {
    Navigator.push(context, PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, animation, __) => const MyStoriesScreen(),
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: FadeTransition(opacity: animation, child: child),
      ),
    ));
  }
}