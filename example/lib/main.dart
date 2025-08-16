// example/lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_macos_maps/flutter_macos_maps.dart';

void main() => runApp(const MaterialApp(home: Demo()));

class Demo extends StatefulWidget {
  const Demo({super.key});
  @override
  State<Demo> createState() => _DemoState();
}

class _DemoState extends State<Demo> {
  FlutterMacosMapsController? ctrl;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('flutter_macos_maps demo')),
    body: Column(
      children: [
        Expanded(
          child: FlutterMacosMapsView(
            initialCamera: CameraPosition(
              target: const LatLng(37.3349, -122.0090),
              latDelta: 0.05,
              lonDelta: 0.05,
            ),
            onCreated: (c) {
              ctrl = c;
              // listen to events
              c.onTap.listen(
                (pos) => debugPrint('tap: ${pos.lat}, ${pos.lon}'),
              );
              c.onAnnotationTap.listen(
                (id) => debugPrint('annotation tapped: $id'),
              );
              c.onRegionChanged.listen(
                (e) => debugPrint('region changed: ${e.camera.target.lat}'),
              );
            },
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            ElevatedButton(
              onPressed: () => ctrl?.setMapType(MapType.hybrid),
              child: const Text('Hybrid'),
            ),
            ElevatedButton(
              onPressed: () => ctrl?.addAnnotation(
                position: const LatLng(37.3349, -122.0090),
                title: 'Apple Park',
              ),
              child: const Text('Add Pin'),
            ),
            ElevatedButton(
              onPressed: () async {
                await ctrl?.addPolyline(
                  points: const [
                    LatLng(37.3349, -122.0090),
                    LatLng(37.3318, -122.0300),
                    LatLng(37.3269, -122.0325),
                  ],
                  color: 0xFFEF6C00,
                  width: 4,
                );
              },
              child: const Text('Polyline'),
            ),
            ElevatedButton(
              onPressed: () => ctrl?.fitBounds(
                northEast: const LatLng(37.36, -121.98),
                southWest: const LatLng(37.30, -122.06),
                padding: 32,
              ),
              child: const Text('Fit Bounds'),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    ),
  );
}
