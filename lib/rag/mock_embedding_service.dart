
class MockEmbeddingService {
  // TEST ONLY: creates deterministic vectors.
  // It does not understand meaning or language.
  List<double> embed(String text) {
    const dimensions = 64;
    final vector = List<double>.filled(dimensions, 0);

    for (final token in text.toLowerCase().split(
      RegExp(r'[^a-z0-9\u0900-\u097F]+'),
    )) {
      if (token.isEmpty) continue;

      var hash = 0;
      for (final unit in token.codeUnits) {
        hash = (hash * 31 + unit) & 0x7fffffff;
      }

      vector[hash % dimensions] += 1;
    }

    final magnitude = vector.fold<double>(
      0,
      (sum, value) => sum + value * value,
    );

    if (magnitude > 0) {
      final norm = magnitude.sqrt();
      for (var i = 0; i < vector.length; i++) {
        vector[i] /= norm;
      }
    }

    return vector;
  }
}
