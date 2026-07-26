/// Tool registry for the agent: spec + handler pairs and the dispatch layer.
///
/// Dispatch never throws — every failure (unknown tool, malformed JSON,
/// handler exception) becomes an error *result* that is reported back to the
/// model so it can correct itself, instead of aborting the agent loop.
library;

import 'dart:convert';

import '../../models/llm_models.dart';

export '../../models/llm_models.dart' show AgentToolSpec;

class AgentToolResult {
  const AgentToolResult(this.text,
      {this.isError = false, this.extraParts = const []});

  /// The text returned to the model (usually compact JSON).
  final String text;

  final bool isError;

  /// Images attached to the result (`view_image`); empty for text tools.
  final List<ChatContentPart> extraParts;
}

AgentToolResult toolOk(Map<String, dynamic> json,
        {List<ChatContentPart> extraParts = const []}) =>
    AgentToolResult(jsonEncode(json), extraParts: extraParts);

AgentToolResult toolError(String message) =>
    AgentToolResult(jsonEncode({'error': message}), isError: true);

typedef AgentToolHandler = Future<AgentToolResult> Function(
    Map<String, dynamic> args);

class AgentTool {
  const AgentTool({
    required this.spec,
    required this.handler,
    this.isWrite = false,
  });

  final AgentToolSpec spec;
  final AgentToolHandler handler;

  /// Write tools mutate caption files; the session may gate them behind a
  /// user confirmation (Phase 2).
  final bool isWrite;
}

class ToolRegistry {
  ToolRegistry(List<AgentTool> tools)
      : _byName = {for (final t in tools) t.spec.name: t};

  final Map<String, AgentTool> _byName;

  List<AgentToolSpec> get specs =>
      [for (final t in _byName.values) t.spec];

  AgentTool? find(String name) => _byName[name];

  /// Parses [argumentsJson] and runs the tool. Returns an error result on
  /// unknown tool / malformed arguments / handler exception.
  Future<AgentToolResult> dispatch(String name, String argumentsJson) async {
    final tool = _byName[name];
    if (tool == null) {
      return toolError('unknown tool "$name"; available: '
          '${_byName.keys.join(', ')}');
    }
    final Map<String, dynamic> args;
    try {
      final decoded = argumentsJson.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(argumentsJson);
      if (decoded is! Map<String, dynamic>) {
        return toolError('arguments must be a JSON object');
      }
      args = decoded;
    } on FormatException catch (e) {
      return toolError('invalid JSON arguments: ${e.message}');
    }
    try {
      return await tool.handler(args);
    } on ToolArgError catch (e) {
      return toolError(e.message);
    } catch (e) {
      return toolError('tool failed: $e');
    }
  }
}

/// Thrown by argument readers on invalid input; dispatch converts it into an
/// error result for the model.
class ToolArgError implements Exception {
  ToolArgError(this.message);

  final String message;

  @override
  String toString() => message;
}

// --- Argument readers ---------------------------------------------------

String requireString(Map<String, dynamic> args, String key) {
  final v = args[key];
  if (v is String && v.trim().isNotEmpty) return v.trim();
  throw ToolArgError('missing or empty required string parameter "$key"');
}

String? optString(Map<String, dynamic> args, String key) {
  final v = args[key];
  if (v == null) return null;
  if (v is String) return v.trim().isEmpty ? null : v.trim();
  throw ToolArgError('parameter "$key" must be a string');
}

bool optBool(Map<String, dynamic> args, String key, {bool fallback = false}) {
  final v = args[key];
  if (v == null) return fallback;
  if (v is bool) return v;
  throw ToolArgError('parameter "$key" must be a boolean');
}

int optInt(
  Map<String, dynamic> args,
  String key, {
  required int fallback,
  int? min,
  int? max,
}) {
  final v = args[key];
  int out;
  if (v == null) {
    out = fallback;
  } else if (v is num) {
    out = v.toInt();
  } else {
    throw ToolArgError('parameter "$key" must be an integer');
  }
  if (min != null && out < min) out = min;
  if (max != null && out > max) out = max;
  return out;
}

List<String> optStringList(
  Map<String, dynamic> args,
  String key, {
  int? maxLength,
}) {
  final v = args[key];
  if (v == null) return const [];
  if (v is! List || v.any((e) => e is! String)) {
    throw ToolArgError('parameter "$key" must be an array of strings');
  }
  final list = v.cast<String>().map((e) => e.trim()).where((e) => e.isNotEmpty);
  final out = list.toList();
  if (maxLength != null && out.length > maxLength) {
    throw ToolArgError('parameter "$key" accepts at most $maxLength items');
  }
  return out;
}

List<String> requireStringList(
  Map<String, dynamic> args,
  String key, {
  int? maxLength,
}) {
  final out = optStringList(args, key, maxLength: maxLength);
  if (out.isEmpty) {
    throw ToolArgError('missing required array parameter "$key"');
  }
  return out;
}
