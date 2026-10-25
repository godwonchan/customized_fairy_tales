import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/cover_asset_helper.dart';
import 'fairy_tale_detail_screen.dart';
import '../widgets/crayong_widgets.dart';

import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FairyTale {
  final String id;
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
    String? id,
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
  }) : id = id ?? 'tale_${DateTime.now().millisecondsSinceEpoch}_${title.hashCode}';

  FairyTale copyWith({
    String? id,
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
      id: id ?? this.id,
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
        final rawId = item['id'] ?? item['tale_id'] ?? item['story_id'];

        return FairyTale(
          id: rawId != null ? 'tale_$rawId' : 'tale_${title.hashCode}',
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

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(canPop),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool canPop) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          if (canPop) ...[
            RoundIconButton(
              icon: Icons.arrow_back_rounded,
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 12),
          ],
          Text('동화 목록', key: _titleKey, style: AppTextStyles.display()),
          const SizedBox(width: 12),
          if (!_isLoading && _errorMessage == null && _stories.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.secondaryLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_stories.length}권',
                style: AppTextStyles.labelMedium(color: const Color(0xFF3E6F2E)),
              ),
            ),
          const Spacer(),
          RoundIconButton(
            icon: Icons.help_outline_rounded,
            tooltip: '도움말 다시보기',
            onTap: () => _checkAndShowTutorial(force: true),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return CrayongStatusView(
        image: CrayongImages.drawing,
        title: '크레용이 동화책을 꺼내고 있어요',
        child: const SizedBox(
          width: 160,
          child: LinearProgressIndicator(minHeight: 6, borderRadius: BorderRadius.all(Radius.circular(3))),
        ),
      );
    }

    if (_errorMessage != null) {
      return CrayongStatusView(
        image: CrayongImages.surprised,
        title: '앗, 동화책을 못 불러왔어요',
        message: kDebugMode
            ? _errorMessage
            : '인터넷이 잘 연결됐는지 확인하고 다시 눌러 줄래요?',
        child: ElevatedButton.icon(
          onPressed: _loadStories,
          icon: const Icon(Icons.refresh_rounded, size: 20),
          label: const Text('다시 해볼래요'),
        ),
      );
    }

    if (_stories.isEmpty) {
      return const CrayongStatusView(
        image: CrayongImages.lying,
        title: '아직 동화책이 없어요',
        message: '조금 있다가 다시 와 줄래요?',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = storyGridColumns(width);
        return RefreshIndicator(
          onRefresh: _loadStories,
          color: AppColors.primaryDark,
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            itemCount: _stories.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 18,
              mainAxisSpacing: 22,
              childAspectRatio: 0.74,
            ),
            itemBuilder: (context, index) {
              final tale = _stories[index];
              return StoryBookCard(
                key: index == 0 ? _firstCardKey : null,
                tale: tale,
                onTap: () => _openTale(tale),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _checkAndShowTutorial({bool force = false}) async {
    if (!mounted || _stories.isEmpty) return;

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final bool isTutorialSeen = prefs.getBool('is_home_tutorial_seen') ?? false;

    if (!isTutorialSeen || force) {
      _initTutorialTargets();
      _tutorialCoachMark = TutorialCoachMark(
        targets: _targets,
        colorShadow: const Color(0xFF3B2F27),
        textSkip: "건너뛰기",
        paddingFocus: 8,
        opacityShadow: 0.75,
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

  void _initTutorialTargets() {
    _targets = [
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
                image: CrayongImages.wink,
                title: "안녕! 나는 크레용이야!",
                description: "너만의 특별한 동화를 같이 만들어 갈\n크레용이야. 우리 같이 마법 같은\n새로운 이야기를 만들어 볼까?",
                onNext: () => controller.next(),
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "firstCardTarget",
        keyTarget: _firstCardKey,
        shape: ShapeLightFocus.RRect,
        radius: 24,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.custom,
            customPosition: CustomTargetContentPosition(
              top: 100,
              left: (MediaQuery.of(context).size.width >= 700) ? 460 : 280,
            ),
            builder: (context, controller) {
              return _buildTutorialBubble(
                context: context,
                image: CrayongImages.proud,
                title: "마음에 드는 동화책 고르기",
                description: "여기 있는 동화책 중 하나를 콕 눌러 봐!\n내가 읽어 주기도 하고, 네 마음대로\n이야기와 그림을 바꿀 수도 있어!",
                isLast: true,
                onNext: () => controller.next(),
              );
            },
          ),
        ],
      ),
    ];
  }

  Widget _buildTutorialBubble({
    required BuildContext context,
    required String image,
    required String title,
    required String description,
    required VoidCallback onNext,
    bool isLast = false,
  }) {
    final screenSize = MediaQuery.of(context).size;
    final crayongHeight = (screenSize.height * 0.34).clamp(180.0, 320.0);

    return Material(
      color: Colors.transparent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(image, height: crayongHeight, fit: BoxFit.contain),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                decoration: AppDecorations.sticker(
                  color: AppColors.secondaryDark,
                  shadowColor: const Color(0xFF457A36),
                  radius: 20,
                  depth: 3,
                ),
                child: Text('크레용', style: AppTextStyles.labelLarge(color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(width: 14),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: (screenSize.width * 0.45).clamp(260.0, 380.0),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.headingMedium()),
                  const SizedBox(height: 8),
                  Text(description, style: AppTextStyles.bodyMedium(color: AppColors.textPrimary)),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: onNext,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      ),
                      child: Text(isLast ? "동화 속으로!" : "다음으로"),
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