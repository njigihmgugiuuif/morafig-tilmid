import 'dart:html' as html;

/// Fires when the browser reports that the connection came back.
Stream<void> onlineEvents() => html.window.onOnline.map((_) {});
