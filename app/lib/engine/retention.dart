/// How long Kantoi keeps what it stores on the device.
library;

enum Retention { days7, days30, forever }

const retentionLabels = {
  Retention.days7: '7 days',
  Retention.days30: '30 days',
  Retention.forever: 'Keep until I delete',
};

const defaultRetention = Retention.days30;

Duration? retentionPeriod(Retention r) => switch (r) {
      Retention.days7 => const Duration(days: 7),
      Retention.days30 => const Duration(days: 30),
      Retention.forever => null,
    };

/// Removes items older than the retention period, in place. Returns how many
/// were removed.
int pruneOld<T>(List<T> items, DateTime Function(T) at, Retention r, {DateTime? now}) {
  final p = retentionPeriod(r);
  if (p == null) return 0;
  final cutoff = (now ?? DateTime.now()).subtract(p);
  final before = items.length;
  items.removeWhere((x) => at(x).isBefore(cutoff));
  return before - items.length;
}
