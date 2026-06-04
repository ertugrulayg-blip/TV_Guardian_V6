// lib/services/voice_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum VoiceState { unavailable, idle, listening, processing }

class VoiceService extends ChangeNotifier {
  final SpeechToText _stt = SpeechToText();
  VoiceState _state = VoiceState.idle;
  bool _init = false;
  String _last = '';
  Timer? _restart;

  final void Function(String) onCommand;
  VoiceService({required this.onCommand});

  VoiceState get state => _state;
  String get lastWords => _last;
  bool get isListening => _state == VoiceState.listening;

  Future<bool> initialize() async {
    _init = await _stt.initialize(
      onError: (_) { _set(VoiceState.idle); _scheduleRestart(); },
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          _set(VoiceState.idle);
          _scheduleRestart();
        }
      },
    );
    if (!_init) _set(VoiceState.unavailable);
    return _init;
  }

  Future<void> startListening() async {
    if (!_init || isListening) return;
    _restart?.cancel();

    final locales = await _stt.locales();
    final locale = locales.any((l) => l.localeId.startsWith('tr'))
        ? 'tr-TR' : 'en-US';

    await _stt.listen(
      onResult: (r) {
        if (!r.finalResult) return;
        final words = r.recognizedWords.trim();
        if (words.isEmpty) return;
        _last = words;
        _set(VoiceState.processing);
        onCommand(words);
        Future.delayed(const Duration(seconds: 1), () => _set(VoiceState.idle));
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      localeId: locale,
      listenMode: ListenMode.dictation,
      partialResults: false,
    );
    _set(VoiceState.listening);
  }

  Future<void> stopListening() async {
    _restart?.cancel();
    await _stt.stop();
    _set(VoiceState.idle);
  }

  void _scheduleRestart() {
    _restart?.cancel();
    _restart = Timer(const Duration(seconds: 2), () {
      if (!isListening) startListening();
    });
  }

  void _set(VoiceState s) { _state = s; notifyListeners(); }

  @override
  void dispose() { stopListening(); _restart?.cancel(); super.dispose(); }
}
