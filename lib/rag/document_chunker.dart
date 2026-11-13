import 'dart:math' as math;

import 'models/document_chunk.dart';

class DocumentChunker {
  const DocumentChunker({this.chunkSize = 700, this.overlap = 120})
    : assert(chunkSize > 0),
      assert(overlap >= 0),
      assert(overlap < chunkSize);

  final int chunkSize;
  final int overlap;

  Stream<DocumentChunk> chunk(
    Stream<String> text, {
    required String documentId,
    required String documentName,
  }) async* {
    final buffer = <int>[];
    var chunkIndex = 0;

    await for (final fragment in text) {
      for (final rune in fragment.runes) {
        buffer.add(rune);
        while (buffer.length >= chunkSize) {
          final end = _findBoundary(buffer);
          final content = String.fromCharCodes(buffer.take(end)).trim();
          if (content.isNotEmpty) {
            yield DocumentChunk(
              documentId: documentId,
              documentName: documentName,
              chunkIndex: chunkIndex++,
              text: content,
            );
          }
          buffer.removeRange(0, end - overlap);
        }
      }
    }

    final remainder = String.fromCharCodes(buffer).trim();
    if (remainder.isNotEmpty) {
      yield DocumentChunk(
        documentId: documentId,
        documentName: documentName,
        chunkIndex: chunkIndex,
        text: remainder,
      );
    }
  }

  int _findBoundary(List<int> buffer) {
    final minimum = math.max(overlap + 1, (chunkSize * 0.75).floor());
    for (var index = chunkSize - 1; index >= minimum; index--) {
      if (buffer[index] == 10 || buffer[index] == 13 || buffer[index] == 32) {
        return index;
      }
    }
    return chunkSize;
  }
}
