enum ShareOutcome { shared, copiedToClipboard, failed }

class ShareResult {
  const ShareResult({required this.outcome, required this.message});

  final ShareOutcome outcome;
  final String message;

  bool get succeeded => outcome != ShareOutcome.failed;

  String get feedback => switch (outcome) {
    ShareOutcome.shared => 'Challenge shared!',
    ShareOutcome.copiedToClipboard =>
      'Challenge copied — paste it into any chat.',
    ShareOutcome.failed => 'Sharing is unavailable right now.',
  };
}
