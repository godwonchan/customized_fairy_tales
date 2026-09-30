import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // ✅ 플랫폼별 자동 분기
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:8000';      // 크롬
    }
    // 안드로이드 에뮬레이터: 10.0.2.2 = Mac의 localhost
    return 'http://10.0.2.2:8000';
  }

  static Future<List<dynamic>> getOriginalStories() async {
    final response = await http.get(Uri.parse('$baseUrl/stories/original'));
    if (response.statusCode != 200) {
      throw Exception('원본 동화 목록 조회 실패: ${response.body}');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  static Future<List<dynamic>> getMyStories() async {
    final response = await http.get(Uri.parse('$baseUrl/stories/my'));
    if (response.statusCode != 200) {
      throw Exception('내 이야기 목록 조회 실패: ${response.body}');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> getStory(int storyId) async {
    final response = await http.get(Uri.parse('$baseUrl/stories/$storyId'));
    if (response.statusCode != 200) {
      throw Exception('동화 상세 조회 실패: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> getOriginalPages(int storyId) async {
    final response =
        await http.get(Uri.parse('$baseUrl/stories/$storyId/pages/original'));
    if (response.statusCode != 200) {
      throw Exception('원본 페이지 조회 실패: ${response.body}');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  static Future<List<dynamic>> getCurrentPages(int storyId) async {
    final response =
        await http.get(Uri.parse('$baseUrl/stories/$storyId/pages/current'));
    if (response.statusCode != 200) {
      throw Exception('현재 페이지 조회 실패: ${response.body}');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  static String storyPageOriginalImageUrl(int storyId, int pageNumber) {
    return '$baseUrl/stories/$storyId/pages/$pageNumber/original-image';
  }

  static String storyPageImageUrl(int storyId, int pageNumber) {
    return '$baseUrl/stories/$storyId/pages/$pageNumber/image';
  }

  static Future<Map<String, dynamic>> sketchInterpret({
    required int storyId,
    required int pageNumber,
    required String selectedText,
    required Uint8List sketchBytes,
  }) async {
    final uri =
        Uri.parse('$baseUrl/stories/$storyId/pages/$pageNumber/sketch-interpret');

    final request = http.MultipartRequest('POST', uri)
      ..fields['selected_text'] = selectedText
      ..files.add(
        http.MultipartFile.fromBytes(
          'sketch_file',
          sketchBytes,
          filename: 'sketch.png',
          contentType: MediaType('image', 'png'),
        ),
      );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw Exception('낙서 해석 실패: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> sketchRevisePreview({
    required int storyId,
    required int pageNumber,
    required String selectedText,
    required String confirmedRequest,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stories/$storyId/sketch-revise-preview'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'page_number': pageNumber,
        'selected_text': selectedText,
        'confirmed_request': confirmedRequest,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('줄거리 수정 미리보기 실패: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> applyRevision({
    required int storyId,
    required List<String> revisedPages,
    String? confirmedRequest,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stories/$storyId/apply-revision'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'revised_pages': revisedPages,
        'confirmed_request': confirmedRequest,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('줄거리 수정 적용 실패: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> applyRevisionAsync({
    required int storyId,
    required List<String> revisedPages,
    required int startPageNumber,
    String? confirmedRequest,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stories/$storyId/apply-revision-async'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'revised_pages': revisedPages,
        'confirmed_request': confirmedRequest,
        'start_page_number': startPageNumber,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('비동기 줄거리 수정 적용 실패: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getRevisionJobStatus({
    required String jobId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/revision-jobs/$jobId'),
    );

    if (response.statusCode != 200) {
      throw Exception('수정 작업 상태 조회 실패: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> rearrangePlots({
    required int storyId,
    required int plotCount,
    String? styleRequest,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stories/$storyId/plots/rearrange'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'plot_count': plotCount,
        'style_request': styleRequest,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('플롯 재배치 실패: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> getPlots(int storyId) async {
    final response =
        await http.get(Uri.parse('$baseUrl/stories/$storyId/plots'));
    if (response.statusCode != 200) {
      throw Exception('플롯 조회 실패: ${response.body}');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> generatePlotContents({
    required int storyId,
    String? styleRequest,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stories/$storyId/plots/generate-contents'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'style_request': styleRequest,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('플롯 내용 생성 실패: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> getPlotContents(int storyId) async {
    final response =
        await http.get(Uri.parse('$baseUrl/stories/$storyId/plots/contents'));
    if (response.statusCode != 200) {
      throw Exception('플롯 본문 조회 실패: ${response.body}');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> regeneratePlotImagesFrom({
    required int storyId,
    required int startPlotNumber,
    String? styleRequest,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stories/$storyId/plots/regenerate-from'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'start_plot_number': startPlotNumber,
        'style_request': styleRequest,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('수정 이후 플롯 이미지 생성 시작 실패: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getPlotImageGenerationStatus({
    required int storyId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/stories/$storyId/plots/image-generation-status'),
    );

    if (response.statusCode != 200) {
      throw Exception('플롯 이미지 생성 상태 조회 실패: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> applyPlotImagesToPages({
    required int storyId,
    required int startPlotNumber,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stories/$storyId/plots/apply-to-pages'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'start_plot_number': startPlotNumber,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('플롯 이미지를 동화에 적용 실패: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> saveAsMyStory({
    required int storyId,
    String? customTitle,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stories/$storyId/save-as-my-story'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'custom_title': customTitle,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('내 이야기 저장 실패: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> resetToOriginal({
    required int storyId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stories/$storyId/reset-to-original'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception('원본 복원 실패: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // [병규 로그인] 회원가입
  static Future<Map<String, dynamic>> signup({
    required String username,
    required String password,
    String? nickname,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'nickname': nickname ?? username,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? '회원가입 실패');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    await _saveAuthData(data);
    return data;
  }

  // [병규 로그인] 로그인
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? '로그인 실패');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    await _saveAuthData(data);
    return data;
  }

  // 토큰 및 유저 정보 로컬 저장
  static Future<void> _saveAuthData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', data['access_token'] ?? '');
    await prefs.setString('username', data['username'] ?? '');
    await prefs.setString('nickname', data['nickname'] ?? '');
  }

  // 로그아웃
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('username');
    await prefs.remove('nickname');
  }

  // 로그인 상태 확인
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    return token != null && token.isNotEmpty;
  }

  // [병규 프로필] 로컬에 저장된 유저 정보 가져오기
  static Future<Map<String, String>> getUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'username': prefs.getString('username') ?? '',
      'nickname': prefs.getString('nickname') ?? '동화친구',
    };
  }

  // [병규 프로필] 닉네임 변경 API 호출 및 로컬 업데이트
  static Future<String> updateNickname(String newNickname) async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? '';

    final response = await http.put(
      Uri.parse('$baseUrl/auth/nickname'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'new_nickname': newNickname,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? '닉네임 변경 실패');
    }

    final data = jsonDecode(response.body);
    final updatedNick = data['nickname'] as String;
    await prefs.setString('nickname', updatedNick); // 로컬 저장소 갱신
    return updatedNick;
  }

  // [무료 영어 번역]
  static Future<String> translateToEnglish(String text) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stories/translate-en'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );

    if (response.statusCode != 200) {
      throw Exception('영어 번역 실패');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    return data['translated_text'] as String;
  }

  // [무료 뉴럴 TTS 음성 가져오기]
  static Future<Uint8List> getStoryTTS({
    required String text,
    required String language, // 'ko' 또는 'en'
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stories/tts'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'text': text,
        'language': language,
      }),
    );

    if (response.statusCode != 200) {
      // 서버에서 보낸 에러 상세 내용(detail)을 그대로 표시
      throw Exception('음성 생성 실패 (${response.statusCode}): ${response.body}');
    }

    return response.bodyBytes;
  }

  // 🗑️ 내가 만든 이야기 삭제 API
  static Future<bool> deleteStory(int storyId) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/api/stories/$storyId'),
        headers: {'Content-Type': 'application/json'},
      );
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (e) {
      debugPrint('동화 삭제 통신 에러: $e');
      return false;
    }
  }

}