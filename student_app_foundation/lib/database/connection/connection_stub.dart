// Platform picker. Do not import the native/web files directly — always
// import this file. Dart's conditional import at the bottom of this file
// swaps in the right implementation at compile time depending on target
// (native VM/AOT vs web/JS), so the rest of the app never needs an if/else.
export 'connection_native.dart'
    if (dart.library.js_interop) 'connection_web.dart';
