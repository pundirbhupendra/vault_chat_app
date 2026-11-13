import 'dart:math' as math;

import 'package:vault_chat_app/rag/embedding_repository.dart';

class FakeEmbeddingService implements EmbeddingService {
  bool downloaded = true;

  @override
  Future<bool> isModelDownloaded() async => downloaded;

  @override
  Future<void> downloadModel({
    void Function(double progress)? onProgress,
  }) async {
    downloaded = true;
    onProgress?.call(1);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<List<double>> embedQuery(String text) async => _embed(text);

  @override
  Future<List<List<double>>> embedDocuments(
    List<String> texts, {
    required String title,
  }) async => [for (final text in texts) _embed('$title $text')];

  @override
  Future<void> dispose() async {}

  List<double> _embed(String text) {
    final vector = List<double>.filled(768, 0);
    for (final token
        in text
            .toLowerCase()
            .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
            .where((token) => token.isNotEmpty)) {
      var hash = 0;
      for (final rune in token.runes) {
        hash = (hash * 31 + rune) & 0x7fffffff;
      }
      vector[hash % vector.length] += 1;
    }

    final norm = math.sqrt(
      vector.fold<double>(0, (sum, value) => sum + value * value),
    );
    if (norm > 0) {
      for (var index = 0; index < vector.length; index++) {
        vector[index] /= norm;
      }
    }
    return vector;
  }
}
