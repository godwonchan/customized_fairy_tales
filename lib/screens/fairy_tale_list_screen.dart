import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/cover_asset_helper.dart';
import 'fairy_tale_detail_screen.dart';
import '../widgets/story_image_view.dart';

class FairyTale {
  final String title;
  final String description;
  final String imagePath;
  final Color cardColor;
  final bool isFavorite;
  final int? storyId;
  final bool isUserStory;
  final String category;
  final String? sourceFolder;
  final String? originalTitle;

  FairyTale({
    required this.title,
    required this.description,
    required this.imagePath,
    required this.cardColor,
    this.isFavorite = false,
    this.storyId,
    this.isUserStory = false,
    this.category = '동화',
    this.sourceFolder,
    this.originalTitle,
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
    String? sourceFolder,
    String? originalTitle,
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
      sourceFolder: sourceFolder ?? this.sourceFolder,
      originalTitle: originalTitle ?? this.originalTitle,
    );
  }
}

class FairyTaleListScreen extends StatefulWidget {
  const FairyTaleListScreen({super.key});

  @override
  State<FairyTaleListScreen> createState() => _FairyTaleListScreenState();
}

class _FairyTaleListScreenState extends State<FairyTaleListScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<FairyTale> _stories = [];

  @override
  void initState() {
    super.initState();
    _loadStories();
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

  Future<void> _loadStories() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final originalData = await ApiService.getOriginalStories();

      final stories = originalData.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value as Map<String, dynamic>;

        final sourceFolder = item['source_folder']?.toString();
        final originalTitle = item['original_title']?.toString();
        final title = (item['title'] ?? '제목 없음').toString();

        return FairyTale(
          title: title,
          description: (item['description'] ?? '동화를 읽어보세요.').toString(),
          imagePath: getCoverAssetPath(
            sourceFolder: sourceFolder,
            originalTitle: originalTitle,
            title: title,
          ),
          cardColor: _colorForIndex(index),
          storyId: item['id'] as int?,
          isUserStory: false,
          category: '동화',
          sourceFolder: sourceFolder,
          originalTitle: originalTitle,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _stories = stories;
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

  void _openTale(FairyTale tale) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FairyTaleDetailScreen(tale: tale),
      ),
    ).then((_) => _loadStories());
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

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF3D2C8D),
        elevation: 0,
        title: const Text('동화목록'),
      ),
      body: _isLoading
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
              : _stories.isEmpty
                  ? const Center(
                      child: Text(
                        '표시할 동화가 없어요.',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadStories,
                      child: GridView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _stories.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isTablet ? 3 : 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.72,
                        ),
                        itemBuilder: (context, index) {
                          final tale = _stories[index];
                          return _buildStoryCard(tale);
                        },
                      ),
                    ),
    );
  }
}