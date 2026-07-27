import 'share_service_platform_stub.dart'
    if (dart.library.js_interop) 'share_service_platform_web.dart'
    as platform;
import 'share_service_types.dart';

export 'share_service_types.dart';

class ShareService {
  const ShareService();

  static const gameName = 'PoMarket';

  static String formatChallengeMessage({
    required int score,
    required String url,
  }) {
    final safeScore = score < 0 ? 0 : score;
    final scoreText = _withThousandsSeparators(safeScore);
    final cleanUrl = url.trim();
    final challenge =
        'I just reached $scoreText points in $gameName! Can you beat me?';
    return cleanUrl.isEmpty ? challenge : '$challenge $cleanUrl';
  }

  Future<ShareResult> shareChallenge({
    required int score,
    required String nickname,
    required String url,
  }) async {
    final cleanNickname = nickname.trim();
    final title = cleanNickname.isEmpty
        ? '$gameName Challenge'
        : "$cleanNickname's $gameName Challenge";
    final message = formatChallengeMessage(score: score, url: url);
    final outcome = await platform.deliverChallenge(
      title: title,
      message: message,
    );
    return ShareResult(outcome: outcome, message: message);
  }

  static String _withThousandsSeparators(int value) {
    final digits = value.toString();
    final output = StringBuffer();
    for (var index = 0; index < digits.length; index += 1) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        output.write(',');
      }
      output.write(digits[index]);
    }
    return output.toString();
  }
}
