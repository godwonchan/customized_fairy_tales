import 'package:flutter/foundation.dart';

import '../models/rpg_models.dart';
import '../services/rpg_api_service.dart';

/// RPG 진행 상태 관리(Provider/ChangeNotifier).
class RpgGameProvider extends ChangeNotifier {
  int? playthroughId;
  String narrative = '';
  List<RpgChoice> choices = [];
  RpgStats stats = RpgStats.empty();
  Map<String, int> lastChanges = {};

  bool isLoading = false;
  bool isEnding = false;
  RpgEndingData? ending;
  String? error;

  bool get hasEnding => ending != null;

  Future<void> startGame({
    required int storyId,
    required String playerName,
    String assetHint = '',
    int maxTurns = 6,
  }) async {
    _setLoading(true);
    error = null;
    try {
      final data = await RpgApiService.start(
        storyId: storyId,
        playerName: playerName,
        assetHint: assetHint,
        maxTurns: maxTurns,
      );
      _applyTurn(RpgTurnData.fromJson(data));
    } catch (e) {
      error = _clean(e);
    }
    _setLoading(false);
  }

  Future<void> choose(String choiceId) => _advance(choiceId: choiceId);

  Future<void> submitFreeText(String text) {
    if (text.trim().isEmpty) return Future.value();
    return _advance(freeText: text.trim());
  }

  /// 인벤토리 아이템 사용 → 행동 텍스트로 변환해 턴 진행(백엔드 free_text 재활용).
  Future<void> useItem({required String name, String description = ''}) {
    if (playthroughId == null || isLoading || hasEnding) return Future.value();
    final extra = description.trim().isEmpty ? '' : ' ($description)';
    final action = "가방에서 '$name'$extra 을(를) 꺼내 사용한다.";
    return _advance(freeText: action);
  }

  Future<void> _advance({String? choiceId, String? freeText}) async {
    if (playthroughId == null || isLoading) return;
    _setLoading(true);
    error = null;
    try {
      final data = await RpgApiService.advanceTurn(
        playthroughId: playthroughId!,
        choiceId: choiceId,
        freeText: freeText,
      );
      _applyTurn(RpgTurnData.fromJson(data));
      if (isEnding) {
        await _fetchEnding();
      }
    } catch (e) {
      error = _clean(e);
    }
    _setLoading(false);
  }

  Future<void> _fetchEnding() async {
    try {
      final data = await RpgApiService.requestEnding(
        playthroughId: playthroughId!,
      );
      ending = RpgEndingData.fromJson(data);
      stats = ending!.stats;
    } catch (e) {
      error = _clean(e);
    }
  }

  void _applyTurn(RpgTurnData t) {
    playthroughId = t.playthroughId;
    narrative = t.narrative;
    choices = t.choices;
    stats = t.stats;
    lastChanges = t.statChanges;
    isEnding = t.isEnding;
  }

  void _setLoading(bool v) {
    isLoading = v;
    notifyListeners();
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');
}
