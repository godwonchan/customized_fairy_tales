import 'package:flutter/material.dart';
import 'fairy_tale_list_screen.dart';
import 'tale_reading_screen.dart';
import '../widgets/story_image_view.dart';

class FairyTaleDetailScreen extends StatelessWidget {
  final FairyTale tale;

  const FairyTaleDetailScreen({
    super.key,
    required this.tale,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF3D2C8D),
        elevation: 0,
        title: const Text('동화 상세'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                height: 260,
                decoration: BoxDecoration(
                  color: tale.cardColor,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: StoryImageView(
                    imagePath: tale.imagePath,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                tale.title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF3D2C8D),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                tale.description,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.6,
                  color: Colors.grey[700],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TaleReadingScreen(
                          tale: tale,
                          initialPage: 0,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7E57C2),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('이 동화 읽기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}