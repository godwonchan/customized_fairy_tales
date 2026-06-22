/// RPG 데이터 모델. 백엔드 응답(JSON)을 그대로 매핑한다.

class RpgChoice {
  final String id;
  final String text;
  const RpgChoice({required this.id, required this.text});

  factory RpgChoice.fromJson(Map<String, dynamic> j) =>
      RpgChoice(id: j['id'].toString(), text: (j['text'] ?? '').toString());
}

class RpgStats {
  final int level;
  final int exp;
  final int courage; // 용기
  final int wisdom; // 지혜
  final int kindness; // 친절

  const RpgStats({
    required this.level,
    required this.exp,
    required this.courage,
    required this.wisdom,
    required this.kindness,
  });

  factory RpgStats.empty() =>
      const RpgStats(level: 1, exp: 0, courage: 0, wisdom: 0, kindness: 0);

  factory RpgStats.fromJson(Map<String, dynamic> j) => RpgStats(
        level: _i(j['level'], 1),
        exp: _i(j['exp']),
        courage: _i(j['courage']),
        wisdom: _i(j['wisdom']),
        kindness: _i(j['kindness']),
      );
}

class RpgTurnData {
  final int playthroughId;
  final int turnIndex;
  final String narrative;
  final List<RpgChoice> choices;
  final Map<String, int> statChanges;
  final RpgStats stats;
  final bool isEnding;

  const RpgTurnData({
    required this.playthroughId,
    required this.turnIndex,
    required this.narrative,
    required this.choices,
    required this.statChanges,
    required this.stats,
    required this.isEnding,
  });

  factory RpgTurnData.fromJson(Map<String, dynamic> j) => RpgTurnData(
        playthroughId: _i(j['playthrough_id']),
        turnIndex: _i(j['turn_index']),
        narrative: (j['narrative'] ?? '').toString(),
        choices: ((j['choices'] ?? []) as List)
            .map((e) => RpgChoice.fromJson(e as Map<String, dynamic>))
            .toList(),
        statChanges: _intMap(j['stat_changes']),
        stats: RpgStats.fromJson((j['stats'] ?? {}) as Map<String, dynamic>),
        isEnding: j['is_ending'] == true,
      );
}

class RpgEndingData {
  final int playthroughId;
  final String endingType;
  final String title;
  final String narrative;
  final RpgStats stats;

  const RpgEndingData({
    required this.playthroughId,
    required this.endingType,
    required this.title,
    required this.narrative,
    required this.stats,
  });

  factory RpgEndingData.fromJson(Map<String, dynamic> j) => RpgEndingData(
        playthroughId: _i(j['playthrough_id']),
        endingType: (j['ending_type'] ?? 'ordinary').toString(),
        title: (j['title'] ?? '이야기의 끝').toString(),
        narrative: (j['narrative'] ?? '').toString(),
        stats: RpgStats.fromJson((j['stats'] ?? {}) as Map<String, dynamic>),
      );
}

class NpcMessage {
  final String role; // user | assistant
  final String content;
  const NpcMessage({required this.role, required this.content});

  bool get isUser => role == 'user';
}

// ---- 내부 변환 헬퍼 ----
int _i(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? fallback;
}

Map<String, int> _intMap(dynamic v) {
  if (v is Map) {
    return v.map((k, value) => MapEntry(k.toString(), _i(value)));
  }
  return {};
}
