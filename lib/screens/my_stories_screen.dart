// lib/screens/my_stories_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/favorites_provider.dart';
import '../services/api_service.dart';
import '../widgets/story_image_view.dart';
import 'fairy_tale_list_screen.dart';
import 'fairy_tale_detail_screen.dart';

import 'package:shared_preferences/shared_preferences.dart';

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

  // 💡 [2번] 휴지통 탭 추가!
  final List<String> _tabs = ['전체', '내가 만든 이야기', '좋아하는 이야기', '휴지통'];

  // 💾 로컬 저장소 키
  static const String _orderKey = 'my_stories_custom_order';
  static const String _trashKey = 'my_stories_trash_ids';

  bool _isLoading = true;
  String? _errorMessage;
  List<FairyTale> _myStories = [];
  final List<FairyTale> _trashedStories = []; // 🗑️ 휴지통 보관함

  // ✏️ [편집 모드] 상태 플래그
  bool _isEditMode = false;

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

  // 💾 순서 및 휴지통 상태 영구 저장 헬퍼
  Future<void> _persistOrderAndTrash() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. 현재 책장 이야기 순서(ID 리스트) 저장
    final orderIds = _myStories
        .where((t) => t.storyId != null)
        .map((t) => t.storyId.toString())
        .toList();
    await prefs.setStringList(_orderKey, orderIds);

    // 2. 휴지통에 들어간 이야기(ID 리스트) 저장
    final trashIds = _trashedStories
        .where((t) => t.storyId != null)
        .map((t) => t.storyId.toString())
        .toList();
    await prefs.setStringList(_trashKey, trashIds);
  }

  // 📥 이야기 불러오기 + 저장된 순서/휴지통 상태 복원
  Future<void> _loadMyStories() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await ApiService.getMyStories();
      final prefs = await SharedPreferences.getInstance();

      final savedOrder = prefs.getStringList(_orderKey) ?? [];
      final savedTrash = (prefs.getStringList(_trashKey) ?? []).toSet();

      final List<FairyTale> loadedStories = [];
      final List<FairyTale> loadedTrash = [];

      for (int i = 0; i < data.length; i++) {
        final item = data[i] as Map<String, dynamic>;
        final storyId = item['id'] as int?;
        final title = (item['title'] ?? '제목 없음').toString();
        final description = (item['description'] ?? '내가 만든 이야기').toString();

        final tale = FairyTale(
          title: title,
          description: description,
          imagePath: storyId != null
              ? ApiService.storyPageImageUrl(storyId, 1)
              : '',
          cardColor: _colorForIndex(i),
          storyId: storyId,
          isUserStory: true,
          category: '내 이야기',
          sourceFolder: item['source_folder']?.toString(),
          originalTitle: item['original_title']?.toString(),
        );

        // 휴지통 키에 포함되어 있으면 휴지통으로, 아니면 책장 목록으로 분류
        if (storyId != null && savedTrash.contains(storyId.toString())) {
          loadedTrash.add(tale);
        } else {
          loadedStories.add(tale);
        }
      }

      // 사용자가 이전에 배치했던 순서대로 정렬 (새로 추가된 이야기는 앞쪽 배치)
      loadedStories.sort((a, b) {
        final aId = a.storyId?.toString() ?? '';
        final bId = b.storyId?.toString() ?? '';
        final aIdx = savedOrder.indexOf(aId);
        final bIdx = savedOrder.indexOf(bId);

        if (aIdx == -1 && bIdx == -1) return 0;
        if (aIdx == -1) return -1; // 새로운 이야기는 맨 앞
        if (bIdx == -1) return 1;
        return aIdx.compareTo(bIdx);
      });

      if (!mounted) return;
      setState(() {
        _myStories = loadedStories;
        _trashedStories
          ..clear()
          ..addAll(loadedTrash);
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

  // 🗑️ [2번] 휴지통으로 이동 확인 팝업
  Future<void> _confirmAndMoveToTrash(FairyTale tale) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Color(0xFFFF7043), size: 26),
            SizedBox(width: 8),
            Text('휴지통으로 이동', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF3D2C8D))),
          ],
        ),
        content: Text(
          '‘${tale.title}’ 동화를 휴지통으로 보낼까요?\n휴지통 탭에서 언제든 다시 복구할 수 있어요! 📦',
          style: const TextStyle(fontSize: 14, color: Color(0xFF4A4458), height: 1.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFDED6ED)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('취소', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dialogCtx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF7043),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('휴지통으로', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final removedIndex = _myStories.indexOf(tale);
      setState(() {
        _myStories.remove(tale);
        _trashedStories.insert(0, tale);
      });
      await _persistOrderAndTrash(); // 👈 저장

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📦 ‘${tale.title}’이(가) 휴지통으로 이동되었어요.'),
            backgroundColor: const Color(0xFF7E57C2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: '실행 취소',
              textColor: Colors.amberAccent,
              onPressed: () async {
                setState(() {
                  _trashedStories.remove(tale);
                  if (removedIndex >= 0 && removedIndex <= _myStories.length) {
                    _myStories.insert(removedIndex, tale);
                  } else {
                    _myStories.add(tale);
                  }
                });
                await _persistOrderAndTrash(); // 👈 실행 취소 시에도 저장
              },
            ),
          ),
        );
      }
    }
  }

  // 🔄 휴지통에서 다시 책장으로 복구
  void _restoreFromTrash(FairyTale tale) async {
    setState(() {
      _trashedStories.remove(tale);
      _myStories.insert(0, tale);
    });
    await _persistOrderAndTrash(); // 👈 저장

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✨ ‘${tale.title}’ 동화가 다시 책장으로 돌아왔어요!'),
        backgroundColor: const Color(0xFF7E57C2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // 💥 휴지통에서 완전 영구 삭제
  Future<void> _confirmPermanentDelete(FairyTale tale) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFFF5252), size: 26),
            SizedBox(width: 8),
            Text('완전 영구 삭제', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF3D2C8D))),
          ],
        ),
        content: Text(
          '‘${tale.title}’ 동화를 완전히 지울까요?\n서버에서 완전히 사라지며 다시 되돌릴 수 없어요! ⚠️',
          style: const TextStyle(fontSize: 14, color: Color(0xFF4A4458), height: 1.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFDED6ED)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('취소', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dialogCtx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5252),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('영구 삭제', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed == true && tale.storyId != null) {
      await ApiService.deleteStory(tale.storyId!);
      setState(() {
        _trashedStories.remove(tale);
      });
      await _persistOrderAndTrash(); // 👈 저장
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('동화가 완전히 삭제되었어요.'),
            backgroundColor: Colors.black87,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
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
    final favItems = favoritesList.map((t) => _StoryItem.fromFairyTale(t)).toList();
    final trashItems = _trashedStories.map((t) => _StoryItem.fromFairyTale(t)).toList();

    final currentItems = _selectedTab == 0
        ? allItems
        : _selectedTab == 1
        ? myItems
        : _selectedTab == 2
        ? favItems
        : trashItems;

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
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF7E57C2)))
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
            _isEditMode ? '책장 순서 편집' : (_selectedTab == 3 ? '휴지통 보관함' : '나의 책장'),
            style: TextStyle(
              fontSize: isTablet ? 28 : 24,
              fontWeight: FontWeight.w800,
              color: _isEditMode ? const Color(0xFF7E57C2) : const Color(0xFF3D2C8D),
            ),
          ),
          const Spacer(),
          // 💡 편집 / 완료 토글
          if (_isEditMode)
            ElevatedButton.icon(
              onPressed: () => setState(() => _isEditMode = false),
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('완료', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7E57C2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
            )
          else if (_selectedTab != 3) ...[
            TextButton.icon(
              onPressed: () => setState(() => _isEditMode = true),
              icon: const Icon(Icons.edit_note_rounded, size: 20, color: Color(0xFF7E57C2)),
              label: const Text('편집', style: TextStyle(color: Color(0xFF7E57C2), fontWeight: FontWeight.bold)),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
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
        ],
      ),
    );
  }

  Widget _buildTabs(bool isTablet, FavoritesProvider favoritesProvider) {
    final counts = [
      _myStories.length + favoritesProvider.favorites.length,
      _myStories.length,
      favoritesProvider.favorites.length,
      _trashedStories.length,
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final isSelected = _selectedTab == index;
          return GestureDetector(
            onTap: () {
              if (_isEditMode) setState(() => _isEditMode = false);
              setState(() => _selectedTab = index);
            },
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
                      color: isSelected ? Colors.white : const Color(0xFF3D2C8D),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white.withOpacity(0.2) : const Color(0xFFEDE7F6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${counts[index]}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : const Color(0xFF7E57C2),
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
      padding: EdgeInsets.fromLTRB(isTablet ? 24 : 16, 8, isTablet ? 24 : 16, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.72,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        if (_selectedTab == 3) {
          // 🗑️ 휴지통 전용 카드 UI
          return _buildTrashCard(items[index].tale);
        }
        return _buildReorderableStoryCard(items[index], index, isTablet);
      },
    );
  }

  // 🗑️ 휴지통 전용 카드 (복구 / 영구삭제 버튼)
  Widget _buildTrashCard(FairyTale tale) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5DFEE)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: Opacity(
                opacity: 0.75,
                child: StoryImageView(imagePath: tale.imagePath, fit: BoxFit.cover),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tale.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF4A4458)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _restoreFromTrash(tale),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          side: const BorderSide(color: Color(0xFF7E57C2)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('복구', style: TextStyle(fontSize: 12, color: Color(0xFF7E57C2), fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _confirmPermanentDelete(tale),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFEBEE),
                          foregroundColor: const Color(0xFFE53935),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('삭제', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🔀 [1번 수정] PC 마우스로도 클릭하자마자 바로 움직이는 Draggable 카드!
  Widget _buildReorderableStoryCard(_StoryItem item, int index, bool isTablet) {
    final tale = item.tale;

    Widget cardContent = Container(
      decoration: BoxDecoration(
        color: tale.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: _isEditMode
            ? Border.all(color: const Color(0xFF7E57C2), width: 2)
            : null,
      ),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: StoryImageView(imagePath: tale.imagePath, fit: BoxFit.cover),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tale.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF3D2C8D)),
                ),
                const SizedBox(height: 4),
                Text(
                  tale.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E5F5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    tale.category,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF7E57C2)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    Widget cardWithBadge = Stack(
      clipBehavior: Clip.none,
      children: [
        cardContent,
        if (_isEditMode && tale.isUserStory)
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: () => _confirmAndMoveToTrash(tale),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5252),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 6, offset: const Offset(0, 2)),
                  ],
                ),
                child: const Icon(Icons.close_rounded, size: 18, color: Colors.white),
              ),
            ),
          ),
      ],
    );

    // 1. 일반 모드: 클릭 시 상세 보기, 롱프레스 시 편집 모드 진입
    if (!_isEditMode) {
      return GestureDetector(
        onLongPress: () => setState(() => _isEditMode = true),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => FairyTaleDetailScreen(tale: tale)),
          );
          _loadMyStories();
        },
        child: cardWithBadge,
      );
    }

    // 2. 🚀 편집 모드: PC 마우스에서도 즉각 드래그되는 Draggable 사용!
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) {
        final fromIndex = details.data;
        setState(() {
          // '전체' 탭이든 '내가 만든 이야기' 탭이든 정상적으로 순서 변경 적용!
          if (fromIndex < _myStories.length && index < _myStories.length) {
            final moved = _myStories.removeAt(fromIndex);
            _myStories.insert(index, moved);
          }
        });
        _persistOrderAndTrash(); // 👈 드래그 드롭 즉시 순서 저장!
      },
      builder: (context, candidateData, rejectedData) {
        return Draggable<int>(
          data: index,
          // 마우스로 잡고 이동할 때 마우스 커서를 따라다니는 피드백 카드
          feedback: Material(
            elevation: 10,
            borderRadius: BorderRadius.circular(20),
            color: Colors.transparent,
            child: SizedBox(
              width: isTablet ? 170 : 140,
              height: (isTablet ? 170 : 140) / 0.72,
              child: Opacity(opacity: 0.9, child: cardContent),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.2, child: cardWithBadge),
          child: MouseRegion(
            cursor: SystemMouseCursors.grab, // 마우스 커서를 손바닥 모양으로 표시
            child: cardWithBadge,
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _selectedTab == 3 ? Icons.delete_outline_rounded : Icons.auto_stories_outlined,
              size: 72,
              color: const Color(0xFFB39DDB),
            ),
            const SizedBox(height: 16),
            Text(
              _selectedTab == 3 ? '휴지통이 비어 있어요' : '아직 저장된 이야기가 없어요',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF3D2C8D)),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedTab == 3 ? '삭제한 이야기가 여기에 보관돼요 ✨' : '나만의 그림 동화를 완성하고 저장하면\n여기에 나타나요 ✨',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.6, color: Colors.grey[600]),
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
            const Text('나의 책장을 불러오지 못했어요', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF3D2C8D))),
            const SizedBox(height: 8),
            Text(_errorMessage ?? '', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadMyStories, child: const Text('다시 시도')),
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