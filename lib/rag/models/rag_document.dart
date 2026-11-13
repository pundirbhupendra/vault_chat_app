enum DocumentIndexStatus { pending, indexing, indexed, failed }

class RagDocument {
  const RagDocument({
    required this.id,
    required this.fileName,
    required this.importedAt,
    required this.filePath,
    required this.contentHash,
    required this.status,
    this.chunkCount = 0,
    this.errorMessage,
  });

  final String id;
  final String fileName;
  final DateTime importedAt;
  final String filePath;
  final String contentHash;
  final DocumentIndexStatus status;
  final int chunkCount;
  final String? errorMessage;

  RagDocument copyWith({
    DocumentIndexStatus? status,
    int? chunkCount,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RagDocument(
      id: id,
      fileName: fileName,
      importedAt: importedAt,
      filePath: filePath,
      contentHash: contentHash,
      status: status ?? this.status,
      chunkCount: chunkCount ?? this.chunkCount,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'fileName': fileName,
    'importedAt': importedAt.toIso8601String(),
    'filePath': filePath,
    'contentHash': contentHash,
    'status': status.name,
    'chunkCount': chunkCount,
    'errorMessage': errorMessage,
  };

  factory RagDocument.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'pending';
    final status = DocumentIndexStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => DocumentIndexStatus.pending,
    );
    return RagDocument(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      importedAt: DateTime.parse(json['importedAt'] as String),
      filePath: json['filePath'] as String,
      contentHash: json['contentHash'] as String,
      status: status,
      chunkCount: (json['chunkCount'] as num?)?.toInt() ?? 0,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}
