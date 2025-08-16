import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// ---------- Small value types ----------
class LatLng {
  final double lat, lon;
  const LatLng(this.lat, this.lon);

  Map<String, double> toMap() => {'lat': lat, 'lon': lon};
  static LatLng fromMap(Map m) => LatLng((m['lat'] as num).toDouble(), (m['lon'] as num).toDouble());
}

class CameraPosition {
  final LatLng target;
  final double? altitude; // meters
  final double? pitch;    // degrees
  final double? heading;  // degrees
  final double? latDelta; // for region-style zoom
  final double? lonDelta;
  const CameraPosition({
    required this.target,
    this.altitude,
    this.pitch,
    this.heading,
    this.latDelta,
    this.lonDelta,
  });

  Map<String, dynamic> toMap() => {
        'target': target.toMap(),
        if (altitude != null) 'altitude': altitude,
        if (pitch != null) 'pitch': pitch,
        if (heading != null) 'heading': heading,
        if (latDelta != null) 'latDelta': latDelta,
        if (lonDelta != null) 'lonDelta': lonDelta,
      };
}

enum MapType { standard, satellite, hybrid }
int _mapTypeToInt(MapType t) => {
      MapType.standard: 0,
      MapType.satellite: 1,
      MapType.hybrid: 2,
    }[t]!;

// ---------- Events ----------
class _MapEvent {
  final String type;
  final Map data;
  _MapEvent(this.type, this.data);

  static _MapEvent from(dynamic e) {
    final m = (e as Map).cast<String, dynamic>();
    return _MapEvent(m['event'] as String, (m['data'] as Map).cast<String, dynamic>());
  }
}

class RegionChanged {
  final CameraPosition camera;
  final bool animated;
  RegionChanged(this.camera, this.animated);
}

typedef OverlayId = String;
typedef AnnotationId = String;

// ---------- Controller ----------
class FlutterMacosMapsController {
  FlutterMacosMapsController._(this._id)
      : _method = MethodChannel('flutter_macos_maps/map_$_id'),
        _events = EventChannel('flutter_macos_maps/events_$_id') {
    _eventStream = _events.receiveBroadcastStream().map(_MapEvent.from).asBroadcastStream();
  }

  final int _id;
  final MethodChannel _method;
  final EventChannel _events;
  late final Stream<_MapEvent> _eventStream;

  // General event streams (filtering by 'event' field)
  Stream<LatLng> get onTap => _eventStream.where((e) => e.type == 'tap').map((e) => LatLng.fromMap(e.data));
  Stream<LatLng> get onLongPress =>
      _eventStream.where((e) => e.type == 'longPress').map((e) => LatLng.fromMap(e.data));
  Stream<AnnotationId> get onAnnotationTap =>
      _eventStream.where((e) => e.type == 'annotationTap').map((e) => e.data['id'] as String);
  Stream<RegionChanged> get onRegionChanged => _eventStream.where((e) => e.type == 'regionChanged').map((e) {
        final cam = e.data['camera'] as Map;
        return RegionChanged(
          CameraPosition(
            target: LatLng.fromMap((cam['target'] as Map).cast()),
            altitude: (cam['altitude'] as num?)?.toDouble(),
            pitch: (cam['pitch'] as num?)?.toDouble(),
            heading: (cam['heading'] as num?)?.toDouble(),
            latDelta: (cam['latDelta'] as num?)?.toDouble(),
            lonDelta: (cam['lonDelta'] as num?)?.toDouble(),
          ),
          (e.data['animated'] as bool?) ?? false,
        );
      });

  // Camera controls
  Future<void> setCamera(CameraPosition camera, {bool animated = true}) =>
      _method.invokeMethod('setCamera', {'camera': camera.toMap(), 'animated': animated});

  Future<void> fitBounds({
    required LatLng northEast,
    required LatLng southWest,
    double padding = 24.0,
    bool animated = true,
  }) =>
      _method.invokeMethod('fitBounds', {
        'ne': northEast.toMap(),
        'sw': southWest.toMap(),
        'padding': padding,
        'animated': animated,
      });

  Future<void> setMapType(MapType type) => _method.invokeMethod('setMapType', {'type': _mapTypeToInt(type)});

  // Annotations
  Future<AnnotationId> addAnnotation({
    required LatLng position,
    String? title,
    String? subtitle,
    String? id, // optional custom id; otherwise native returns a UUID
  }) async {
    final res = await _method.invokeMethod<String>('addAnnotation', {
      'pos': position.toMap(),
      if (title != null) 'title': title,
      if (subtitle != null) 'subtitle': subtitle,
      if (id != null) 'id': id,
    });
    return res!;
  }

  Future<void> removeAnnotation(AnnotationId id) =>
      _method.invokeMethod('removeAnnotation', {'id': id});

  // Overlays
  Future<OverlayId> addPolyline({
    required List<LatLng> points,
    int color = 0xFF1E88E5, // ARGB
    double width = 3.0,
    String? id,
  }) async {
    final res = await _method.invokeMethod<String>('addPolyline', {
      'points': points.map((p) => p.toMap()).toList(),
      'color': color,
      'width': width,
      if (id != null) 'id': id,
    });
    return res!;
  }

  Future<OverlayId> addPolygon({
    required List<LatLng> points,
    int strokeColor = 0xFF1E88E5,
    int fillColor = 0x331E88E5, // 20% alpha fill
    double width = 2.0,
    String? id,
  }) async {
    final res = await _method.invokeMethod<String>('addPolygon', {
      'points': points.map((p) => p.toMap()).toList(),
      'strokeColor': strokeColor,
      'fillColor': fillColor,
      'width': width,
      if (id != null) 'id': id,
    });
    return res!;
  }

  Future<OverlayId> addCircle({
    required LatLng center,
    required double radius, // meters
    int strokeColor = 0xFF43A047,
    int fillColor = 0x3343A047,
    double width = 2.0,
    String? id,
  }) async {
    final res = await _method.invokeMethod<String>('addCircle', {
      'center': center.toMap(),
      'radius': radius,
      'strokeColor': strokeColor,
      'fillColor': fillColor,
      'width': width,
      if (id != null) 'id': id,
    });
    return res!;
  }

  Future<void> removeOverlay(OverlayId id) => _method.invokeMethod('removeOverlay', {'id': id});
  Future<void> clearOverlays() => _method.invokeMethod('clearOverlays');
}

class FlutterMacosMapsView extends StatefulWidget {
  const FlutterMacosMapsView({super.key, this.onCreated, this.initialCamera});
  final void Function(FlutterMacosMapsController controller)? onCreated;
  final CameraPosition? initialCamera;

  @override
  State<FlutterMacosMapsView> createState() => _FlutterMacosMapsViewState();
}

class _FlutterMacosMapsViewState extends State<FlutterMacosMapsView> {
  @override
  Widget build(BuildContext context) {
    return AppKitView(
      viewType: 'com.yourorg.flutter_macos_maps/map',
      creationParams: {
        if (widget.initialCamera != null) 'camera': widget.initialCamera!.toMap(),
      },
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (id) {
        widget.onCreated?.call(FlutterMacosMapsController._(id));
      },
    );
  }
}