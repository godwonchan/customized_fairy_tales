import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/npc_chat_provider.dart';

const _kBg = Color(0xFFF8F4FF);
const _kPrimary = Color(0xFF7E57C2);
const _kPrimaryLight = Color(0xFF9575CD);
const _kPill = Color(0xFFEDE7F6);
const _kInk = Color(0xFF3D2C8D);

/// NPC 자유 대화 화면.
class RpgNpcChatScreen extends StatelessWidget {
  final int playthroughId;
  final String initialNpcName;

  const RpgNpcChatScreen({
    super.key,
    required this.playthroughId,
    this.initialNpcName = '놀부',
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NpcChatProvider(
        playthroughId: playthroughId,
        npcName: initialNpcName,
      ),
      child: const _NpcChatView(),
    );
  }
}

class _NpcChatView extends StatefulWidget {
  const _NpcChatView();

  @override
  State<_NpcChatView> createState() => _NpcChatViewState();
}

class _NpcChatViewState extends State<_NpcChatView> {
  final _msgCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _msgCtrl.dispose();
    _nameCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NpcChatProvider>(
      builder: (context, chat, _) {
        _scrollDown();
        return Scaffold(
          backgroundColor: _kBg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: _kPrimary,
            title: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                      color: _kPill, shape: BoxShape.circle),
                  child: const Icon(Icons.person, size: 18, color: _kPrimary),
                ),
                const SizedBox(width: 8),
                Text(chat.npcName,
                    style: const TextStyle(
                        color: _kInk, fontWeight: FontWeight.w700)),
              ],
            ),
            actions: [
              IconButton(
                tooltip: '대화 상대 바꾸기',
                icon: const Icon(Icons.swap_horiz),
                onPressed: () => _changeNpcDialog(context, chat),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: chat.messages.isEmpty
                      ? Center(
                          child: Text(
                            "'${chat.npcName}'에게 말을 걸어보세요",
                            style: const TextStyle(color: Color(0xFFA99FC4)),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.all(16),
                          itemCount: chat.messages.length,
                          itemBuilder: (_, i) {
                            final m = chat.messages[i];
                            return _bubble(m.content, m.isUser);
                          },
                        ),
                ),
                if (chat.isLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: LinearProgressIndicator(
                        color: _kPrimary, backgroundColor: _kPill, minHeight: 3),
                  ),
                _inputBar(chat),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bubble(String text, bool isUser) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: isUser ? _kPrimary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser
              ? null
              : Border.all(color: _kPrimaryLight.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(
                color: _kPrimary.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isUser ? Colors.white : _kInk,
            fontSize: 15,
            height: 1.45,
          ),
        ),
      ),
    );
  }

  Widget _inputBar(NpcChatProvider chat) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _msgCtrl,
              enabled: !chat.isLoading,
              style: const TextStyle(color: _kInk),
              decoration: InputDecoration(
                hintText: '메시지 입력',
                hintStyle: const TextStyle(color: Color(0xFFB6ABD6)),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: _kPrimaryLight.withOpacity(0.4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: _kPrimary, width: 1.5),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: _kPrimaryLight.withOpacity(0.4)),
                ),
              ),
              onSubmitted: (_) => _send(chat),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: _kPrimary,
            child: IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white),
              onPressed: chat.isLoading ? null : () => _send(chat),
            ),
          ),
        ],
      ),
    );
  }

  void _send(NpcChatProvider chat) {
    final t = _msgCtrl.text;
    if (t.trim().isEmpty) return;
    _msgCtrl.clear();
    chat.send(t);
  }

  void _changeNpcDialog(BuildContext context, NpcChatProvider chat) {
    _nameCtrl.text = chat.npcName;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('대화 상대',
            style: TextStyle(color: _kInk, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: _nameCtrl,
          style: const TextStyle(color: _kInk),
          decoration: InputDecoration(
            hintText: '예: 놀부, 마녀, 늑대',
            hintStyle: const TextStyle(color: Color(0xFFB6ABD6)),
            filled: true,
            fillColor: _kPill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              chat.setNpcName(_nameCtrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('바꾸기'),
          ),
        ],
      ),
    );
  }
}
