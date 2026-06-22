import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import 'api_service.dart';

/// RPG 전용 API.
class RpgApiService {
  static String get baseUrl => ApiService.baseUrl;

  static Future<Map<String, dynamic>> start({
    required int storyId,
    required String playerName,
    String assetHint = '',
    int maxTurns = 6,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/rpg/start'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'story_id': storyId,
        'player_name': playerName,
        'asset_hint': assetHint,
        'max_turns': maxTurns,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('RPG 시작 실패: ${response.body}');
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> advanceTurn({
    required int playthroughId,
    String? choiceId,
    String? freeText,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/rpg/turn'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'playthrough_id': playthroughId,
        'choice_id': choiceId,
        'free_text': freeText,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('턴 진행 실패: ${response.body}');
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> npcChat({
    required int playthroughId,
    required String npcName,
    required String message,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/rpg/npc/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'playthrough_id': playthroughId,
        'npc_name': npcName,
        'message': message,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('NPC 대화 실패: ${response.body}');
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> requestEnding({
    required int playthroughId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/rpg/ending'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'playthrough_id': playthroughId}),
    );
    if (response.statusCode != 200) {
      throw Exception('엔딩 생성 실패: ${response.body}');
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  /// 장면 이미지(PNG 바이트) — 현재 미사용(호환 유지)
  static Future<Uint8List> fetchSceneImage({
    required int playthroughId,
    required String narrative,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/rpg/scene'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'playthrough_id': playthroughId,
        'narrative': narrative,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('장면 이미지 실패: ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  /// 엔딩 4컷 이미지(PNG 바이트). 그린 아이템 목록(itemHints)을 함께 보내 반영.
  static Future<Uint8List> fetchFinalComic({
    required int playthroughId,
    List<String> itemHints = const [],
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/rpg/final-image'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'playthrough_id': playthroughId,
        'item_hints': itemHints,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('4컷 이미지 실패: ${response.statusCode}');
    }
    return response.bodyBytes;
  }
}
