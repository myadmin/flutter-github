/// Web 端 URL 策略的跨平台门面
library;

export 'web_url_strategy_stub.dart'
    if (dart.library.js_interop) 'web_url_strategy_web.dart';
