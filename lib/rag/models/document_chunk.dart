class DocumentChunk {
  const DocumentChunk({
    required this.documentId,
    required this.documentName,
    required this.chunkIndex,
    required this.text,
    this.pageNumber,
  });

  final String documentId;
  final String documentName;
  final int chunkIndex;
  final String text;
  final int? pageNumber;

  String get id => '$documentId:$chunkIndex';
}
