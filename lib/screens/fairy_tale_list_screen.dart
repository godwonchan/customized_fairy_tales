import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/cover_asset_helper.dart';
import 'fairy_tale_detail_screen.dart';
import '../widgets/story_image_view.dart';

import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lottie/lottie.dart';

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

  // [병규 튜토리얼] 타깃 지정을 위한 GlobalKey 및 컨트롤러
  final GlobalKey _titleKey = GlobalKey();
  final GlobalKey _firstCardKey = GlobalKey();
  TutorialCoachMark? _tutorialCoachMark;
  List<TargetFocus> _targets = [];

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

      // [병규 튜토리얼 추가] 카드 렌더링 후 첫 화면 튜토리얼 실행
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndShowTutorial();
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

  Widget _buildStoryCard(FairyTale tale, {Key? key}) {
    return GestureDetector(
      key: key, // 전달받은 key 연결
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
        title: Text('동화목록', key: _titleKey),
        actions: [
          // [추가] 언제든 튜토리얼을 다시 볼 수 있는 도움말 버튼
          IconButton(
            icon: const Icon(Icons.help_outline, color: Color(0xFF7E57C2)),
            tooltip: '도움말 다시보기',
            onPressed: () => _checkAndShowTutorial(force: true),
          ),
          const SizedBox(width: 8),
        ],
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
                          // [수정] 0번째 첫 번째 카드에만 _firstCardKey 할당
                          return _buildStoryCard(
                            tale,
                            key: index == 0 ? _firstCardKey : null,
                          );
                        },
                      ),
                    ),
    );
  }
  // [병규 튜토리얼] 최초 1회 실행 체크 (force: true 시 도움말 버튼에서 강제 실행)
  Future<void> _checkAndShowTutorial({bool force = false}) async {
    if (!mounted || _stories.isEmpty) return;

    await Future.delayed(const Duration(milliseconds: 400)); // 카드 렌더링 완료 대기
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final bool isTutorialSeen = prefs.getBool('is_home_tutorial_seen') ?? false;

    if (true/*!isTutorialSeen || force*/) {
      _initTutorialTargets();
      _tutorialCoachMark = TutorialCoachMark(
        targets: _targets,
        colorShadow: const Color(0xFF2D3436),
        textSkip: "건너뛰기",
        paddingFocus: 8,
        opacityShadow: 0.8,
        onFinish: () async {
          await prefs.setBool('is_home_tutorial_seen', true);
        },
        onSkip: () {
          prefs.setBool('is_home_tutorial_seen', true);
          return true;
        },
      )..show(context: context);
    }
  }

  // [병규 튜토리얼] 첫 화면 2단계 타깃 설정
  void _initTutorialTargets() {
    _targets = [
      // 1단계: 환영 인사 (상단 타이틀 영역)
      TargetFocus(
        identify: "titleTarget",
        keyTarget: _titleKey,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return _buildTutorialBubble(
                context: context,
                title: "안녕! 이야기 세상에 온 걸 환영해!",
                description: "나는 너만의 특별한 동화를 함께 만들어갈\n이야기 요정이야! 우리 함께 마법 같은\n새로운 이야기를 만들어볼까?",
                onNext: () => controller.next(),
              );
            },
          ),
        ],
      ),

      // 2단계: 첫 번째 동화책 선택 유도
      TargetFocus(
        identify: "firstCardTarget",
        keyTarget: _firstCardKey,
        shape: ShapeLightFocus.RRect,
        radius: 20,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.custom,
            customPosition: CustomTargetContentPosition(
              top: 100, // 카드 윗부분 높이에 맞춰 배치
              // 카드 가로 너비를 고려해 카드 바로 오른쪽(빈 어두운 영역)에 요정 배치
              left: (MediaQuery.of(context).size.width >= 700) ? 460 : 280,
            ),
            builder: (context, controller) {
              return _buildTutorialBubble(
                context: context,
                title: "마음에 드는 동화책 고르기",
                description: "여기 있는 동화책 중 하나를 콕 눌러봐!\n내가 읽어주기도 하고, 네 마음대로\n이야기와 그림을 직접 바꿀 수도 있어!",
                isLast: true,
                onNext: () => controller.next(),
              );
            },
          ),
        ],
      ),
    ];
  }

  // [병규 튜토리얼] 요정 + 말풍선 UI 컴포넌트
  Widget _buildTutorialBubble({
    required BuildContext context,
    required String title,
    required String description,
    required VoidCallback onNext,
    bool isLast = false,
  }) {
    final screenSize = MediaQuery.of(context).size;
    final fairyHeight = (screenSize.height * 0.38).clamp(200.0, 360.0);

    return Material(
      color: Colors.transparent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Lottie 요정 캐릭터
          SizedBox(
            height: fairyHeight,
            width: fairyHeight * 0.75,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Lottie.asset(
                    'assets/animations/fairy.json',
                    fit: BoxFit.contain,
                    repeat: true,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7E57C2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    "이야기 요정",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // 설명 말풍선
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: (screenSize.width * 0.45).clamp(260.0, 380.0),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFD1C4E9), width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 6)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3D2C8D),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF4A4A4A),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: onNext,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7E57C2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        isLast ? "동화 속으로!" : "다음으로",
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}