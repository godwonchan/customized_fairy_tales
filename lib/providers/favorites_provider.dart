import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/fairy_tale_list_screen.dart';

class FavoritesProvider extends ChangeNotifier {
  static const _prefsKey = 'favorite_tales';

  final List<FairyTale> _favorites = [];

  FavoritesProvider() {
    _load();
  }

  List<FairyTale> get favorites => List.unmodifiable(_favorites);

  bool isFavorite(FairyTale tale) {
    return _favorites.any((t) => t.title == tale.title);
  }

  void toggleFavorite(FairyTale tale) {
    if (isFavorite(tale)) {
      _favorites.removeWhere((t) => t.title == tale.title);
    } else {
      _favorites.add(tale.copyWith(isFavorite: true));
    }
    notifyListeners();
    _save();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final list = jsonDecode(raw) as List<dynamic>;
      _favorites
        ..clear()
        ..addAll(list.map((e) => _fromJson(e as Map<String, dynamic>)));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_favorites.map(_toJson).toList()));
    } catch (_) {}
  }

  Map<String, dynamic> _toJson(FairyTale t) => {
        'id': t.id,
        'title': t.title,
        'description': t.description,
        'imagePath': t.imagePath,
        'cardColor': t.cardColor.toARGB32(),
        'storyId': t.storyId,
        'isUserStory': t.isUserStory,
        'category': t.category,
        'sourceFolder': t.sourceFolder,
        'originalTitle': t.originalTitle,
      };

  FairyTale _fromJson(Map<String, dynamic> j) => FairyTale(
        id: j['id'] as String?,
        title: (j['title'] ?? '제목 없음') as String,
        description: (j['description'] ?? '') as String,
        imagePath: (j['imagePath'] ?? '') as String,
        cardColor: Color((j['cardColor'] ?? 0xFFFFF3DC) as int),
        isFavorite: true,
        storyId: j['storyId'] as int?,
        isUserStory: (j['isUserStory'] ?? false) as bool,
        category: (j['category'] ?? '동화') as String,
        sourceFolder: j['sourceFolder'] as String?,
        originalTitle: j['originalTitle'] as String?,
      );
}