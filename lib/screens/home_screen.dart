import 'package:flutter/material.dart';
import 'fairy_tale_list_screen.dart';
import 'fairy_tale_detail_screen.dart';
import 'my_stories_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/cover_asset_helper.dart';
import '../widgets/dh_ui.dart';
import '../widgets/story_image_view.dart';
import 'creation/custom_story_create_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialIndex = 0, this.initialMyStoriesTab = 0});

  final int initialIndex;
  final int initialMyStoriesTab;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _selectedIndex = widget.initialIndex;
  late int _myStoriesTab = widget.initialMyStoriesTab;

  // 아래 메뉴: 홈 화면과 같은 아이콘(assets/toy_shelf/icons)과 이름
  static const _tabs = [
    {'icon': 'home', 'label': '홈'},
    {'icon': 'open_book', 'label': '동화 목록'},
    {'icon': 'heart_book', 'label': '내 이야기'},
    {'icon': 'settings', 'label': '설정'},
  ];

  void _selectTab(int index, {int myStoriesTab = 0}) {
    setState(() {
      _selectedIndex = index;
      _myStoriesTab = myStoriesTab;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_selectedIndex == 0) {
      // 홈: 배경과 아래 메뉴까지 홈 화면이 직접 그린다 (장난감 책장 시안)
      body = HomeScreen(
        onTabChange: _selectTab,
        onOpenFavorites: () => _selectTab(2, myStoriesTab: 2),
      );
    } else {
      final pages = [
        const SizedBox.shrink(),
        const FairyTaleListScreen(),
        MyStoriesScreen(key: ValueKey(_myStoriesTab), initialTab: _myStoriesTab),
        const SettingsScreen(),
      ];
      body = Column(
        children: [
          Expanded(child: pages[_selectedIndex]),
          Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: _buildDock())),
        ],
      );
    }

    return ToyScaffold(
      backgroundColor: AppColors.background,
      // 홈의 검색창을 눌러 키보드가 올라와도 화면을 줄이지 않는다 (줄이면 책·아래 메뉴가 넘침, 검색창은 맨 위라 가려지지 않음)
      resizeToAvoidBottomInset: false,
      body: body,
    );
  }

  Widget _buildDock() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0DA),
            borderRadius: BorderRadius.circular(44),
            border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 3),
            boxShadow: const [
              BoxShadow(color: Color(0xFFE3C79E), offset: Offset(0, 5)),
              BoxShadow(color: Color(0x40A9794A), blurRadius: 8, offset: Offset(0, 9)),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              for (int index = 0; index < _tabs.length; index++) ...[
                if (index > 0) Container(width: 2, height: 44, color: const Color(0xFFDDBF94)),
                Expanded(
                  child: DhPressable(
                    label: '${_tabs[index]['label']} 탭${_selectedIndex == index ? ', 선택됨' : ''}',
                    onTap: () => _selectTab(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: _selectedIndex == index ? const Color(0xFFFFE9A0) : Colors.transparent,
                        borderRadius: BorderRadius.circular(34),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset('assets/toy_shelf/icons/${_tabs[index]['icon']}.png', width: 38, height: 38),
                          Text(_tabs[index]['label']!, maxLines: 1, style: dhText(19, color: const Color(0xFF4E2C15), height: 1.1)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onTabChange, this.onOpenFavorites});

  final ValueChanged<int>? onTabChange;
  final VoidCallback? onOpenFavorites;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _floatController =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true);
  final TextEditingController _searchController = TextEditingController();

  FairyTale? _recommended; // 오늘의 추천: 서버의 원본 동화 (없으면 기본 그림과 제목)

  @override
  void initState() {
    super.initState();
    _loadRecommended();
  }

  @override
  void dispose() {
    _floatController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // 오늘의 추천: 서버의 원본 동화 중 날짜에 따라 한 권 (서버에 못 닿으면 기본 책을 그대로 둠)
  Future<void> _loadRecommended() async {
    try {
      final data = await ApiService.getOriginalStories();
      if (!mounted || data.isEmpty) return;
      final item = data[DateTime.now().day % data.length] as Map<String, dynamic>;
      final title = (item['title'] ?? '').toString();
      if (title.isEmpty) return;
      setState(() {
        _recommended = FairyTale(
          id: 'tale_${item['id']}',
          title: title,
          description: (item['description'] ?? '동화를 읽어보세요.').toString(),
          imagePath: getCoverAssetPath(
            sourceFolder: item['source_folder']?.toString(),
            originalTitle: item['original_title']?.toString(),
            title: title,
          ),
          cardColor: AppColors.primaryLight,
          storyId: item['id'] as int?,
          sourceFolder: item['source_folder']?.toString(),
          originalTitle: item['original_title']?.toString(),
        );
      });
    } catch (e) {
      debugPrint('추천 동화 불러오기 실패 (기본 책 표시): $e');
    }
  }

  Future<void> _openProfile() async {
    await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
  }

  String get _todayLabel {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final now = DateTime.now();
    return '${now.month}월 ${now.day}일 ${weekdays[now.weekday - 1]}요일';
  }

  void _goToTab(int index) {
    if (widget.onTabChange != null) {
      widget.onTabChange!(index);
      return;
    }
    final page = index == 1 ? const FairyTaleListScreen() : const MyStoriesScreen();
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _openFavorites() {
    if (widget.onOpenFavorites != null) {
      widget.onOpenFavorites!();
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => const MyStoriesScreen(initialTab: 2)));
  }

  void _openRecommended() {
    final tale = _recommended;
    if (tale == null) {
      _goToTab(1);
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => FairyTaleDetailScreen(tale: tale)));
  }

  void _navigateToStoryCreation() {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, animation, _) => const CustomStoryCreateScreen(),
        transitionsBuilder: (_, animation, _, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: FadeTransition(opacity: animation, child: child),
        ),
      ),
    );
  }

  // 제목을 책 표지에 맞게 두 줄로 나눔 (띄어쓰기가 있으면 가운데 가까운 곳에서)
  String _twoLines(String title) {
    final t = title.trim();
    if (t.contains('\n') || t.length <= 4) return t;
    final spaces = [for (int i = 0; i < t.length; i++) if (t[i] == ' ') i];
    if (spaces.isEmpty) return t;
    final mid = t.length / 2;
    final cut = spaces.reduce((a, b) => (a - mid).abs() <= (b - mid).abs() ? a : b);
    return '${t.substring(0, cut)}\n${t.substring(cut + 1)}';
  }

  // ── '장난감 책장' 시안(1586×992)과 똑같이 보이도록 시안 그림을 깔고, 그 위에 버튼 자리와 바뀌는 글자만 얹는다 ──
  // (받은 에셋 묶음은 납작한 벡터 재구성본이라 조립하면 시안의 도톰한 점토 질감이 나오지 않는다)
  // 좌표는 모두 시안 픽셀 기준이고, DhDesignCanvas 가 화면 크기에 맞게 통째로 줄이거나 키운다.
  static const String _ts = 'assets/toy_shelf';
  static const Color _ink = Color(0xFF4E2C15); // 시안의 갈색 글씨

  @override
  Widget build(BuildContext context) {
    final rec = _recommended;
    // 시안의 추천 책은 백설공주. 다른 동화가 추천되면 그 표지와 제목으로 덮는다
    final recIsSnowWhite = rec == null || rec.title.replaceAll(' ', '').contains('백설공주');
    return Stack(
      children: [
        // 화면 비율이 시안과 많이 다를 때 남는 곳에 보이는 벽과 탁자
        Positioned.fill(child: Image.asset('$_ts/backgrounds/background_room.png', fit: BoxFit.fill)),
        Positioned.fill(
          child: DhDesignCanvas(
            children: [
              Positioned.fill(child: Image.asset('$_ts/backgrounds/home_full.png', fit: BoxFit.fill, filterQuality: FilterQuality.medium)),

              // 날짜: 그림 속 날짜를 덮고 오늘 날짜를 씀
              DhPatch(
                const Rect.fromLTRB(912, 38, 1124, 81),
                const Color(0xFFFDEAD6),
                radius: 10,
                child: Semantics(
                  label: '오늘은 $_todayLabel',
                  child: ExcludeSemantics(
                    child: FittedBox(fit: BoxFit.scaleDown, child: Text(_todayLabel, maxLines: 1, style: dhText(30, color: _ink))),
                  ),
                ),
              ),
              // 왼쪽 위 이름표: 그림 속 인사말('동화친구님, 안녕하세요')을 덮고 앱 이름표를 씀
              DhPatch(
                const Rect.fromLTRB(150, 39, 448, 84),
                const Color(0xFFE2EDB5),
                radius: 10,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('크레용의 동화 나라', maxLines: 1, style: dhText(34, color: _ink)),
                ),
              ),
              // 오늘의 추천이 백설공주가 아닐 때: 서버 표지와 제목으로 바꿈
              if (!recIsSnowWhite) ...[
                if (rec.storyId != null)
                  Positioned.fromRect(
                    rect: const Rect.fromLTRB(514, 262, 756, 500),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: StoryImageView(imagePath: ApiService.storyPageImageUrl(rec.storyId!, 0), fit: BoxFit.cover),
                    ),
                  ),
                DhPatch(
                  const Rect.fromLTRB(526, 566, 750, 660),
                  const Color(0xFFB6D5F3),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(_twoLines(rec.title), textAlign: TextAlign.center, maxLines: 2, style: dhText(50, color: _ink, height: 1.08)),
                  ),
                ),
              ],

              // 누르는 자리들 (그림 위의 투명 버튼, 누르면 살짝 밝아짐)
              DhHit(const Rect.fromLTRB(73, 756, 421, 925), '시작, 새 동화 만들기', _navigateToStoryCreation, radius: 66),
              DhHit(const Rect.fromLTRB(486, 247, 765, 765), '오늘의 추천 ${rec?.title ?? '백설공주'}', _openRecommended, radius: 44),
              DhHit(const Rect.fromLTRB(765, 247, 1020, 765), '원래 동화를 동화 바꾸기', () => _goToTab(1), radius: 44),
              DhHit(const Rect.fromLTRB(1020, 247, 1279, 765), '읽던 동화 이어서 읽기', () => _goToTab(1), radius: 44),
              DhHit(const Rect.fromLTRB(1279, 247, 1551, 765), '좋아하는 동화 즐겨찾기', _openFavorites, radius: 44),
              DhHit(const Rect.fromLTRB(1183, 26, 1431, 94), '동화 찾기', () => _goToTab(1), radius: 34),
              DhHit(const Rect.fromLTRB(1474, 24, 1558, 106), '내 프로필', _openProfile, radius: 42),
              DhHit(const Rect.fromLTRB(752, 850, 980, 966), '동화 목록 탭', () => _goToTab(1), radius: 40),
              DhHit(const Rect.fromLTRB(986, 850, 1212, 966), '내 이야기 탭', () => _goToTab(2), radius: 40),
              DhHit(const Rect.fromLTRB(1218, 850, 1432, 966), '설정 탭', () => _goToTab(3), radius: 40),
            ],
          ),
        ),
      ],
    );
  }
}
