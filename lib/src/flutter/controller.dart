import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../core/diagnostics.dart';
import '../core/exceptions.dart';
import '../core/layout.dart';
import '../core/prediction.dart';

/// Publishes the most recently committed text-wrap selection after layout.
///
/// The value is assigned synchronously so layout clients can inspect it right
/// away. Listener notification is deferred to the end of the frame to avoid a
/// reentrant build while the internal `RenderTextAutoWrap` is laying out.
///
/// If multiple renderers share a controller, the last commit wins. A frame
/// notification publishes that final snapshot; detaching an earlier writer
/// does not cancel a later writer's pending notification. Use a separate
/// controller per widget when independent results are needed.
final class TextAutoWrapController extends ChangeNotifier {
  TextWrapResult? _result;
  List<TextWrapFailure> _failures = const [];
  Object? _owner;
  var _generation = 0;
  var _notificationScheduled = false;
  var _hasUnnotifiedChange = false;
  var _disposed = false;

  /// The latest immutable selection committed by an attached renderer.
  /// Null before layout or when native diagnostic geometry is unavailable.
  TextWrapResult? get result => _result;

  /// Alias for [result] for value-listenable-style consumers.
  TextWrapResult? get value => _result;

  /// Failures observed during the latest layout, even if [result] is null.
  /// Cleared by the next successful selection. Notifications are frame-deferred.
  List<TextWrapFailure> get failures => _failures;

  /// Internal renderer hook; notifies after the current frame.
  void commitResult(
    Object owner,
    TextWrapResult value, {
    List<TextWrapFailure> failures = const [],
  }) {
    if (_disposed) return;
    final materiallyEquivalent =
        _sameResult(_result, value) && _sameFailures(_failures, failures);
    _result = value;
    _failures = List.unmodifiable(failures);
    if (materiallyEquivalent && !_hasUnnotifiedChange) return;
    _hasUnnotifiedChange = true;
    if (_notificationScheduled && identical(_owner, owner)) return;
    _owner = owner;
    _schedule(owner);
  }

  /// Internal renderer hook; clears stale geometry when measurement fails.
  void clearResult(Object owner, {List<TextWrapFailure> failures = const []}) {
    if (_disposed) return;
    final equivalent = _result == null && _sameFailures(_failures, failures);
    _result = null;
    _failures = List.unmodifiable(failures);
    if (equivalent && !_hasUnnotifiedChange) return;
    _hasUnnotifiedChange = true;
    if (_notificationScheduled && identical(_owner, owner)) return;
    _owner = owner;
    _schedule(owner);
  }

  /// Internal renderer hook; invalidates a pending renderer notification.
  void detachOwner(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _generation++;
    _notificationScheduled = false;
    // Keep the change pending: an equivalent commit by a reattached or new
    // owner still needs to deliver the notification this detach cancelled.
  }

  void _schedule(Object owner) {
    _notificationScheduled = true;
    final generation = ++_generation;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed ||
          !_notificationScheduled ||
          generation != _generation ||
          !identical(_owner, owner)) {
        return;
      }
      _notificationScheduled = false;
      _hasUnnotifiedChange = false;
      _owner = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _hasUnnotifiedChange = false;
    _owner = null;
    _generation++;
    _notificationScheduled = false;
    super.dispose();
  }
}

bool _sameFailures(List<TextWrapFailure> left, List<TextWrapFailure> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i].stage != right[i].stage ||
        left[i].reason != right[i].reason ||
        !_sameFailureError(left[i].error, right[i].error)) {
      return false;
    }
  }
  return true;
}

bool _sameFailureError(Object left, Object right) {
  if (left.runtimeType != right.runtimeType) return false;
  if (left is TextWrapException && right is TextWrapException) {
    return left.message == right.message;
  }
  if (left is StateError && right is StateError) {
    return left.message == right.message;
  }
  if (left is RangeError &&
      right is RangeError &&
      (!_sameErrorValue(left.start, right.start) ||
          !_sameErrorValue(left.end, right.end))) {
    return false;
  }
  if (left is ArgumentError && right is ArgumentError) {
    return left.name == right.name &&
        _sameErrorValue(left.message, right.message) &&
        _sameErrorValue(left.invalidValue, right.invalidValue);
  }
  // Opaque custom errors have no safe, stable content contract. Group them by
  // type rather than invoking arbitrary toString/equality code or notifying
  // on each newly allocated error during a repeated failing layout.
  return true;
}

bool _sameErrorValue(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is String && right is String) return left == right;
  if (left is num && right is num) {
    // Web does not consider NaN identical to itself. Repeated numeric failure
    // values still describe the same error, independent of backend identity.
    return left == right || (left.isNaN && right.isNaN);
  }
  if (left is bool && right is bool) return left == right;
  return false;
}

bool _sameResult(TextWrapResult? left, TextWrapResult right) {
  if (identical(left, right)) return true;
  if (left == null ||
      left.applied != right.applied ||
      left.reason != right.reason ||
      left.source != right.source ||
      left.overflow != right.overflow) {
    return false;
  }
  final leftLayout = left.layout;
  final rightLayout = right.layout;
  if (leftLayout.sourceText != rightLayout.sourceText ||
      leftLayout.lineCount != rightLayout.lineCount ||
      leftLayout.totalModelCost != rightLayout.totalModelCost ||
      !_sameInts(left.breakOffsets, right.breakOffsets) ||
      !_sameRanges(left.ranges, right.ranges) ||
      !_sameDoubles(left.widths, right.widths) ||
      !_sameCandidates(
        leftLayout.selectedCandidates,
        rightLayout.selectedCandidates,
      )) {
    return false;
  }
  return true;
}

bool _sameCandidates(List<BreakCandidate> left, List<BreakCandidate> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    final leftCandidate = left[index];
    final rightCandidate = right[index];
    if (leftCandidate.offset != rightCandidate.offset ||
        leftCandidate.penalty != rightCandidate.penalty ||
        leftCandidate.levelName != rightCandidate.levelName ||
        leftCandidate.consensusCount != rightCandidate.consensusCount ||
        leftCandidate.isFallback != rightCandidate.isFallback) {
      return false;
    }
  }
  return true;
}

bool _sameInts(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameRanges(List<TextLineRange> left, List<TextLineRange> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index].start != right[index].start ||
        left[index].end != right[index].end) {
      return false;
    }
  }
  return true;
}

bool _sameDoubles(List<double> left, List<double> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
