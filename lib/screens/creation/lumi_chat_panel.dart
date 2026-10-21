// lib/screens/creation/lumi_chat_panel.dart
import 'package:flutter/material.dart';
import 'custom_story_create_screen.dart' show ChatMessage, ChatRole, QuickReply;
import 'lumi_chat_controller.dart';

// 루미 대화 목록 + 입력줄 (입력을 어떻게 처리할지는 화면마다 onSend로 정함)
class LumiChatPanel extends StatefulWidget {
  final LumiChatController controller;
  final TextEditingController inputController;
  final bool enabled;
  final bool isListening;
  final String hintText;
  final VoidCallback onSend;
  final VoidCallback onMicTap;

  const LumiChatPanel({
    super.key,
    required this.controller,
    required this.inputController,
    required this.enabled,
    required this.isListening,
    required this.hintText,
    required this.onSend,
    required this.onMicTap,
  });

  @override
  State<LumiChatPanel> createState() => _LumiChatPanelState();
}

class _LumiChatPanelState extends State<LumiChatPanel> {
  static const String _lumiImagePath = 'assets/images/lumi.jpg';
  static const Color _purple = Color(0xFF7C4DFF);
  static const Color _purpleDark = Color(0xFF5B2FE0);
  static const Color _ink = Color(0xFF2B2A4C);
  static const Color _cardLine = Color(0xFFEAE6F8);
  static const Color _cardEdge = Color(0xFFDCD5F3);

  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scrollToBottom);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scrollToBottom);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              children: [
                for (final m in widget.controller.messages) _buildBubble(m),
                if (widget.controller.isThinking) _buildBubble(ChatMessage(ChatRole.lumi, '…')),
                if (!widget.controller.isThinking && widget.controller.quickReplies.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 42, bottom: 10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [for (final r in widget.controller.quickReplies) _buildQuickReply(r)],
                    ),
                  ),
              ],
            ),
          ),
        ),
        _buildInputRow(),
      ],
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: _cardLine, width: 2),
      ),
      child: ClipOval(
        child: Image.asset(
          _lumiImagePath,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) => Container(
            color: _purple,
            child: const Icon(Icons.face_retouching_natural, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(ChatMessage m) {
    final isLumi = m.role == ChatRole.lumi;
    final bubble = Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isLumi ? Colors.white : _purple,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isLumi ? 6 : 20),
            topRight: Radius.circular(isLumi ? 20 : 6),
            bottomLeft: const Radius.circular(20),
            bottomRight: const Radius.circular(20),
          ),
          border: isLumi ? Border.all(color: _cardLine, width: 2) : null,
          boxShadow: [BoxShadow(color: isLumi ? _cardEdge : _purpleDark, offset: const Offset(0, 3))],
        ),
        child: Text(
          m.text,
          style: TextStyle(fontSize: 16, height: 1.4, color: isLumi ? _ink : Colors.white),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isLumi ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: isLumi
            ? [_buildAvatar(), const SizedBox(width: 8), bubble, const SizedBox(width: 24)]
            : [const SizedBox(width: 48), bubble],
      ),
    );
  }

  Widget _buildQuickReply(QuickReply r) {
    return GestureDetector(
      onTap: r.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: r.primary ? _purple : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: r.primary ? _purple : _cardLine, width: 2),
          boxShadow: [BoxShadow(color: r.primary ? _purpleDark : _cardEdge, offset: const Offset(0, 3))],
        ),
        child: Text(
          r.label,
          style: TextStyle(fontSize: 16, color: r.primary ? Colors.white : _ink),
        ),
      ),
    );
  }

  Widget _buildInputRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.inputController,
              enabled: widget.enabled,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => widget.onSend(),
              style: const TextStyle(fontSize: 16, color: _ink),
              decoration: InputDecoration(
                hintText: widget.isListening ? '듣고 있어! 말해 봐…' : widget.hintText,
                hintStyle: TextStyle(
                  fontSize: 15,
                  color: widget.isListening ? _purple : Colors.grey[500],
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: _cardLine, width: 2)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: _cardLine, width: 2)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: _purple, width: 2)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildRoundButton(
            icon: widget.isListening ? Icons.mic : Icons.mic_none_rounded,
            color: widget.isListening ? Colors.redAccent : Colors.white,
            iconColor: widget.isListening ? Colors.white : _purple,
            onTap: widget.enabled ? widget.onMicTap : null,
          ),
          const SizedBox(width: 8),
          _buildRoundButton(
            icon: Icons.send_rounded,
            color: _purple,
            iconColor: Colors.white,
            onTap: widget.enabled ? widget.onSend : null,
          ),
        ],
      ),
    );
  }

  Widget _buildRoundButton({
    required IconData icon,
    required Color color,
    required Color iconColor,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: enabled ? color : Colors.grey[300],
          shape: BoxShape.circle,
          border: color == Colors.white ? Border.all(color: _cardLine, width: 2) : null,
          boxShadow: [BoxShadow(color: enabled ? _cardEdge : Colors.black12, offset: const Offset(0, 3))],
        ),
        child: Icon(icon, color: enabled ? iconColor : Colors.white, size: 26),
      ),
    );
  }
}
