import 'package:equatable/equatable.dart';
import 'rag/models/retrieved_chunk.dart';

enum MessageRole { system, user, assistant }

class ChatMessage extends Equatable {
  final String id;
  final MessageRole role;
  final String content;
  final bool isStreaming;
  final List<RetrievedChunk> sources;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.isStreaming = false,
    this.sources = const [],
  });

  ChatMessage copyWith({
    String? content,
    bool? isStreaming,
    List<RetrievedChunk>? sources,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      isStreaming: isStreaming ?? this.isStreaming,
      sources: sources ?? this.sources,
    );
  }

  @override
  List<Object?> get props => [id, role, content, isStreaming, sources];
}
