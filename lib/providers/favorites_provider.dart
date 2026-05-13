import 'package:flutter/material.dart';
import '../screens/fairy_tale_list_screen.dart';

class FavoritesProvider extends ChangeNotifier {
  // 즐겨찾기 목록
  final List<FairyTale> _favorites = [];

  List<FairyTale> get favorites => List.unmodifiable(_favorites);

  // 즐겨찾기 여부 확인
  bool isFavorite(FairyTale tale) {
    return _favorites.any((t) => t.title == tale.title);
  }

  // 즐겨찾기 토글
  void toggleFavorite(FairyTale tale) {
    if (isFavorite(tale)) {
      _favorites.removeWhere((t) => t.title == tale.title);
    } else {
      _favorites.add(tale);
    }
    notifyListeners();
  }
}