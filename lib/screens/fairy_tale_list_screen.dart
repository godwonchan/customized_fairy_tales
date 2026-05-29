import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'fairy_tale_detail_screen.dart';
import 'tale_reading_screen.dart';

enum FairyTaleTab { original, myBookshelf }

class FairyTale {
  final String title;
  final String description;
  final String imagePath;
  final Color cardColor;
  final bool isFavorite;
  final int? storyId;
  final bool isUserStory;
  final String category;

  FairyTale({
    required this.title,
    required this.description,
    required this.imagePath,
    required this.cardColor,
    this.isFavorite = false,
    this.storyId,
    this.isUserStory = false,
    this.category = '동화',
  });

  FairyTale copyWith({
    String? title,
    String? description,
    String? imagePath,
    Color? cardColor,
    bool? isFavorite,
    int? storyId,
    bool? isUserStory,
    String? category,
  }) {
    return FairyTale(
      title: title ?? this.title,
      description: description ?? this.description,
      imagePath: imagePath ?? this.imagePath,
      cardColor: cardColor ?? this.cardColor,
      isFavorite: isFavorite ?? this.isFavorite,
      storyId: storyId ?? this.storyId,
      isUserStory: isUserStory ?? this.isUserStory,
      category: category ?? this.category,
    );
  }
}

class FairyTaleListScreen extends StatefulWidget {
  final FairyTaleTab initialTab;

  const FairyTaleListScreen({
    super.key,
    this.initialTab = FairyTaleTab.original,
  });

  @override
  State<FairyTaleListScreen> createState() => _FairyTaleListScreenState();
}

class _FairyTaleListScreenState extends State<FairyTaleListScreen> {
  late FairyTaleTab _currentTab;

  bool _isLoading = true;
  String? _errorMessage;

  List<FairyTale> _originalStories = [];
  List<FairyTale> _myStories = [];

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
    _loadStories();
  }

  Color _colorForIndex(int index, {bool isUserStory = false}) {
    final originalColors = [
      const Color(0xFFFFF3E0),
      const Color(0xFFE8F5E9),
      const Color(0xFFE3F2FD),
      const Color(0xFFF3E5F5),
      const Color(0xFFFFEBEE),
      const Color(0xFFE0F7FA),
    ];

    final userColors = [
      const Color(0xFFEDE7F6),
      const Color(0xFFE1F5FE),
      const Color(0xFFE8F5E9),
      const Color(0xFFFFF8E1),
      const Color(0xFFFCE4EC),
      const Color(0xFFE0F2F1),
    ];

    final palette = isUserStory ? userColors : originalColors;
    return palette[index % palette.length];
  }

  Future<void> _loadStories() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final originalData = await ApiService.getOriginalStories();
      final myData = await ApiService.getMyStories();

      final originalStories = originalData.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value as Map<String, dynamic>;

        return FairyTale(
          title: (item['title'] ?? '제목 없음').toString(),
          description: (item['description'] ?? '동화를 읽어보세요.').toString(),
          imagePath: '',
          cardColor: _colorForIndex(index, isUserStory: false),
          storyId: item['id'] as int?,
          isUserStory: false,
          category: '동화',
        );
      }).toList();

      final myStories = myData.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value as Map<String, dynamic>;

        return FairyTale(
          title: (item['title'] ?? '내 이야기').toString(),
          description: (item['description'] ?? '내가 만든 동화예요.').toString(),
          imagePath: '',
          cardColor: _colorForIndex(index, isUserStory: true),
          storyId: item['id'] as int?,
          isUserStory: true,
          category: '나의 책장',
        );
      }).toList();

      if (!mounted) return;

      setState(() {
        _originalStories = originalStories;
        _myStories = myStories;
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

  List<FairyTale> get _currentStories =>
      _currentTab == FairyTaleTab.original ? _originalStories : _myStories;

  void _openTale(FairyTale tale) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => tale.isUserStory
            ? TaleReadingScreen(
                tale: tale,
                useCurrentVersion: true,
              )
            : FairyTaleDetailScreen(tale: tale),
      ),
    ).then((_) => _loadStories());
  }

  Widget _buildTab({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF7E57C2) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? const Color(0xFF7E57C2) : Colors.grey.shade300,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : const Color(0xFF3D2C8D),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStoryCard(FairyTale tale) {
    return GestureDetector(
      onTap: () => _openTale(tale),
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
                child: const Center(
                  child: Icon(
                    Icons.auto_stories,
                    size: 56,
                    color: Color(0xFF7E57C2),
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
                    maxLines: 1,
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
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
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
                      if (tale.isUserStory)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDE7F6),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            '나의 책장',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF7E57C2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF3D2C8D),
        elevation: 0,
        title: const Text('동화'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                _buildTab(
                  label: '동화목록',
                  selected: _currentTab == FairyTaleTab.original,
                  onTap: () => setState(() => _currentTab = FairyTaleTab.original),
                ),
                const SizedBox(width: 10),
                _buildTab(
                  label: '나의 책장',
                  selected: _currentTab == FairyTaleTab.myBookshelf,
                  onTap: () => setState(() => _currentTab = FairyTaleTab.myBookshelf),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF7E57C2),
                    ),
                  )
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      )
                    : _currentStories.isEmpty
                        ? Center(
                            child: Text(
                              _currentTab == FairyTaleTab.original
                                  ? '표시할 동화가 없어요.'
                                  : '아직 저장된 내 이야기가 없어요.',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadStories,
                            child: GridView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _currentStories.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: isTablet ? 3 : 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.72,
                              ),
                              itemBuilder: (context, index) {
                                final tale = _currentStories[index];
                                return _buildStoryCard(tale);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}