import 'package:flutter/services.dart';

import 'capture.dart';

/// Recursos nativos do Android: widget da tela inicial e notificações.
class NativeBridge {
  static const _ch = MethodChannel('financa/capture');

  static bool get supported => CaptureBridge.supported;

  static Future<void> updateWidget(Map<String, Object?> data) async {
    if (!supported) return;
    try {
      await _ch.invokeMethod('updateWidget', data);
    } catch (_) {}
  }

  static Future<void> notify(int id, String title, String body) async {
    if (!supported) return;
    try {
      await _ch.invokeMethod('notify', {'id': id, 'title': title, 'body': body});
    } catch (_) {}
  }

  /// Agenda lembretes (substitui os anteriores). Cada item: id, at (ms), title, body.
  static Future<void> schedule(List<Map<String, Object?>> reminders) async {
    if (!supported) return;
    try {
      await _ch.invokeMethod('schedule', {'items': reminders});
    } catch (_) {}
  }

  static Future<bool> notificationsAllowed() async {
    if (!supported) return false;
    try {
      return await _ch.invokeMethod<bool>('notificationsAllowed') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestNotificationPermission() async {
    if (!supported) return;
    try {
      await _ch.invokeMethod('requestNotificationPermission');
    } catch (_) {}
  }

  /// Preferência lida pelo lado nativo (ex.: avisar quando capturar um gasto).
  static Future<void> setFlag(String key, bool value) async {
    if (!supported) return;
    try {
      await _ch.invokeMethod('setFlag', {'key': key, 'value': value});
    } catch (_) {}
  }
}
