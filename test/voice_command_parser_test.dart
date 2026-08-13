import 'package:flutter_test/flutter_test.dart';
import 'package:ai_drive/features/voice/services/voice_assistant_service.dart';

void main() {
  group('VoiceCommandParser', () {
    test('parses Arabic "home" command', () {
      expect(VoiceCommandParser.parse('خذني للبيت'), VoiceIntent.navigateHome);
    });

    test('parses English "record" command', () {
      expect(VoiceCommandParser.parse('start record now'), VoiceIntent.recordVideo);
    });

    test('falls back to unknown', () {
      expect(VoiceCommandParser.parse('what is the weather'), VoiceIntent.unknown);
    });
  });
}
