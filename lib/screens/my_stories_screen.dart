import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/favorites_provider.dart';
import '../services/api_service.dart';
import '../widgets/story_image_view.dart';
import 'fairy_tale_list_screen.dart';
import 'fairy_tale_detail_screen.dart';
import 'home_screen.dart';

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

  bool _isLoading = true;
  String? _errorMessage;
  List<FairyTale> _myStories = [];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    _loadMyStories();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Color _colorForIndex(int index) {
    final colors = [
      const Color(0xFFFFF3E0),
      const Color(0xFFE8F5E9),
      const Color(0xFFE3F2FD),
      const Color(0xFFF3E5F5),
      const Color(0xFFFFEBEE),
      const Color(0xFFE0F7FA),
    ];
    return colors[index % colors.length];
  }

  Future<void> _loadMyStories() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await ApiService.getMyStories();

      final stories = data.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value as Map<String, dynamic>;

        final storyId = item['id'] as int?;
        final title = (item['title'] ?? '제목 없음').toString();
        final description = (item['description'] ?? '내가 만든 이야기').toString();

        return FairyTale(
          title: title,
          description: description,
          imagePath: storyId != null
              ? ApiService.storyPageImageUrl(storyId, 1)
              : '',
          cardColor: _colorForIndex(index),
          storyId: storyId,
          isUserStory: true,
          category: '내 이야기',
          sourceFolder: item['source_folder']?.toString(),
          originalTitle: item['original_title']?.toString(),
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _myStories = stories;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _goHome() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final favoritesProvider = context.watch<FavoritesProvider>();
    final favoritesList = favoritesProvider.favorites;

    final allItems = [
      ..._myStories.map((t) => _StoryItem.fromFairyTale(t)),
      ...favoritesList.map((t) => _StoryItem.fromFairyTale(t)),
    ];

    final myItems = _myStories.map((t) => _StoryItem.fromFairyTale(t)).toList();
    final favItems = favoritesList
        .map((t) => _StoryItem.fromFairyTale(t))
        .toList();

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
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage != null
                    ? _buildErrorState()
                    : currentItems.isEmpty
                    ? _buildEmptyState()
                    : _buildGrid(currentItems, isTablet),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isTablet) {
    final hPadding = isTablet ? 28.0 : 18.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(hPadding, 18, hPadding, 0),
      child: Row(
        children: [
          Text(
            '나의 책장',
            style: TextStyle(
              fontSize: isTablet ? 28 : 24,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF3D2C8D),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _goHome,
            icon: const Icon(Icons.home_rounded),
            color: const Color(0xFF7E57C2),
            tooltip: '홈으로',
          ),
          IconButton(
            onPressed: _loadMyStories,
            icon: const Icon(Icons.refresh),
            color: const Color(0xFF7E57C2),
            tooltip: '새로고침',
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(bool isTablet, FavoritesProvider favoritesProvider) {
    final counts = [
      _myStories.length + favoritesProvider.favorites.length,
      _myStories.length,
      favoritesProvider.favorites.length,
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final isSelected = _selectedTab == index;
          return GestureDetector(
            onTap: () => setState(() => _selectedTab = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF7E57C2) : Colors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFF7E57C2).withOpacity(0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              child: Row(
                children: [
                  Text(
                    _tabs[index],
                    style: TextStyle(
                      fontSize: isTablet ? 14 : 12,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF3D2C8D),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withOpacity(0.2)
                          : const Color(0xFFEDE7F6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${counts[index]}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFF7E57C2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: _tabs.length,
      ),
    );
  }

  Widget _buildGrid(List<_StoryItem> items, bool isTablet) {
    final crossAxisCount = isTablet ? 3 : 2;

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 24 : 16,
        0,
        isTablet ? 24 : 16,
        24,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.72,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildStoryCard(items[index]),
    );
  }

  Widget _buildStoryCard(_StoryItem item) {
    final tale = item.tale;

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FairyTaleDetailScreen(tale: tale)),
        );
        _loadMyStories();
      },
      child: Container(
        decoration: BoxDecoration(
          color: tale.cardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: tale.cardColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  child: StoryImageView(
                    imagePath: tale.imagePath,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tale.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3D2C8D),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tale.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E5F5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tale.category,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF7E57C2),
                      ),
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.auto_stories_outlined,
              size: 72,
              color: Color(0xFFB39DDB),
            ),
            const SizedBox(height: 16),
            const Text(
              '아직 저장된 이야기가 없어요',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3D2C8D),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '동화를 수정하고 저장하면\n여기에 나타나요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.redAccent),
            const SizedBox(height: 12),
            const Text(
              '나의 책장을 불러오지 못했어요',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3D2C8D),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadMyStories,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryItem {
  final FairyTale tale;

  _StoryItem({required this.tale});

  factory _StoryItem.fromFairyTale(FairyTale tale) {
    return _StoryItem(tale: tale);
  }
}
