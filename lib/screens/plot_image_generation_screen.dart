import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'fairy_tale_list_screen.dart';
import 'tale_reading_screen.dart';

class PlotImageGenerationScreen extends StatefulWidget {
  final FairyTale tale;
  final TaleBook taleBook;
  final int editedPageIndex;

  const PlotImageGenerationScreen({
    super.key,
    required this.tale,
    required this.taleBook,
    required this.editedPageIndex,
  });

  @override
  State<PlotImageGenerationScreen> createState() =>
      _PlotImageGenerationScreenState();
}

class _PlotImageGenerationScreenState extends State<PlotImageGenerationScreen> {
  bool _isLoading = true;
  bool _isStarting = false;
  bool _isApplying = false;
  bool _isPreparingPlots = false;
  String? _errorMessage;

  List<dynamic> _plots = [];
  List<dynamic> _plotContents = [];
  Map<String, dynamic>? _statusData;
  Timer? _pollingTimer;

  int get _storyId => widget.tale.storyId ?? -1;

  int get _startPlotNumber {
    if (_plots.isEmpty) return widget.editedPageIndex + 1;
    final raw = widget.editedPageIndex + 1;
    if (raw < 1) return 1;
    if (raw > _plots.length) return _plots.length;
    return raw;
  }

  @override
  void initState() {
    super.initState();
    _prepareAndLoad();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _prepareAndLoad() async {
    if (_storyId <= 0) {
      setState(() {
        _errorMessage = 'storyId가 없어 플롯 이미지를 생성할 수 없어요.';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _isPreparingPlots = true;
      _errorMessage = null;
    });

    try {
      var plots = await ApiService.getPlots(_storyId);

      if (plots.isEmpty) {
        await ApiService.rearrangePlots(
          storyId: _storyId,
          plotCount: widget.taleBook.pages.length,
        );
        plots = await ApiService.getPlots(_storyId);
      }

      var contents = await ApiService.getPlotContents(_storyId);

      if (contents.isEmpty) {
        await ApiService.generatePlotContents(storyId: _storyId);
        contents = await ApiService.getPlotContents(_storyId);
      }

      Map<String, dynamic>? status;
      try {
        status =
            await ApiService.getPlotImageGenerationStatus(storyId: _storyId);
      } catch (_) {
        status = null;
      }

      if (!mounted) return;

      setState(() {
        _plots = plots;
        _plotContents = contents;
        _statusData = status;
        _isLoading = false;
        _isPreparingPlots = false;
      });

      _handlePollingByStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
        _isPreparingPlots = false;
      });
    }
  }

  Future<void> _startGeneration() async {
    setState(() {
      _isStarting = true;
      _errorMessage = null;
    });

    try {
      if (_plots.isEmpty) {
        await ApiService.rearrangePlots(
          storyId: _storyId,
          plotCount: widget.taleBook.pages.length,
        );
        _plots = await ApiService.getPlots(_storyId);
      }

      if (_plotContents.isEmpty) {
        await ApiService.generatePlotContents(storyId: _storyId);
        _plotContents = await ApiService.getPlotContents(_storyId);
      }

      await ApiService.regeneratePlotImagesFrom(
        storyId: _storyId,
        startPlotNumber: _startPlotNumber,
      );

      await _refreshStatus();
      _startPolling();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$_startPlotNumber번 플롯부터 이미지 생성을 시작했어요.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('시작 실패: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isStarting = false);
      }
    }
  }

  Future<void> _applyToStoryPages() async {
    setState(() {
      _isApplying = true;
      _errorMessage = null;
    });

    try {
      await ApiService.applyPlotImagesToPages(
        storyId: _storyId,
        startPlotNumber: _startPlotNumber,
      );

      await ApiService.saveAsMyStory(_storyId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('나의 책장에 저장되었어요.')),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const FairyTaleListScreen(
            initialTab: FairyTaleTab.myBookshelf,
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isApplying = false);
      }
    }
  }

  Future<void> _refreshStatus() async {
    final status = await ApiService.getPlotImageGenerationStatus(storyId: _storyId);
    if (!mounted) return;
    setState(() {
      _statusData = status;
    });
    _handlePollingByStatus();
  }

  void _handlePollingByStatus() {
    final status = (_statusData?['status'] ?? '').toString().toLowerCase();
    if (status == 'processing' || status == 'running') {
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        await _refreshStatus();
      } catch (_) {}
    });
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  String _contentForPlot(int plotNumber) {
    final matched = _plotContents.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['plot_number'] == plotNumber,
          orElse: () => null,
        );
    return matched?['content']?.toString() ?? '';
  }

  Map<String, dynamic>? _plotStatus(int plotNumber) {
    final plots = (_statusData?['plots'] as List?) ?? [];
    for (final item in plots) {
      final map = item as Map<String, dynamic>;
      if (map['plot_number'] == plotNumber) return map;
    }
    return null;
  }

  bool _isBeforeStartPlot(int plotNumber) => plotNumber < _startPlotNumber;

  bool get _canApplyFinalImages {
    if (_plots.isEmpty) return false;
    for (final raw in _plots) {
      final plot = raw as Map<String, dynamic>;
      final plotNumber = plot['plot_number'] as int;
      if (_isBeforeStartPlot(plotNumber)) continue;

      final statusMap = _plotStatus(plotNumber);
      final status = statusMap?['image_status']?.toString() ??
          plot['image_status']?.toString() ??
          'pending';

      if (status.toLowerCase() != 'completed') {
        return false;
      }
    }
    return true;
  }

  String _statusText(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'completed':
        return '완료';
      case 'processing':
      case 'running':
        return '생성 중';
      case 'failed':
        return '실패';
      default:
        return '대기 중';
    }
  }

  Color _statusColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'completed':
        return const Color(0xFF43A047);
      case 'processing':
      case 'running':
        return const Color(0xFF7E57C2);
      case 'failed':
        return const Color(0xFFE53935);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final progressPercent =
        ((_statusData?['progress_percent'] ?? 0) as num).toDouble();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF3D2C8D),
        elevation: 0,
        title: const Text('플롯 이미지 만들기'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF7E57C2)),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              : Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '진행 상황',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF3D2C8D),
                            ),
                          ),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value: (progressPercent / 100).clamp(0.0, 1.0),
                            minHeight: 10,
                            backgroundColor: const Color(0xFFEDE7F6),
                            valueColor: const AlwaysStoppedAnimation(
                              Color(0xFF7E57C2),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: _plots.length,
                        itemBuilder: (context, index) {
                          final plot = _plots[index] as Map<String, dynamic>;
                          final plotNumber = plot['plot_number'] as int;
                          final summary = plot['summary']?.toString() ?? '';
                          final content = _contentForPlot(plotNumber);
                          final statusMap = _plotStatus(plotNumber);
                          final status = statusMap?['image_status']?.toString() ??
                              plot['image_status']?.toString() ??
                              'pending';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'PLOT $plotNumber',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF7E57C2),
                                      ),
                                    ),
                                    const Spacer(),
                                    if (_isBeforeStartPlot(plotNumber))
                                      const Text(
                                        '유지',
                                        style: TextStyle(color: Colors.grey),
                                      )
                                    else
                                      Text(
                                        _statusText(status),
                                        style: TextStyle(
                                          color: _statusColor(status),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  summary,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF3D2C8D),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  content,
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: _isBeforeStartPlot(plotNumber)
                                      ? Image.network(
                                          '${ApiService.storyPageImageUrl(_storyId, plotNumber)}?ts=${DateTime.now().millisecondsSinceEpoch}',
                                          height: 180,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                        )
                                      : status.toLowerCase() == 'completed'
                                          ? Image.network(
                                              '${ApiService.plotImageUrl(_storyId, plotNumber)}?ts=${DateTime.now().millisecondsSinceEpoch}',
                                              height: 180,
                                              width: double.infinity,
                                              fit: BoxFit.cover,
                                            )
                                          : Container(
                                              height: 180,
                                              color: const Color(0xFFF8F4FF),
                                              child: Center(
                                                child: Text(
                                                  _statusText(status),
                                                  style: const TextStyle(
                                                    color: Color(0xFF7E57C2),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: (_isStarting || _isPreparingPlots)
                                  ? null
                                  : _startGeneration,
                              child: Text(_isStarting ? '시작 중...' : '수정 이후 생성 시작'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: (!_canApplyFinalImages || _isApplying)
                                  ? null
                                  : _applyToStoryPages,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7E57C2),
                                foregroundColor: Colors.white,
                              ),
                              child: _isApplying
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('나의 책장에 저장'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}