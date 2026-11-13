import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dart_vector_index/dart_vector_index.dart';
import 'package:path_provider/path_provider.dart';

import 'document_chunker.dart';
import 'document_parser.dart';
import 'embedding_repository.dart';
import 'models/document_chunk.dart';
import 'models/rag_document.dart';
import 'models/retrieved_chunk.dart';

class RagRepository {
  RagRepository({
    EmbeddingService? embeddingService,
    this._storageDirectory,
    DocumentChunker? chunker,
    DocumentParser? parser,
  }) : _embeddings = embeddingService ?? EmbeddingRepository(),
       _chunker = chunker ?? const DocumentChunker(),
       _parser = parser ?? DocumentParser();

  static const _embeddingDimensions = 768;
  static const _embeddingBatchSize = 8;

  final EmbeddingService _embeddings;
  final Directory? _storageDirectory;
  final DocumentChunker _chunker;
  final DocumentParser _parser;
  final Map<String, RagDocument> _documents = {};

  late Directory _ragDirectory;
  late File _indexFile;
  late File _documentsFile;
  late VectorStore _store;
  bool _initialized = false;
  String? _recoveryMessage;
  String? _indexingDocumentId;

  String? get recoveryMessage => _recoveryMessage;

  List<RagDocument> get documents {
    _ensureInitialized();
    return List.unmodifiable(
      _documents.values.toList()
        ..sort((left, right) => right.importedAt.compareTo(left.importedAt)),
    );
  }

  int get indexedChunkCount {
    _ensureInitialized();
    return _store.count;
  }

  Future<bool> get isEmbeddingModelDownloaded =>
      _embeddings.isModelDownloaded();

  Future<void> downloadEmbeddingModel({
    void Function(double progress)? onProgress,
  }) => _embeddings.downloadModel(onProgress: onProgress);

  Future<void> initialize() async {
    if (_initialized) return;

    final supportDirectory =
        _storageDirectory ?? await getApplicationSupportDirectory();
    _ragDirectory = Directory('${supportDirectory.path}/rag');
    await _ragDirectory.create(recursive: true);
    final documentsDirectory = Directory('${_ragDirectory.path}/documents');
    await documentsDirectory.create(recursive: true);
    _indexFile = File('${_ragDirectory.path}/vector_index.json');
    _documentsFile = File('${_ragDirectory.path}/documents.json');
    if (await _documentsFile.exists()) {
      final decoded = jsonDecode(await _documentsFile.readAsString());
      if (decoded is! List) {
        throw const FormatException('The local document catalog is invalid.');
      }
      for (final entry in decoded) {
        final document = RagDocument.fromJson(
          Map<String, dynamic>.from(entry as Map),
        );
        _documents[document.id] = document;
      }
    }

    if (await _indexFile.exists()) {
      try {
        _store = await VectorStore.loadFromFile(_indexFile);
        if (_store.count > 0 && _store.dimension != _embeddingDimensions) {
          _recoveryMessage =
              'The saved vector index uses an incompatible embedding size and will be rebuilt.';
          _resetIndexAndDocuments();
        }
      } catch (error) {
        _recoveryMessage =
            'The saved vector index could not be read and will be rebuilt: $error';
        _resetIndexAndDocuments();
      }
    } else {
      _store = _newStore();
      if (_documents.values.any(
        (document) => document.status == DocumentIndexStatus.indexed,
      )) {
        _recoveryMessage =
            'The saved vector index is missing; indexed documents must be indexed again.';
        _resetIndexAndDocuments();
      }
    }

    for (final entry in _documents.entries.toList()) {
      final document = entry.value;
      if (document.status == DocumentIndexStatus.indexing) {
        _documents[entry.key] = document.copyWith(
          status: DocumentIndexStatus.pending,
          clearError: true,
        );
      }
    }
    await _saveDocuments();
    if (_recoveryMessage != null || !await _indexFile.exists()) {
      await _store.saveToFile(_indexFile);
    }
    _initialized = true;
  }

  Future<RagDocument> importDocument({
    required String fileName,
    required Stream<List<int>> bytes,
  }) async {
    _ensureInitialized();
    final extension = _extensionOf(fileName);
    if (extension != 'txt' && extension != 'md') {
      throw UnsupportedError('Only .txt and .md documents are supported.');
    }

    final temporaryFile = File(
      '${_ragDirectory.path}/documents/import-${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    try {
      await temporaryFile.create(recursive: true);
      await temporaryFile.openWrite().addStream(bytes);
      final digest = await sha256.bind(temporaryFile.openRead()).first;
      final contentHash = digest.toString();
      final existing = _documents.values.cast<RagDocument?>().firstWhere(
        (document) => document?.contentHash == contentHash,
        orElse: () => null,
      );
      if (existing != null) {
        await temporaryFile.delete();
        return existing;
      }

      final id = contentHash;
      final file = File('${_ragDirectory.path}/documents/$id.$extension');
      await temporaryFile.rename(file.path);
      final document = RagDocument(
        id: id,
        fileName: fileName,
        importedAt: DateTime.now(),
        filePath: file.path,
        contentHash: contentHash,
        status: DocumentIndexStatus.pending,
      );
      _documents[id] = document;
      await _saveDocuments();
      return document;
    } catch (_) {
      if (await temporaryFile.exists()) await temporaryFile.delete();
      rethrow;
    }
  }

  Future<void> indexDocument(
    String documentId, {
    void Function(int indexedChunks)? onProgress,
  }) async {
    _ensureInitialized();
    if (_indexingDocumentId != null) {
      throw StateError('Another document is currently being indexed.');
    }
    final original = _documents[documentId];
    if (original == null) {
      throw StateError('Document $documentId was not found.');
    }
    final file = File(original.filePath);
    if (!await file.exists()) {
      throw FileSystemException(
        'The imported document file is missing.',
        file.path,
      );
    }

    _indexingDocumentId = documentId;
    var indexedChunks = 0;
    try {
      for (var index = 0; index < original.chunkCount; index++) {
        _store.remove('$documentId:$index');
      }
      await _store.saveToFile(_indexFile);

      var document = original.copyWith(
        status: DocumentIndexStatus.indexing,
        chunkCount: 0,
        clearError: true,
      );
      _documents[documentId] = document;
      await _saveDocuments();
      await _embeddings.initialize();

      final batch = <DocumentChunk>[];
      await for (final chunk in _chunker.chunk(
        _parser.extractText(file),
        documentId: documentId,
        documentName: original.fileName,
      )) {
        batch.add(chunk);
        if (batch.length == _embeddingBatchSize) {
          indexedChunks = await _indexBatch(document, batch, indexedChunks);
          document = _documents[documentId]!;
          batch.clear();
          onProgress?.call(indexedChunks);
        }
      }
      if (batch.isNotEmpty) {
        indexedChunks = await _indexBatch(document, batch, indexedChunks);
        document = _documents[documentId]!;
        onProgress?.call(indexedChunks);
      }
      if (indexedChunks == 0) {
        throw FormatException(
          'No readable text was found in ${original.fileName}.',
        );
      }

      _documents[documentId] = document.copyWith(
        status: DocumentIndexStatus.indexed,
        chunkCount: indexedChunks,
      );
      await _saveDocuments();
    } catch (error) {
      for (var index = 0; index < indexedChunks; index++) {
        _store.remove('$documentId:$index');
      }
      await _store.saveToFile(_indexFile);
      _documents[documentId] = original.copyWith(
        status: DocumentIndexStatus.failed,
        chunkCount: 0,
        errorMessage: error.toString(),
      );
      await _saveDocuments();
      rethrow;
    } finally {
      _indexingDocumentId = null;
    }
  }

  Future<int> _indexBatch(
    RagDocument document,
    List<DocumentChunk> chunks,
    int alreadyIndexed,
  ) async {
    final vectors = await _embeddings.embedDocuments([
      for (final chunk in chunks) chunk.text,
    ], title: document.fileName);
    if (vectors.length != chunks.length) {
      throw StateError(
        'The embedding service returned an unexpected vector count.',
      );
    }

    final newCount = alreadyIndexed + chunks.length;
    _documents[document.id] = document.copyWith(
      status: DocumentIndexStatus.indexing,
      chunkCount: newCount,
    );
    await _saveDocuments();
    for (var index = 0; index < chunks.length; index++) {
      final chunk = chunks[index];
      final vector = vectors[index];
      if (vector.length != _embeddingDimensions) {
        throw StateError(
          'Embedding dimension ${vector.length} does not match the saved index dimension $_embeddingDimensions.',
        );
      }
      _store.add(
        id: chunk.id,
        vector: vector,
        metadata: {
          'documentId': chunk.documentId,
          'documentName': chunk.documentName,
          'chunkId': chunk.id,
          'chunkIndex': chunk.chunkIndex,
          'content': chunk.text,
          if (chunk.pageNumber != null) 'pageNumber': chunk.pageNumber,
        },
      );
    }
    await _store.saveToFile(_indexFile);
    return newCount;
  }

  Future<List<RetrievedChunk>> retrieve(String query, {int topK = 3}) async {
    _ensureInitialized();
    if (topK <= 0) throw ArgumentError.value(topK, 'topK', 'Must be positive.');
    if (_store.count == 0 || query.trim().isEmpty) return const [];

    await _embeddings.initialize();
    final vector = await _embeddings.embedQuery(query);
    if (vector.length != _embeddingDimensions) {
      throw StateError(
        'Query embedding dimension ${vector.length} does not match the saved index dimension $_embeddingDimensions.',
      );
    }
    final results = _store.similaritySearch(vector, limit: max(topK * 2, topK));
    final retrieved = <RetrievedChunk>[];
    final seen = <String>{};
    for (final result in results) {
      final metadata = result.metadata;
      final text = metadata['content'] as String?;
      final chunkId = metadata['chunkId'] as String? ?? result.id;
      if (text == null || !seen.add(text.trim())) continue;
      retrieved.add(
        RetrievedChunk(
          documentId: metadata['documentId'] as String? ?? '',
          documentName:
              metadata['documentName'] as String? ?? 'Unknown document',
          chunkId: chunkId,
          chunkIndex: (metadata['chunkIndex'] as num?)?.toInt() ?? 0,
          text: text,
          score: result.score,
          pageNumber: (metadata['pageNumber'] as num?)?.toInt(),
        ),
      );
      if (retrieved.length == topK) break;
    }
    return retrieved;
  }

  String formatContext(List<RetrievedChunk> chunks) {
    if (chunks.isEmpty) return '';
    return [
      for (final chunk in chunks) '[${chunk.sourceLabel}]\n${chunk.text}',
    ].join('\n\n');
  }

  Future<void> deleteDocument(String documentId) async {
    _ensureInitialized();
    if (_indexingDocumentId == documentId) {
      throw StateError(
        'Wait for indexing to finish before deleting this document.',
      );
    }
    final document = _documents[documentId];
    if (document == null) return;
    for (var index = 0; index < document.chunkCount; index++) {
      _store.remove('$documentId:$index');
    }
    await _store.saveToFile(_indexFile);
    final file = File(document.filePath);
    if (await file.exists()) await file.delete();
    _documents.remove(documentId);
    await _saveDocuments();
  }

  Future<void> dispose() => _embeddings.dispose();

  VectorStore _newStore() => VectorStore(
    type: IndexType.hnsw,
    metric: DistanceMetric.cosine,
    randomSeed: 42,
  );

  void _resetIndexAndDocuments() {
    _store = _newStore();
    for (final entry in _documents.entries.toList()) {
      _documents[entry.key] = entry.value.copyWith(
        status: DocumentIndexStatus.pending,
        chunkCount: 0,
        clearError: true,
      );
    }
  }

  Future<void> _saveDocuments() async {
    final temporary = File('${_documentsFile.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(
        _documents.values.map((document) => document.toJson()).toList(),
      ),
      flush: true,
    );
    if (await _documentsFile.exists()) await _documentsFile.delete();
    await temporary.rename(_documentsFile.path);
  }

  String _extensionOf(String fileName) {
    final separator = fileName.lastIndexOf('.');
    return separator < 0 ? '' : fileName.substring(separator + 1).toLowerCase();
  }

  void _ensureInitialized() {
    if (!_initialized) throw StateError('Call initialize() first.');
  }
}
