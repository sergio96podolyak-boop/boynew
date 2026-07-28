import 'sfx_backend.dart';
import 'sfx_platform_stub.dart'
    if (dart.library.io) 'sfx_platform_io.dart'
    if (dart.library.js_interop) 'sfx_platform_web.dart'
    as platform;

SfxBackend createSfxBackend() => platform.createSfxBackend();
