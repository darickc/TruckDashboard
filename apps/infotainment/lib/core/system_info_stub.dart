import 'system_info.dart';

/// The browser has no files of the head unit's to read.
SystemInfo platformSystemInfo() =>
    FixedSystemInfo(SystemFacts.unavailable('the browser preview has none'));
