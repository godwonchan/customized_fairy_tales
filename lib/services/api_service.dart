import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:8000';

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
    final response = await http.get(Uri.parse('$baseUrl/stories/$storyId/plots'));
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
}