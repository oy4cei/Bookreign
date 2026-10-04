import AVFoundation
import SwiftUI
import UIKit

/// A live camera view that reports EAN-13 and Code 128 values to its parent.
/// The parent decides whether a value is an ISBN and whether to add it to a batch.
struct BarcodeScannerView: View {
    let onCode: (String) -> Void

    init(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
    }

    var body: some View {
        ScannerCameraView(onCode: onCode, localeIdentifier: L10n.locale.identifier)
            .background(Color.black)
            .accessibilityLabel(L("Сканер штрихкодов"))
    }
}

private struct ScannerCameraView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let localeIdentifier: String

    func makeUIViewController(context: Context) -> ScannerViewController {
        ScannerViewController(onCode: onCode)
    }

    func updateUIViewController(_ controller: ScannerViewController, context: Context) {
        controller.onCode = onCode
        controller.refreshLocalizedText()
    }
}

private final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: (String) -> Void

    private let session = AVCaptureSession()
    private let output = AVCaptureMetadataOutput()
    private let sessionQueue = DispatchQueue(label: "books.scanner.capture")
    private let metadataQueue = DispatchQueue(label: "books.scanner.metadata")
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let statusLabel = UILabel()
    private let torchButton = UIButton(type: .system)
    private var viewVisible = false
    // Localized state is rendered only on the main queue, never on capture queues.
    private var statusMessage: LocalizedMessage?
    private var torchEnabled = false

    // These properties are accessed only on sessionQueue.
    private var shouldRun = false
    private var configured = false
    private var camera: AVCaptureDevice?

    // These properties are accessed only on metadataQueue.
    private var lastSeenAt: [String: Date] = [:]
    private var lastEmittedAt: [String: Date] = [:]

    init(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        statusLabel.textColor = .white
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.layer.cornerRadius = 12
        statusLabel.layer.masksToBounds = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        torchButton.setTitle(L("Включить фонарик"), for: .normal)
        torchButton.tintColor = .white
        torchButton.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        torchButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        torchButton.layer.cornerRadius = 12
        torchButton.translatesAutoresizingMaskIntoConstraints = false
        torchButton.isHidden = true
        torchButton.addTarget(self, action: #selector(toggleTorch), for: .touchUpInside)
        view.addSubview(torchButton)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
            torchButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            torchButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            torchButton.heightAnchor.constraint(equalToConstant: 44),
            torchButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 176)
        ])

        showStatus("Подготовка камеры…")
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: .AVCaptureSessionRuntimeError, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: .AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: session)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewVisible = true
        startIfPermitted()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewVisible = false
        stop()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func refreshLocalizedText() {
        statusLabel.text = statusMessage.map { "  \(L($0))  " }
        statusLabel.isHidden = statusMessage == nil
        torchButton.setTitle(torchEnabled ? L("Выключить фонарик") : L("Включить фонарик"), for: .normal)
    }

    private func showStatus(_ message: LocalizedMessage?) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = message
            self?.refreshLocalizedText()
        }
    }

    private func startIfPermitted() {
        guard UIApplication.shared.applicationState == .active else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.shouldRun = true
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                self.configureAndStart()
            case .notDetermined:
                self.showStatus("Разрешите доступ к камере для сканирования книг.")
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    self?.sessionQueue.async { [weak self] in
                        guard let self, self.shouldRun else { return }
                        if granted {
                            self.configureAndStart()
                        } else {
                            self.showStatus("Доступ к камере запрещён. Разрешите его в настройках iPhone.")
                        }
                    }
                }
            case .denied, .restricted:
                self.showStatus("Доступ к камере недоступен. Проверьте разрешение в настройках iPhone.")
            @unknown default:
                self.showStatus("Не удалось получить доступ к камере.")
            }
        }
    }

    private func configureAndStart() {
        guard shouldRun else { return }
        if !configured {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(for: .video) else {
                showStatus("Камера недоступна. В симуляторе используйте ввод ISBN вручную.")
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                session.beginConfiguration()
                session.sessionPreset = .high
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration()
                    showStatus("Не удалось настроить сканер камеры.")
                    return
                }
                session.addInput(input)
                session.addOutput(output)
                let types: [AVMetadataObject.ObjectType] = [.ean13, .code128].filter {
                    output.availableMetadataObjectTypes.contains($0)
                }
                guard !types.isEmpty else {
                    session.commitConfiguration()
                    showStatus("Эта камера не поддерживает сканирование штрихкодов.")
                    return
                }
                output.metadataObjectTypes = types
                output.setMetadataObjectsDelegate(self, queue: metadataQueue)
                session.commitConfiguration()
                camera = device
                configured = true
                DispatchQueue.main.async { [weak self] in
                    self?.torchButton.isHidden = !device.hasTorch
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.showStatus("Не удалось запустить камеру: \(L10n.error(error))")
                }
                return
            }
        }

        guard !session.isRunning else {
            showStatus(nil)
            return
        }
        session.startRunning()
        showStatus(session.isRunning ? nil : "Камера не запустилась. Попробуйте открыть сканер ещё раз.")
    }

    private func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.shouldRun = false
            if self.session.isRunning { self.session.stopRunning() }
            self.setTorch(false)
        }
    }

    @objc private func applicationDidEnterBackground() { stop() }

    @objc private func applicationDidBecomeActive() {
        guard viewIfLoaded?.window != nil else { return }
        startIfPermitted()
    }

    @objc private func sessionRuntimeError() {
        showStatus("Ошибка камеры. Попробуйте открыть сканер ещё раз.")
    }

    @objc private func sessionWasInterrupted() {
        showStatus("Камера временно недоступна.")
    }

    @objc private func sessionInterruptionEnded() {
        sessionQueue.async { [weak self] in self?.configureAndStart() }
    }

    @objc private func toggleTorch() {
        sessionQueue.async { [weak self] in
            guard let self, let camera = self.camera, camera.hasTorch else { return }
            self.setTorch(camera.torchMode != .on)
        }
    }

    private func setTorch(_ enabled: Bool) {
        guard let camera, camera.hasTorch else { return }
        do {
            try camera.lockForConfiguration()
            camera.torchMode = enabled ? .on : .off
            camera.unlockForConfiguration()
            DispatchQueue.main.async { [weak self] in
                self?.torchEnabled = enabled
                self?.refreshLocalizedText()
            }
        } catch {
            showStatus("Не удалось переключить фонарик.")
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        let now = Date()
        let codes = Set(metadataObjects.compactMap { object -> String? in
            guard let barcode = object as? AVMetadataMachineReadableCodeObject,
                  barcode.type == .ean13 || barcode.type == .code128 else { return nil }
            return barcode.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })

        for code in codes {
            let lastSeen = lastSeenAt[code]
            let lastEmitted = lastEmittedAt[code]
            let leftFrame = lastSeen.map { now.timeIntervalSince($0) > 1 } ?? true
            let cooledDown = lastEmitted.map { now.timeIntervalSince($0) >= 4 } ?? true
            if leftFrame || cooledDown {
                lastEmittedAt[code] = now
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.viewVisible else { return }
                    self.onCode(code)
                }
            }
            lastSeenAt[code] = now
        }

        // Keep the debounce maps small on long batch-scanning sessions.
        lastSeenAt = lastSeenAt.filter { now.timeIntervalSince($0.value) < 30 }
        lastEmittedAt = lastEmittedAt.filter { now.timeIntervalSince($0.value) < 30 }
    }
}
