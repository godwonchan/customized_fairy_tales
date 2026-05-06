import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '동화 앱',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'NotoSansKR',
        scaffoldBackgroundColor: const Color(0xFFF8F4FF),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB39DDB)),
        // 화면 전환 애니메이션 기본 설정
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      home: const FairyTaleListScreen(),
    );
  }
}

// ───────────────────────── 화면 크기 헬퍼 ─────────────────────────

class ScreenSize {
  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= 600;

  static bool isLargeTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= 900;

  static int gridColumns(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 900) return 5;
    if (width >= 600) return 4;
    return 2;
  }

  static double horizontalPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 900) return 48;
    if (width >= 600) return 32;
    return 16;
  }

  static double titleFontSize(BuildContext context) =>
      isTablet(context) ? 28 : 22;

  static double cardTitleFontSize(BuildContext context) =>
      isTablet(context) ? 15 : 13;

  static double tabFontSize(BuildContext context) =>
      isTablet(context) ? 15 : 13;

  static double searchBarWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 900) return 320;
    if (width >= 600) return 260;
    return 200;
  }
}

// ───────────────────────── 데이터 모델 ─────────────────────────

class FairyTale {
  final String title;
  final String imagePath;
  final Color cardColor;
  final String category;
  final String description;
  final String theme;
  final String ageRange;
  final String wordCount;
  bool isFavorite;

  FairyTale({
    required this.title,
    required this.imagePath,
    required this.cardColor,
    required this.category,
    required this.description,
    required this.theme,
    required this.ageRange,
    required this.wordCount,
    this.isFavorite = false,
  });
}

// ───────────────────────── 샘플 데이터 ─────────────────────────

final List<FairyTale> sampleTales = [
  FairyTale(
    title: '빨간 망토',
    imagePath: 'assets/red_riding_hood.png',
    cardColor: const Color(0xFFFFCDD2),
    category: '고전 동화',
    description: '숲 속 마을에 사는 빨간 망토 소녀가 할미니에 선물을 전하러 가는 길에 늑대를 만나면서 벌어지는 이야기',
    theme: '용기, 지혜',
    ageRange: '5~9세',
    wordCount: '약 2,400자',
    isFavorite: false,
  ),
  FairyTale(
    title: '아기 돼지 삼 형제',
    imagePath: 'assets/three_pigs.png',
    cardColor: const Color(0xFFFFE0B2),
    category: '고전 동화',
    description: '세 마리 아기 돼지가 각자의 방법으로 집을 짓고 늑대로부터 살아남는 이야기',
    theme: '협동, 지혜',
    ageRange: '4~8세',
    wordCount: '약 1,800자',
    isFavorite: true,
  ),
  FairyTale(
    title: '백설공주',
    imagePath: 'assets/snow_white.png',
    cardColor: const Color(0xFFE1F5FE),
    category: '고전 동화',
    description: '마음씨 착한 백설공주와 일곱 난쟁이, 그리고 질투에 사로잡힌 마녀의 이야기',
    theme: '선함, 우정',
    ageRange: '5~10세',
    wordCount: '약 3,000자',
    isFavorite: false,
  ),
  FairyTale(
    title: '피노키오',
    imagePath: 'assets/pinocchio.png',
    cardColor: const Color(0xFFFFF9C4),
    category: '창작 동화',
    description: '나무로 만들어진 인형 피노키오가 진짜 사람이 되기 위해 모험을 떠나는 이야기',
    theme: '정직, 성장',
    ageRange: '6~10세',
    wordCount: '약 3,500자',
    isFavorite: true,
  ),
  FairyTale(
    title: '인어공주',
    imagePath: 'assets/little_mermaid.png',
    cardColor: const Color(0xFFE8EAF6),
    category: '고전 동화',
    description: '바닷속 인어공주가 인간 세계를 동경하며 사랑을 찾아 떠나는 아름다운 이야기',
    theme: '사랑, 희생',
    ageRange: '7~12세',
    wordCount: '약 4,000자',
    isFavorite: true,
  ),
  FairyTale(
    title: '신데렐라',
    imagePath: 'assets/cinderella.png',
    cardColor: const Color(0xFFF3E5F5),
    category: '고전 동화',
    description: '착하고 부지런한 신데렐라가 요정의 도움으로 왕자님을 만나게 되는 이야기',
    theme: '희망, 친절',
    ageRange: '5~10세',
    wordCount: '약 2,800자',
    isFavorite: true,
  ),
  FairyTale(
    title: '헨젤과 그레텔',
    imagePath: 'assets/hansel_gretel.png',
    cardColor: const Color(0xFFE8F5E9),
    category: '고전 동화',
    description: '숲속에서 길을 잃은 남매가 과자로 만든 집을 발견하고 마녀와 맞서는 이야기',
    theme: '용기, 형제애',
    ageRange: '5~9세',
    wordCount: '약 2,600자',
    isFavorite: false,
  ),
  FairyTale(
    title: '브레멘 음악대',
    imagePath: 'assets/bremen.png',
    cardColor: const Color(0xFFFCE4EC),
    category: '고전 동화',
    description: '늙어서 버림받은 동물들이 함께 브레멘으로 여행을 떠나는 우정 가득한 이야기',
    theme: '우정, 협동',
    ageRange: '5~9세',
    wordCount: '약 2,200자',
    isFavorite: false,
  ),
];

const List<String> categories = ['전체', '인기', '고전 동화', '창작 동화', '판타지', '우정', '모험'];

// ═══════════════════════════════════════════════════════════════
//  목록 화면
// ═══════════════════════════════════════════════════════════════

class FairyTaleListScreen extends StatefulWidget {
  const FairyTaleListScreen({super.key});

  @override
  State<FairyTaleListScreen> createState() => _FairyTaleListScreenState();
}

class _FairyTaleListScreenState extends State<FairyTaleListScreen> {
  int _selectedCategoryIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  List<FairyTale> _tales = List.from(sampleTales);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleFavorite(int index) {
    setState(() {
      _tales[index].isFavorite = !_tales[index].isFavorite;
    });
  }

  void _onSearch(String value) {
    setState(() {
      _tales = sampleTales.where((t) => t.title.contains(value)).toList();
    });
  }

  // ── 상세 페이지로 이동 (Hero 애니메이션 포함) ──
  void _goToDetail(FairyTale tale) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, animation, __) => FairyTaleDetailScreen(tale: tale),
        transitionsBuilder: (_, animation, __, child) {
          // 오른쪽에서 슬라이드 + 페이드 효과
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            _buildCategoryTabs(context),
            const SizedBox(height: 20),
            Expanded(child: _buildGrid(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isTablet = ScreenSize.isTablet(context);
    final hPadding = ScreenSize.horizontalPadding(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(hPadding, 16, hPadding, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('02 동화 목록',
              style: TextStyle(fontSize: isTablet ? 14 : 12, color: Colors.grey[500])),
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
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Icon(Icons.chevron_left, color: const Color(0xFF7E57C2), size: isTablet ? 28 : 22),
                ),
              ),
              const SizedBox(width: 12),
              Text('동화 목록',
                  style: TextStyle(
                    fontSize: ScreenSize.titleFontSize(context),
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF3D2C8D),
                    letterSpacing: -0.5,
                  )),
              const Spacer(),
              Container(
                width: ScreenSize.searchBarWidth(context),
                height: isTablet ? 46 : 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearch,
                  style: TextStyle(fontSize: isTablet ? 15 : 13),
                  decoration: InputDecoration(
                    hintText: '원하는 동화를 검색해보세요',
                    hintStyle: TextStyle(fontSize: isTablet ? 14 : 12, color: Colors.grey[400]),
                    prefixIcon: Icon(Icons.search, size: isTablet ? 22 : 18, color: Colors.grey[400]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs(BuildContext context) {
    final isTablet = ScreenSize.isTablet(context);
    final hPadding = ScreenSize.horizontalPadding(context);

    return SizedBox(
      height: isTablet ? 44 : 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: hPadding),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final bool isSelected = _selectedCategoryIndex == index;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategoryIndex = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 16, vertical: isTablet ? 10 : 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF7E57C2) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: isSelected ? const Color(0xFF7E57C2).withOpacity(0.3) : Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                categories[index],
                style: TextStyle(
                  fontSize: ScreenSize.tabFontSize(context),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? Colors.white : Colors.grey[600],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    final hPadding = ScreenSize.horizontalPadding(context);

    return GridView.builder(
      padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: 4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: ScreenSize.gridColumns(context),
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.82,
      ),
      itemCount: _tales.length,
      itemBuilder: (context, index) => _buildTaleCard(context, index),
    );
  }

  Widget _buildTaleCard(BuildContext context, int index) {
    final tale = _tales[index];
    final isTablet = ScreenSize.isTablet(context);

    return GestureDetector(
      onTap: () => _goToDetail(tale), // ← 상세 페이지로 이동
      child: Hero(
        tag: 'tale_${tale.title}', // Hero 애니메이션 태그
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        child: Container(
                          width: double.infinity,
                          color: tale.cardColor,
                          child: Center(
                            child: Icon(Icons.auto_stories, size: isTablet ? 80 : 60, color: tale.cardColor.withOpacity(0.4)),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8, right: 8,
                        child: GestureDetector(
                          onTap: () => _toggleFavorite(index),
                          child: Container(
                            width: isTablet ? 36 : 30,
                            height: isTablet ? 36 : 30,
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.85), shape: BoxShape.circle),
                            child: Icon(
                              tale.isFavorite ? Icons.favorite : Icons.favorite_border,
                              size: isTablet ? 20 : 16,
                              color: tale.isFavorite ? const Color(0xFFE91E63) : Colors.grey[400],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(isTablet ? 12 : 10, isTablet ? 10 : 8, isTablet ? 12 : 10, isTablet ? 12 : 10),
                  child: Text(
                    tale.title,
                    style: TextStyle(fontSize: ScreenSize.cardTitleFontSize(context), fontWeight: FontWeight.w600, color: const Color(0xFF3D2C8D)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  상세 화면
// ═══════════════════════════════════════════════════════════════

class FairyTaleDetailScreen extends StatefulWidget {
  final FairyTale tale;

  const FairyTaleDetailScreen({super.key, required this.tale});

  @override
  State<FairyTaleDetailScreen> createState() => _FairyTaleDetailScreenState();
}

class _FairyTaleDetailScreenState extends State<FairyTaleDetailScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.tale.isFavorite;

    // 콘텐츠 등장 애니메이션
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = ScreenSize.isTablet(context);
    final tale = widget.tale;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      body: SafeArea(
        child: isTablet ? _buildTabletLayout(context, tale) : _buildPhoneLayout(context, tale),
      ),
    );
  }

  // ── 태블릿 레이아웃 (좌우 분할) ──
  Widget _buildTabletLayout(BuildContext context, FairyTale tale) {
    return Row(
      children: [
        // 왼쪽 — 이미지
        Expanded(
          flex: 5,
          child: Hero(
            tag: 'tale_${tale.title}',
            child: Container(
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: tale.cardColor,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Center(
                child: Icon(Icons.auto_stories, size: 120, color: tale.cardColor.withOpacity(0.4)),
              ),
            ),
          ),
        ),
        // 오른쪽 — 정보
        Expanded(
          flex: 5,
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: _buildInfoPanel(context, tale, isTablet: true),
            ),
          ),
        ),
      ],
    );
  }

  // ── 폰 레이아웃 (상하 분할) ──
  Widget _buildPhoneLayout(BuildContext context, FairyTale tale) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 이미지
          Stack(
            children: [
              Hero(
                tag: 'tale_${tale.title}',
                child: Container(
                  width: double.infinity,
                  height: 260,
                  color: tale.cardColor,
                  child: Center(
                    child: Icon(Icons.auto_stories, size: 100, color: tale.cardColor.withOpacity(0.4)),
                  ),
                ),
              ),
              // 뒤로가기 버튼
              Positioned(
                top: 12, left: 16,
                child: _backButton(),
              ),
              // 하트 버튼
              Positioned(
                top: 12, right: 16,
                child: _favoriteButton(),
              ),
            ],
          ),
          FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: _buildInfoPanel(context, tale, isTablet: false),
            ),
          ),
        ],
      ),
    );
  }

  // ── 공통 정보 패널 ──
  Widget _buildInfoPanel(BuildContext context, FairyTale tale, {required bool isTablet}) {
    return Padding(
      padding: EdgeInsets.all(isTablet ? 32 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 태블릿일 때만 상단 버튼들 표시
          if (isTablet) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_backButton(), _favoriteButton()],
            ),
            const SizedBox(height: 24),
          ],

          // 브레드크럼
          Text('03 동화 상세',
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 12),

          // 제목
          Text(
            tale.title,
            style: TextStyle(
              fontSize: isTablet ? 32 : 24,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF3D2C8D),
            ),
          ),
          const SizedBox(height: 12),

          // 카테고리 뱃지
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFEDE7F6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              tale.category,
              style: const TextStyle(fontSize: 12, color: Color(0xFF7E57C2), fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 20),

          // 설명
          Text(
            tale.description,
            style: TextStyle(
              fontSize: isTablet ? 16 : 14,
              color: Colors.grey[700],
              height: 1.7,
            ),
          ),
          const SizedBox(height: 24),

          // 정보 카드 (주제 / 권장 연령 / 글자 수)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                _infoItem('주제', tale.theme),
                _divider(),
                _infoItem('권장 연령', tale.ageRange),
                _divider(),
                _infoItem('글자 수', tale.wordCount),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // 버튼들
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7E57C2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: Text('이 동화로 재구성하기', style: TextStyle(fontSize: isTablet ? 17 : 15, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF7E57C2),
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Color(0xFF7E57C2), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('그림으로 동화 만들기', style: TextStyle(fontSize: isTablet ? 17 : 15, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7E57C2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('NEW', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 뒤로가기 버튼 ──
  Widget _backButton() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: const Icon(Icons.chevron_left, color: Color(0xFF7E57C2), size: 22),
      ),
    );
  }

  // ── 하트 버튼 ──
  Widget _favoriteButton() {
    return GestureDetector(
      onTap: () => setState(() => _isFavorite = !_isFavorite),
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Icon(
          _isFavorite ? Icons.favorite : Icons.favorite_border,
          size: 18,
          color: _isFavorite ? const Color(0xFFE91E63) : Colors.grey[400],
        ),
      ),
    );
  }

  // ── 정보 아이템 ──
  Widget _infoItem(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3D2C8D))),
        ],
      ),
    );
  }

  // ── 구분선 ──
  Widget _divider() {
    return Container(width: 1, height: 32, color: Colors.grey[200]);
  }
}