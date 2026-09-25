import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// Asks the user for a `.json` file and returns its text, or null when the
/// dialog is cancelled. Throws [FileSystemException] when the file cannot be
/// read (invalid UTF-8 included).
Future<String?> pickAndReadJson() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  final path = result?.files.single.path;
  if (path == null) return null;
  return File(path).readAsString();
}

/// Asks where to save a `.json` file (suggesting [fileName]) and writes
/// [contents] there. Returns the chosen path, or null when cancelled.
/// Throws [FileSystemException] when the write fails.
Future<String?> saveJson({
  required String fileName,
  required String contents,
}) async {
  final path = await FilePicker.saveFile(
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (path == null) return null;
  await File(path).writeAsString(contents);
  return path;
}
