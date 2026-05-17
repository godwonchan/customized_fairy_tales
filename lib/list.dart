import 'package:flutter/material.dart';
import 'many_find.dart';
import 'main.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SimpleBookshelfPage(),
    );
  }
}

class SimpleBookshelfPage extends StatelessWidget {
  const SimpleBookshelfPage({super.key});

  final books = const [
    {
      "title": "지우와 늑대의\n우정 이야기",
      "date": "2026.05.10",
      "image": "lib/assets/girls.png",
    },
    {
      "title": "우주를 여행한\n피노키오",
      "date": "2026.05.09",
      "image": "lib/assets/pino.png",
    },
    {
      "title": "바닷속 친구들과\n인어공주",
      "date": "2026.05.08",
      "image": "lib/assets/sea_girl.png",
    },
    {
      "title": "마법 학교의\n신데렐라",
      "date": "2026.05.07",
      "image": "lib/assets/magic.png",
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfffff8fb),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 70),

                  Padding(
                    padding: const EdgeInsets.only(left: 77),
                    child: Row(
                      children: [
                        _tab("전체", true),
                        _tab("내가 만든 이야기", false),
                        _tab("좋아하는 이야기", false),

                        const SizedBox(width: 402),

                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const StoryHomePage(),
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

                  const SizedBox(height: 1),

                  Expanded(
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: books
                            .map(
                              (book) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                child: SizedBox(
                                  width: 220,
                                  height: 430,
                                  child: _bookCard(book),
                                ),
                              ),
                            )
                            .toList(),
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
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
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

  Widget _bookCard(Map<String, String> book) {
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
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                book["image"]!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book["title"]!,
                    style: const TextStyle(
                      fontSize: 18,
                      height: 1.45,
                      fontWeight: FontWeight.w800,
                      color: Color(0xff333333),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    book["date"]!,
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