import AVFoundation
import SwiftUI
import UIKit

/// Полноэкранный сканер QR: камера на весь экран, подсказка, «Закрыть». Первый распознанный код закрывает
/// сканер и отдаёт текст наружу — дальше он обрабатывается как вставленный. Без разрешения или без камеры —
/// объяснение и выход к вставке текста. В Debug аргумент `-contacts-scan` подменяет камеру готовой строкой.
struct QRScannerView: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()
    @State private var delivered = false

    var body: some View {
        ZStack {
            switch camera.state {
            case .checking:
                Color.black.ignoresSafeArea()
            case .running:
                cameraScreen
            case .noAccess:
                unavailableScreen(
                    title: "Нет доступа к камере",
                    text: "Разрешите доступ в Настройках или вставьте ключ текстом.", showSettings: true)
            case .noCamera:
                unavailableScreen(
                    title: "Камера недоступна",
                    text: "На этом устройстве нет камеры. Вставьте ключ текстом.", showSettings: false)
            }
        }
        .accessibilityIdentifier("scanner.view")
        .task {
            if let payload = LaunchStorage.scannerOverride {
                deliver(payload)
                return
            }
            await camera.start { payload in deliver(payload) }
        }
        .onDisappear { camera.stop() }
    }

    private func deliver(_ payload: String) {
        guard !delivered else { return }
        delivered = true
        camera.stop()
        onScan(payload)
        dismiss()
    }

    private var cameraScreen: some View {
        ZStack(alignment: .top) {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .mask {
                    Rectangle()
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .frame(width: 240, height: 240)
                                .blendMode(.destinationOut)
                        )
                        .compositingGroup()
                        .ignoresSafeArea()
                }
                .allowsHitTesting(false)
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 3)
                .frame(width: 240, height: 240)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            VStack {
                HStack {
                    Spacer()
                    closeButton
                        .foregroundStyle(.white)
                }
                Spacer()
                Text("Наведите на QR-код с экрана «Мой ключ» собеседника")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 36)
                    .accessibilityIdentifier("scanner.hint")
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    private func unavailableScreen(title: String, text: String, showSettings: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                closeButton
            }
            .padding(.horizontal, 20)
            .frame(height: 44)
            Spacer()
            Image(systemName: "camera")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.weight(.semibold))
                .padding(.top, 14)
                .accessibilityIdentifier("scanner.noAccess")
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .accessibilityIdentifier("scanner.noAccessText")
            if showSettings {
                Button("Открыть Настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                .accessibilityIdentifier("scanner.openSettings")
                .padding(.top, 12)
            }
            Button("Вставить ключ текстом") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
                .fixedSize()
                .accessibilityIdentifier("scanner.pasteInstead")
                .padding(.top, 12)
            Spacer()
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var closeButton: some View {
        Button("Закрыть") { dismiss() }
            .font(.body)
            .frame(minHeight: 44)
            .accessibilityIdentifier("scanner.close")
    }
}

/// Сессия камеры и распознавание QR. Запуск — вне главного потока; результат — на главном.
@MainActor
@Observable
final class CameraController {
    enum State {
        case checking
        case running
        case noAccess
        case noCamera
    }

    private(set) var state: State = .checking
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.cipherkeyboard.scanner")
    private var delegate: MetadataDelegate?

    func start(onCode: @escaping @MainActor (String) -> Void) async {
        var status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            status = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
        }
        guard status == .authorized else {
            state = .noAccess
            return
        }
        guard let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            state = .noCamera
            return
        }
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            state = .noCamera
            return
        }
        session.beginConfiguration()
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        guard output.availableMetadataObjectTypes.contains(.qr) else {
            state = .noCamera
            return
        }
        let delegate = MetadataDelegate(onCode: onCode)
        self.delegate = delegate
        output.setMetadataObjectsDelegate(delegate, queue: queue)
        output.metadataObjectTypes = [.qr]
        state = .running
        let session = session
        queue.async { session.startRunning() }
    }

    func stop() {
        guard session.isRunning else { return }
        let session = session
        queue.async { session.stopRunning() }
    }
}

/// Делегат вывода метаданных: первый QR-код передаётся на главный поток, остальные игнорируются.
private final class MetadataDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate, Sendable {
    private let onCode: @MainActor (String) -> Void

    init(onCode: @escaping @MainActor (String) -> Void) {
        self.onCode = onCode
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            let code =
                metadataObjects
                .compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
                .first(where: { $0.type == .qr })?.stringValue
        else { return }
        let onCode = onCode
        Task { @MainActor in onCode(code) }
    }
}

/// Слой предпросмотра камеры на весь экран.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // `layerClass` гарантирует класс слоя; при другом классе предпросмотра просто не будет.
            (layer as? AVCaptureVideoPreviewLayer) ?? AVCaptureVideoPreviewLayer()
        }
    }
}
