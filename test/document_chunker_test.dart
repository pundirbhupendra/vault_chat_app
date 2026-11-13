import 'package:flutter_test/flutter_test.dart';
import 'package:vault_chat_app/rag/document_chunker.dart';

void main() {
  test('chunks long Unicode text with a bounded overlap', () async {
    final source = String.fromCharCodes(List.filled(1700, 0x0915));
    final chunks = await const DocumentChunker()
        .chunk(
          Stream<String>.value(source),
          documentId: 'document',
          documentName: 'hindi.txt',
        )
        .toList();

    expect(chunks.length, greaterThan(1));
    expect(chunks.first.text.runes.length, 700);
    expect(chunks[1].text.substring(0, 120), chunks.first.text.substring(580));
    expect(chunks.last.text.runes.length, lessThanOrEqualTo(700));
    expect(chunks.map((chunk) => chunk.chunkIndex), [0, 1, 2]);
  });

  test(
    'preserves paragraph boundaries and skips whitespace-only input',
    () async {
      const chunker = DocumentChunker(chunkSize: 24, overlap: 4);
      final chunks = await chunker
          .chunk(
            Stream<String>.fromIterable([
              'First paragraph long.\n\n',
              'Second paragraph.',
            ]),
            documentId: 'document',
            documentName: 'notes.md',
          )
          .toList();

      expect(chunks, isNotEmpty);
      expect(chunks.first.text, 'First paragraph long.');
      expect(
        await chunker
            .chunk(
              Stream<String>.value(' \n  '),
              documentId: 'empty',
              documentName: 'empty.txt',
            )
            .toList(),
        isEmpty,
      );
    },
  );
}
