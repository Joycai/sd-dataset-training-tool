import 'dart:async';

/// Run-local cancellation shared by tools, state, and I/O. Zones keep existing
/// caption handlers compatible without putting a mutable token on shared state.
class OperationContext {
  OperationContext({
    required this.cancelled,
    this.invalidReason,
    this.cancelSignal,
    this.writeAuthorized = false,
  });

  final bool Function() cancelled;
  final Future<void>? cancelSignal;
  final bool writeAuthorized;
  final String? Function()? invalidReason;
  static final Object _key = Object();
  static OperationContext? get current =>
      Zone.current[_key] as OperationContext?;

  String? get reason =>
      cancelled() ? 'operation cancelled' : invalidReason?.call();
  static bool get stopped => current?.reason != null;

  static void check() {
    final reason = current?.reason;
    if (reason != null) throw StateError(reason);
  }

  Future<T> run<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_key: this});
}
