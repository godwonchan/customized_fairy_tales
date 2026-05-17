import 'package:flutter/material.dart';
import 'list.dart';
import 'many_find.dart';
import 'main_list.dart';
import 'etc.dart';

void main() {
  runApp(const StoryMainApp());
}

class StoryMainApp extends StatelessWidget {
  const StoryMainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: StoryHomePage(),
    );
  }
}

class StoryHomePage extends StatelessWidget {
  const StoryHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: Color(0xfffbf5ff),
          image: DecorationImage(
            image: AssetImage("lib/assets/ra.png"),
            fit: BoxFit.cover,
            alignment: Alignment(1.3, 1.0),
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              _sideBar(context),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(34, 32, 34, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _heroText(),

                      const SizedBox(height: 26),

                      _searchBar(),

                      const SizedBox(height: 24),

                      Expanded(
                        child: _menuCards(),
                      ),

                      const SizedBox(height: 18),

                      _bottomStoryBar(),
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

  Widget _sideBar(BuildContext context) {
    return Container(
      width: 120,
      margin: const EdgeInsets.all(22),
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.86),
        borderRadius: BorderRadius.circular(38),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [

          // 홈
          _sideItem(Icons.home_rounded, "홈", true),

          // 동화 목록
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const MainListPage_01(),
                ),
              );
            },
            child: _sideItem(
              Icons.menu_book_rounded,
              "동화 목록",
              false,
            ),
          ),

          // 그린 동화
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const SimpleBookshelfPage(),
                ),
              );
            },
            child: _sideItem(
              Icons.bookmark_border_rounded,
              "그린 동화",
              false,
            ),
          ),

          // 즐겨찾기
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const SimpleBookshelfPage_02(),
                ),
              );
            },
            child: _sideItem(
              Icons.favorite_border_rounded,
              "즐겨찾기",
              false,
            ),
          ),

          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const SettingsPage(),
                ),
              );
            },
            child:    _sideItem(
            Icons.settings_rounded,
            "설정",
            false,
          ),

          ),




          const Spacer(),

          const CircleAvatar(
            radius: 32,
            backgroundColor: Color(0xffffd8bd),
            child: Text(
              "👧",
              style: TextStyle(fontSize: 28),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sideItem(
    IconData icon,
    String text,
    bool selected,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xff8a63df)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              icon,
              color: selected
                  ? Colors.white
                  : const Color(0xff8d8799),
              size: 30,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected
                  ? const Color(0xff8a63df)
                  : const Color(0xff797385),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroText() {
    return Padding(
      padding: const EdgeInsets.only(left: 14, top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "안녕! ✨",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xff25213f),
            ),
          ),

          const SizedBox(height: 16),

          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 40,
                height: 1.15,
                fontWeight: FontWeight.w900,
                color: Color(0xff25213f),
              ),
              children: [
                TextSpan(text: "오늘은 어떤 "),
                TextSpan(
                  text: "이야기",
                  style: TextStyle(
                    color: Color(0xff8a63df),
                  ),
                ),
                TextSpan(text: "를\n만들까? ✨"),
              ],
            ),
          ),

          const SizedBox(height: 18),

          const Text(
            "상상한 이야기가 특별한 동화가 되는 곳",
            style: TextStyle(
              fontSize: 17,
              color: Color(0xff6d6678),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Container(
      margin: const EdgeInsets.only(left: 14),
      width: 430,
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(30),
      ),
      child: const Row(
        children: [
          Expanded(
            child: Text(
              "동화를 검색해보세요",
              style: TextStyle(
                color: Color(0xff9b94aa),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          Icon(
            Icons.search_rounded,
            color: Color(0xff8a63df),
            size: 30,
          ),
        ],
      ),
    );
  }

  Widget _menuCards() {
    return Padding(
      padding: const EdgeInsets.only(right: 80),
      child: Row(
        children: [
          _mainCard(
            "🤖",
            "AI로 새 이야기 만들기",
            "AI가 도와주는 창작으로\n나만의 동화를 만들어보세요",
            const Color(0xff8a63df),
          ),

          const SizedBox(width: 18),

          _mainCard(
            "🎨",
            "그림으로 동화 만들기",
            "그림을 그리고 이야기를\n자동으로 완성해보세요",
            const Color(0xffff7043),
          ),

          const SizedBox(width: 18),

          _mainCard(
            "📖",
            "랜덤 동화 추천",
            "오늘의 기분에 딱 맞는\n동화를 추천해드려요",
            const Color(0xff20a64a),
          ),
        ],
      ),
    );
  }

  Widget _mainCard(
    String emoji,
    String title,
    String desc,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.88),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 44),
              ),
            ),

            const SizedBox(height: 20),

            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              desc,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xff6f6879),
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),

            const Spacer(),

            Align(
              alignment: Alignment.bottomRight,
              child: Icon(
                Icons.arrow_forward_rounded,
                color: color,
                size: 32,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomStoryBar() {
    return Padding(
      padding: const EdgeInsets.only(right: 80),
      child: Container(
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(30),
        ),
        child: const Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: Color(0xff8a63df),
              child: Icon(
                Icons.auto_awesome,
                color: Colors.white,
              ),
            ),

            SizedBox(width: 16),

            Text(
              "오늘의 한 줄 동화",
              style: TextStyle(
                color: Color(0xff8a63df),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),

            SizedBox(width: 20),

            Expanded(
              child: Text(
                "마법 같은 하루가 될 거야, 네가 상상하는 모든 순간이 이야기니까.",
                style: TextStyle(
                  color: Color(0xff5f5a6f),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            Icon(
              Icons.arrow_forward_rounded,
              color: Color(0xff5f5a6f),
            ),
          ],
        ),
      ),
    );
  }
}