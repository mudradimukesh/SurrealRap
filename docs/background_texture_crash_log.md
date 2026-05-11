# Background Texture Crash Log

This document tracks the crash investigation for changing background textures on imported books.

## What Is Now Captured

- Flutter framework errors through `FlutterError.onError`
- Unhandled async/platform errors through `PlatformDispatcher.instance.onError`
- Widget build failures through `ErrorWidget.builder`
- Dart zone failures through `runZonedGuarded`
- Browser window errors on web through `window.onerror`
- Browser promise rejection events through `unhandledrejection`
- Texture change requests, including book title, format, current page, and target texture
- Texture change completion after the next rendered frame
- Texture image load failures, including the asset path and stack trace when Flutter provides it
- Texture dropdown and post-frame failures with Flutter/Dart stack traces

## Where To See The Log

Open the app, go to the Reader tab, and open Reader Tools. The app now shows a `Crash Log Document` section with the persisted log entries.

On web, the log is also persisted in browser `localStorage` under:

`surreal_rap_error_log_v1`

The same log is mirrored into `sessionStorage` so the app can recover it after a soft reload. The newest error appears at the top of the in-app document under `Latest Application Error`.

## Current Collected Error

No Dart/Flutter exception was recovered from the app log. I searched the Codex browser storage and the Chrome storage for `surreal_rap_error_log_v1`, `reader.texture.change`, texture load failures, `FlutterError`, and `PlatformDispatcher` entries, and no saved app error entry was present.

Latest run checked:

```text
Sun May 10 22:59:36 CDT 2026  GET /                              200
Sun May 10 22:59:36 CDT 2026  GET /main.dart.js                  200
Sun May 10 22:59:47 CDT 2026  GET /assets/assets/textures/crumpled_paper.png  200
```

The current `build/web/main.dart.js` does contain the new in-app crash logger strings:

```text
Storage key: surreal_rap_error_log_v1
reader.texture.change.postFrame
reader.tools.texture.dropdown
browser.window.onerror
```

Because the expected boot entry `app.error_log.install` and storage key `surreal_rap_error_log_v1` were not found after this crash, this run did not produce a Flutter/Dart stack trace inside the application. The most likely explanation is that the page was still running a stale service-worker-cached build, or the browser/webview renderer died before the logger could persist its first entry.

The recovered Codex host evidence shows the preview renderer was closed/destroyed instead:

```text
Sun May 10 21:13:01 CDT 2026
electron: renderer.destroyed
data: { id: 3, url: "about:blank" }

Sun May 10 21:13:01 CDT 2026
electron: window.closed
data: { id: 3, url: "about:blank" }
```

The local web server is still alive and serving the app:

```text
HEAD / HTTP/1.1 200
Server: SimpleHTTP/0.6 Python/3.13.2
```

Chrome Crashpad did not have a recent crash dump for this run, and the local server did not report HTTP 404/500 errors. That means the current visible failure is a browser/webview renderer teardown, not a captured Flutter exception. If the texture switch still crashes before the in-app logger can write to localStorage, the next step is to reproduce with Chrome DevTools open and capture the Console error at the moment the renderer dies.
