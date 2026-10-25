import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/favorites_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/crayong_widgets.dart';
import 'creation/custom_story_create_screen.dart';
import 'fairy_tale_list_screen.dart';
import 'fairy_tale_detail_screen.dart';

class MyStoriesScreen extends StatefulWidget {
  const MyStoriesScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<MyStoriesScreen> createState() => _MyStoriesScreenState();
}

class _MyStoriesScreenState extends State<MyStoriesScreen>
    with SingleTickerProviderStateMixin {
  late int _selectedTab;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  static const List<String> _tabs = ['전체', '내가 만든 이야기', '좋아하는 이야기'];
  static const List<IconData> _tabIcons = [
    Icons.auto_stories_rounded,
    Icons.brush_rounded,
    Icons.favorite_rounded,
  ];

  bool _isLoading = true;
  String? _errorMessage;
  List<FairyTale> _myStories = [];

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab.clamp(0, _tabs.length - 1);
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
    const colors = [
      AppColors.primaryLight,
      AppColors.secondaryLight,
      AppColors.accentLight,
      Color(0xFFE2F0F8),
      AppColors.surfaceVariant,
      Color(0xFFEDE6F6),
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
          imagePath: storyId != null ? ApiService.storyPageImageUrl(storyId, 1) : '',
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

  Future<void> _openTale(FairyTale tale) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FairyTaleDetailScreen(tale: tale)),
    );
    _loadMyStories();
  }

  void _openCreation() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CustomStoryCreateScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final favoritesProvider = context.watch<FavoritesProvider>();
    final favoritesList = favoritesProvider.favorites;

    final allItems = [..._myStories, ...favoritesList];
    final currentItems = _selectedTab == 0
        ? allItems
        : _selectedTab == 1
            ? _myStories
            : favoritesList;

    final counts = [allItems.length, _myStories.length, favoritesList.length];
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(canPop),
              const SizedBox(height: 8),
              _buildTabs(counts),
              const SizedBox(height: 12),
              Expanded(child: _buildBody(currentItems)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool canPop) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          if (canPop) ...[
            RoundIconButton(
              icon: Icons.arrow_back_rounded,
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 12),
          ],
          Text('나의 책장', style: AppTextStyles.display()),
          const SizedBox(width: 8),
          Image.asset(CrayongImages.wink, height: 44),
          const Spacer(),
          RoundIconButton(
            icon: Icons.refresh_rounded,
            tooltip: '새로고침',
            onTap: _loadMyStories,
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(List<int> counts) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final isSelected = _selectedTab == index;
          return GestureDetector(
            onTap: () => setState(() => _selectedTab = index),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isSelected ? AppColors.primaryDark : AppColors.border,
                      blurRadius: 0,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      _tabIcons[index],
                      size: 16,
                      color: isSelected ? AppColors.onPrimary : AppColors.textHint,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _tabs[index],
                      style: AppTextStyles.headingSmall(
                        color: isSelected ? AppColors.onPrimary : AppColors.textSecondary,
                      ).copyWith(height: 1.2),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.surface : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${counts[index]}',
                        style: AppTextStyles.labelSmall(color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(List<FairyTale> items) {
    if (_isLoading) {
      return const CrayongStatusView(
        image: CrayongImages.drawing,
        title: '크레용이 책장을 정리하고 있어요',
        child: SizedBox(
          width: 160,
          child: LinearProgressIndicator(minHeight: 6, borderRadius: BorderRadius.all(Radius.circular(3))),
        ),
      );
    }

    if (_errorMessage != null && _selectedTab != 2) {
      return CrayongStatusView(
        image: CrayongImages.surprised,
        title: '앗, 책장을 못 열었어요',
        message: kDebugMode ? _errorMessage : '인터넷이 잘 연결됐는지 확인하고 다시 눌러 줄래요?',
        child: ElevatedButton.icon(
          onPressed: _loadMyStories,
          icon: const Icon(Icons.refresh_rounded, size: 20),
          label: const Text('다시 해볼래요'),
        ),
      );
    }

    if (items.isEmpty) {
      if (_selectedTab == 2) {
        return const CrayongStatusView(
          image: CrayongImages.lying,
          title: '아직 좋아하는 이야기가 없어요',
          message: '마음에 드는 동화를 즐겨찾기 하면 여기에 모여요.',
        );
      }
      return CrayongStatusView(
        image: CrayongImages.painter,
        title: '아직 만든 이야기가 없어요',
        message: '동화를 바꾸거나 새로 만들면 여기에 모여요.',
        child: ElevatedButton.icon(
          onPressed: _openCreation,
          icon: const Icon(Icons.brush_rounded, size: 20),
          label: const Text('크레용이랑 만들러 가기'),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: _loadMyStories,
          color: AppColors.primaryDark,
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: storyGridColumns(constraints.maxWidth),
              crossAxisSpacing: 18,
              mainAxisSpacing: 22,
              childAspectRatio: 0.74,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final tale = items[index];
              return StoryBookCard(
                tale: tale,
                onTap: () => _openTale(tale),
                chipColor: tale.isUserStory ? AppColors.primaryLight : null,
                chipTextColor: tale.isUserStory ? AppColors.primaryText : null,
              );
            },
          ),
        );
      },
    );
  }
}