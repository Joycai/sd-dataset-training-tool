import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// Asks the user for a `.json` file and returns its text, or null when the
/// dialog is cancelled. Throws [FileSystemException] when the file cannot be
/// read (invalid UTF-8 included).
Future<String?> pickAndReadJson() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  final path = files.firstOrNull?.path;
  if (path == null) return null;
  return File(path).readAsString();
}

/// Asks where to save a `.json` file (suggesting [fileName]) and writes
/// [contents] there. Returns the chosen path, or null when cancelled.
/// Throws [FileSystemException] when the write fails.
///
/// The plugin writes the bytes itself on every desktop platform, so the
/// contents must be handed over up front rather than written afterwards.
Future<String?> saveJson({
  required String fileName,
  required String contents,
}) async {
  final uri = await FilePicker.saveFile(
    fileName: fileName,
    bytes: utf8.encode(contents),
    mimeType: 'application/json',
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  return uri?.toFilePath();
}
