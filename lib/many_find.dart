import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import 'list.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SimpleBookshelfPage_02(),
    );
  }
}

class SimpleBookshelfPage_02 extends StatefulWidget {
  const SimpleBookshelfPage_02({super.key});

  @override
  State<SimpleBookshelfPage_02> createState() =>
      _SimpleBookshelfPage_02State();
}

class _SimpleBookshelfPage_02State extends State<SimpleBookshelfPage_02> {
  final List<Map<String, dynamic>> books = [
    {
      "title": "지우와 늑대의\n우정 이야기",
      "date": "2026.05.10",
      "image": "lib/assets/girls.png",
      "liked": false,
    },
    {
      "title": "우주를 여행한\n피노키오",
      "date": "2026.05.09",
      "image": "lib/assets/pino.png",
      "liked": false,
    },
    {
      "title": "바닷속 친구들과\n인어공주",
      "date": "2026.05.08",
      "image": "lib/assets/sea_girl.png",
      "liked": false,
    },
    {
      "title": "마법 학교의\n신데렐라",
      "date": "2026.05.07",
      "image": "lib/assets/magic.png",
      "liked": false,
    },
  ];

  @override
  void initState() {
    super.initState();
    loadLikes();
  }

  Future<void> loadLikes() async {
    final prefs = await SharedPreferences.getInstance();

    for (int i = 0; i < books.length; i++) {
      books[i]["liked"] = prefs.getBool("liked_$i") ?? false;
    }

    setState(() {});
  }

  Future<void> saveLike(int index) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      "liked_$index",
      books[index]["liked"],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfffff8fb),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 28,
                vertical: 28,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 70),
                  Padding(
                    padding: const EdgeInsets.only(left: 77),
                    child: Row(
                      children: [
                        _tab("편집", true),
                        const SizedBox(width: 754),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const StoryHomePage(),
                              ),
                            );
                          },
                          child: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Color(0xff8a63df),
                              size: 26,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: books.asMap().entries.map((entry) {
                          final int index = entry.key;
                          final Map<String, dynamic> book = entry.value;

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: SizedBox(
                              width: 220,
                              height: 430,
                              child: _bookCard(book, index),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(String text, bool selected) {
    return Container(
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.symmetric(
        horizontal: 28,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: selected ? const Color(0xff8a63df) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        text,
        style: TextStyle(
          color: selected ? Colors.white : const Color(0xff2f2f2f),
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _bookCard(Map<String, dynamic> book, int index) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 250,
            margin: const EdgeInsets.all(10),
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                book["image"],
                fit: BoxFit.cover,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          book["title"],
                          style: const TextStyle(
                            fontSize: 18,
                            height: 1.45,
                            fontWeight: FontWeight.w800,
                            color: Color(0xff333333),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          setState(() {
                            books[index]["liked"] = !books[index]["liked"];
                          });

                          await saveLike(index);
                        },
                        child: Icon(
                          book["liked"]
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: book["liked"]
                              ? const Color(0xff8a63df)
                              : const Color(0xffc5b4ec),
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    book["date"],
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xff9b9b9b),
                      fontWeight: FontWeight.w600,
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