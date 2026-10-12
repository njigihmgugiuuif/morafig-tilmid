/// Not-web fallback: no "back online" signal is available, so only the
/// timer and the app-open / app-resume triggers run.
Stream<void> onlineEvents() => const Stream<void>.empty();
