import 'dart:io';
import 'dart:math';

import 'package:background_downloader/background_downloader.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vault_chat_app/model/model_download_notifications.dart';

abstract interface class EmbeddingService {
  Future<bool> isModelDownloaded();

  Future<void> downloadModel({void Function(double progress)? onProgress});

  Future<void> initialize();

  Future<List<double>> embedQuery(String text);

  Future<List<List<double>>> embedDocuments(
    List<String> texts, {
    required String title,
  });

  Future<void> dispose();
}

class EmbeddingRepository implements EmbeddingService {
  static const modelUrl =
      'https://huggingface.co/ggml-org/embeddinggemma-300M-GGUF/resolve/main/'
      'embeddinggemma-300M-Q8_0.gguf?download=true';
  static const modelFileName = 'embeddinggemma-300M-Q8_0.gguf';

  EmbeddingRepository() : _engine = LlamaEngine(LlamaBackend());

  final LlamaEngine _engine;
  bool _initialized = false;

  Future<String> get _modelPath async {
    final directory = await getApplicationSupportDirectory();
    final modelsDirectory = Directory('${directory.path}/models');
    await modelsDirectory.create(recursive: true);
    return '${modelsDirectory.path}/$modelFileName';
  }

  @override
  Future<bool> isModelDownloaded() async {
    final file = File(await _modelPath);
    return await file.exists() && await file.length() > 0;
  }

  @override
  Future<void> downloadModel({
    void Function(double progress)? onProgress,
  }) async {
    await ModelDownloadNotifications.initialize();
    await ModelDownloadNotifications.requestPermission();

    final path = await _modelPath;
    final target = File(path);
    if (await target.exists() && await target.length() > 0) return;

    final temporary = File('$path.download');
    if (await temporary.exists()) await temporary.delete();
    if (await target.exists()) await target.delete();
    try {
      final task = DownloadTask(
        url: modelUrl,
        filename: '$modelFileName.download',
        directory: 'models',
        baseDirectory: BaseDirectory.applicationSupport,
        updates: Updates.statusAndProgress,
        allowPause: true,
        retries: 5,
      );
      final result = await FileDownloader().download(
        task,
        onProgress: (progress) {
          if (progress >= 0 && progress <= 1) onProgress?.call(progress);
        },
      );
      if (result.status != TaskStatus.complete) {
        throw StateError('Embedding model download failed: ${result.status}.');
      }
      if (!await temporary.exists() || await temporary.length() == 0) {
        throw StateError(
          'The embedding model download produced an empty file.',
        );
      }
      await temporary.rename(target.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    final path = await _modelPath;
    if (!await isModelDownloaded()) {
      throw StateError(
        'Download the EmbeddingGemma model before indexing or searching documents.',
      );
    }

    await _engine.setModel(
      LlamaModel(ModelSource.path(path)),
      params: ModelParams(
        contextSize: 2048,
        numberOfThreads: max(2, min(4, Platform.numberOfProcessors - 1)),
        device: ComputeDevice.cpu,
      ),
    );
    if (!_engine.supportsEmbeddings) {
      await _engine.unloadModel();
      throw StateError(
        'The loaded embedding model or llama.cpp backend does not support embeddings.',
      );
    }
    _initialized = true;
  }

  LlamaTextEmbedder get _embedder => LlamaTextEmbedder(
    _engine,
    profile: LlamaEmbeddingProfile.embeddingGemma2,
    normalize: true,
  );

  @override
  Future<List<double>> embedQuery(String text) async {
    _ensureInitialized();
    return _embedder.embed(
      LlamaEmbeddingText.query(
        text,
        task: LlamaEmbeddingTask.questionAnswering,
      ),
    );
  }

  @override
  Future<List<List<double>>> embedDocuments(
    List<String> texts, {
    required String title,
  }) async {
    _ensureInitialized();
    return _embedder.embedBatch([
      for (final text in texts) LlamaEmbeddingText.document(text, title: title),
    ]);
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('Initialize the embedding model first.');
    }
  }

  @override
  Future<void> dispose() => _engine.dispose();
}
