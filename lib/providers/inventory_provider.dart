import 'package:flutter/foundation.dart';

import '../models/rpg_inventory_item.dart';

/// 인벤토리(가방) 상태. RpgPlayScreen 범위에서 생성해 사용.
class InventoryProvider extends ChangeNotifier {
  final List<InventoryItem> _items = [];

  /// 가장 최근에 사용(장착)한 아이템 → 장면 이미지에 합성됨.
  InventoryItem? lastUsedItem;

  List<InventoryItem> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  int get length => _items.length;

  void add(InventoryItem item) {
    _items.add(item);
    notifyListeners();
  }

  void remove(String id) {
    _items.removeWhere((e) => e.id == id);
    if (lastUsedItem?.id == id) lastUsedItem = null;
    notifyListeners();
  }

  void markUsed(InventoryItem item) {
    lastUsedItem = item;
    notifyListeners();
  }

  void clear() {
    _items.clear();
    lastUsedItem = null;
    notifyListeners();
  }
}
