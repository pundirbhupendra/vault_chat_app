
import 'dart:io';

import 'package:dart_vector_index/dart_vector_index.dart';
import 'package:path_provider/path_provider.dart';

class LocalVectorStore {
  LocalVectorStore._(this._store, this._file);

  final VectorStore _store;
  final File _file;

  int get count => _store.count;

  static Future<LocalVectorStore> open() async {
    final directory = await getApplicationSupportDirectory();

    final file = File(
      '${directory.path}/rag/vector_index.json',
    );

    await file.parent.create(recursive: true);

    final store = await file.exists()
        ? await VectorStore.loadFromFile(file)
        : VectorStore(
            type: IndexType.hnsw,
            metric: DistanceMetric.cosine,
            randomSeed: 42,
          );

    return LocalVectorStore._(store, file);
  }

  void addChunk({
    required String id,
    required List<double> embedding,
    required String content,
    required String documentName,
    required int chunkIndex,
    int? pageNumber,
  }) {
    _store.add(
      id: id,
      vector: embedding,
      metadata: {
        'content': content,
        'documentName': documentName,
        'chunkIndex': chunkIndex,
        if (pageNumber != null) 'pageNumber': pageNumber,
      },
    );
  }

  List<SearchResult> search(
    List<double> queryEmbedding, {
    int topK = 3,
  }) {
    return _store.similaritySearch(
      queryEmbedding,
      limit: topK,
    );
  }

  Future<void> save() async {
    await _store.saveToFile(_file);
  }
}
