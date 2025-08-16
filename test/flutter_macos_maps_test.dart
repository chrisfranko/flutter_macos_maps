import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_macos_maps/flutter_macos_maps.dart';
import 'package:flutter_macos_maps/flutter_macos_maps_platform_interface.dart';
import 'package:flutter_macos_maps/flutter_macos_maps_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterMacosMapsPlatform
    with MockPlatformInterfaceMixin
    implements FlutterMacosMapsPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterMacosMapsPlatform initialPlatform =
      FlutterMacosMapsPlatform.instance;

  test('$MethodChannelFlutterMacosMaps is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterMacosMaps>());
  });

  test('getPlatformVersion', () async {
    FlutterMacosMaps flutterMacosMapsPlugin = FlutterMacosMaps();
    MockFlutterMacosMapsPlatform fakePlatform = MockFlutterMacosMapsPlatform();
    FlutterMacosMapsPlatform.instance = fakePlatform;

    expect(await flutterMacosMapsPlugin.getPlatformVersion(), '42');
  });
}
