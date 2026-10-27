import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'chat_message.dart';
import 'local_llm_repository.dart';
import 'cloud_llm_repository.dart';
import 'ai_chat_repository.dart';

class HybridAiRepository implements AiChatRepository {
  final LocalLlmRepository _localRepo;
  final CloudLlmRepository _cloudRepo;
  final Connectivity _connectivity = Connectivity();

  // Max characters (~1200 tokens) safe for a 2048-context mobile GGUF model
  static const int _maxLocalPromptChars = 4800;

  HybridAiRepository({
    required this._localRepo,
    required this._cloudRepo,
  });

  @override
  Stream<ChatStreamChunk> streamChatCompletion(
    List<ChatMessage> history, {
    bool forceOffline = false,
  }) async* {
    // 1. Privacy / User-Override Gate
    if (forceOffline) {
      yield* _streamFromLocal(history);
      return;
    }

    // 2. Connectivity Check
    final connectivityResult = await _connectivity.checkConnectivity();
    final isOnline = !connectivityResult.contains(ConnectivityResult.none);

    // 3. Complexity & Context Length Gate
    final needsCloudCapability = _requiresCloudEscalation(history);

    if (needsCloudCapability && isOnline) {
      try {
        yield* _streamFromCloud(history);
        return;
      } catch (_) {
        // Cloud failed mid-flight -> gracefully degrade to on-device GGUF
        yield* _streamFromLocal(history);
        return;
      }
    }

    // 4. Default: Device-Primary with Cloud Fallback on Error/Low Confidence
    try {
      final buffer = StringBuffer();
      await for (final token in _localRepo.streamChatCompletion(history)) {
        buffer.write(token);

        // Self-Aware Escalation: If the SLM outputs "[ESCALATE]" when unsure
        if (buffer.toString().contains('[ESCALATE]') && isOnline) {
          yield* _streamFromCloud(history);
          return;
        }

        yield ChatStreamChunk(
          token: token,
          source: InferenceSource.onDevice,
        );
      }
    } catch (localError) {
      // If local GGUF throws an OOM or FFI exception and we have internet, fallback to Cloud
      if (isOnline) {
        yield* _streamFromCloud(history);
      } else {
        rethrow;
      }
    }
  }

  /// Heuristic router: Checks token budget and complex reasoning triggers
  bool _requiresCloudEscalation(List<ChatMessage> history) {
    final lastUserPrompt = history.last.content.toLowerCase();
    final totalChars = history.fold<int>(0, (sum, msg) => sum + msg.content.length);

    // Escalate if prompt + history exceeds safe mobile KV-cache limits
    if (totalChars > _maxLocalPromptChars) return true;

    // Escalate for heavy multi-step coding or architectural synthesis
    final complexKeywords = [
      'write a full',
      'refactor this entire',
      'analyze this large',
      'step-by-step mathematical proof',
    ];
    return complexKeywords.any((kw) => lastUserPrompt.contains(kw));
  }

  Stream<ChatStreamChunk> _streamFromLocal(List<ChatMessage> history) {
    return _localRepo.streamChatCompletion(history).map(
          (token) => ChatStreamChunk(
            token: token,
            source: InferenceSource.onDevice,
          ),
        );
  }

  Stream<ChatStreamChunk> _streamFromCloud(List<ChatMessage> history) {
    return _cloudRepo.streamChatCompletion(history).map(
          (token) => ChatStreamChunk(
            token: token,
            source: InferenceSource.cloudFallback,
          ),
        );
  }
}