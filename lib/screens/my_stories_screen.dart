import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/favorites_provider.dart';
import 'fairy_tale_list_screen.dart';

// ═══════════════════════════════════════════════════════════════
//  나의 책장 - 내가 만든 이야기 데이터 모델
// ═══════════════════════════════════════════════════════════════

class MyStory {
  final String id;
  final String title;
  final String imagePath;
  final String date;
  final String category;

  MyStory({
    required this.id,
    required this.title,
    required this.imagePath,
    required this.date,
    required this.category,
  });
}

// 샘플 - 내가 만든 이야기 데이터
final List<MyStory> sampleMyStories = [
  MyStory(
    id: '1',
    title: '지우와 늑대의\n우정 이야기',
    imagePath: 'assets/red_riding_hood.jpeg',
    date: '2024.06.10',
    category: '고전 동화',
  ),
  MyStory(
    id: '2',
    title: '우주를 여행한\n피노키오',
    imagePath: 'assets/pinocchio.jpeg',
    date: '2024.06.09',
    category: '창작 동화',
  ),
  MyStory(
    id: '3',
    title: '바닷속 친구들과\n인어공주',
    imagePath: 'assets/little_mermaid.jpeg',
    date: '2024.06.08',
    category: '고전 동화',
  ),
  MyStory(
    id: '4',
    title: '마법 학교의\n신데렐라',
    imagePath: 'assets/cinderella.jpeg',
    date: '2024.06.07',
    category: '창작 동화',
  ),
];

// ═══════════════════════════════════════════════════════════════
//  나의 책장 화면
// ═══════════════════════════════════════════════════════════════

class MyStoriesScreen extends StatefulWidget {
  const MyStoriesScreen({super.key});

  @override
  State<MyStoriesScreen> createState() => _MyStoriesScreenState();
}

class _MyStoriesScreenState extends State<MyStoriesScreen>
    with SingleTickerProviderStateMixin {
  int _selectedTab = 0;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  final List<String> _tabs = ['전체', '내가 만든 이야기', '좋아하는 이야기'];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
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
    final favoritesProvider = context.watch<FavoritesProvider>();
    final favoritesList = favoritesProvider.favorites;

    // 탭별 데이터
    final allItems = [
      ...sampleMyStories.map((s) => _StoryItem.fromMyStory(s)),
      ...favoritesList.map((t) => _StoryItem.fromFairyTale(t)),
    ];
    final myItems =
        sampleMyStories.map((s) => _StoryItem.fromMyStory(s)).toList();
    final favItems =
        favoritesList.map((t) => _StoryItem.fromFairyTale(t)).toList();

    final currentItems = _selectedTab == 0
        ? allItems
        : _selectedTab == 1
            ? myItems
            : favItems;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, isTablet),
              const SizedBox(height: 16),
              _buildTabs(isTablet, favoritesProvider),
              const SizedBox(height: 16),
              Expanded(
                child: currentItems.isEmpty
                    ? _buildEmptyState()
                    : _buildGrid(currentItems, isTablet),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 헤더 ──
  Widget _buildHeader(BuildContext context, bool isTablet) {
    final hPadding = isTablet ? 32.0 : 16.0;
    final favCount =
        context.watch<FavoritesProvider>().favorites.length;
    final totalCount = sampleMyStories.length + favCount;

    return Padding(
      padding: EdgeInsets.fromLTRB(hPadding, 16, hPadding, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('07 나의 책장',
              style:
                  TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 8),
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.maybePop(context),
                child: Container(
                  width: isTablet ? 44 : 36,
                  height: isTablet ? 44 : 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: Icon(Icons.chevron_left,
                      color: const Color(0xFF7E57C2),
                      size: isTablet ? 28 : 22),
                ),
              ),
              const SizedBox(width: 12),
              Text('나의 책장',
                  style: TextStyle(
                      fontSize: isTablet ? 28 : 22,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF3D2C8D),
                      letterSpacing: -0.5)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_stories,
                        size: 16, color: Color(0xFF7E57C2)),
                    const SizedBox(width: 6),
                    Text('총 ${totalCount}개의 이야기',
                        style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF7E57C2),
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 탭 ──
  Widget _buildTabs(bool isTablet, FavoritesProvider provider) {
    final hPadding = isTablet ? 32.0 : 16.0;
    final favCount = provider.favorites.length;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPadding),
      child: Row(
        children: _tabs.asMap().entries.map((entry) {
          final index = entry.key;
          final label = entry.value;
          final isSelected = _selectedTab == index;

          // 좋아하는 이야기 탭에 개수 뱃지
          final showBadge = index == 2 && favCount > 0;

          return GestureDetector(
            onTap: () {
              setState(() => _selectedTab = index);
              _animController.forward(from: 0);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF7E57C2)
                    : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? const Color(0xFF7E57C2).withOpacity(0.3)
                        : Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: isTablet ? 14 : 13,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isSelected
                          ? Colors.white
                          : Colors.grey[600],
                    ),
                  ),
                  if (showBadge) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withOpacity(0.3)
                            : const Color(0xFF7E57C2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$favCount',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? Colors.white
                              : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── 그리드 ──
  Widget _buildGrid(List<_StoryItem> items, bool isTablet) {
    final hPadding = isTablet ? 32.0 : 16.0;
    final columns = isTablet ? 4 : 2;

    return GridView.builder(
      padding:
          EdgeInsets.symmetric(horizontal: hPadding, vertical: 4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: isTablet ? 0.75 : 0.7,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) =>
          _buildStoryCard(items[index], isTablet),
    );
  }

  // ── 스토리 카드 ──
  Widget _buildStoryCard(_StoryItem item, bool isTablet) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${item.title.replaceAll('\n', ' ')} 읽기'),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16)),
                    child: Image.asset(
                      item.imagePath,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (_, __, ___) => Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFEDE7F6),
                              const Color(0xFFD1C4E9),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16)),
                        ),
                        child: Center(
                          child: Icon(Icons.auto_stories,
                              size: isTablet ? 60 : 50,
                              color: Colors.white.withOpacity(0.7)),
                        ),
                      ),
                    ),
                  ),
                  // 뱃지
                  Positioned(
                    top: 8, left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: item.isMyStory
                            ? const Color(0xFF7E57C2)
                            : const Color(0xFFE91E63),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.isMyStory ? '내 작품' : '즐겨찾기',
                        style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  // 하트
                  Positioned(
                    top: 8, right: 8,
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.85),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        item.isMyStory
                            ? Icons.more_vert
                            : Icons.favorite,
                        size: 16,
                        color: item.isMyStory
                            ? Colors.grey[600]
                            : const Color(0xFFE91E63),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: isTablet ? 14 : 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF3D2C8D),
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.category,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 빈 상태 ──
  Widget _buildEmptyState() {
    final messages = [
      '동화를 탐색하고 즐겨찾기를 추가해보세요!',
      '아직 만든 이야기가 없어요!\nAI로 나만의 동화를 만들어보세요 😊',
      '동화 목록에서 하트를 눌러\n좋아하는 동화를 추가해보세요 💜',
    ];

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _selectedTab == 2
                ? Icons.favorite_border
                : Icons.auto_stories,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            _selectedTab == 1
                ? '아직 만든 이야기가 없어요!'
                : _selectedTab == 2
                    ? '좋아하는 이야기가 없어요!'
                    : '이야기가 없어요!',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[400]),
          ),
          const SizedBox(height: 8),
          Text(
            messages[_selectedTab],
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[300]),
          ),
        ],
      ),
    );
  }
}

// ── 통합 아이템 모델 ──
class _StoryItem {
  final String title;
  final String imagePath;
  final String category;
  final bool isMyStory;

  _StoryItem({
    required this.title,
    required this.imagePath,
    required this.category,
    required this.isMyStory,
  });

  factory _StoryItem.fromMyStory(MyStory s) => _StoryItem(
        title: s.title,
        imagePath: s.imagePath,
        category: s.category,
        isMyStory: true,
      );

  factory _StoryItem.fromFairyTale(FairyTale t) => _StoryItem(
        title: t.title,
        imagePath: 'assets/${t.imagePath}',
        category: t.category,
        isMyStory: false,
      );
}