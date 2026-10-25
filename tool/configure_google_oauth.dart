import 'dart:convert';
import 'dart:io';

/// Writes the optional Google OAuth client that ships inside release builds.
///
/// `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET` come from the CI
/// secrets. When they are absent this still writes an empty file so local and
/// fork builds compile with the guided client setup instead of one-tap sign in.
void main() {
  final clientId = (Platform.environment['GOOGLE_OAUTH_CLIENT_ID'] ?? '')
      .trim();
  final clientSecret =
      (Platform.environment['GOOGLE_OAUTH_CLIENT_SECRET'] ?? '').trim();
  final configured = clientId.isNotEmpty && clientSecret.isNotEmpty;

  final file = File('assets/config/google_oauth.json');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'clientId': configured ? clientId : '',
      'clientSecret': configured ? clientSecret : '',
    }),
  );

  if (configured) {
    stdout.writeln('Google OAuth client embedded for this build.');
  } else {
    stdout.writeln(
      'Google OAuth secrets are not set; this build uses guided setup.',
    );
  }
}
