import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'models/rag_document.dart';
import 'rag_repository.dart';

class DocumentManagementScreen extends StatefulWidget {
  const DocumentManagementScreen({super.key});

  @override
  State<DocumentManagementScreen> createState() =>
      _DocumentManagementScreenState();
}

class _DocumentManagementScreenState extends State<DocumentManagementScreen> {
  List<RagDocument> _documents = const [];
  bool _embeddingModelReady = false;
  bool _loading = true;
  bool _importing = false;
  bool _downloadingModel = false;
  String? _activeDocumentId;
  int _indexedChunks = 0;
  double _downloadProgress = 0;

  RagRepository get _repository => context.read<RagRepository>();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final documents = _repository.documents;
      final modelReady = await _repository.isEmbeddingModelDownloaded;
      if (!mounted) return;
      setState(() {
        _documents = documents;
        _embeddingModelReady = modelReady;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(error);
    }
  }

  Future<void> _pickDocuments() async {
    final selectedFiles = await FilePicker.pickFiles(
      dialogTitle: 'Import text or Markdown documents',
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md'],
    );
    if (selectedFiles.isEmpty || !mounted) return;

    setState(() => _importing = true);
    try {
      for (final selectedFile in selectedFiles) {
        final document = await _repository.importDocument(
          fileName: selectedFile.name,
          bytes: selectedFile.readAsByteStream(),
        );
        if (_embeddingModelReady &&
            document.status != DocumentIndexStatus.indexed) {
          await _indexDocument(document.id);
        }
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _importing = false);
        await _refresh();
      }
    }
  }

  Future<void> _downloadEmbeddingModel() async {
    setState(() {
      _downloadingModel = true;
      _downloadProgress = 0;
    });
    try {
      await _repository.downloadEmbeddingModel(
        onProgress: (progress) {
          if (mounted) setState(() => _downloadProgress = progress);
        },
      );
      await _refresh();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _downloadingModel = false);
    }
  }

  Future<void> _indexDocument(String documentId) async {
    setState(() {
      _activeDocumentId = documentId;
      _indexedChunks = 0;
    });
    try {
      await _repository.indexDocument(
        documentId,
        onProgress: (count) {
          if (mounted) setState(() => _indexedChunks = count);
        },
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _activeDocumentId = null);
        await _refresh();
      }
    }
  }

  Future<void> _deleteDocument(RagDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text('Remove "${document.fileName}" and its indexed chunks?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.deleteDocument(document.id);
      await _refresh();
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Local documents')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_repository.recoveryMessage case final message?)
                  Card(
                    color: Colors.orange.shade900,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(message),
                    ),
                  ),
                _buildEmbeddingModelCard(),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Supported formats'),
                    subtitle: const Text(
                      'Import .txt and .md files. PDF text extraction is not configured in this build.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _importing || _activeDocumentId != null
                      ? null
                      : _pickDocuments,
                  icon: _importing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: Text(_importing ? 'Importing...' : 'Import documents'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Imported documents (${_documents.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_documents.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No local documents have been imported.'),
                  ),
                for (final document in _documents) _buildDocumentCard(document),
              ],
            ),
    );
  }

  Widget _buildEmbeddingModelCard() {
    if (_embeddingModelReady) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.check_circle, color: Colors.greenAccent),
          title: Text('Embedding model ready'),
          subtitle: Text('EmbeddingGemma 300M Q8_0 · runs locally'),
        ),
      );
    }
    final downloading = _downloadingModel;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Download the local embedding model',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'EmbeddingGemma 300M Q8_0 (about 334 MB) is a separate model from Qwen and is subject to the Google Gemma Terms. Its first download requires internet access; document indexing and search then run on-device.',
            ),
            const SizedBox(height: 12),
            if (downloading) ...[
              LinearProgressIndicator(
                value: _downloadProgress > 0 ? _downloadProgress : null,
              ),
              const SizedBox(height: 8),
              Text(
                _downloadProgress > 0
                    ? '${(_downloadProgress * 100).toStringAsFixed(1)}%'
                    : 'Connecting...',
              ),
            ] else
              FilledButton.icon(
                onPressed: _downloadEmbeddingModel,
                icon: const Icon(Icons.download),
                label: const Text('Download embedding model'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentCard(RagDocument document) {
    final indexing = _activeDocumentId == document.id;
    final status = switch (document.status) {
      DocumentIndexStatus.pending => 'Not indexed',
      DocumentIndexStatus.indexing => 'Indexing...',
      DocumentIndexStatus.indexed => 'Indexed',
      DocumentIndexStatus.failed => 'Indexing failed',
    };
    return Card(
      child: ListTile(
        leading: Icon(
          document.status == DocumentIndexStatus.indexed
              ? Icons.description
              : Icons.insert_drive_file_outlined,
        ),
        title: Text(document.fileName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$status · ${document.chunkCount} chunks'),
            if (document.errorMessage != null)
              Text(
                document.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (indexing) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
              Text('Indexed $_indexedChunks chunks so far'),
            ],
          ],
        ),
        isThreeLine: document.errorMessage != null || indexing,
        trailing: PopupMenuButton<String>(
          enabled: !indexing && _activeDocumentId == null,
          onSelected: (action) {
            if (action == 'index') _indexDocument(document.id);
            if (action == 'delete') _deleteDocument(document);
          },
          itemBuilder: (context) => [
            if (_embeddingModelReady &&
                document.status != DocumentIndexStatus.indexed)
              const PopupMenuItem(value: 'index', child: Text('Index / retry')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}
