import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'chat_message.dart';

class CloudLlmRepository {
  final Dio _dio;
  final String apiKey;
  final String baseUrl;
  final String modelName;
  CancelToken? _activeCancelToken;

  CloudLlmRepository({
    required this.apiKey,
    // Works with OpenAI, Groq, OpenRouter, or Gemini OpenAI-compatible endpoints
    this.baseUrl = 'https://api.openai.com/v1',
    this.modelName = 'gpt-4o-mini',
    Dio? dio,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 30),
              ),
            );

  /// Streams tokens from the cloud LLM using Server-Sent Events (SSE)
  Stream<String> streamChatCompletion(List<ChatMessage> history) async* {
    _activeCancelToken = CancelToken();

    // Keep recent messages + system prompt to match LocalLlmRepository behavior
    final recentMessages =
        history.length > 10 ? history.sublist(history.length - 10) : history;

    final payloadMessages = <Map<String, String>>[
      {
        'role': 'system',
        'content':
            'You are a helpful, concise AI assistant acting as the cloud fallback for a mobile AI app.',
      },
      ...recentMessages
          .where((m) => m.content.trim().isNotEmpty)
          .map((m) => {
                'role': _mapRole(m.role),
                'content': m.content,
              }),
    ];

    final response = await _dio.post<ResponseBody>(
      '$baseUrl/chat/completions',
      cancelToken: _activeCancelToken,
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        },
        responseType: ResponseType.stream,
      ),
      data: {
        'model': modelName,
        'messages': payloadMessages,
        'temperature': 0.7,
        'max_tokens': 512,
        'stream': true,
      },
    );

    final byteStream = response.data?.stream;
    if (byteStream == null) return;

    // Decode UTF-8 chunks and split by lines for SSE parsing
    final lineStream = byteStream
        .map((Uint8List chunk) => List<int>.from(chunk))
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lineStream) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;

      final dataPayload = trimmed.substring(5).trim();
      if (dataPayload == '[DONE]') break;

      try {
        final Map<String, dynamic> json = jsonDecode(dataPayload);
        final choices = json['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final delta = choices.first['delta'] as Map<String, dynamic>?;
          final token = delta?['content'] as String?;
          if (token != null && token.isNotEmpty) {
            yield token;
          }
        }
      } catch (_) {
        // Ignore malformed/partial SSE keep-alive frames
      }
    }
  }

  /// Cancels an in-flight cloud stream if the user taps Stop
  void stopGeneration() {
    if (_activeCancelToken != null && !_activeCancelToken!.isCancelled) {
      _activeCancelToken!.cancel('User stopped cloud generation');
    }
  }

  String _mapRole(MessageRole role) {
    switch (role) {
      case MessageRole.system:
        return 'system';
      case MessageRole.user:
        return 'user';
      case MessageRole.assistant:
        return 'assistant';
    }
  }
}