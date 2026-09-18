//
//  ZoneMapView.swift
//  地图选点：长按地图任意位置即可设为 A 区域中心，并画出半径圈
//

import SwiftUI
import MapKit

struct ZoneMapView: UIViewRepresentable {

    @Binding var center: CLLocationCoordinate2D?
    var radius: Double
    /// 每 +1 就自动把地图移到当前位置
    var recenterTrigger: Int = 0
    var onLongPress: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        map.mapType = .standard
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
                                         span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)),
                      animated: false)

        let lp = UILongPressGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.handleLongPress(_:)))
        lp.minimumPressDuration = 0.5
        map.addGestureRecognizer(lp)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // 重新画 A 区域圈
        map.removeOverlays(map.overlays)
        let pins = map.annotations.filter { !($0 is MKUserLocation) }
        map.removeAnnotations(pins)

        if let center {
            let circle = MKCircle(center: center, radius: max(10, radius))
            map.addOverlay(circle)

            let pin = MKPointAnnotation()
            pin.coordinate = center
            pin.title = "A 区域"
            pin.subtitle = "半径 \(Int(radius)) 米"
            map.addAnnotation(pin)

            // 只在中心点变化时才移动镜头，避免用户手动拖动被反复拉回
            let last = context.coordinator.lastCenter
            let moved = last == nil
                || abs(last!.latitude - center.latitude) > 0.00001
                || abs(last!.longitude - center.longitude) > 0.00001
            if moved {
                context.coordinator.lastCenter = center
                let span = MKCoordinateSpan(latitudeDelta: max(0.002, radius / 40000),
                                            longitudeDelta: max(0.002, radius / 40000))
                map.setRegion(MKCoordinateRegion(center: center, span: span), animated: true)
            }
        }

        // 定位到当前位置
        if context.coordinator.lastRecenter != recenterTrigger {
            context.coordinator.lastRecenter = recenterTrigger
            if let loc = map.userLocation.location {
                map.setRegion(MKCoordinateRegion(center: loc.coordinate,
                                                 span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)),
                              animated: true)
            }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ZoneMapView
        var lastCenter: CLLocationCoordinate2D?
        var lastRecenter: Int = 0

        init(_ parent: ZoneMapView) {
            self.parent = parent
            super.init()
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: map)
            let coordinate = map.convert(point, toCoordinateFrom: map)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onLongPress(coordinate)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let circle = overlay as? MKCircle else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let r = MKCircleRenderer(circle: circle)
            r.fillColor = UIColor.systemBlue.withAlphaComponent(0.18)
            r.strokeColor = UIColor.systemBlue
            r.lineWidth = 2
            return r
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let id = "zonePin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKPinAnnotationView
                ?? MKPinAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.canShowCallout = true
            view.pinTintColor = .systemBlue
            return view
        }
    }
}
