// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

typedef BrowserErrorCallback =
    void Function(String source, String message, String? stack);

const _logKey = 'surreal_rap_error_log_v1';

List<String> loadPersistedErrorLog() {
  try {
    final raw =
        html.window.localStorage[_logKey] ??
        html.window.sessionStorage[_logKey];
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.whereType<String>().toList(growable: false);
    }
  } catch (_) {
    return const [];
  }
  return const [];
}

void savePersistedErrorLog(List<String> entries) {
  try {
    final encoded = jsonEncode(entries);
    html.window.localStorage[_logKey] = encoded;
    html.window.sessionStorage[_logKey] = encoded;
    html.window.name = '$_logKey:$encoded';
  } catch (_) {
    try {
      html.window.sessionStorage[_logKey] = jsonEncode(entries);
    } catch (_) {
      // If browser storage is blocked, keep the in-memory log in the app.
    }
  }
}

void clearPersistedErrorLog() {
  try {
    html.window.localStorage.remove(_logKey);
    html.window.sessionStorage.remove(_logKey);
    if ((html.window.name ?? '').startsWith('$_logKey:')) {
      html.window.name = '';
    }
  } catch (_) {
    // Nothing else to clear when browser storage is unavailable.
  }
}

void installBrowserErrorCapture(BrowserErrorCallback onError) {
  html.window.addEventListener('error', (event) {
    if (event is html.ErrorEvent) {
      final location = [
        if (event.filename != null && event.filename!.isNotEmpty)
          event.filename,
        if (event.lineno != null) 'line ${event.lineno}',
        if (event.colno != null) 'col ${event.colno}',
      ].join(' ');
      onError(
        'browser.window.onerror',
        [
          event.message ?? 'Uncaught browser error',
          if (location.isNotEmpty) location,
        ].join('\n'),
        event.error?.toString(),
      );
      return;
    }
    onError('browser.window.onerror', event.toString(), null);
  });

  html.window.addEventListener('unhandledrejection', (event) {
    onError('browser.unhandledrejection', event.toString(), null);
  });
}
