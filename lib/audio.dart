import 'package:flutter/material.dart';
import 'show.dart';
//오디오 페이지

class AudioPlayerPage extends StatefulWidget {
  const AudioPlayerPage({super.key});

  @override
  State<AudioPlayerPage> createState() => _AudioPlayerPageState();
}

class _AudioPlayerPageState extends State<AudioPlayerPage> {
  bool _isPlaying = true;
  double _progress = 0.27; // 02:18 / 08:45 기준
  int _currentTrack = 1;
  final int _totalTracks = 8;

  String _formatTime(double ratio, double totalSeconds) {
    final seconds = (ratio * totalSeconds).round();
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    const double totalSeconds = 525; // 08:45

    return Scaffold(
      backgroundColor: const Color(0xfffff8fb),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ 상단 헤더
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.07),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Color(0xff8a63df),
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  const Text(
                    '오디오 듣기',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xff2d2323),
                    ),
                  ),
                  const Spacer(),
                  // ✅ 공유 버튼
                  _iconButton(Icons.ios_share_rounded),
                  const SizedBox(width: 12),
                  // ✅ 북마크 버튼
                  _iconButton(Icons.bookmark_border_rounded),
                ],
              ),

              const SizedBox(height: 32),

              // ✅ 메인 콘텐츠 (좌: 앨범아트 / 우: 플레이어)
              Expanded(
                child: Row(
                  children: [
                    // ✅ 좌측 앨범 아트
                    Container(
                      width: 340,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xff8a63df).withOpacity(0.25),
                            blurRadius: 40,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: Image.asset(
                          'lib/assets/girls.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),

                    const SizedBox(width: 52),

                    // ✅ 우측 플레이어 컨트롤
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 제목 + 트랙 번호
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                '빨간 망토',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xff2d2323),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  '$_currentTrack / $_totalTracks',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xffaaa4b3),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 40),

                          // ✅ 재생 컨트롤 버튼
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              // 이전 트랙
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (_currentTrack > 1) _currentTrack--;
                                    _progress = 0;
                                  });
                                },
                                child: Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(22),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.fast_rewind_rounded,
                                    color: Color(0xff8a63df),
                                    size: 28,
                                  ),
                                ),
                              ),

                              const SizedBox(width: 20),

                              // 재생/일시정지
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _isPlaying = !_isPlaying;
                                  });
                                },
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xff9d73ff),
                                        Color(0xff8a63df),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(28),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xff8a63df)
                                            .withOpacity(0.45),
                                        blurRadius: 24,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    _isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                              ),

                              const SizedBox(width: 20),

                              // 다음 트랙
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (_currentTrack < _totalTracks) {
                                      _currentTrack++;
                                    }
                                    _progress = 0;
                                  });
                                },
                                child: Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(22),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.fast_forward_rounded,
                                    color: Color(0xff8a63df),
                                    size: 28,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 44),

                          // ✅ 프로그레스 바
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 6,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 10,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 20,
                              ),
                              activeTrackColor: const Color(0xff8a63df),
                              inactiveTrackColor: const Color(0xffe8e0f5),
                              thumbColor: const Color(0xff8a63df),
                              overlayColor:
                                  const Color(0xff8a63df).withOpacity(0.15),
                            ),
                            child: Slider(
                              value: _progress,
                              onChanged: (value) {
                                setState(() {
                                  _progress = value;
                                });
                              },
                            ),
                          ),

                          // 시간 표시
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatTime(_progress, totalSeconds),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xff8a63df),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Text(
                                  '08:45',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xffaaa4b3),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 40),

                          // ✅ 목차 보기 버튼
                          GestureDetector(
                            onTap: () {},
                            child: Container(
                              width: 180,
                              height: 52,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(26),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Text(
                                  '목차 보기',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xff8a63df),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
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

  Widget _iconButton(IconData icon) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: const Color(0xff8a63df), size: 22),
    );
  }
}