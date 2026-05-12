import 'package:flutter/material.dart';
import 'fairy_tale_detail_screen.dart';

// ───────────────────────── 화면 크기 헬퍼 ─────────────────────────

class ScreenSize {
  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= 600;

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

final List<FairyTale> sampleTales = [
  FairyTale(title: '빨간 망토', imagePath: 'red_riding_hood.jpeg', cardColor: const Color(0xFFFFCDD2), category: '고전 동화', description: '숲 속 마을에 사는 빨간 망토 소녀가 할머니에 선물을 전하러 가는 길에 늑대를 만나면서 벌어지는 이야기', theme: '용기, 지혜', ageRange: '5~9세', wordCount: '약 2,400자', isFavorite: false),
  FairyTale(title: '아기 돼지 삼 형제', imagePath: 'three_pigs.jpeg', cardColor: const Color(0xFFFFE0B2), category: '고전 동화', description: '세 마리 아기 돼지가 각자의 방법으로 집을 짓고 늑대로부터 살아남는 이야기', theme: '협동, 지혜', ageRange: '4~8세', wordCount: '약 1,800자', isFavorite: true),
  FairyTale(title: '백설공주', imagePath: 'book_001_Snow_White/Snow_White_cover.png', cardColor: const Color(0xFFE1F5FE), category: '고전 동화', description: '마음씨 착한 백설공주와 일곱 난쟁이, 그리고 질투에 사로잡힌 마녀의 이야기', theme: '선함, 우정', ageRange: '5~10세', wordCount: '약 3,000자', isFavorite: false),
  FairyTale(title: '피노키오', imagePath: 'pinocchio.jpeg', cardColor: const Color(0xFFFFF9C4), category: '창작 동화', description: '나무로 만들어진 인형 피노키오가 진짜 사람이 되기 위해 모험을 떠나는 이야기', theme: '정직, 성장', ageRange: '6~10세', wordCount: '약 3,500자', isFavorite: true),
  FairyTale(title: '인어공주', imagePath: 'little_mermaid.jpeg', cardColor: const Color(0xFFE8EAF6), category: '고전 동화', description: '바닷속 인어공주가 인간 세계를 동경하며 사랑을 찾아 떠나는 아름다운 이야기', theme: '사랑, 희생', ageRange: '7~12세', wordCount: '약 4,000자', isFavorite: true),
  FairyTale(title: '신데렐라', imagePath: 'cinderella.jpeg', cardColor: const Color(0xFFF3E5F5), category: '고전 동화', description: '착하고 부지런한 신데렐라가 요정의 도움으로 왕자님을 만나게 되는 이야기', theme: '희망, 친절', ageRange: '5~10세', wordCount: '약 2,800자', isFavorite: true),
  FairyTale(title: '헨젤과 그레텔', imagePath: 'hansel_gretel.jpeg', cardColor: const Color(0xFFE8F5E9), category: '고전 동화', description: '숲속에서 길을 잃은 남매가 과자로 만든 집을 발견하고 마녀와 맞서는 이야기', theme: '용기, 형제애', ageRange: '5~9세', wordCount: '약 2,600자', isFavorite: false),
  FairyTale(title: '브레멘 음악대', imagePath: 'bremen.jpeg', cardColor: const Color(0xFFFCE4EC), category: '고전 동화', description: '늙어서 버림받은 동물들이 함께 브레멘으로 여행을 떠나는 우정 가득한 이야기', theme: '우정, 협동', ageRange: '5~9세', wordCount: '약 2,200자', isFavorite: false),
];

const List<String> categories = ['전체', '인기', '고전 동화', '창작 동화', '판타지', '우정', '모험'];

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
    setState(() => _tales[index].isFavorite = !_tales[index].isFavorite);
  }

  void _onSearch(String value) {
    setState(() => _tales = sampleTales.where((t) => t.title.contains(value)).toList());
  }

  void _goToDetail(FairyTale tale) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, animation, _) => FairyTaleDetailScreen(tale: tale),
        transitionsBuilder: (_, animation, _, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
                .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
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
          Text('02 동화 목록', style: TextStyle(fontSize: isTablet ? 14 : 12, color: Colors.grey[500])),
          const SizedBox(height: 8),
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.maybePop(context),
                child: Container(
                  width: isTablet ? 44 : 36, height: isTablet ? 44 : 36,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))]),
                  child: Icon(Icons.chevron_left, color: const Color(0xFF7E57C2), size: isTablet ? 28 : 22),
                ),
              ),
              const SizedBox(width: 12),
              Text('동화 목록', style: TextStyle(fontSize: ScreenSize.titleFontSize(context), fontWeight: FontWeight.w700, color: const Color(0xFF3D2C8D), letterSpacing: -0.5)),
              const Spacer(),
              Container(
                width: ScreenSize.searchBarWidth(context), height: isTablet ? 46 : 38,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 8, offset: const Offset(0, 2))]),
                child: TextField(
                  controller: _searchController, onChanged: _onSearch,
                  style: TextStyle(fontSize: isTablet ? 15 : 13),
                  decoration: InputDecoration(
                    hintText: '원하는 동화를 검색해보세요',
                    hintStyle: TextStyle(fontSize: isTablet ? 14 : 12, color: Colors.grey[400]),
                    prefixIcon: Icon(Icons.search, size: isTablet ? 22 : 18, color: Colors.grey[400]),
                    border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
        separatorBuilder: (_, _) => const SizedBox(width: 8),
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
                boxShadow: [BoxShadow(
                  color: isSelected ? const Color(0xFF7E57C2).withOpacity(0.3) : Colors.black.withOpacity(0.06),
                  blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Text(categories[index], style: TextStyle(
                fontSize: ScreenSize.tabFontSize(context),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? Colors.white : Colors.grey[600],
              )),
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
        crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: 0.82,
      ),
      itemCount: _tales.length,
      itemBuilder: (context, index) => _buildTaleCard(context, index),
    );
  }

  Widget _buildTaleCard(BuildContext context, int index) {
    final tale = _tales[index];
    final isTablet = ScreenSize.isTablet(context);
    return GestureDetector(
      onTap: () => _goToDetail(tale),
      child: Hero(
        tag: 'tale_${tale.title}',
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 12, offset: const Offset(0, 4))]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        child: Image.asset('assets/${tale.imagePath}', fit: BoxFit.cover,
                          width: double.infinity, height: double.infinity,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: tale.cardColor,
                            child: Center(child: Icon(Icons.auto_stories, size: isTablet ? 80 : 60, color: tale.cardColor.withOpacity(0.4))),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8, right: 8,
                        child: GestureDetector(
                          onTap: () => _toggleFavorite(index),
                          child: Container(
                            width: isTablet ? 36 : 30, height: isTablet ? 36 : 30,
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.85), shape: BoxShape.circle),
                            child: Icon(tale.isFavorite ? Icons.favorite : Icons.favorite_border,
                              size: isTablet ? 20 : 16,
                              color: tale.isFavorite ? const Color(0xFFE91E63) : Colors.grey[400]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(isTablet ? 12 : 10, isTablet ? 10 : 8, isTablet ? 12 : 10, isTablet ? 12 : 10),
                  child: Text(tale.title,
                    style: TextStyle(fontSize: ScreenSize.cardTitleFontSize(context), fontWeight: FontWeight.w600, color: const Color(0xFF3D2C8D)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}