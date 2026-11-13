import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vault_chat_app/model/model_spec.dart';
import 'package:vault_chat_app/model/model_download_notifications.dart';
import 'chat_message.dart';

class LocalLlmRepository {
  final LlamaEngine _llama = LlamaEngine(LlamaBackend());
  ModelSpec _activeSpec = ModelSpec.qwen1_5B;
  DownloadTask? _activeDownloadTask;

  ModelSpec get activeSpec => _activeSpec;

  Future<void> initDownloader() => ModelDownloadNotifications.initialize();

  /// Resolves the storage path inside ApplicationSupport/models
  /// (Safe from iOS iCloud automatic backups and OS temp purges)
  Future<String> getModelPath(ModelSpec spec) async {
    final dir = await getApplicationSupportDirectory();
    final modelsDir = Directory('${dir.path}/models');
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return '${modelsDir.path}/${spec.fileName}';
  }

  /// Verifies if the cached GGUF model exists and matches expected size thresholds
  Future<bool> isModelDownloaded([ModelSpec? spec]) async {
    final target = spec ?? _activeSpec;
    final path = await getModelPath(target);
    final file = File(path);
    if (!await file.exists()) return false;

    final length = await file.length();
    return length >= (target.expectedBytes * 0.98);
  }

  /// Starts an OS-managed background download with pause/resume & Wi-Fi resilience
  Future<bool> downloadModel({
    ModelSpec? spec,
    bool requireWiFi = false,
    required void Function(double progress) onProgress,
    required void Function(TaskStatus status) onStatus,
  }) async {
    await ModelDownloadNotifications.initialize();
    await ModelDownloadNotifications.requestPermission();

    final target = spec ?? _activeSpec;
    _activeSpec = target;

    _activeDownloadTask = DownloadTask(
      url: target.url,
      filename: target.fileName,
      directory: 'models',
      baseDirectory: BaseDirectory.applicationSupport,
      updates: Updates.statusAndProgress,
      allowPause:
          true, // Enables HTTP Range resume & background session continuation
      priority: 0, // Android 14+ User-Initiated Data Transfer (UIDT)
      requiresWiFi: requireWiFi,
      retries: 5,
    );

    final result = await FileDownloader().download(
      _activeDownloadTask!,
      onProgress: (progress) {
        if (progress >= 0.0 && progress <= 1.0) {
          onProgress(progress);
        }
      },
      onStatus: onStatus,
    );

    return result.status == TaskStatus.complete;
  }

  Future<void> pauseDownload() async {
    if (_activeDownloadTask != null) {
      await FileDownloader().pause(_activeDownloadTask!);
    }
  }

  Future<void> resumeDownload() async {
    if (_activeDownloadTask != null) {
      await FileDownloader().resume(_activeDownloadTask!);
    }
  }

  Future<void> cancelDownload() async {
    if (_activeDownloadTask != null) {
      await FileDownloader().cancelTaskWithId(_activeDownloadTask!.taskId);
    }
  }

  /// Loads the GGUF model using the platform's supported compute backend.
  Future<void> loadModel([ModelSpec? spec]) async {
    if (spec != null && spec.id != _activeSpec.id) {
      await unloadModel();
      _activeSpec = spec;
    }

    final path = await getModelPath(_activeSpec);
    final int optimalThreads = (Platform.numberOfProcessors > 2)
        ? (Platform.numberOfProcessors - 2).clamp(2, 6)
        : 2;

    await _llama.setModel(
      LlamaModel(ModelSource.path(path)),
      params: ModelParams(
        contextSize: 2048,
        numberOfThreads: optimalThreads,
        device: Platform.isAndroid ? ComputeDevice.cpu : ComputeDevice.auto,
      ),
    );
  }

  /// Streams generated tokens with a bounded conversation history.
  Stream<String> streamChatCompletion(
    List<ChatMessage> history, {
    String? systemPrompt,
  }) {
    final params = GenerationParams(
      temp: 0.7,
      topP: 0.9,
      topK: 40,
      maxTokens: 512,
      penalty: 1.1,
    );

    return _llama
        .create(
          _toLlamaMessages(history, systemPrompt: systemPrompt),
          params: params,
        )
        .map((chunk) => chunk.text);
  }

  /// Keeps the recent conversation within the configured context window.
  List<LlamaChatMessage> _toLlamaMessages(
    List<ChatMessage> history, {
    String? systemPrompt,
  }) {
    final recentMessages = history.length > 6
        ? history.sublist(history.length - 6)
        : history;
    return [
      LlamaChatMessage.fromText(
        role: LlamaChatRole.system,
        text:
            systemPrompt ??
            'You are a helpful, concise AI assistant running 100% offline on the user\'s phone.',
      ),
      for (final msg in recentMessages)
        if (msg.role == MessageRole.user)
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: msg.content)
        else if (msg.role == MessageRole.assistant && msg.content.isNotEmpty)
          LlamaChatMessage.fromText(
            role: LlamaChatRole.assistant,
            text: msg.content,
          ),
    ];
  }

  Future<void> unloadModel() async {
    await _llama.unloadModel();
  }

  Future<void> dispose() => _llama.dispose();
}
