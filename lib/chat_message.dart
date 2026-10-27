import 'package:equatable/equatable.dart';

enum MessageRole { system, user, assistant }

class ChatMessage extends Equatable {
  final String id;
  final MessageRole role;
  final String content;
  final bool isStreaming;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.isStreaming = false,
  });

  ChatMessage copyWith({String? content, bool? isStreaming}) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  @override
  List<Object?> get props => [id, role, content, isStreaming];
}