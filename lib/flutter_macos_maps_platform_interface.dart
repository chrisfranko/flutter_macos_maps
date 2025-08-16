import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_macos_maps_method_channel.dart';

abstract class FlutterMacosMapsPlatform extends PlatformInterface {
  /// Constructs a FlutterMacosMapsPlatform.
  FlutterMacosMapsPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterMacosMapsPlatform _instance = MethodChannelFlutterMacosMaps();

  /// The default instance of [FlutterMacosMapsPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterMacosMaps].
  static FlutterMacosMapsPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterMacosMapsPlatform] when
  /// they register themselves.
  static set instance(FlutterMacosMapsPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
