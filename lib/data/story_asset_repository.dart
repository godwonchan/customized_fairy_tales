import 'dart:convert';
import 'package:flutter/services.dart';
import '../screens/fairy_tale_list_screen.dart';
import '../screens/tale_reading_screen.dart';

class StoryAssetRepository {
  static Future<TaleBook> loadTaleBook(FairyTale tale) async {
    final jsonPath = _resolveStoryJsonPath(tale);
    print('JSON PATH = $jsonPath');

    final raw = await rootBundle.loadString(jsonPath);
    print('JSON LOAD SUCCESS');
    print(raw);

    final Map<String, dynamic> data = jsonDecode(raw);

    final pages = (data['pages'] as List<dynamic>).map((item) {
      final map = item as Map<String, dynamic>;
      return TalePage(
        pageNumber: map['pageNumber'] as int,
        text: (map['text'] ?? '').toString(),
        imagePath: (map['imagePath'] ?? '').toString(),
        highlightText: map['highlightText']?.toString(),
      );
    }).toList();

    return TaleBook(
      tale: tale,
      pages: pages,
    );
  }

  static String resolveCoverPath(FairyTale tale) {
    final key =
        '${tale.title} ${tale.originalTitle ?? ''} ${tale.sourceFolder ?? ''}'
            .toLowerCase();

    if (key.contains('snow') || key.contains('백설')) {
      return 'assets/cover.png';
    }

    return 'assets/cover.png';
  }

  static String _resolveStoryJsonPath(FairyTale tale) {
    final key =
        '${tale.title} ${tale.originalTitle ?? ''} ${tale.sourceFolder ?? ''}'
            .toLowerCase();

    if (key.contains('snow') || key.contains('백설')) {
      return 'assets/book_001_Snow_White/story_data.json';
    }

    return 'assets/book_001_Snow_White/story_data.json';
  }
}