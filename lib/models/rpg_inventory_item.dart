import 'dart:typed_data';

enum ItemType { weapon, item, animal, etc }

class InventoryItem {
  final String id;
  final String name;
  final Uint8List imageBytes;
  final ItemType type;
  final String description; // Phase2: /rpg/describe 결과 채울 자리

  InventoryItem({
    required this.id,
    required this.name,
    required this.imageBytes,
    this.type = ItemType.item,
    this.description = '',
  });

  String get typeLabel {
    switch (type) {
      case ItemType.weapon:
        return '무기';
      case ItemType.animal:
        return '동물';
      case ItemType.item:
        return '아이템';
      case ItemType.etc:
        return '물건';
    }
  }
}
