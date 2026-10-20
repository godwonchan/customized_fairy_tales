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
  final List<Map<String, String>>? storyNotes; // 🎯 [추가!] 아이와 루미의 대화 메모 수신
  final Map<String, dynamic>? cachedStoryData;
  final String? taleId;

  const StoryPreviewScreen({
    super.key,
    required this.assetPngBytes,
    required this.aiDelegated,
    required this.assetDescriptions,
    this.storyNotes, // 🎯 [추가]
    this.cachedStoryData,
    this.taleId,
  });

  @override
  State<StoryPreviewScreen> createState() => _StoryPreviewScreenState();
}

class _StoryPreviewScreenState extends State<StoryPreviewScreen> {
  static const String _baseUrl = 'http://localhost:8000';

  bool _isGenerating = true;
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

    // 💡 더미 데이터("신나는 모험 이야기")가 아닌 유효한 캐시가 있을 때만 재사용
    final bool isDummyFallback = widget.cachedStoryData?['title'] == '신나는 모험 이야기' ||
        widget.cachedStoryData?['title'] == '신나는 모험';

    if (widget.cachedStoryData != null && !isDummyFallback) {
      _storyTitle = widget.cachedStoryData!['title'] ?? '우리가 만든 동화 이야기';
      _storyPages = List<Map<String, dynamic>>.from(widget.cachedStoryData!['pages'] ?? []);
      _isGenerating = false;
    } else {
      // 🎯 더미 캐시이거나 처음 진입 시 백엔드 gpt-5.5 호출!
      _fetchRealStory();
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
  //  🌐 백엔드 FastAPI gpt-5.5 줄거리 생성 API 호출
  // ═══════════════════════════════════════════════════════════════
  Future<void> _fetchRealStory({String? feedback}) async {
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
          'asset_descriptions': widget.assetDescriptions,
          'story_notes': widget.storyNotes ?? [], // 🎯 아이와 루미가 나눈 대화 기록 전송!
          'feedback': feedback,
          'previous_story': previousStoryPayload,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _storyTitle = data['title'] ?? '우리가 만든 동화 이야기';
          final List pagesRaw = data['pages'] ?? [];
          _storyPages = pagesRaw.map((p) => {
            'page': '${p['page']}화',
            'title': p['title'] ?? '',
            'content': p['content'] ?? '',
            'layout_type': p['layout_type'] ?? 'single',
            'prompt': p['visual_scene_prompt'] ?? '',
            'characters': List<String>.from(p['characters'] ?? []),
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

    _fetchRealStory(feedback: prompt);
    _feedbackController.clear();
  }

  void _popWithStoryData() {
    if (_storyPages.isNotEmpty) {
      Navigator.pop(context, {
        'title': _storyTitle,
        'pages': _storyPages,
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
        _popWithStoryData();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F5FC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Color(0xFF3D2C8D)),
            onPressed: _popWithStoryData,
          ),
          title: const Text('줄거리 확인하기', style: TextStyle(color: Color(0xFF3D2C8D), fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              tooltip: '이야기 다시 짓기',
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF7E57C2)),
              onPressed: _isGenerating ? null : () => _fetchRealStory(),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // 🎯 카테고리 칩 바를 걷어내고 심플하고 감성적인 타이틀 안내 바로 교체
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Color(0xFFEBE5F5))),
                ),
                child: Row(
                  children: [
                    const Text('✨', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '아이가 들려준 이야기와 그림으로 쓴 세상에 하나뿐인 동화야',
                        style: TextStyle(fontSize: 13, color: Color(0xFF7E57C2), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),

              // 이야기 제목
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Text(
                  _storyTitle,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF3D2C8D)),
                  textAlign: TextAlign.center,
                ),
              ),

              // 페이지별 줄거리 본문
              Expanded(
                child: _isGenerating
                    ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 40, height: 40,
                        child: CircularProgressIndicator(strokeWidth: 3.5, color: Color(0xFF7E57C2)),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '요정 루미가 아이와의 대화를 엮어\n세상에 하나뿐인 동화를 짓고 있어... ✨',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14.5, color: Color(0xFF7E57C2), height: 1.5, fontWeight: FontWeight.bold),
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
                            style: const TextStyle(fontSize: 14, color: Color(0xFF2C2440), height: 1.55),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // 피드백 입력 바
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Colors.white,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _feedbackController,
                        enabled: !_isGenerating,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (val) {
                          if (!_isGenerating && val.trim().isNotEmpty) {
                            _applyFeedback();
                          }
                        },
                        decoration: InputDecoration(
                          hintText: _isListening ? '듣고 있어요! 말씀해 보세요...' : '글로 쓰거나 마이크로 이야기 수정을 부탁해 봐!',
                          hintStyle: TextStyle(
                            fontSize: 12.5,
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
                          size: 26,
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

              // 최종 확정 버튼 바
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
                        onPressed: _popWithStoryData,
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

  // 페이지 인덱스별로 생성된 이미지와, 생성 당시의 장면 정보를 보관
  // (장면 정보가 그대로인 페이지는 다시 그리지 않음)
  final Map<int, String> _pageImages = {};
  final Map<int, String> _pageImageSignatures = {};

  String _sceneSignature(int index) {
    final p = _storyPages[index];
    return jsonEncode([p['prompt'] ?? '', p['layout_type'] ?? 'single', p['characters'] ?? []]);
  }

  bool _hasImage(int index) =>
      (_pageImages[index] ?? '').isNotEmpty &&
      _pageImageSignatures[index] == _sceneSignature(index);

  // ── 🎨 OpenAI gpt-image-2 일러스트 생성 요청 및 완성 뷰어 이동 ──
  Future<void> _createFinalStorybook() async {
    // 이미지가 없는 페이지만 생성 요청
    final targets = [
      for (int i = 0; i < _storyPages.length; i++)
        if (!_hasImage(i)) i,
    ];

    if (targets.isNotEmpty) {
      _showPrintingDialog();
      try {
        await _requestIllustrations(targets);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        debugPrint('최종 동화책 생성 에러: $e');
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('동화책을 인쇄하는 중에 문제가 생겼어. 다시 시도해 줘!')),
        );
        return;
      }
    }
    if (!mounted) return;

    final failed = [
      for (int i = 0; i < _storyPages.length; i++)
        if (!_hasImage(i)) i,
    ];
    if (failed.isNotEmpty) {
      final retry = await _askRetryFailedPages(failed);
      if (!mounted || retry == null) return;
      if (retry) {
        await _createFinalStorybook();
        return;
      }
    }

    _openReader();
  }

  void _showPrintingDialog() {
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
                '예쁜 수채화 그림과 이야기를 엮는 중이야 (잠시만 기다려줘)',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 지정한 페이지들만 서버에 요청하고, 성공한 이미지를 _pageImages에 보관
  Future<void> _requestIllustrations(List<int> targetIndexes) async {
    final Map<String, String> drawnAssetsBase64 = {};
    widget.assetPngBytes.forEach((catId, bytes) {
      if (bytes != null && bytes.isNotEmpty && (widget.aiDelegated[catId] != true)) {
        drawnAssetsBase64[catId] = base64Encode(bytes);
      }
    });

    // 🎯 OpenAI gpt-image-2 파이프라인 전송 페이로드 구성
    final payload = {
      'drawn_assets_base64': drawnAssetsBase64,
      'pages': targetIndexes.map((idx) {
        final p = _storyPages[idx];

        final safePrompt = (p['prompt'] != null && p['prompt'].toString().trim().isNotEmpty)
            ? p['prompt'].toString().trim()
            : 'A whimsical watercolor storybook illustration of the characters.';

        return {
          'page_number': idx + 1,
          'scene_prompt': safePrompt,
          'layout_type': p['layout_type'] ?? 'single',
          'characters': p['characters'] ?? [],
        };
      }).toList(),
    };

    final res = await http.post(
      Uri.parse('$_baseUrl/api/story/generate_illustrations'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (res.statusCode != 200) {
      throw Exception('일러스트 생성 실패: ${res.statusCode}');
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final List illustrations = data['illustrations'] ?? [];
    for (final item in illustrations) {
      final idx = (item['page_number'] as int) - 1;
      final url = (item['image_url'] ?? '').toString();
      if (url.isNotEmpty) {
        _pageImages[idx] = url;
        _pageImageSignatures[idx] = _sceneSignature(idx);
      } else {
        debugPrint('[${idx + 1}페이지] 그림 생성 실패: ${item['error']}');
      }
    }
  }

  // 실패한 페이지가 있을 때 다시 그릴지 묻기 (true: 다시 그리기, false: 그대로 보기, null: 닫기)
  Future<bool?> _askRetryFailedPages(List<int> failedIndexes) {
    final pageLabels = failedIndexes.map((i) => '${i + 1}').join(', ');
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('그림 몇 장을 못 그렸어', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF3D2C8D))),
        content: Text('$pageLabels페이지 그림을 그리지 못했어.\n이 페이지만 다시 그려 볼까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('그림 없이 볼래', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7E57C2),
              foregroundColor: Colors.white,
            ),
            child: const Text('다시 그리기'),
          ),
        ],
      ),
    );
  }

  void _openReader() {
    final List<Map<String, dynamic>> finalPages = [
      for (int i = 0; i < _storyPages.length; i++)
        {
          ..._storyPages[i],
          'imageUrl': _hasImage(i) ? _pageImages[i]! : '',
        },
    ];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => StoryReaderScreen(
          title: _storyTitle,
          pages: finalPages,
          assetPngBytes: widget.assetPngBytes,
          taleId: widget.taleId,
        ),
      ),
    );
  }
}