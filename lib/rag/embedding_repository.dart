
import 'package:llamadart/llamadart.dart';

class EmbeddingRepository {
  EmbeddingRepository()
      : _engine = LlamaEngine(LlamaBackend());

  final LlamaEngine _engine;
  bool _initialized = false;

  Future<void> initialize(String modelPath) async {
    if (_initialized) return;

    await _engine.setModel(
      LlamaModel(ModelSource.path(modelPath)),
      params: const ModelParams(
        contextSize: 512,
        numberOfThreads: 2,
        device: ComputeDevice.cpu,
      ),
    );

    if (!_engine.supportsEmbeddings) {
      throw StateError(
        'The loaded model/backend does not support embeddings.',
      );
    }

    _initialized = true;
  }

  Future<List<double>> embedQuery(String text) async {
    _ensureInitialized();
    return _engine.embed(text, normalize: true);
  }

  Future<List<List<double>>> embedDocuments(
    List<String> texts,
  ) async {
    _ensureInitialized();
    return _engine.embedBatch(texts, normalize: true);
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('Initialize the embedding model first.');
    }
  }

  Future<void> dispose() => _engine.dispose();
}
