DateTime? computeVaultAutoLockDeadline({
  required DateTime? unlockedAt,
  required int? autoLockMinutes,
}) {
  if (unlockedAt == null || autoLockMinutes == null) {
    return null;
  }
  return unlockedAt.add(Duration(minutes: autoLockMinutes));
}

Duration? computeVaultAutoLockRemaining({
  required DateTime now,
  required DateTime? unlockedAt,
  required int? autoLockMinutes,
}) {
  final deadline = computeVaultAutoLockDeadline(
    unlockedAt: unlockedAt,
    autoLockMinutes: autoLockMinutes,
  );
  if (deadline == null) {
    return null;
  }

  final remaining = deadline.difference(now);
  if (remaining <= Duration.zero) {
    return Duration.zero;
  }
  return remaining;
}

String formatVaultAutoLockCountdown(Duration remaining) {
  final totalSeconds = remaining.inSeconds < 0 ? 0 : remaining.inSeconds;
  final hours = totalSeconds ~/ Duration.secondsPerHour;
  final minutes =
      (totalSeconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
  final seconds = totalSeconds % Duration.secondsPerMinute;

  String twoDigits(int value) => value.toString().padLeft(2, '0');

  return 'Autolock in '
      '${twoDigits(hours)}h:${twoDigits(minutes)}m:${twoDigits(seconds)}s';
}
