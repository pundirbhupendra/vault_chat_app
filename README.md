# Vault Chat

Vault Chat is an on-device Flutter chat app. Qwen handles generation through
`llamadart`; imported TXT and Markdown documents can be indexed and searched
locally to provide retrieved context and source references in chat.

## Local document search

1. Download the Qwen model from the chat screen.
2. Open **Local documents** and import `.txt` or `.md` files.
3. Download **EmbeddingGemma 300M Q8_0** (about 334 MB) from the document
   screen. The first download requires internet access.
4. Index imported documents, then ask questions in English, Hindi, or Hinglish.
   Answers that use retrieved passages show the source filename, chunk number,
   and page number when one is available.

Chat generation uses the existing Qwen model. EmbeddingGemma is a separate
multilingual embedding model, loaded and managed independently. Embeddings,
document extraction, vector search, and generation run on-device after both
models have been downloaded. Imported files, document metadata, and the cosine
vector index are kept in application support storage.

The embedding model is distributed under the [Google Gemma Terms of Use](https://ai.google.dev/gemma/terms);
review those terms before downloading. The app does not download documents or
send prompts, embeddings, or retrieved text to a server. It does not currently
include a PDF text-extraction package, so PDF files are not supported.

## Retrieval implementation

- UTF-8 text and Markdown are decoded as streams and split into configurable
  700-character chunks with 120-character overlap.
- EmbeddingGemma query/document task formatting is applied consistently using
  the installed `llamadart` embedding API; vectors are normalized to 768
  dimensions.
- `dart_vector_index` stores cosine-search vectors and source metadata locally.
- Document content hashes prevent duplicate imports; deleting a document also
  removes its chunks and copied file.
- Retrieved passage contents are treated as untrusted prompt data. Prompt
  instructions reduce, but cannot guarantee prevention of, prompt injection.

Run checks with:

```shell
flutter analyze
flutter test
```
