import 'chat_message.dart';

enum InferenceSource { onDevice, cloudFallback }

class ChatStreamChunk {
  final String token;
  final InferenceSource source;

  const ChatStreamChunk({required this.token, required this.source});
}

abstract class AiChatRepository {
  Stream<ChatStreamChunk> streamChatCompletion(
    List<ChatMessage> history, {
    bool forceOffline = false,
  });
}