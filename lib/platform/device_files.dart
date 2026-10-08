// Device file access (phase C): pick photos / files and hand a file out.
//
// Conditional export: on Flutter Web (the deployed PWA) the real browser file
// input is used; everywhere else the stub reports "not available" honestly.
// NO package was added for this (pubspec.yaml is frozen in phase C): the web
// implementation uses the SDK's own browser API. Choosing a cross-platform
// image package for native builds is the OPEN decision O-4, to be taken after
// a Web/PWA, offline, compression and export review, in a separate commit.
export 'device_files_stub.dart'
    if (dart.library.html) 'device_files_web.dart';
