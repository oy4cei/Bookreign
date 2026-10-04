import AVFoundation
import SwiftUI
import UIKit

/// Captures one cover photo and returns an upright JPEG for local OCR.
struct BookCameraPicker: UIViewControllerRepresentable {
    @Environment(\.locale) private var locale
    let onImage: (Data) -> Void
    let onCancel: () -> Void

    init(onImage: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
        self.onImage = onImage
        self.onCancel = onCancel
    }

    func makeUIViewController(context: Context) -> BookCameraController {
        BookCameraController(onImage: onImage, onCancel: onCancel)
    }

    func updateUIViewController(_ controller: BookCameraController, context: Context) {
        controller.onImage = onImage
        controller.onCancel = onCancel
        controller.refreshLocalizedText()
    }
}

final class BookCameraController: UIViewController, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    var onImage: (Data) -> Void
    var onCancel: () -> Void

    private let statusLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private var statusMessage: LocalizedMessage = "Подготовка камеры…"
    private var requestedPermission = false
    private var presentedCamera = false
    private var deliveredResult = false

    init(onImage: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
        self.onImage = onImage
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        refreshLocalizedText()
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .body)
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [statusLabel, closeButton])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !presentedCamera, !deliveredResult else { return }
        checkCameraAccess()
    }

    func refreshLocalizedText() {
        statusLabel.text = L(statusMessage)
        closeButton.setTitle(L("Закрыть"), for: .normal)
    }

    private func showStatus(_ message: LocalizedMessage) {
        statusMessage = message
        refreshLocalizedText()
    }

    private func checkCameraAccess() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showStatus("Камера недоступна. Выберите фото обложки из медиатеки.")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera()
        case .notDetermined:
            guard !requestedPermission else { return }
            requestedPermission = true
            showStatus("Разрешите доступ к камере для фото обложки.")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.view.window != nil else { return }
                    if granted {
                        self.showCamera()
                    } else {
                        self.showStatus("Доступ к камере запрещён. Разрешите его в настройках iPhone или выберите фото из медиатеки.")
                    }
                }
            }
        case .denied:
            showStatus("Доступ к камере запрещён. Разрешите его в настройках iPhone или выберите фото из медиатеки.")
        case .restricted:
            showStatus("Доступ к камере ограничен. Выберите фото обложки из медиатеки.")
        @unknown default:
            showStatus("Не удалось получить доступ к камере. Выберите фото обложки из медиатеки.")
        }
    }

    private func showCamera() {
        guard !presentedCamera, view.window != nil else { return }
        presentedCamera = true
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        picker.delegate = self
        picker.modalPresentationStyle = .fullScreen
        present(picker, animated: true)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        guard !deliveredResult else { return }
        deliveredResult = true
        picker.dismiss(animated: false) { [weak self] in self?.onCancel() }
    }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard !deliveredResult else { return }
        deliveredResult = true
        let data = (info[.originalImage] as? UIImage).flatMap(Self.compactJPEG)
        picker.dismiss(animated: false) { [weak self] in
            guard let self else { return }
            if let data { self.onImage(data) } else { self.onCancel() }
        }
    }

    @objc private func close() {
        guard !deliveredResult else { return }
        deliveredResult = true
        onCancel()
    }

    private static func compactJPEG(from image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1600
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > 0 else { return nil }
        let scale = min(1, maxDimension / longestSide)
        let size = CGSize(width: max(1, image.size.width * scale),
                          height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // Requested dimensions are output pixels, regardless of screen scale.
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let upright = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return upright.jpegData(compressionQuality: 0.82)
    }
}
