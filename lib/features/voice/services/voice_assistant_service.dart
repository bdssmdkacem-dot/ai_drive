import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Voice command + spoken-warning layer.
///
/// v1 note: always-on "Hey Drive" hotword detection requires a dedicated
/// wake-word engine. For the offline MVP, listening is started by a
/// tap-to-talk button instead of a hotword.
class VoiceAssistantService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _initialized = false;

  Future<bool> init() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize();
    await _tts.setLanguage('ar-SA');
    await _tts.setSpeechRate(0.48);
    return _initialized;
  }

  bool get isListening => _speech.isListening;

  Future<void> startListening({
    required void Function(String command) onCommand,
  }) async {
    if (!_initialized) await init();
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          onCommand(result.recognizedWords.trim());
        }
      },
      listenOptions: stt.SpeechListenOptions(localeId: 'ar-SA'),
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }

  Future<void> speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }
}

enum VoiceIntent {
  navigateHome,
  navigateWork,
  callContact,
  nearestGasStation,
  nearestParking,
  cancelRoute,
  recordVideo,
  saveClip,
  startParkingMode,
  stopRecording,
  unknown,
}

class VoiceCommandParser {
  static VoiceIntent parse(String text) {
    final t = text.toLowerCase().trim();

    bool has(List<String> phrases) => phrases.any((p) => t.contains(p));

    // Include common Arabic preposition/article forms such as "للبيت"
    // in addition to the standalone "البيت".
    if (has(['home', 'البيت', 'للبيت', 'المنزل', 'للمنزل'])) {
      return VoiceIntent.navigateHome;
    }
    if (has(['work', 'العمل', 'للعمل', 'الشغل'])) {
      return VoiceIntent.navigateWork;
    }
    if (has(['call', 'اتصل'])) return VoiceIntent.callContact;
    if (has(['gas', 'fuel', 'بنزين', 'محطة وقود'])) {
      return VoiceIntent.nearestGasStation;
    }
    if (has(['parking', 'موقف', 'باركينج'])) {
      return VoiceIntent.nearestParking;
    }
    if (has(['cancel', 'إلغاء', 'الغاء'])) return VoiceIntent.cancelRoute;
    if (has(['record', 'سجل', 'تسجيل'])) return VoiceIntent.recordVideo;
    if (has(['save', 'clip', 'احفظ'])) return VoiceIntent.saveClip;
    if (has(['start parking', 'وضع الوقوف'])) {
      return VoiceIntent.startParkingMode;
    }
    if (has(['stop', 'أوقف', 'ايقاف'])) return VoiceIntent.stopRecording;

    return VoiceIntent.unknown;
  }
}
