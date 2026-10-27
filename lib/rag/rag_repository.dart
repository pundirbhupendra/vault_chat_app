
import 'dart:io';
import 'dart:math' as math;

import 'package:dart_vector_index/dart_vector_index.dart';
import 'package:path_provider/path_provider.dart';

class RagRepository {
  static const int _dimensions = 128;

  late VectorStore _store;
  late File _indexFile;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    final directory = await getApplicationSupportDirectory();
    final ragDirectory = Directory('${directory.path}/rag');

    await ragDirectory.create(recursive: true);

    _indexFile = File('${ragDirectory.path}/vector_index.json');

    _store = await _indexFile.exists()
        ? VectorStore.loadFromFile(_indexFile)
        : VectorStore(
            type: IndexType.hnsw,
            metric: DistanceMetric.cosine,
            randomSeed: 42,
          );

    _initialized = true;
  }

  // TEST ONLY: deterministic token hashing, not semantic embeddings.
  List<double> _embed(String text) {
    final vector = List<double>.filled(_dimensions, 0);

    final tokens = text
        .toLowerCase()
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((token) => token.isNotEmpty);

    for (final token in tokens) {
      var hash = 0;

      for (final unit in token.codeUnits) {
        hash = (hash * 31 + unit) & 0x7fffffff;
      }

      vector[hash % _dimensions] += 1;
    }

    final norm = math.sqrt(
      vector.fold<double>(
        0,
        (sum, value) => sum + value * value,
      ),
    );

    if (norm > 0) {
      for (var i = 0; i < vector.length; i++) {
        vector[i] /= norm;
      }
    }

    return vector;
  }

  List<String> _chunkText(
    String text, {
    int maxChars = 500,
  }) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (normalized.isEmpty) return [];

    final chunks = <String>[];

    for (var start = 0; start < normalized.length;) {
      var end = math.min(start + maxChars, normalized.length);

      if (end < normalized.length) {
        final boundary = normalized.lastIndexOf(' ', end);

        if (boundary > start) end = boundary;
      }

      chunks.add(normalized.substring(start, end).trim());

      start = end;
      while (start < normalized.length &&
          normalized[start] == ' ') {
        start++;
      }
    }

    return chunks.where((chunk) => chunk.isNotEmpty).toList();
  }

  Future<void> indexText({
    required String documentId,
    required String documentName,
    required String text,
  }) async {
    _ensureInitialized();

    final chunks = _chunkText(text);

    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];

      _store.add(
        id: '${documentId}_$i',
        vector: _embed(chunk),
        metadata: {
          'documentId': documentId,
          'documentName': documentName,
          'chunkIndex': i,
          'content': chunk,
        },
      );
    }

    await _store.saveToFile(_indexFile);
  }

  Future<String> retrieveContext(
    String question, {
    int topK = 3,
  }) async {
    _ensureInitialized();

    final results = _store.similaritySearch(
      _embed(question),
      limit: topK,
    );

    return results.map((result) {
      final metadata = result.metadata;

      return '''
Source: ${metadata['documentName']}
Chunk: ${metadata['chunkIndex']}
Content: ${metadata['content']}
''';
    }).join('\n---\n');
  }

  int get indexedChunkCount {
    _ensureInitialized();
    return _store.count;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('Call initialize() first.');
    }
  }
}
