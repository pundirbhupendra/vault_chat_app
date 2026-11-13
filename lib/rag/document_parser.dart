import 'dart:convert';
import 'dart:io';

class DocumentParser {
  Stream<String> extractText(File file) {
    final extension = file.path.split('.').last.toLowerCase();
    if (extension != 'txt' && extension != 'md') {
      throw UnsupportedError('Only .txt and .md documents are supported.');
    }
    return file.openRead().transform(utf8.decoder);
  }
}
