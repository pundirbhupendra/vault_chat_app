class ModelSpec {
  final String id;
  final String name;
  final String fileName;
  final String url;
  final int expectedBytes;

  const ModelSpec({
    required this.id,
    required this.name,
    required this.fileName,
    required this.url,
    required this.expectedBytes,
  });

  static const qwen1_5B = ModelSpec(
    id: 'qwen-1.5b',
    name: 'Qwen 2.5 1.5B (Fast • 986 MB)',
    fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    url: 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
    expectedBytes: 986048384, // Exact byte size or minimum threshold
  );

  static const qwen3B = ModelSpec(
    id: 'qwen-3b',
    name: 'Qwen 2.5 3B (Reasoning/RAG • 1.93 GB)',
    fileName: 'qwen2.5-3b-instruct-q4_k_m.gguf',
    url: 'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf',
    expectedBytes: 1929900000,
  );
}