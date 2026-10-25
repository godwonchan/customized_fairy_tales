import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FontSizeProvider extends ChangeNotifier {
  static const _prefsKey = 'app_font_size';
  static const List<String> options = ['작게', '중간', '크게'];
  static const Map<String, double> _scales = {
    '작게': 0.9,
    '중간': 1.0,
    '크게': 1.2,
  };

  String _size = '중간';

  FontSizeProvider() {
    _load();
  }

  String get size => _size;
  double get scale => _scales[_size] ?? 1.0;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && _scales.containsKey(saved) && saved != _size) {
      _size = saved;
      notifyListeners();
    }
  }

  Future<void> setSize(String size) async {
    if (!_scales.containsKey(size) || size == _size) return;
    _size = size;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, size);
  }
}