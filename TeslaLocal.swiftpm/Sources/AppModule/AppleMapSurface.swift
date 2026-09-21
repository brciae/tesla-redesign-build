import SwiftUI
import MapKit

/// Native Apple Maps 3D surface tailored for Tesla OLED dark cockpit.
/// Requires zero external developer keys, tracks vehicle GPS and heading in real time,
/// and marks the active destination received from vehicle telemetry.
struct AppleMapSurface: View {
    var destinationCoordinate: CLLocationCoordinate2D?
    var destinationName: String?
    @State private var isTracking = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MapKitContainer(destinationCoordinate: destinationCoordinate, destinationName: destinationName, isTracking: $isTracking)
                .edgesIgnoringSafeArea(.all)

            if !isTracking {
                Button {
                    isTracking = true
                } label: {
                    Label("현위치", systemImage: "location.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
                .padding(16)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
    }
}

private struct MapKitContainer: UIViewRepresentable {
    var destinationCoordinate: CLLocationCoordinate2D?
    var destinationName: String?
    @Binding var isTracking: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.overrideUserInterfaceStyle = .dark
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .followWithHeading
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.showsCompass = true
        mapView.pointOfInterestFilter = .excludingAll
        mapView.mapType = .standard

        // Set initial camera pitch to 55 degrees for authentic 3D driving view
        let camera = mapView.camera
        camera.pitch = 55.0
        mapView.setCamera(camera, animated: false)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        if isTracking && mapView.userTrackingMode != .followWithHeading {
            mapView.setUserTrackingMode(.followWithHeading, animated: true)
        }

        // Manage destination annotation
        let nonUserAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        if let dest = destinationCoordinate, CLLocationCoordinate2DIsValid(dest) {
            if let existing = nonUserAnnotations.first as? MKPointAnnotation {
                if existing.coordinate.latitude != dest.latitude || existing.coordinate.longitude != dest.longitude {
                    existing.coordinate = dest
                    existing.title = destinationName ?? "목적지"
                }
            } else {
                mapView.removeAnnotations(nonUserAnnotations)
                let pin = MKPointAnnotation()
                pin.coordinate = dest
                pin.title = destinationName ?? "목적지"
                mapView.addAnnotation(pin)
            }
        } else if !nonUserAnnotations.isEmpty {
            mapView.removeAnnotations(nonUserAnnotations)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapKitContainer

        init(_ parent: MapKitContainer) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            DispatchQueue.main.async {
                self.parent.isTracking = (mode == .followWithHeading || mode == .follow)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let id = "DestinationPin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.markerTintColor = UIColor(red: 0.89, green: 0.12, blue: 0.14, alpha: 1.0) // Tesla Red
            view.glyphImage = UIImage(systemName: "flag.fill")
            view.canShowCallout = true
            return view
        }
    }
}
