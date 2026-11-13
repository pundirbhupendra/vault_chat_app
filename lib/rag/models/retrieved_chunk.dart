class RetrievedChunk {
  const RetrievedChunk({
    required this.documentId,
    required this.documentName,
    required this.chunkId,
    required this.chunkIndex,
    required this.text,
    required this.score,
    this.pageNumber,
  });

  final String documentId;
  final String documentName;
  final String chunkId;
  final int chunkIndex;
  final String text;
  final double score;
  final int? pageNumber;

  String get sourceLabel =>
      '$documentName${pageNumber == null ? '' : ' · page $pageNumber'} · chunk ${chunkIndex + 1}';
}
