import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault_chat_app/rag/models/document_chunk.dart';
import 'package:vault_chat_app/rag/models/retrieved_chunk.dart';
import 'package:vault_chat_app/rag/rag_repository.dart';

import 'fakes/fake_embedding_service.dart';

void main() {
  late Directory directory;
  late RagRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vault-rag-test-');
    repository = RagRepository(
      storageDirectory: directory,
      embeddingService: FakeEmbeddingService(),
    );
    await repository.initialize();
  });

  tearDown(() async {
    await repository.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('detects duplicate imports by content hash', () async {
    const text = 'Offline notes about Hindi and local search.';
    final first = await repository.importDocument(
      fileName: 'notes.txt',
      bytes: Stream<List<int>>.value(utf8.encode(text)),
    );
    final duplicate = await repository.importDocument(
      fileName: 'copy.md',
      bytes: Stream<List<int>>.value(utf8.encode(text)),
    );

    expect(duplicate.id, first.id);
    expect(repository.documents, hasLength(1));
  });

  test('indexes and retrieves persisted source metadata', () async {
    final document = await repository.importDocument(
      fileName: 'travel.md',
      bytes: Stream<List<int>>.value(
        utf8.encode(
          'Delhi is the capital of India. Hindi: भारत की राजधानी दिल्ली है.',
        ),
      ),
    );
    await repository.indexDocument(document.id);

    final results = await repository.retrieve('What is the capital of India?');
    expect(results, hasLength(1));
    expect(results.single.documentName, 'travel.md');
    expect(results.single.documentId, document.id);
    expect(results.single.chunkIndex, 0);
    expect(results.single.pageNumber, isNull);
    expect(
      repository.formatContext(results),
      contains('[travel.md · chunk 1]'),
    );
    expect(repository.indexedChunkCount, 1);
  });

  test('removes document files, metadata, and vectors', () async {
    final document = await repository.importDocument(
      fileName: 'remove.txt',
      bytes: Stream<List<int>>.value(
        utf8.encode('This document will be deleted.'),
      ),
    );
    await repository.indexDocument(document.id);
    final sourceFile = File(document.filePath);

    await repository.deleteDocument(document.id);

    expect(repository.documents, isEmpty);
    expect(repository.indexedChunkCount, 0);
    expect(await sourceFile.exists(), isFalse);
  });

  test('formats page and chunk citations without inventing a page', () {
    const chunk = RetrievedChunk(
      documentId: 'id',
      documentName: 'manual.pdf',
      chunkId: 'id:2',
      chunkIndex: 2,
      pageNumber: 8,
      text: 'Source excerpt.',
      score: 0.9,
    );
    expect(chunk.sourceLabel, 'manual.pdf · page 8 · chunk 3');
    const textChunk = DocumentChunk(
      documentId: 'id',
      documentName: 'notes.txt',
      chunkIndex: 0,
      text: 'Text',
    );
    expect(textChunk.pageNumber, isNull);

    final context = repository.formatContext([chunk]);
    expect(context, contains('[manual.pdf · page 8 · chunk 3]'));
    expect(context, contains('Source excerpt.'));
  });
}
