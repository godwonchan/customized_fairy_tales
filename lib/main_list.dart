import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import 'many_find.dart';
import 'show.dart';

class MainListPage_01 extends StatefulWidget {
  const MainListPage_01({super.key});

  @override
  State<MainListPage_01> createState() => _MainListPage_01State();
}

class _MainListPage_01State extends State<MainListPage_01> {
  final List<Map<String, String>> books = const [
    {"title": "빨간 망토", "image": "lib/assets/girls.png"},
    {"title": "아기 돼지 삼 형제", "image": "lib/assets/pino.png"},
    {"title": "백설공주", "image": "lib/assets/sea_girl.png"},
    {"title": "피노키오", "image": "lib/assets/pino.png"},
    {"title": "신데렐라", "image": "lib/assets/magic.png"},
    {"title": "인어공주", "image": "lib/assets/sea_girl.png"},
    {"title": "헨젤과 그레텔", "image": "lib/assets/girls.png"},
    {"title": "브레멘 음악대", "image": "lib/assets/girls.png"},
  ];

  int _selectedIndex = -1;
  late List<bool> _favorites;

  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<Map<String, String>> get _filteredBooks {
    if (_searchQuery.isEmpty) return books;
    return books.where((book) {
      return book["title"]!.contains(_searchQuery);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _favorites = List.filled(books.length, false);
    _loadFavorites();

    // ✅ 한글 조합 완성 후 반영되는 리스너 방식
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      for (int i = 0; i < books.length; i++) {
        _favorites[i] = prefs.getBool('favorite_$i') ?? false;
      }
    });
  }

  Future<void> _toggleFavorite(int originalIndex) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _favorites[originalIndex] = !_favorites[originalIndex];
    });
    await prefs.setBool('favorite_$originalIndex', _favorites[originalIndex]);
  }

  void _startSearch() {
    setState(() {
      _isSearching = true;
    });
    Future.delayed(const Duration(milliseconds: 50), () {
      _searchFocusNode.requestFocus();
    });
  }

  void _stopSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
    });
    _searchFocusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfffff8fb),
      body: SafeArea(
        child: GestureDetector(
          onTap: () {
            if (_isSearching) _stopSearch();
          },
          child: Row(
            children: [
              _sideBar(context),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 42, 42, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _topHeader(context),
                      const SizedBox(height: 26),
                      if (!_isSearching) ...[
                        _categoryTabs(),
                        const SizedBox(height: 24),
                      ] else ...[
                        const SizedBox(height: 8),
                      ],
                      Expanded(
                        child: _filteredBooks.isEmpty
                            ? _emptySearchResult()
                            : GridView.builder(
                                padding: EdgeInsets.zero,
                                itemCount: _filteredBooks.length,
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 4,
                                  crossAxisSpacing: 20,
                                  mainAxisSpacing: 22,
                                  childAspectRatio: 1.05,
                                ),
                                itemBuilder: (context, index) {
                                  final book = _filteredBooks[index];
                                  final originalIndex = books.indexWhere(
                                      (b) => b["title"] == book["title"]);

                                  return GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedIndex = originalIndex;
                                      });
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const ShowPage(),
                                        ),
                                      );
                                    },
                                    child: _bookCard(
                                      title: book["title"]!,
                                      imagePath: book["image"]!,
                                      selected: _selectedIndex == originalIndex,
                                      isFavorite: _favorites[originalIndex],
                                      onFavoriteTap: () =>
                                          _toggleFavorite(originalIndex),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptySearchResult() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.search_off_rounded,
            size: 72,
            color: Color(0xffccc6d9),
          ),
          const SizedBox(height: 20),
          Text(
            '"$_searchQuery" 검색 결과가 없어요',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xffaaa4b3),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '다른 동화 제목을 검색해보세요!',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xffccc6d9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sideBar(BuildContext context) {
    return Container(
      width: 110,
      margin: const EdgeInsets.all(18),
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(34),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const StoryHomePage(),
                ),
              );
            },
            child: _sideItem(Icons.home_rounded, "홈", false),
          ),
          _sideItem(Icons.menu_book_rounded, "동화 목록", true),
          _sideItem(Icons.bookmark_border_rounded, "그린 동화", false),
          _sideItem(Icons.star_border_rounded, "그림으로\n만들기", false),
          GestureDetector(
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const SimpleBookshelfPage_02(),
                ),
              );
            },
            child: _sideItem(Icons.favorite_border_rounded, "즐겨찾기", false),
          ),
          _sideItem(Icons.settings_rounded, "설정", false),
          const Spacer(),
          const CircleAvatar(
            radius: 24,
            backgroundColor: Color(0xffffd8bd),
            child: Text("👧", style: TextStyle(fontSize: 22)),
          ),
        ],
      ),
    );
  }

  Widget _sideItem(IconData icon, String text, bool selected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: selected ? const Color(0xff8a63df) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              color: selected ? Colors.white : const Color(0xff77727f),
              size: 26,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              height: 1.15,
              fontWeight: FontWeight.w800,
              color:
                  selected ? const Color(0xff8a63df) : const Color(0xff77727f),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topHeader(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () {
            if (_isSearching) {
              _stopSearch();
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const StoryHomePage(),
                ),
              );
            }
          },
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Color(0xff8a63df),
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 22),
        const Spacer(),
        GestureDetector(
          onTap: _isSearching ? null : _startSearch,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 480,
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: _isSearching
                    ? const Color(0xff8a63df)
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded,
                    color: Color(0xff8a63df), size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: _isSearching
                      ? TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          // ✅ onChanged 제거 - 리스너가 대신 처리
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.search,
                          enableSuggestions: false,
                          autocorrect: false,
                          onEditingComplete: () {},
                          style: const TextStyle(
                            fontSize: 15,
                            color: Color(0xff333333),
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: '동화 제목을 입력하세요',
                            hintStyle: TextStyle(
                              fontSize: 15,
                              color: Color(0xffaaa4b3),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : const Text(
                          "원하는 동화를 검색해보세요",
                          style: TextStyle(
                            fontSize: 15,
                            color: Color(0xffaaa4b3),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                if (_isSearching && _searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _searchQuery = '';
                        _searchController.clear();
                      });
                      _searchFocusNode.requestFocus();
                    },
                    child: const Icon(
                      Icons.cancel_rounded,
                      color: Color(0xffccc6d9),
                      size: 22,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _categoryTabs() {
    final tabs = ["전체", "인기", "고전 동화", "창작 동화", "판타지", "우정", "모험"];

    return Row(
      children: tabs.asMap().entries.map((entry) {
        final selected = entry.key == 0;
        return Container(
          margin: const EdgeInsets.only(right: 14),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? const Color(0xff8a63df) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Text(
            entry.value,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xff333333),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _bookCard({
    required String title,
    required String imagePath,
    required bool selected,
    required bool isFavorite,
    required VoidCallback onFavoriteTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selected ? const Color(0xff8a63df) : Colors.white,
          width: selected ? 3.0 : 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: selected
                ? const Color(0xff8a63df).withOpacity(0.35)
                : Colors.black.withOpacity(0.20),
            blurRadius: selected ? 24 : 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: Image.asset(
                  imagePath,
                  width: double.infinity,
                  height: 165,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: GestureDetector(
                  onTap: onFavoriteTap,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: animation,
                      child: child,
                    ),
                    child: Icon(
                      isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      key: ValueKey(isFavorite),
                      color:
                          isFavorite ? const Color(0xffff4d6d) : Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 16, 14),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: Color(0xff222222),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}