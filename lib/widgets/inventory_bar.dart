import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/rpg_inventory_item.dart';
import '../providers/inventory_provider.dart';
import '../providers/rpg_game_provider.dart';
import 'item_draw_dialog.dart';

const _kPrimary = Color(0xFF7E57C2);
const _kPrimaryLight = Color(0xFF9575CD);
const _kPill = Color(0xFFEDE7F6);
const _kInk = Color(0xFF3D2C8D);

/// 하단 인벤토리 바. 탭=사용, 길게누르기=삭제, +타일=그리기.
class InventoryBar extends StatelessWidget {
  const InventoryBar({super.key});

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    return Container(
      height: 86,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: _kPrimary.withOpacity(0.07),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('🎒', style: TextStyle(fontSize: 20)),
          ),
          Expanded(
            child: inv.isEmpty
                ? _emptyHint(context)
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: inv.items.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      if (i == inv.items.length) return _addTile(context);
                      return _itemTile(context, inv.items[i], inv.lastUsedItem);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyHint(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text('무기·아이템·동물을 그려서 가방에 담아보세요',
              style: TextStyle(color: Color(0xFFA99FC4), fontSize: 12)),
        ),
        _addTile(context),
      ],
    );
  }

  Widget _addTile(BuildContext context) {
    return GestureDetector(
      onTap: () => _addItem(context),
      child: Container(
        width: 62,
        decoration: BoxDecoration(
          color: _kPill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kPrimaryLight.withOpacity(0.5)),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: _kPrimary, size: 22),
            SizedBox(height: 2),
            Text('그리기',
                style: TextStyle(
                    color: _kPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _itemTile(
      BuildContext context, InventoryItem item, InventoryItem? used) {
    final isUsed = used?.id == item.id;
    return GestureDetector(
      onTap: () => _useItem(context, item),
      onLongPress: () => _confirmDelete(context, item),
      child: Container(
        width: 62,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _kPill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUsed ? _kPrimary : _kPrimaryLight.withOpacity(0.3),
            width: isUsed ? 2.5 : 1,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(item.imageBytes, fit: BoxFit.cover),
            if (isUsed)
              const Positioned(
                top: 3,
                right: 3,
                child: Icon(Icons.check_circle, color: _kPrimary, size: 15),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.white.withOpacity(0.88),
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _kInk,
                      fontSize: 10,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addItem(BuildContext context) async {
    final item = await showDialog<InventoryItem>(
      context: context,
      builder: (_) => const ItemDrawDialog(),
    );
    if (item != null && context.mounted) {
      context.read<InventoryProvider>().add(item);
    }
  }

  void _useItem(BuildContext context, InventoryItem item) {
    final game = context.read<RpgGameProvider>();
    if (game.isLoading || game.hasEnding) return;
    final desc = item.description.trim().isEmpty
        ? item.typeLabel
        : item.description.trim();
    context.read<InventoryProvider>().markUsed(item);
    game.useItem(name: item.name, description: desc);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _kPrimary,
        duration: const Duration(milliseconds: 1200),
        content: Text("'${item.name}' 을(를) 사용했어요"),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, InventoryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text("'${item.name}' 삭제",
            style: const TextStyle(color: _kInk, fontWeight: FontWeight.w700)),
        content: const Text('가방에서 뺄까요?',
            style: TextStyle(color: Color(0xFF6E6690))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Color(0xFFE5689B))),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      context.read<InventoryProvider>().remove(item.id);
    }
  }
}
