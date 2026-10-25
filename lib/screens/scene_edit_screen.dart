import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_theme.dart';
import '../widgets/crayong_widgets.dart';
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

  Color _selectedColor = const Color(0xFF3B2F27);
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

  final List<Color> _colorPalette = const [
    Color(0xFF3B2F27),
    Color(0xFFE53935),
    Color(0xFFFF8F00),
    Color(0xFFFFD600),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Color(0xFF5E35B1),
    Color(0xFF795548),
    Color(0xFFEC407A),
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

  void _showMessage(String text, {String image = CrayongImages.wink}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Image.asset(image, width: 30, height: 30),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: AppTextStyles.labelLarge(color: Colors.white))),
          ],
        ),
      ),
    );
  }

  String _friendlyError(Object e, String fallback) => kDebugMode ? '$fallback\n$e' : fallback;

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
    if (_previewRevisedPages == null || _previewRevisedPages!.isEmpty) {
      return '';
    }
    const startPage = 1;
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

      _highlights.add(HighlightRange(start: start, end: end, text: selectedText));
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
    final boundary = _sketchKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _generatePreviewFlow() async {
    if (widget.tale.storyId == null) {
      _showMessage('서버에 있는 동화만 바꿀 수 있어요.', image: CrayongImages.surprised);
      return;
    }

    if (_highlights.isEmpty) {
      _showMessage('먼저 바꾸고 싶은 문장을 손가락으로 쭉 칠해 줘요.', image: CrayongImages.surprised);
      return;
    }

    if (!_hasSketch) {
      _showMessage('그림판에 바꾸고 싶은 장면을 그려 줘요.', image: CrayongImages.painter);
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
      final pageNumber = widget.taleBook.pages[widget.selectedPageIndex].pageNumber;

      final interpretResult = await ApiService.sketchInterpret(
        storyId: widget.tale.storyId!,
        pageNumber: pageNumber,
        selectedText: selectedText,
        sketchBytes: sketchBytes,
      );

      final interpreted = interpretResult['interpreted_request'] as String? ?? '';

      if (!mounted) return;
      setState(() {
        _interpretedRequest = interpreted;
        _chatMessages.add({
          'role': 'ai',
          'text': interpreted.isEmpty
              ? '앗, 그림을 잘 못 알아봤어요. 조금 더 크게 그려 줄래요?'
              : '크레용은 이렇게 이해했어요!\n$interpreted',
        });
      });

      final previewResult = await ApiService.sketchRevisePreview(
        storyId: widget.tale.storyId!,
        pageNumber: pageNumber,
        selectedText: selectedText,
        confirmedRequest: interpreted,
      );

      final revisedPages = (previewResult['revised_pages'] as List<dynamic>).map((e) => e.toString()).toList();
      final originalPages = (previewResult['original_pages'] as List<dynamic>).map((e) => e.toString()).toList();
      final generatedImagePaths = _extractGeneratedImagePaths(previewResult);

      if (!mounted) return;
      setState(() {
        _previewRevisedPages = revisedPages;
        _originalPages = originalPages;
        _generatedImagePaths = generatedImagePaths;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(e, '이야기를 바꾸다가 문제가 생겼어요.');
        _chatMessages.add({'role': 'ai', 'text': _friendlyError(e, '앗, 이야기를 바꾸다가 문제가 생겼어요. 다시 해 볼까요?')});
      });
      _showMessage('미리보기를 못 만들었어요. 다시 해 볼래요?', image: CrayongImages.surprised);
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _regenerateFromChat() async {
    if (widget.tale.storyId == null) return;

    final request = _chatController.text.trim();
    if (request.isEmpty) return;

    if (_highlights.isEmpty) {
      _showMessage('먼저 바꾸고 싶은 문장을 칠해 줘요.', image: CrayongImages.surprised);
      return;
    }

    setState(() {
      _chatMessages.add({'role': 'user', 'text': request});
      _chatController.clear();
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final pageNumber = widget.taleBook.pages[widget.selectedPageIndex].pageNumber;

      final previewResult = await ApiService.sketchRevisePreview(
        storyId: widget.tale.storyId!,
        pageNumber: pageNumber,
        selectedText: _selectedTextForApi,
        confirmedRequest: request,
      );

      final revisedPages = (previewResult['revised_pages'] as List<dynamic>).map((e) => e.toString()).toList();
      final originalPages = (previewResult['original_pages'] as List<dynamic>).map((e) => e.toString()).toList();
      final generatedImagePaths = _extractGeneratedImagePaths(previewResult);

      if (!mounted) return;
      setState(() {
        _interpretedRequest = request;
        _previewRevisedPages = revisedPages;
        _originalPages = originalPages;
        _generatedImagePaths = generatedImagePaths;
        _chatMessages.add({'role': 'ai', 'text': '좋아요! 말한 대로 다시 바꿔 봤어요.'});
        _showPreviewTab = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(e, '다시 바꾸다가 문제가 생겼어요.');
        _chatMessages.add({'role': 'ai', 'text': _friendlyError(e, '앗, 다시 바꾸다가 문제가 생겼어요.')});
      });
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _applyPreview() async {
    if (widget.tale.storyId == null || _previewRevisedPages == null) return;

    setState(() {
      _isApplyingAsync = true;
      _errorMessage = null;
      _progressPercent = 0;
      _progressMessage = '크레용이 새 그림을 그리고 있어요. 30초마다 알려 줄게요.';
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
      _progressTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
        try {
          final status = await ApiService.getRevisionJobStatus(jobId: jobId);

          if (!mounted) return;

          setState(() {
            _progressPercent = (status['progress_percent'] ?? 0) as int;
            _progressMessage = status['message']?.toString() ?? '크레용이 새 그림을 그리고 있어요.';
            _generatedImagePaths = (status['generated_image_paths'] as List<dynamic>?)?.map((e) => e.toString()).toList();
          });

          final jobStatus = (status['status'] ?? '').toString().toLowerCase();

          if (jobStatus == 'completed') {
            timer.cancel();

            final generatedImagePaths =
                (status['generated_image_paths'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? _generatedImagePaths;

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
              _errorMessage = status['error']?.toString() ?? '그림을 못 그렸어요.';
            });
            _showMessage(kDebugMode ? '적용 실패: $_errorMessage' : '그림을 못 그렸어요. 다시 해 볼래요?', image: CrayongImages.surprised);
          }
        } catch (e) {
          timer.cancel();
          if (!mounted) return;
          setState(() {
            _isApplyingAsync = false;
            _errorMessage = _friendlyError(e, '진행 상황을 못 가져왔어요.');
          });
          _showMessage('진행 상황을 못 가져왔어요.', image: CrayongImages.surprised);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isApplyingAsync = false;
        _errorMessage = _friendlyError(e, '적용하다가 문제가 생겼어요.');
      });
      _showMessage('적용하다가 문제가 생겼어요. 다시 해 볼래요?', image: CrayongImages.surprised);
    }
  }

  void _resetAll() {
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
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTablet = width >= 700;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isTablet),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: isTablet ? 300 : 240, child: _buildScriptPanel()),
                    const SizedBox(width: 14),
                    Expanded(child: _buildCanvasPanel()),
                    if (_showPreviewPanel) ...[
                      const SizedBox(width: 14),
                      SizedBox(width: isTablet ? 340 : 260, child: _buildPreviewPanel()),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isTablet) {
    final page = widget.taleBook.pages[widget.selectedPageIndex];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(
        children: [
          RoundIconButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('장면 바꾸기', style: AppTextStyles.headingLarge()),
                Text(
                  '${widget.tale.title} · ${page.pageNumber}번 장면',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (isTablet) _buildStepIndicator(),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    const steps = ['동화 읽기', '장면 고르기', '장면 바꾸기'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: i < 2 ? AppColors.secondaryDark : AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: i < 2
                    ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                    : Text('3', style: AppTextStyles.labelSmall(color: AppColors.onPrimary)),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              steps[i],
              style: i == 2
                  ? AppTextStyles.headingSmall().copyWith(fontSize: 16, height: 1.1)
                  : AppTextStyles.labelSmall(color: AppColors.textHint),
            ),
            if (i < steps.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textHint),
              ),
          ],
        ],
      ),
    );
  }

  Widget _panelTitle(int step, String title, {Widget? trailing}) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: AppDecorations.sticker(
            color: AppColors.primary,
            shadowColor: AppColors.primaryDark,
            radius: 14,
            depth: 2,
          ),
          child: Center(child: Text('$step', style: AppTextStyles.labelMedium(color: AppColors.onPrimary))),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: AppTextStyles.headingSmall())),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _textAction(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(label, style: AppTextStyles.labelSmall(color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScriptPanel() {
    return Container(
      decoration: AppDecorations.card(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 14, 10),
            child: _panelTitle(
              1,
              '바꿀 문장 칠하기',
              trailing: _highlights.isEmpty ? null : _textAction('다 지우기', Icons.refresh_rounded, _clearHighlights),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _highlights.isEmpty ? AppColors.surfaceVariant : AppColors.primaryLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    _highlights.isEmpty ? Icons.touch_app_rounded : Icons.check_circle_rounded,
                    size: 17,
                    color: AppColors.primaryText,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _highlights.isEmpty ? '문장을 꾹 누르고 쭉 끌어서 칠해요' : '${_highlights.length}곳을 칠했어요',
                      style: AppTextStyles.labelMedium(color: AppColors.primaryText),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHighlightedText(),
                  if (_highlights.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text('칠한 문장', style: AppTextStyles.labelMedium()),
                    const SizedBox(height: 8),
                    ..._highlights.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final h = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '"${h.text}"',
                                style: AppTextStyles.bodySmall(color: AppColors.textPrimary),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _removeHighlight(idx),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.close_rounded, size: 18, color: AppColors.primaryText),
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
    final baseStyle = AppTextStyles.storyBody(fontSize: 17).copyWith(height: 1.9);

    void onSelection(TextSelection selection, SelectionChangedCause? cause) {
      if (cause == SelectionChangedCause.longPress || cause == SelectionChangedCause.drag) {
        final start = selection.start;
        final end = selection.end;
        if (start >= 0 && end > start) {
          _addHighlight(start, end);
        }
      }
    }

    if (_highlights.isEmpty) {
      return SelectableText(_fullText, style: baseStyle, onSelectionChanged: onSelection);
    }

    final List<TextSpan> spans = [];
    final sortedHighlights = List<HighlightRange>.from(_highlights)..sort((a, b) => a.start.compareTo(b.start));

    int currentIndex = 0;
    for (final highlight in sortedHighlights) {
      if (highlight.start > currentIndex) {
        spans.add(TextSpan(text: _fullText.substring(currentIndex, highlight.start), style: baseStyle));
      }
      spans.add(
        TextSpan(
          text: _fullText.substring(highlight.start, highlight.end),
          style: baseStyle.copyWith(
            fontWeight: FontWeight.w700,
            backgroundColor: const Color(0x99FFD35A),
          ),
        ),
      );
      currentIndex = highlight.end;
    }

    if (currentIndex < _fullText.length) {
      spans.add(TextSpan(text: _fullText.substring(currentIndex), style: baseStyle));
    }

    return SelectableText.rich(TextSpan(children: spans), onSelectionChanged: onSelection);
  }

  Widget _buildCanvasPanel() {
    final busy = _isGenerating || _isApplyingAsync;
    return Container(
      decoration: AppDecorations.card(radius: 24),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: _panelTitle(
              2,
              '새 장면 그리기',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _textAction('되돌리기', Icons.undo_rounded, _undo),
                  const SizedBox(width: 6),
                  _textAction('다 지우기', Icons.delete_outline_rounded, _clearCanvas),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _buildToolbar(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.border, width: 2),
                      ),
                      child: _buildCanvas(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildColorBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              children: [
                _BigStickerButton(
                  label: _isGenerating ? '크레용이 생각하고 있어요...' : '크레용에게 보내기',
                  icon: Icons.auto_awesome_rounded,
                  loading: _isGenerating,
                  onTap: busy ? null : _generatePreviewFlow,
                ),
                if (_isApplyingAsync) ...[
                  const SizedBox(height: 12),
                  _buildProgress(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.secondaryLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Image.asset(CrayongImages.drawing, height: 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _progressMessage ?? '크레용이 새 그림을 그리고 있어요.',
                        style: AppTextStyles.bodySmall(color: const Color(0xFF3E6F2E)),
                      ),
                    ),
                    Text('$_progressPercent%', style: AppTextStyles.headingSmall()),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: (_progressPercent / 100).clamp(0.0, 1.0),
                  minHeight: 8,
                  borderRadius: const BorderRadius.all(Radius.circular(4)),
                  backgroundColor: AppColors.surface,
                  valueColor: const AlwaysStoppedAnimation(AppColors.secondaryDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    final tools = [
      {'icon': Icons.edit_rounded, 'label': '펜', 'eraser': false},
      {'icon': Icons.auto_fix_normal_rounded, 'label': '지우개', 'eraser': true},
    ];

    return Column(
      children: tools.map((tool) {
        final isEraserTool = tool['eraser'] as bool;
        final isActive = isEraserTool == _isEraser;
        return GestureDetector(
          onTap: () => setState(() => _isEraser = isEraserTool),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.only(bottom: 8),
              width: 56,
              height: 60,
              decoration: BoxDecoration(
                color: isActive ? AppColors.primaryLight : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isActive ? AppColors.primary : Colors.transparent, width: 2),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(tool['icon'] as IconData, size: 22, color: isActive ? AppColors.textPrimary : AppColors.textHint),
                  const SizedBox(height: 2),
                  Text(
                    tool['label'] as String,
                    style: AppTextStyles.labelSmall(color: isActive ? AppColors.textPrimary : AppColors.textHint),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCanvas() {
    return RepaintBoundary(
      key: _sketchKey,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _colorPalette.map((color) {
                final isSelected = _selectedColor == color && !_isEraser;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedColor = color;
                    _isEraser = false;
                  }),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: isSelected ? 34 : 30,
                      height: isSelected ? 34 : 30,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? AppColors.surface : AppColors.border,
                          width: isSelected ? 3 : 2,
                        ),
                        boxShadow: isSelected
                            ? const [BoxShadow(color: AppColors.primary, blurRadius: 0, spreadRadius: 3)]
                            : null,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(width: 12),
          Text('굵기', style: AppTextStyles.labelMedium()),
          SizedBox(
            width: 140,
            child: Slider(
              value: _strokeWidth,
              min: 2,
              max: 30,
              onChanged: (v) => setState(() => _strokeWidth = v),
            ),
          ),
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            child: Container(
              width: _strokeWidth.clamp(4.0, 30.0),
              height: _strokeWidth.clamp(4.0, 30.0),
              decoration: BoxDecoration(
                color: _isEraser ? AppColors.border : _selectedColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPanel() {
    final canApply = _previewRevisedPages != null && !_isGenerating && !_isApplyingAsync;
    return Container(
      decoration: AppDecorations.card(radius: 24),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 0),
            child: Row(
              children: [
                Image.asset(CrayongImages.wink, height: 36),
                const SizedBox(width: 8),
                Expanded(child: Text('크레용이 바꾼 이야기', style: AppTextStyles.headingSmall())),
                IconButton(
                  onPressed: () => setState(() => _showPreviewPanel = false),
                  icon: const Icon(Icons.close_rounded, color: AppColors.textHint),
                  tooltip: '닫기',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            child: Row(
              children: [
                Expanded(child: _previewTab('미리보기', true)),
                const SizedBox(width: 8),
                Expanded(child: _previewTab('크레용과 이야기', false)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(child: _showPreviewTab ? _buildPreviewContent() : _buildChatContent()),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: _isApplyingAsync ? null : _resetAll,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        side: const BorderSide(color: AppColors.border, width: 2),
                      ),
                      child: const Text('다시 그리기'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: canApply ? _applyPreview : null,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                      child: _isApplyingAsync
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onPrimary),
                            )
                          : const Text('이대로 할래요', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
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
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: AppTextStyles.headingSmall(
              color: isActive ? AppColors.onPrimary : AppColors.textSecondary,
            ).copyWith(fontSize: 16, height: 1.1),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewContent() {
    if (_isGenerating && _previewRevisedPages == null) {
      return const CrayongStatusView(
        image: CrayongImages.drawing,
        imageHeight: 120,
        title: '크레용이 이야기를 바꾸고 있어요',
        child: SizedBox(
          width: 140,
          child: LinearProgressIndicator(minHeight: 6, borderRadius: BorderRadius.all(Radius.circular(3))),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_highlights.isNotEmpty) ...[
            Text('이렇게 바뀌어요', style: AppTextStyles.labelMedium()),
            const SizedBox(height: 8),
            ..._highlights.map(
              (h) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '"${h.text}"',
                      style: AppTextStyles.bodySmall(color: AppColors.textSecondary).copyWith(
                        decoration: TextDecoration.lineThrough,
                        decorationColor: AppColors.textHint,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Icon(Icons.arrow_downward_rounded, size: 16, color: AppColors.primaryText),
                    ),
                    Text(
                      _interpretedRequest == null ? '크레용이 바꾸는 중이에요' : _interpretedRequest!,
                      style: AppTextStyles.bodyMedium(color: AppColors.textPrimary),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (_previewRevisedPages != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.secondaryLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.secondaryDark),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${_changedPagesSummary()}를 새 이야기에 맞게 다시 썼어요.',
                          style: AppTextStyles.labelMedium(color: const Color(0xFF3E6F2E)),
                        ),
                      ),
                    ],
                  ),
                  if (_generatedImagePaths != null && _generatedImagePaths!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '새 그림 ${_generatedImagePaths!.length}장이 준비됐어요.',
                      style: AppTextStyles.bodySmall(color: const Color(0xFF3E6F2E)),
                    ),
                  ],
                  if (_isApplyingAsync) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: (_progressPercent / 100).clamp(0.0, 1.0),
                      minHeight: 8,
                      borderRadius: const BorderRadius.all(Radius.circular(4)),
                      backgroundColor: AppColors.surface,
                      valueColor: const AlwaysStoppedAnimation(AppColors.secondaryDark),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _progressMessage ?? '크레용이 새 그림을 그리고 있어요.',
                      style: AppTextStyles.bodySmall(color: const Color(0xFF3E6F2E)),
                    ),
                  ],
                ],
              ),
            ),
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(CrayongImages.surprised, height: 36),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_errorMessage!, style: AppTextStyles.bodySmall(color: AppColors.error))),
                ],
              ),
            ),
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
                    ? '어때요? 마음에 들어요?\n더 바꾸고 싶은 게 있으면 크레용한테 말해 줘요!'
                    : '지금은 이렇게 바꾸고 있어요.\n$_interpretedRequest',
              ),
              ..._chatMessages.map((msg) => _chatBubble(msg['role']!, msg['text']!)),
              if (_isGenerating) _chatBubble('ai', '음... 생각하는 중이에요.'),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border, width: 1.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  style: AppTextStyles.bodyMedium(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: '이렇게 바꿔 줘!',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: AppColors.border, width: 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: AppColors.border, width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: AppColors.primary, width: 2),
                    ),
                  ),
                  onSubmitted: (_) => _regenerateFromChat(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _isGenerating ? null : _regenerateFromChat,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: AppDecorations.primaryButton(radius: 22, depth: 3),
                    child: const Icon(Icons.send_rounded, size: 20, color: AppColors.onPrimary),
                  ),
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
        mainAxisAlignment: isAI ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isAI) ...[
            Container(
              width: 34,
              height: 34,
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(color: AppColors.secondaryLight, shape: BoxShape.circle),
              child: Image.asset(CrayongImages.wink),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 230),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: isAI ? AppColors.secondaryLight : AppColors.primaryLight,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isAI ? 4 : 16),
                  topRight: Radius.circular(isAI ? 16 : 4),
                  bottomLeft: const Radius.circular(16),
                  bottomRight: const Radius.circular(16),
                ),
              ),
              child: Text(
                text,
                style: AppTextStyles.bodySmall(
                  color: isAI ? const Color(0xFF2F4F24) : AppColors.textPrimary,
                ).copyWith(height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BigStickerButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback? onTap;

  const _BigStickerButton({
    required this.label,
    required this.icon,
    required this.loading,
    required this.onTap,
  });

  @override
  State<_BigStickerButton> createState() => _BigStickerButtonState();
}

class _BigStickerButtonState extends State<_BigStickerButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const depth = 5.0;
    final enabled = widget.onTap != null;
    final down = _pressed && enabled;

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 58,
          width: double.infinity,
          transform: Matrix4.translationValues(0, down ? depth : 0, 0),
          decoration: AppDecorations.sticker(
            color: enabled || widget.loading ? AppColors.primary : AppColors.surfaceVariant,
            shadowColor: enabled || widget.loading ? AppColors.primaryDark : AppColors.border,
            radius: 20,
            depth: down ? 0 : depth,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.loading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onPrimary),
                )
              else
                Icon(widget.icon, size: 22, color: AppColors.onPrimary),
              const SizedBox(width: 10),
              Text(widget.label, style: AppTextStyles.button().copyWith(fontSize: 22)),
            ],
          ),
        ),
      ),
    );
  }
}