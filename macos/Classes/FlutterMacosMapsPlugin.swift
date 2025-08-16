import Cocoa
import FlutterMacOS
import MapKit
import CoreLocation

public class FlutterMacosMapsPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let factory = MapKitViewFactory(messenger: registrar.messenger)
    registrar.register(factory, withId: "com.yourorg.flutter_macos_maps/map")
  }
}

final class MapKitViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    return MapKitView(viewId: viewId, args: args as? [String: Any], messenger: messenger)
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class MapKitView: NSView, CLLocationManagerDelegate, MKMapViewDelegate, FlutterStreamHandler {
  private let mapView = MKMapView()
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?

  private let locationManager = CLLocationManager()

  // Book-keeping for overlays/annotations
  private var overlaysById: [String: MKOverlay] = [:]
  private var stylesByOverlayId: [String: OverlayStyle] = [:]
  private var annotationsById: [String: MKPointAnnotation] = [:]

  struct OverlayStyle {
    let stroke: NSColor
    let fill: NSColor?
    let lineWidth: CGFloat
  }

  init(viewId: Int64, args: [String: Any]?, messenger: FlutterBinaryMessenger) {
    self.methodChannel = FlutterMethodChannel(
      name: "flutter_macos_maps/map_\(viewId)",
      binaryMessenger: messenger
    )
    self.eventChannel = FlutterEventChannel(
      name: "flutter_macos_maps/events_\(viewId)",
      binaryMessenger: messenger
    )
    super.init(frame: .zero)

    // Native view setup
    addSubview(mapView)
    mapView.delegate = self

    // Use Auto Layout (preferred over autoresizing masks)
    mapView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      mapView.leadingAnchor.constraint(equalTo: leadingAnchor),
      mapView.trailingAnchor.constraint(equalTo: trailingAnchor),
      mapView.topAnchor.constraint(equalTo: topAnchor),
      mapView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    methodChannel.setMethodCallHandler(handle)
    eventChannel.setStreamHandler(self)

    if let cam = args?["camera"] as? [String: Any] {
      applyInitialCamera(cam)
    }

    // Gestures: tap & long-press
    let tap = NSClickGestureRecognizer(target: self, action: #selector(onTap(_:)))
    addGestureRecognizer(tap)

    let press = NSPressGestureRecognizer(target: self, action: #selector(onLongPress(_:)))
    press.minimumPressDuration = 0.45
    addGestureRecognizer(press)

    locationManager.delegate = self
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  deinit {
    methodChannel.setMethodCallHandler(nil)
    eventChannel.setStreamHandler(nil)
  }

  // MARK: - MethodChannel handling

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setCamera":
      guard let m = call.arguments as? [String: Any],
            let cam = m["camera"] as? [String: Any] else {
        result(FlutterError(code:"bad_args", message:"setCamera", details:nil)); return
      }
      setCamera(cam, animated: (m["animated"] as? Bool) ?? true)
      result(nil)

    case "fitBounds":
      guard let m = call.arguments as? [String: Any],
            let ne = m["ne"] as? [String: Any],
            let sw = m["sw"] as? [String: Any] else {
        result(FlutterError(code:"bad_args", message:"fitBounds", details:nil)); return
      }
      let padding = CGFloat((m["padding"] as? NSNumber)?.doubleValue ?? 24.0)
      let animated = (m["animated"] as? Bool) ?? true
      fitBounds(northEast: ne, southWest: sw, padding: padding, animated: animated)
      result(nil)

    case "setMapType":
      guard let m = call.arguments as? [String: Any], let t = m["type"] as? Int else {
        result(FlutterError(code:"bad_args", message:"setMapType", details:nil)); return
      }
      mapView.mapType = {
        switch t {
        case 1: return .satellite
        case 2: return .hybrid
        default: return .standard
        }
      }()
      result(nil)

    // ----- Annotations -----
    case "addAnnotation":
      guard let a = call.arguments as? [String: Any],
            let pos = a["pos"] as? [String: Any] else {
        result(FlutterError(code:"bad_args", message:"addAnnotation", details:nil)); return
      }
      let id = (a["id"] as? String) ?? UUID().uuidString
      let lat = (pos["lat"] as! NSNumber).doubleValue
      let lon = (pos["lon"] as! NSNumber).doubleValue
      let ann = MKPointAnnotation()
      ann.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
      ann.title = a["title"] as? String
      ann.subtitle = a["subtitle"] as? String
      annotationsById[id] = ann
      mapView.addAnnotation(ann)
      result(id)

    case "removeAnnotation":
      guard let a = call.arguments as? [String: Any], let id = a["id"] as? String,
            let ann = annotationsById.removeValue(forKey: id) else {
        result(nil); return
      }
      mapView.removeAnnotation(ann)
      result(nil)

    // ----- Overlays -----
    case "addPolyline":
      guard let a = call.arguments as? [String: Any],
            let pts = a["points"] as? [[String: Any]] else {
        result(FlutterError(code:"bad_args", message:"addPolyline", details:nil)); return
      }
      let id = (a["id"] as? String) ?? UUID().uuidString
      let coords = pts.map {
        CLLocationCoordinate2D(
          latitude: ($0["lat"] as! NSNumber).doubleValue,
          longitude: ($0["lon"] as! NSNumber).doubleValue
        )
      }
      let poly = MKPolyline(coordinates: coords, count: coords.count)
      overlaysById[id] = poly
      stylesByOverlayId[id] = OverlayStyle(
        stroke: colorFromARGB(a["color"] as? NSNumber ?? 0xFF1E88E5),
        fill: nil,
        lineWidth: CGFloat((a["width"] as? NSNumber)?.doubleValue ?? 3.0)
      )
      mapView.addOverlay(poly)
      result(id)

    case "addPolygon":
      guard let a = call.arguments as? [String: Any],
            let pts = a["points"] as? [[String: Any]] else {
        result(FlutterError(code:"bad_args", message:"addPolygon", details:nil)); return
      }
      let id = (a["id"] as? String) ?? UUID().uuidString
      let coords = pts.map {
        CLLocationCoordinate2D(
          latitude: ($0["lat"] as! NSNumber).doubleValue,
          longitude: ($0["lon"] as! NSNumber).doubleValue
        )
      }
      let poly = MKPolygon(coordinates: coords, count: coords.count)
      overlaysById[id] = poly
      stylesByOverlayId[id] = OverlayStyle(
        stroke: colorFromARGB(a["strokeColor"] as? NSNumber ?? 0xFF1E88E5),
        fill: colorFromARGB(a["fillColor"] as? NSNumber ?? 0x331E88E5),
        lineWidth: CGFloat((a["width"] as? NSNumber)?.doubleValue ?? 2.0)
      )
      mapView.addOverlay(poly)
      result(id)

    case "addCircle":
      guard let a = call.arguments as? [String: Any],
            let c = a["center"] as? [String: Any] else {
        result(FlutterError(code:"bad_args", message:"addCircle", details:nil)); return
      }
      let id = (a["id"] as? String) ?? UUID().uuidString
      let lat = (c["lat"] as! NSNumber).doubleValue
      let lon = (c["lon"] as! NSNumber).doubleValue
      let radius = (a["radius"] as! NSNumber).doubleValue
      let circle = MKCircle(center: CLLocationCoordinate2D(latitude: lat, longitude: lon), radius: radius)
      overlaysById[id] = circle
      stylesByOverlayId[id] = OverlayStyle(
        stroke: colorFromARGB(a["strokeColor"] as? NSNumber ?? 0xFF43A047),
        fill: colorFromARGB(a["fillColor"] as? NSNumber ?? 0x3343A047),
        lineWidth: CGFloat((a["width"] as? NSNumber)?.doubleValue ?? 2.0)
      )
      mapView.addOverlay(circle)
      result(id)

    case "removeOverlay":
      guard let a = call.arguments as? [String: Any], let id = a["id"] as? String,
            let ov = overlaysById.removeValue(forKey: id) else {
        result(nil); return
      }
      stylesByOverlayId.removeValue(forKey: id)
      mapView.removeOverlay(ov)
      result(nil)

    case "clearOverlays":
      mapView.removeOverlays(mapView.overlays)
      overlaysById.removeAll()
      stylesByOverlayId.removeAll()
      result(nil)

    case "showsUserLocation":
      guard let a = call.arguments as? [String: Any], let v = a["value"] as? Bool else {
        result(nil); return
      }
      if v { locationManager.requestWhenInUseAuthorization() }
      mapView.showsUserLocation = v
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Camera helpers

  private func applyInitialCamera(_ cam: [String: Any]) {
    setCamera(cam, animated: false)
  }

  private func setCamera(_ cam: [String: Any], animated: Bool) {
    guard let t = cam["target"] as? [String: Any] else { return }
    let lat = (t["lat"] as! NSNumber).doubleValue
    let lon = (t["lon"] as! NSNumber).doubleValue

    if let altitudeNum = cam["altitude"] as? NSNumber {
      // Camera with altitude/pitch/heading
      let camera = MKMapCamera()
      camera.centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
      camera.altitude = altitudeNum.doubleValue
      if let h = (cam["heading"] as? NSNumber)?.doubleValue { camera.heading = h }
      if let p = (cam["pitch"] as? NSNumber)?.doubleValue { camera.pitch = p }
      mapView.setCamera(camera, animated: animated)
    } else if let latDeltaNum = cam["latDelta"] as? NSNumber,
              let lonDeltaNum = cam["lonDelta"] as? NSNumber {
      // Region-based
      let span = MKCoordinateSpan(latitudeDelta: latDeltaNum.doubleValue, longitudeDelta: lonDeltaNum.doubleValue)
      let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
        span: span
      )
      mapView.setRegion(region, animated: animated)
    } else {
      // Default small span
      let span = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
      let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
        span: span
      )
      mapView.setRegion(region, animated: animated)
    }
  }

  private func fitBounds(northEast ne: [String: Any], southWest sw: [String: Any], padding: CGFloat, animated: Bool) {
    let neCoord = CLLocationCoordinate2D(latitude: (ne["lat"] as! NSNumber).doubleValue,
                                         longitude: (ne["lon"] as! NSNumber).doubleValue)
    let swCoord = CLLocationCoordinate2D(latitude: (sw["lat"] as! NSNumber).doubleValue,
                                         longitude: (sw["lon"] as! NSNumber).doubleValue)

    let pt1 = MKMapPoint(neCoord)
    let pt2 = MKMapPoint(swCoord)
    let rect = MKMapRect(
      origin: MKMapPoint(x: min(pt1.x, pt2.x), y: min(pt1.y, pt2.y)),
      size: MKMapSize(width: abs(pt1.x - pt2.x), height: abs(pt1.y - pt2.y))
    )
    mapView.setVisibleMapRect(
      rect,
      edgePadding: NSEdgeInsets(top: padding, left: padding, bottom: padding, right: padding),
      animated: animated
    )
  }

  // MARK: - Events

  @objc private func onTap(_ g: NSClickGestureRecognizer) {
    guard g.state == .ended else { return }
    let p = g.location(in: mapView)
    let coord = mapView.convert(p, toCoordinateFrom: mapView)
    emit("tap", ["lat": coord.latitude, "lon": coord.longitude])
  }

  @objc private func onLongPress(_ g: NSPressGestureRecognizer) {
    if g.state == .ended {
      let p = g.location(in: mapView)
      let coord = mapView.convert(p, toCoordinateFrom: mapView)
      emit("longPress", ["lat": coord.latitude, "lon": coord.longitude])
    }
  }

  func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
    let center = mapView.region.center
    let span = mapView.region.span
    let cam = mapView.camera
    emit("regionChanged", [
      "camera": [
        "target": ["lat": center.latitude, "lon": center.longitude],
        "latDelta": span.latitudeDelta,
        "lonDelta": span.longitudeDelta,
        "altitude": cam.altitude,
        "pitch": cam.pitch,
        "heading": cam.heading,
      ],
      "animated": animated
    ])
  }

  func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
    if let ann = view.annotation as? MKPointAnnotation {
      if let (id, _) = annotationsById.first(where: { $0.value === ann }) {
        emit("annotationTap", ["id": id])
      }
    }
  }

  private func emit(_ event: String, _ data: [String: Any]) {
    eventSink?(["event": event, "data": data])
  }

  // MARK: - Overlay rendering

  func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
    // Lookup style for this overlay
    let style = stylesByOverlayId.first(where: { overlaysById[$0.key] === overlay })?.value

    if let polyline = overlay as? MKPolyline {
      let r = MKPolylineRenderer(polyline: polyline)
      if let s = style { r.strokeColor = s.stroke; r.lineWidth = s.lineWidth }
      return r
    } else if let polygon = overlay as? MKPolygon {
      let r = MKPolygonRenderer(polygon: polygon)
      if let s = style {
        r.strokeColor = s.stroke
        r.lineWidth = s.lineWidth
        if let f = s.fill { r.fillColor = f }
      }
      return r
    } else if let circle = overlay as? MKCircle {
      let r = MKCircleRenderer(circle: circle)
      if let s = style {
        r.strokeColor = s.stroke
        r.lineWidth = s.lineWidth
        if let f = s.fill { r.fillColor = f }
      }
      return r
    }
    return MKOverlayRenderer(overlay: overlay)
  }

  // MARK: - Stream handler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  // MARK: - Utils

  private func colorFromARGB(_ n: NSNumber) -> NSColor {
    let v = n.uint32Value
    let a = CGFloat((v >> 24) & 0xFF) / 255.0
    let r = CGFloat((v >> 16) & 0xFF) / 255.0
    let g = CGFloat((v >> 8) & 0xFF) / 255.0
    let b = CGFloat(v & 0xFF) / 255.0
    return NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
  }
}