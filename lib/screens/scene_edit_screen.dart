import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'fairy_tale_list_screen.dart';
import 'tale_reading_screen.dart';
import 'ai_result_screen.dart';
import '../services/api_service.dart';

class HighlightRange {
  final int start;
  final int end;
  final String text;

  HighlightRange({required this.start, required this.end, required this.text});
}

class DrawingPath {
  final Color color;
  final double strokeWidth;
  final List<Offset> points;

  DrawingPath({
    required this.color,
    required this.strokeWidth,
    required this.points,
  });
}

class DrawingPainter extends CustomPainter {
  final List<DrawingPath> paths;

  DrawingPainter(this.paths);

  @override
  void paint(Canvas canvas, Size size) {
    for (final path in paths) {
      if (path.points.isEmpty) continue;

      final paint = Paint()
        ..color = path.color
        ..strokeWidth = path.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final drawPath = Path();
      drawPath.moveTo(path.points.first.dx, path.points.first.dy);

      for (int i = 1; i < path.points.length; i++) {
        drawPath.lineTo(path.points[i].dx, path.points[i].dy);
      }

      canvas.drawPath(drawPath, paint);
    }
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) => true;
}

class SceneEditScreen extends StatefulWidget {
  final FairyTale tale;
  final TaleBook taleBook;
  final int selectedPageIndex;

  const SceneEditScreen({
    super.key,
    required this.tale,
    required this.taleBook,
    required this.selectedPageIndex,
  });

  @override
  State<SceneEditScreen> createState() => _SceneEditScreenState();
}

class _SceneEditScreenState extends State<SceneEditScreen> {
  final List<DrawingPath> _paths = [];
  DrawingPath? _currentPath;
  final GlobalKey _sketchKey = GlobalKey();

  Color _selectedColor = Colors.black;
  double _strokeWidth = 12.0;
  bool _isEraser = false;

  late String _fullText;
  final List<HighlightRange> _highlights = [];
  final TextEditingController _textController = TextEditingController();

  bool _showPreviewPanel = false;
  bool _isGenerating = false;
  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, String>> _chatMessages = [];
  bool _showPreviewTab = true;

  String? _interpretedRequest;
  List<String>? _previewRevisedPages;
  List<String>? _originalPages;
  List<String>? _generatedImagePaths;
  String? _errorMessage;

  String? _revisionJobId;
  bool _isApplyingAsync = false;
  int _progressPercent = 0;
  String? _progressMessage;
  Timer? _progressTimer;

  final List<Color> _colorPalette = [
    Colors.black,
    const Color(0xFFE53935),
    const Color(0xFFFF8F00),
    const Color(0xFFFFD600),
    const Color(0xFF43A047),
    const Color(0xFF1E88E5),
    const Color(0xFF5E35B1),
    const Color(0xFF795548),
    const Color(0xFFEC407A),
  ];

  @override
  void initState() {
    super.initState();
    _initText();
  }

  void _initText() {
    final page = widget.taleBook.pages[widget.selectedPageIndex];
    _fullText = page.text;
    if (page.highlightText != null) {
      _fullText += '\n${page.highlightText}';
    }
    _textController.text = _fullText;
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _chatController.dispose();
    _textController.dispose();
    super.dispose();
  }

  String get _selectedTextForApi {
    if (_highlights.isEmpty) return '';
    return _highlights.map((h) => h.text).join(' / ');
  }

  bool get _hasSketch {
    if (_paths.isNotEmpty) return true;
    if (_currentPath != null && _currentPath!.points.isNotEmpty) return true;
    return false;
  }

  List<String>? _extractGeneratedImagePaths(Map<String, dynamic> result) {
    final candidates = [
      result['generated_image_paths'],
      result['generated_images'],
      result['image_paths'],
      result['image_urls'],
    ];

    for (final candidate in candidates) {
      if (candidate is List) {
        final paths = candidate.map((e) => e.toString()).toList();
        if (paths.isNotEmpty) return paths;
      }
    }
    return null;
  }

  String _changedPagesSummary() {
    if (_previewRevisedPages == null || _previewRevisedPages!.isEmpty)
      return '';
    final startPage = 1;
    final endPage = _previewRevisedPages!.length;
    return startPage == endPage ? '$startPage페이지' : '$startPage~$endPage페이지';
  }

  void _addHighlight(int start, int end) {
    if (start >= end) return;
    final selectedText = _fullText.substring(start, end);
    if (selectedText.trim().isEmpty) return;

    setState(() {
      _highlights.removeWhere(
        (h) =>
            (h.start <= start && h.end >= start) ||
            (h.start <= end && h.end >= end) ||
            (start <= h.start && end >= h.end),
      );

      _highlights.add(
        HighlightRange(start: start, end: end, text: selectedText),
      );
    });
  }

  void _removeHighlight(int index) {
    setState(() => _highlights.removeAt(index));
  }

  void _clearHighlights() {
    setState(() => _highlights.clear());
  }

  void _clearCanvas() {
    setState(() {
      _paths.clear();
      _currentPath = null;
    });
  }

  void _undo() {
    if (_paths.isNotEmpty) {
      setState(() => _paths.removeLast());
    }
  }

  Future<Uint8List> _captureSketchBytes() async {
    final boundary =
        _sketchKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _generatePreviewFlow() async {
    if (widget.tale.storyId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('서버 동화만 수정할 수 있어요.')));
      return;
    }

    if (_highlights.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 바꾸고 싶은 텍스트를 드래그해서 선택해주세요.')),
      );
      return;
    }

    if (!_hasSketch) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('먼저 그림판에 낙서를 그려주세요.')));
      return;
    }

    setState(() {
      _showPreviewPanel = true;
      _showPreviewTab = true;
      _isGenerating = true;
      _errorMessage = null;
      _interpretedRequest = null;
      _previewRevisedPages = null;
      _originalPages = null;
      _generatedImagePaths = null;
      _chatMessages.clear();
    });

    try {
      final sketchBytes = await _captureSketchBytes();
      final selectedText = _selectedTextForApi;
      final pageNumber =
          widget.taleBook.pages[widget.selectedPageIndex].pageNumber;

      final interpretResult = await ApiService.sketchInterpret(
        storyId: widget.tale.storyId!,
        pageNumber: pageNumber,
        selectedText: selectedText,
        sketchBytes: sketchBytes,
      );

      final interpreted =
          interpretResult['interpreted_request'] as String? ?? '';

      setState(() {
        _interpretedRequest = interpreted;
        _chatMessages.add({
          'role': 'ai',
          'text': interpreted.isEmpty
              ? '낙서 해석 결과를 만들지 못했어요.'
              : '이렇게 이해했어요:\n$interpreted',
        });
      });

      final previewResult = await ApiService.sketchRevisePreview(
        storyId: widget.tale.storyId!,
        pageNumber: pageNumber,
        selectedText: selectedText,
        confirmedRequest: interpreted,
      );

      final revisedPages = (previewResult['revised_pages'] as List<dynamic>)
          .map((e) => e.toString())
          .toList();

      final originalPages = (previewResult['original_pages'] as List<dynamic>)
          .map((e) => e.toString())
          .toList();

      final generatedImagePaths = _extractGeneratedImagePaths(previewResult);

      setState(() {
        _previewRevisedPages = revisedPages;
        _originalPages = originalPages;
        _generatedImagePaths = generatedImagePaths;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _chatMessages.add({'role': 'ai', 'text': '미리보기 생성 중 오류가 발생했어요.\n$e'});
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('미리보기 생성 실패: $e')));
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _regenerateFromChat() async {
    if (widget.tale.storyId == null) return;

    final request = _chatController.text.trim();
    if (request.isEmpty) return;

    if (_highlights.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('먼저 선택된 텍스트가 있어야 해요.')));
      return;
    }

    setState(() {
      _chatMessages.add({'role': 'user', 'text': request});
      _chatController.clear();
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final pageNumber =
          widget.taleBook.pages[widget.selectedPageIndex].pageNumber;

      final previewResult = await ApiService.sketchRevisePreview(
        storyId: widget.tale.storyId!,
        pageNumber: pageNumber,
        selectedText: _selectedTextForApi,
        confirmedRequest: request,
      );

      final revisedPages = (previewResult['revised_pages'] as List<dynamic>)
          .map((e) => e.toString())
          .toList();

      final originalPages = (previewResult['original_pages'] as List<dynamic>)
          .map((e) => e.toString())
          .toList();

      final generatedImagePaths = _extractGeneratedImagePaths(previewResult);

      setState(() {
        _interpretedRequest = request;
        _previewRevisedPages = revisedPages;
        _originalPages = originalPages;
        _generatedImagePaths = generatedImagePaths;
        _chatMessages.add({
          'role': 'ai',
          'text': '좋아요! 말씀하신 내용으로 다시 미리보기를 만들었어요.',
        });
        _showPreviewTab = true;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _chatMessages.add({'role': 'ai', 'text': '다시 생성하는 중 오류가 발생했어요.\n$e'});
      });
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _applyPreview() async {
    if (widget.tale.storyId == null || _previewRevisedPages == null) return;

    setState(() {
      _isApplyingAsync = true;
      _errorMessage = null;
      _progressPercent = 0;
      _progressMessage = '이미지 생성 중... 진행 상황은 30초마다 갱신돼요.';
    });

    try {
      final startResult = await ApiService.applyRevisionAsync(
        storyId: widget.tale.storyId!,
        revisedPages: _previewRevisedPages!,
        confirmedRequest: _interpretedRequest,
        startPageNumber: widget.selectedPageIndex + 1,
      );

      final jobId = startResult['job_id'] as String;
      _revisionJobId = jobId;

      _progressTimer?.cancel();
      _progressTimer = Timer.periodic(const Duration(seconds: 30), (
        timer,
      ) async {
        try {
          final status = await ApiService.getRevisionJobStatus(jobId: jobId);

          if (!mounted) return;

          setState(() {
            _progressPercent = (status['progress_percent'] ?? 0) as int;
            _progressMessage = status['message']?.toString() ?? '이미지 생성 중...';
            _generatedImagePaths =
                (status['generated_image_paths'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList();
          });

          final jobStatus = (status['status'] ?? '').toString().toLowerCase();

          if (jobStatus == 'completed') {
            timer.cancel();

            final generatedImagePaths =
                (status['generated_image_paths'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                _generatedImagePaths;

            if (!mounted) return;

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AIResultScreen(
                  tale: widget.tale,
                  taleBook: widget.taleBook,
                  editedPageIndex: widget.selectedPageIndex,
                  revisedPages: _previewRevisedPages!,
                  generatedImagePaths: generatedImagePaths,
                  confirmedRequest: _interpretedRequest,
                ),
              ),
            );

            setState(() {
              _isApplyingAsync = false;
            });
          } else if (jobStatus == 'failed') {
            timer.cancel();
            if (!mounted) return;
            setState(() {
              _isApplyingAsync = false;
              _errorMessage = status['error']?.toString() ?? '이미지 생성 실패';
            });
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('적용 실패: $_errorMessage')));
          }
        } catch (e) {
          timer.cancel();
          if (!mounted) return;
          setState(() {
            _isApplyingAsync = false;
            _errorMessage = e.toString();
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('상태 조회 실패: $e')));
        }
      });
    } catch (e) {
      setState(() {
        _isApplyingAsync = false;
        _errorMessage = e.toString();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('적용 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, isTablet),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: isTablet ? 300 : 240,
                    child: _buildScriptPanel(isTablet),
                  ),
                  Expanded(child: _buildCanvasPanel(isTablet)),
                  if (_showPreviewPanel)
                    SizedBox(
                      width: isTablet ? 320 : 260,
                      child: _buildPreviewPanel(isTablet),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isTablet) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 24 : 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF8F4FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.chevron_left,
                color: Color(0xFF7E57C2),
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '장면 수정하기',
                style: TextStyle(
                  fontSize: isTablet ? 18 : 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF3D2C8D),
                ),
              ),
              Text(
                '선택한 장면을 그림으로 그리고, 바꾸고 싶은 내용을 적어주세요.',
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScriptPanel(bool isTablet) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                const Text(
                  '바꾸고 싶은 내용 선택',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3D2C8D),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _clearHighlights,
                  child: Text(
                    '초기화',
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _highlights.isEmpty
                    ? const Color(0xFFF8F4FF)
                    : const Color(0xFFEDE7F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _highlights.isEmpty ? Icons.info_outline : Icons.highlight,
                    size: 14,
                    color: _highlights.isEmpty
                        ? Colors.grey[400]
                        : const Color(0xFF7E57C2),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _highlights.isEmpty
                          ? '텍스트를 드래그해서 선택하세요'
                          : '${_highlights.length}개 구간 선택됨',
                      style: TextStyle(
                        fontSize: 11,
                        color: _highlights.isEmpty
                            ? Colors.grey[400]
                            : const Color(0xFF7E57C2),
                        fontWeight: _highlights.isEmpty
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '텍스트를 길게 눌러 드래그해서 바꾸고 싶은 부분을 선택하세요.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  _buildHighlightedText(),
                  if (_highlights.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      '선택한 구간',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[500],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._highlights.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final h = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD600).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '"${h.text}"',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF3D2C8D),
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _removeHighlight(idx),
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightedText() {
    if (_highlights.isEmpty) {
      return SelectableText(
        _fullText,
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF3D2C8D),
          height: 1.9,
        ),
        onSelectionChanged: (selection, cause) {
          if (cause == SelectionChangedCause.longPress ||
              cause == SelectionChangedCause.drag) {
            final start = selection.start;
            final end = selection.end;
            if (start >= 0 && end > start) {
              _addHighlight(start, end);
            }
          }
        },
      );
    }

    final List<TextSpan> spans = [];
    final sortedHighlights = List<HighlightRange>.from(_highlights)
      ..sort((a, b) => a.start.compareTo(b.start));

    int currentIndex = 0;
    for (final highlight in sortedHighlights) {
      if (highlight.start > currentIndex) {
        spans.add(
          TextSpan(
            text: _fullText.substring(currentIndex, highlight.start),
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF3D2C8D),
              height: 1.9,
            ),
          ),
        );
      }
      spans.add(
        TextSpan(
          text: _fullText.substring(highlight.start, highlight.end),
          style: TextStyle(
            fontSize: 14,
            color: const Color(0xFF3D2C8D),
            height: 1.9,
            fontWeight: FontWeight.w600,
            backgroundColor: const Color(0xFFFFD600).withOpacity(0.5),
          ),
        ),
      );
      currentIndex = highlight.end;
    }

    if (currentIndex < _fullText.length) {
      spans.add(
        TextSpan(
          text: _fullText.substring(currentIndex),
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF3D2C8D),
            height: 1.9,
          ),
        ),
      );
    }

    return SelectableText.rich(
      TextSpan(children: spans),
      onSelectionChanged: (selection, cause) {
        if (cause == SelectionChangedCause.longPress ||
            cause == SelectionChangedCause.drag) {
          final start = selection.start;
          final end = selection.end;
          if (start >= 0 && end > start) {
            _addHighlight(start, end);
          }
        }
      },
    );
  }

  Widget _buildCanvasPanel(bool isTablet) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                const Text(
                  '새롭게 그리고 싶은 장면을 그려주세요!',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3D2C8D),
                  ),
                ),
                const Spacer(),
                _iconBtn(Icons.undo, _undo),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _clearCanvas,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[200]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 14,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '전체 지우기',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              children: [
                _buildToolbar(),
                Expanded(child: _buildCanvas()),
              ],
            ),
          ),
          _buildColorBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_isGenerating || _isApplyingAsync)
                        ? null
                        : _generatePreviewFlow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7E57C2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _isGenerating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('AI로 수정 결과 미리보기'),
                  ),
                ),
                if (_isApplyingAsync) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: (_progressPercent / 100).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: const Color(0xFFEDE7F6),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF7E57C2)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _progressMessage ?? '이미지 생성 중...',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7E57C2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_progressPercent%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3D2C8D),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[200]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: Colors.grey[500]),
      ),
    );
  }

  Widget _buildToolbar() {
    final tools = [
      {'icon': Icons.edit, 'label': '펜'},
      {'icon': Icons.auto_fix_high, 'label': '지우개'},
    ];

    return Container(
      width: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: tools.map((tool) {
          final isActive =
              tool['label'] == '펜' && !_isEraser ||
              tool['label'] == '지우개' && _isEraser;
          return GestureDetector(
            onTap: () {
              if (tool['label'] == '펜') setState(() => _isEraser = false);
              if (tool['label'] == '지우개') setState(() => _isEraser = true);
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              width: 44,
              height: 52,
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFFEDE7F6) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    tool['icon'] as IconData,
                    size: 20,
                    color: isActive
                        ? const Color(0xFF7E57C2)
                        : Colors.grey[500],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tool['label'] as String,
                    style: TextStyle(
                      fontSize: 9,
                      color: isActive
                          ? const Color(0xFF7E57C2)
                          : Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCanvas() {
    return RepaintBoundary(
      key: _sketchKey,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: Colors.white,
          child: GestureDetector(
            onPanStart: (details) {
              setState(() {
                _currentPath = DrawingPath(
                  color: _isEraser ? Colors.white : _selectedColor,
                  strokeWidth: _isEraser ? 24 : _strokeWidth,
                  points: [details.localPosition],
                );
                _paths.add(_currentPath!);
              });
            },
            onPanUpdate: (details) {
              setState(() {
                _currentPath?.points.add(details.localPosition);
              });
            },
            onPanEnd: (_) => _currentPath = null,
            child: CustomPaint(
              painter: DrawingPainter(_paths),
              child: Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.transparent,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          ..._colorPalette.map((color) {
            final isSelected = _selectedColor == color && !_isEraser;
            return GestureDetector(
              onTap: () => setState(() {
                _selectedColor = color;
                _isEraser = false;
              }),
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF7E57C2)
                        : Colors.grey[300]!,
                    width: isSelected ? 2.5 : 1,
                  ),
                ),
              ),
            );
          }),
          const SizedBox(width: 12),
          Text('굵기', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          Expanded(
            child: Slider(
              value: _strokeWidth,
              min: 2,
              max: 30,
              activeColor: const Color(0xFF7E57C2),
              onChanged: (v) => setState(() => _strokeWidth = v),
            ),
          ),
          Text(
            '${_strokeWidth.round()}px',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPanel(bool isTablet) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              children: [
                const Text(
                  '수정 결과 미리보기',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3D2C8D),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _showPreviewPanel = false),
                  child: const Icon(Icons.close, size: 18, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                _previewTab('미리보기', true),
                const SizedBox(width: 8),
                _previewTab('AI와 이야기하기', false),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          Expanded(
            child: _showPreviewTab
                ? _buildPreviewContent()
                : _buildChatContent(),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        (_previewRevisedPages == null ||
                            _isGenerating ||
                            _isApplyingAsync)
                        ? null
                        : _applyPreview,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7E57C2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      minimumSize: const Size(0, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: _isApplyingAsync
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '이대로 적용하기',
                            style: TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ),

                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isApplyingAsync
                        ? null
                        : () {
                            setState(() {
                              _showPreviewPanel = false;
                              _paths.clear();
                              _currentPath = null;
                              _previewRevisedPages = null;
                              _originalPages = null;
                              _generatedImagePaths = null;
                              _interpretedRequest = null;
                              _errorMessage = null;
                              _progressPercent = 0;
                              _progressMessage = null;
                            });
                          },
                    child: const Text('다시 그리기'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewTab(String label, bool isPreview) {
    final isActive = _showPreviewTab == isPreview;
    return GestureDetector(
      onTap: () => setState(() => _showPreviewTab = isPreview),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF7E57C2) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? const Color(0xFF7E57C2) : Colors.grey[200]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? Colors.white : Colors.grey[500],
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_highlights.isNotEmpty) ...[
            Text(
              '바뀌는 내용',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 8),
            ..._highlights.map(
              (h) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F4FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '"${h.text}"',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7E57C2),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward,
                      size: 14,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _interpretedRequest == null
                            ? 'AI가 바꾸는 중이에요'
                            : _interpretedRequest!,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (_previewRevisedPages != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEDE7F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_changedPagesSummary()}가 새 흐름에 맞게 다시 구성되었어요.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7E57C2),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_generatedImagePaths != null &&
                      _generatedImagePaths!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '생성 이미지 ${_generatedImagePaths!.length}개가 준비되었어요.',
                      style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                    ),
                  ],
                  if (_isApplyingAsync) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: (_progressPercent / 100).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: Colors.white,
                      valueColor: const AlwaysStoppedAnimation(
                        Color(0xFF7E57C2),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _progressMessage ?? '이미지 생성 중...',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF7E57C2),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (_errorMessage != null)
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
        ],
      ),
    );
  }

  Widget _buildChatContent() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _chatBubble(
                'ai',
                _interpretedRequest == null
                    ? '어때요? 마음에 드나요?\n더 바꾸고 싶은 점이 있으면 저에게 이야기해 주세요!'
                    : '현재 이렇게 이해하고 있어요:\n$_interpretedRequest',
              ),
              ..._chatMessages.map(
                (msg) => _chatBubble(msg['role']!, msg['text']!),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Colors.grey[200]!)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '원하는 수정 내용을 말해보세요...',
                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => _regenerateFromChat(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _regenerateFromChat,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFF7E57C2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send, size: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chatBubble(String role, String text) {
    final isAI = role == 'ai';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isAI
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isAI) ...[
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: Color(0xFFEDE7F6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.emoji_nature,
                size: 16,
                color: Color(0xFF7E57C2),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            constraints: const BoxConstraints(maxWidth: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isAI ? const Color(0xFFEDE7F6) : const Color(0xFF7E57C2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: isAI ? const Color(0xFF3D2C8D) : Colors.white,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
