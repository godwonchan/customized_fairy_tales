// lib/screens/creation/lumi_chat_controller.dart
import 'package:flutter/widgets.dart';
// 메시지 타입은 아직 그리기 화면에 있음 (그리기 화면을 이 컨트롤러로 옮길 때 이 파일로 이동)
import 'custom_story_create_screen.dart' show ChatMessage, ChatRole, QuickReply;

// 화면이 바뀌어도 이어지는 루미 대화 상태
class LumiChatController extends ChangeNotifier {
  final List<ChatMessage> messages = [];
  bool isThinking = false;
  List<QuickReply> quickReplies = []; // 루미 말풍선 아래 빠른 답 버튼

  // 대화 창 열림 여부와, 아이가 끌어서 옮긴 창·버튼 위치 (null이면 기본 위치)
  bool isOpen = false;
  Offset? windowPosition;
  Offset? buttonPosition;

  void setOpen(bool value) {
    isOpen = value;
    notifyListeners();
  }

  void moveWindow(Offset position) {
    windowPosition = position;
    notifyListeners();
  }

  void moveButton(Offset position) {
    buttonPosition = position;
    notifyListeners();
  }

  void addLumi(String text) {
    messages.add(ChatMessage(ChatRole.lumi, text));
    notifyListeners();
  }

  void addChild(String text) {
    messages.add(ChatMessage(ChatRole.child, text));
    quickReplies = []; // 아이가 답했으니 이전 질문의 버튼은 치움
    notifyListeners();
  }

  void setQuickReplies(List<QuickReply> replies) {
    quickReplies = replies;
    notifyListeners();
  }

  void setThinking(bool value) {
    isThinking = value;
    notifyListeners();
  }
}
