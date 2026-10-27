import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'chat_message.dart';
import 'local_chat_bloc.dart';

class LocalChatScreen extends StatefulWidget {
  const LocalChatScreen({super.key});

  @override
  State<LocalChatScreen> createState() => _LocalChatScreenState();
}

class _LocalChatScreenState extends State<LocalChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, size: 20, color: Colors.greenAccent),
            SizedBox(width: 8),
            Text('Offline AI Chat (Qwen 1.5B)'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear Context',
            onPressed: () => context.read<LocalChatBloc>().add(ClearConversationEvent()),
          ),
        ],
      ),
      body: BlocConsumer<LocalChatBloc, LocalChatState>(
        listener: (context, state) {
          if (state.status == EngineStatus.generating) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
          }
        },
        builder: (context, state) {
          if (state.status == EngineStatus.needsDownload ||
              state.status == EngineStatus.downloading) {
            return _buildModelDownloaderView(context, state);
          }

          if (state.status == EngineStatus.loadingModel ||
              state.status == EngineStatus.initial) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading GGUF layers into GPU memory...'),
                ],
              ),
            );
          }

          return Column(
            children: [
              if (state.errorMessage != null)
                MaterialBanner(
                  content: Text(state.errorMessage!),
                  backgroundColor: Colors.red.shade900,
                  actions: [
                    TextButton(
                      onPressed: () => context.read<LocalChatBloc>().add(CheckModelStatusEvent()),
                      child: const Text('RETRY'),
                    ),
                  ],
                ),
              Expanded(
                child: state.messages.isEmpty
                    ? const Center(
                        child: Text(
                          '100% On-Device & Offline.\nAsk anything to start chatting!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: state.messages.length,
                        itemBuilder: (context, index) {
                          return _MessageBubble(message: state.messages[index]);
                        },
                      ),
              ),
              _buildMessageInput(context, state.status == EngineStatus.generating),
            ],
          );
        },
      ),
    );
  }

  Widget _buildModelDownloaderView(BuildContext context, LocalChatState state) {
    final isDownloading = state.status == EngineStatus.downloading;
    final pct = (state.downloadProgress * 100).toStringAsFixed(1);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.memory, size: 56, color: Colors.blueAccent),
                const SizedBox(height: 16),
                const Text(
                  'Download On-Device Model',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                if (isDownloading) ...[
                  LinearProgressIndicator(value: state.downloadProgress),
                  const SizedBox(height: 12),
                  Text('Downloading... $pct%'),
                ] else
                  FilledButton.icon(
                    onPressed: () =>
                        context.read<LocalChatBloc>().add(StartDownloadModelEvent()),
                    icon: const Icon(Icons.download),
                    label: const Text('Download Model'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput(BuildContext context, bool isGenerating) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                enabled: !isGenerating,
                decoration: InputDecoration(
                  hintText: isGenerating ? 'Generating on device...' : 'Ask anything offline...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) => _send(context),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: isGenerating ? null : () => _send(context),
              icon: isGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  void _send(BuildContext context) {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    context.read<LocalChatBloc>().add(SendUserMessageEvent(text));
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: isUser ? Colors.blueAccent : Colors.grey.shade800,
          borderRadius: BorderRadius.circular(16),
        ),
        child: isUser
            ? Text(message.content, style: const TextStyle(color: Colors.white))
            : MarkdownBody(
                data: message.content.isEmpty && message.isStreaming
                    ? '_Thinking..._'
                    : message.content,
              ),
      ),
    );
  }
}