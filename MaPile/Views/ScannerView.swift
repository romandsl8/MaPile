import SwiftUI
import VisionKit
import AVFoundation

/// Feuille de scan du code-barres ISBN (EAN-13) avec la caméra.
struct ScannerSheet: View {
    var onFound: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var permission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        NavigationStack {
            Group {
                if permission == .authorized && BarcodeScannerView.isAvailable {
                    BarcodeScannerView(onFound: onFound)
                        .ignoresSafeArea()
                        .overlay(alignment: .bottom) {
                            Text("Visez le code-barres au dos du livre")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .glassEffect()
                                .padding(.bottom, 40)
                        }
                } else if permission == .notDetermined {
                    ProgressView()
                } else {
                    ContentUnavailableView {
                        Label("Caméra indisponible", systemImage: "camera.badge.ellipsis")
                    } description: {
                        Text("Autorisez l'accès à la caméra dans Réglages › MaPile, ou tapez l'ISBN dans la recherche.")
                    } actions: {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("Ouvrir les Réglages", destination: url)
                                .buttonStyle(.glass)
                        }
                    }
                }
            }
            .navigationTitle("Scanner un livre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .task {
            if permission == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                permission = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
    }
}

struct BarcodeScannerView: UIViewControllerRepresentable {
    var onFound: (String) -> Void

    @MainActor static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if !controller.isScanning && !context.coordinator.found {
            try? controller.startScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        var found = false

        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !found else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let value = barcode.payloadStringValue,
                   value.count == 13,
                   value.hasPrefix("978") || value.hasPrefix("979") {
                    found = true
                    dataScanner.stopScanning()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onFound(value)
                    return
                }
            }
        }
    }
}
