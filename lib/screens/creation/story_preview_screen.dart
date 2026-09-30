// lib/screens/creation/story_preview_screen.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'story_reader_screen.dart';

class StoryPreviewScreen extends StatefulWidget {
  final Map<String, Uint8List?> assetPngBytes;
  final Map<String, bool> aiDelegated;
  final Map<String, Map<String, String>> assetDescriptions;
  final Map<String, dynamic>? cachedStoryData; // 👈 [추가] 이전 줄거리 데이터

  const StoryPreviewScreen({
    super.key,
    required this.assetPngBytes,
    required this.aiDelegated,
    required this.assetDescriptions,
    this.cachedStoryData, // 👈 [추가]
  });

  @override
  State<StoryPreviewScreen> createState() => _StoryPreviewScreenState();
}

class _StoryPreviewScreenState extends State<StoryPreviewScreen> {
  static const String _baseUrl = 'http://localhost:8000'; // 웹: localhost, 에뮬레이터: 10.0.2.2

  bool _isGenerating = true;
  String _selectedMood = '🚀 신나는 모험';

  final List<String> _moodChips = [
    '🚀 신나는 모험',
    '🤣 엉뚱하고 웃기게',
    '🌸 마법과 감동',
    '🧁 달콤한 간식 나라',
    '🕵️ 비밀 탐정',
  ];

  final TextEditingController _feedbackController = TextEditingController();

  // STT 음성 인식
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  String _storyTitle = '루미가 동화를 짓고 있어... ✨';
  List<Map<String, dynamic>> _storyPages = [];

  @override
  void initState() {
    super.initState();
    _initSpeech();
    // 💡 이전에 만들어둔 줄거리가 있다면 새로 호출하지 않고 즉시 복원!
    if (widget.cachedStoryData != null) {
      _storyTitle = widget.cachedStoryData!['title'] ?? '멋진 모험 이야기';
      _selectedMood = widget.cachedStoryData!['mood'] ?? _selectedMood;
      _storyPages =
      List<Map<String, dynamic>>.from(widget.cachedStoryData!['pages'] ?? []);
      _isGenerating = false;
    } else {
      // 처음 진입했을 때만 백엔드 GPT 호출!
      _fetchRealStory(mood: _selectedMood);
    }
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (val) => debugPrint('STT 오류: $val'),
        onStatus: (val) => debugPrint('STT 상태: $val'),
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('STT 초기화 실패: $e');
    }
  }

  // 🎙️ 피드백 마이크 음성인식 토글
  void _toggleFeedbackListening() async {
    if (!_speechAvailable) {
      await _initSpeech();
    }
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('마이크 권한을 확인해 줘!')),
      );
      return;
    }

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);

      await _speech.listen(
        localeId: 'ko_KR',
        onResult: (result) {
          setState(() {
            _feedbackController.text = result.recognizedWords;
            if (result.finalResult) {
              _isListening = false;
            }
          });
        },
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  🌐 백엔드 FastAPI GPT-4o-mini 줄거리 생성 API 호출
  // ═══════════════════════════════════════════════════════════════
  Future<void> _fetchRealStory({required String mood, String? feedback}) async {
    setState(() => _isGenerating = true);

    Map<String, dynamic>? previousStoryPayload;
    if (feedback != null && _storyPages.isNotEmpty) {
      previousStoryPayload = {
        'title': _storyTitle,
        'pages': _storyPages,
      };
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/story/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'mood': mood,
          'asset_descriptions': widget.assetDescriptions,
          'feedback': feedback,
          'previous_story': previousStoryPayload,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _storyTitle = data['title'] ?? '멋진 모험 이야기';
          final List pagesRaw = data['pages'] ?? [];
          _storyPages = pagesRaw.map((p) => {
            'page': '${p['page']}화',
            'title': p['title'] ?? '',
            'content': p['content'] ?? '',
            'layout_type': p['layout_type'] ?? 'single', // 👈 이 줄 추가!
            'prompt': p['visual_scene_prompt'] ?? '',
          }).toList();
          _isGenerating = false;
        });

        if (feedback != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✨ 루미가 아이의 요청을 반영해 이야기를 새롭게 고쳤어!'),
              backgroundColor: Color(0xFF7E57C2),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        throw Exception('서버 응답 에러: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('줄거리 생성 에러: $e');
      setState(() {
        _isGenerating = false;
        _storyTitle = '신비한 마법 모험 이야기';
        _storyPages = [
          {'page': '1화', 'title': '새로운 출발', 'content': '용감한 친구들이 함께 모여 신비한 비밀의 장소로 떠났어요!'},
          {'page': '2화', 'title': '마법의 힘', 'content': '위험한 순간이 찾아왔지만, 소중한 도구로 힘을 합쳐 이겨냈답니다.'},
          {'page': '3화', 'title': '모두의 축제', 'content': '마을 친구들과 함께 맛있는 간식을 나누며 행복한 파티를 열었어요!'},
        ];
      });
    }
  }

  void _applyFeedback() {
    final prompt = _feedbackController.text.trim();
    if (prompt.isEmpty) return;

    if (_isListening) {
      _speech.stop();
      _isListening = false;
    }

    _fetchRealStory(mood: _selectedMood, feedback: prompt);
    _feedbackController.clear();
  }

  // 🔙 줄거리 데이터를 담아서 이전(그리기) 화면으로 복귀
  void _popWithStoryData() {
    if (_storyPages.isNotEmpty) {
      Navigator.pop(context, {
        'title': _storyTitle,
        'pages': _storyPages,
        'mood': _selectedMood,
      });
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _popWithStoryData(); // 💡 시스템 뒤로가기 시에도 줄거리 보존
        },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F5FC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Color(0xFF3D2C8D)),
            onPressed: _popWithStoryData, // 👈 [수정] _popWithStoryData 호출
          ),
        title: const Text('줄거리 확인하기', style: TextStyle(color: Color(0xFF3D2C8D), fontWeight: FontWeight.bold)),
        actions: [
          // 🔄 이야기 다시 짓기 버튼
          IconButton(
            tooltip: '이야기 다시 짓기',
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF7E57C2)),
            onPressed: _isGenerating ? null : () => _fetchRealStory(mood: _selectedMood),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 1. 이야기 분위기 칩 선택 바
            Container(
              height: 48,
              margin: const EdgeInsets.only(top: 8),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _moodChips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final mood = _moodChips[index];
                  final isSelected = _selectedMood == mood;
                  return ChoiceChip(
                    label: Text(mood),
                    selected: isSelected,
                    selectedColor: const Color(0xFF7E57C2),
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? Colors.white : const Color(0xFF4A4458),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: isSelected ? const Color(0xFF7E57C2) : const Color(0xFFE0D8ED)),
                    ),
                    onSelected: _isGenerating ? null : (val) {
                      if (val) {
                        setState(() => _selectedMood = mood);
                        _fetchRealStory(mood: mood);
                      }
                    },
                  );
                },
              ),
            ),

            // 2. 이야기 제목
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                _storyTitle,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF3D2C8D)),
                textAlign: TextAlign.center,
              ),
            ),

            // 3. 페이지별 줄거리 본문
            Expanded(
              child: _isGenerating
                  ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 36, height: 36,
                      child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF7E57C2)),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '요정 루미가 아이의 그림으로\n마법 동화책을 짓고 있어... ✨',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Color(0xFF7E57C2), height: 1.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              )
                  : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                itemCount: _storyPages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final page = _storyPages[index];
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFEBE5F5)),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3EDFA),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                page['page']!,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF7E57C2)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                page['title']!,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF3D2C8D)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          page['content']!,
                          style: const TextStyle(fontSize: 13.5, color: Color(0xFF2C2440), height: 1.5),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // 4. 하단 피드백 입력 바 (음성 STT + 텍스트)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _feedbackController,
                      enabled: !_isGenerating,
                      textInputAction: TextInputAction.send, // 👈 [1번] 엔터 키를 '전송' 아이콘으로
                      onSubmitted: (val) {
                        // 🚀 [1번] 키보드 엔터 치면 마우스 안 누르고 즉시 수정 요청!
                        if (!_isGenerating && val.trim().isNotEmpty) {
                          _applyFeedback();
                        }
                      },
                      decoration: InputDecoration(
                        hintText: _isListening ? '듣고 있어요! 말씀해 보세요...' : '글로 쓰거나 마이크로 이야기 수정을 부탁해 봐!',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: _isListening ? const Color(0xFF7E57C2) : Colors.grey[400],
                          fontWeight: _isListening ? FontWeight.bold : FontWeight.normal,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF9F7FC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFFE0D8ED))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFFE0D8ED))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // 🎙️ [2번] 아이들이 콕 누르기 쉽게 큼직해진 마이크 버튼 (50x50)
                  GestureDetector(
                    onTap: _isGenerating ? null : _toggleFeedbackListening,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: _isListening ? Colors.redAccent : const Color(0xFFF3EDFA),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _isListening
                                ? Colors.redAccent.withOpacity(0.35)
                                : const Color(0xFF7E57C2).withOpacity(0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none_rounded,
                        color: _isListening ? Colors.white : const Color(0xFF7E57C2),
                        size: 26, // 💡 아이콘 크기 26으로 확대!
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  IconButton(
                    onPressed: _isGenerating ? null : _applyFeedback,
                    icon: const Icon(Icons.send_rounded, color: Color(0xFF7E57C2), size: 24),
                  ),
                ],
              ),
            ),

            // 5. 최종 확정 버튼 바
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))],
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: OutlinedButton.icon(
                      onPressed: _popWithStoryData, // 👈 [수정] Navigator.pop(context) 대신 호출!
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('그림 더 고칠래'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF7E57C2),
                        side: const BorderSide(color: Color(0xFFDED6ED)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 6,
                    child: ElevatedButton.icon(
                      onPressed: _isGenerating ? null : () => _createFinalStorybook(),
                      icon: const Icon(Icons.auto_stories, size: 18),
                      label: const Text('이 이야기로 완성! ✨'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7E57C2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
  // ── 🎨 일러스트 생성 요청 및 완성 뷰어 이동 ──
  Future<void> _createFinalStorybook() async {
    // 1. 루미의 마법 로딩 팝업 띄우기
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          margin: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48, height: 48,
                child: CircularProgressIndicator(strokeWidth: 3.5, color: Color(0xFF7E57C2)),
              ),
              const SizedBox(height: 20),
              const Text(
                '루미가 동화책을 마법으로 인쇄하고 있어! 📖✨',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF3D2C8D)),
              ),
              const SizedBox(height: 8),
              Text(
                '예쁜 그림과 이야기를 엮는 중이야 (잠시만 기다려줘)',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      // 💡 1. 아이가 직접 그린 모든 카테고리 그림을 Base64로 자동 수집
      final Map<String, String> drawnAssetsBase64 = {};
      widget.assetPngBytes.forEach((catId, bytes) {
        // AI에게 위임하지 않고 아이가 직접 그린 경우만 전송
        if (bytes != null && bytes.isNotEmpty && (widget.aiDelegated[catId] != true)) {
          drawnAssetsBase64[catId] = base64Encode(bytes);
        }
      });

      // 2. 백엔드 요청 페이로드
      final payload = {
        'drawn_assets_base64': drawnAssetsBase64, // 👈 아이가 그린 모든 그림 맵 전달!
        'pages': _storyPages.asMap().entries.map((entry) {
          final idx = entry.key;
          final p = entry.value;
          return {
            'page_number': idx + 1,
            'scene_prompt': (p['prompt'] != null && p['prompt'].toString().trim().isNotEmpty)
                ? p['prompt']
                : p['content'],
            'mood': _selectedMood,
            'layout_type': p['layout_type'] ?? 'single', // 👈 이 줄 추가!
          };
        }).toList(),
      };

      final res = await http.post(
        Uri.parse('$_baseUrl/api/story/generate_illustrations'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      // 로딩 팝업 닫기
      if (mounted) Navigator.pop(context);

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final List illustrations = data['illustrations'] ?? [];

        // 각 페이지 데이터에 완성된 이미지 URL 결합
        final List<Map<String, dynamic>> finalPages = [];
        for (int i = 0; i < _storyPages.length; i++) {
          finalPages.add({
            ..._storyPages[i],
            'imageUrl': (i < illustrations.length) ? illustrations[i]['image_url'] : '',
          });
        }

        // 3. ✨ 최종 동화책 뷰어로 이동!
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => StoryReaderScreen(
                title: _storyTitle,
                pages: finalPages,
                assetPngBytes: widget.assetPngBytes,
              ),
            ),
          );
        }
      } else {
        throw Exception('일러스트 생성 실패');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // 로딩 닫기
      debugPrint('최종 동화책 생성 에러: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('동화책을 인쇄하는 중에 문제가 생겼어. 다시 시도해 줘!')),
      );
    }
  }
}