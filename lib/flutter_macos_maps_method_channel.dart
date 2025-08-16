import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_macos_maps_platform_interface.dart';

/// An implementation of [FlutterMacosMapsPlatform] that uses method channels.
class MethodChannelFlutterMacosMaps extends FlutterMacosMapsPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_macos_maps');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
