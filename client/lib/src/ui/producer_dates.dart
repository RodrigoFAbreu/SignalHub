const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// When something happened, short, in local time: the time of day for today
/// (`00:36`), otherwise the date (`27 Sep`, with the year when it is not this
/// year's). [now] is for tests.
String whenLabel(DateTime time, {DateTime? now}) {
  final t = time.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  if (t.year == today.year && t.month == today.month && t.day == today.day) {
    return '${two(t.hour)}:${two(t.minute)}';
  }
  final date = '${t.day} ${_months[t.month - 1]}';
  return t.year == today.year ? date : '$date ${t.year}';
}
