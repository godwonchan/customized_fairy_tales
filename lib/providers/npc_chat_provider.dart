import 'package:flutter/foundation.dart';

import '../models/rpg_models.dart';
import '../services/rpg_api_service.dart';

/// NPC 자유 대화 상태 관리.
class NpcChatProvider extends ChangeNotifier {
  final int playthroughId;
  String npcName;

  NpcChatProvider({required this.playthroughId, required this.npcName});

  final List<NpcMessage> messages = [];
  bool isLoading = false;
  String? error;

  void setNpcName(String name) {
    if (name.trim().isEmpty || name == npcName) return;
    npcName = name.trim();
    messages.clear();
    error = null;
    notifyListeners();
  }

  Future<void> send(String text) async {
    final msg = text.trim();
    if (msg.isEmpty || isLoading) return;

    messages.add(NpcMessage(role: 'user', content: msg));
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final data = await RpgApiService.npcChat(
        playthroughId: playthroughId,
        npcName: npcName,
        message: msg,
      );
      messages.add(
        NpcMessage(role: 'assistant', content: (data['reply'] ?? '').toString()),
      );
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      messages.add(const NpcMessage(role: 'assistant', content: '(지금은 대답할 수 없어요…)'));
    }

    isLoading = false;
    notifyListeners();
  }
}