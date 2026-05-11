typedef BrowserErrorCallback =
    void Function(String source, String message, String? stack);

final List<String> _memoryLog = [];

List<String> loadPersistedErrorLog() => List.unmodifiable(_memoryLog);

void savePersistedErrorLog(List<String> entries) {
  _memoryLog
    ..clear()
    ..addAll(entries);
}

void clearPersistedErrorLog() {
  _memoryLog.clear();
}

void installBrowserErrorCapture(BrowserErrorCallback onError) {}
