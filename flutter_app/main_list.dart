import 'package:flutter/material.dart';
import 'main.dart';
import 'many_find.dart';

class MainListPage_01 extends StatelessWidget {
  const MainListPage_01({super.key});

  final List<Map<String, String>> books = const [
    {
      "title": "빨간 망토",
      "image": "lib/assets/girls.png",
    },
    {
      "title": "아기 돼지 삼 형제",
      "image": "lib/assets/pino.png",
    },
    {
      "title": "백설공주",
      "image": "lib/assets/sea_girl.png",
    },
    {
      "title": "피노키오",
      "image": "lib/assets/pino.png",
    },
    {
      "title": "신데렐라",
      "image": "lib/assets/magic.png",
    },
    {
      "title": "인어공주",
      "image": "lib/assets/sea_girl.png",
    },
    {
      "title": "헨젤과 그레텔",
      "image": "lib/assets/girls.png",
    },
    {
      "title": "브레멘 음악대",
      "image": "lib/assets/girls.png",
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfffff8fb),
      body: SafeArea(
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
                    _categoryTabs(),
                    const SizedBox(height: 24),

                    Expanded(
                      child: GridView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: books.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 22,
                          childAspectRatio: 1.05,
                        ),
                        itemBuilder: (context, index) {
                          return _bookCard(
                            title: books[index]["title"]!,
                            imagePath: books[index]["image"]!,
                            selected: index == 0,
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
              color: selected ? const Color(0xff8a63df) : const Color(0xff77727f),
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
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const StoryHomePage(),
              ),
            );
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

        Container(
          width: 480,
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          child: const Row(
            children: [
              Icon(Icons.search_rounded, color: Color(0xff8a63df), size: 28),
              SizedBox(width: 14),
              Text(
                "원하는 동화를 검색해보세요",
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xffaaa4b3),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
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
  }) {
    return Container(
  
decoration: BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(22),
  border: Border.all(
    color: selected
        ? const Color(0xff9d73ff)
        : const Color(0xffffffffff),
    width: selected ? 2.2 : 1.4,
  ),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withOpacity(0.20),
      blurRadius: 18,
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
              const Positioned(
                top: 10,
                right: 10,
                child: Icon(
                  Icons.favorite_border_rounded,
                  color: Colors.white,
                  size: 30,
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