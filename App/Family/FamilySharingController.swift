import SwiftUI
import CloudKit

struct FamilySharingController: UIViewControllerRepresentable {
    let share: CKShare
    let family: FamilySharingCoordinator
    func makeCoordinator() -> Coordinator { Coordinator(family, share: share) }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: family.transport.container)
        controller.modalPresentationStyle = .formSheet
        controller.availablePermissions = [.allowPrivate, .allowReadOnly, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let family: FamilySharingCoordinator
        let context: FamilyShareCallbackContext?
        init(_ family: FamilySharingCoordinator, share: CKShare) {
            self.family = family
            context = family.callbackContext(for: share)
        }
        func itemTitle(for controller: UICloudSharingController) -> String? { "Bookreign" }
        func cloudSharingController(_ controller: UICloudSharingController, failedToSaveShareWithError error: Error) {
            Task { await family.sharingFailed(context, shareID: controller.share?.recordID, error: error) }
        }
        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {
            Task { await family.sharingSaved(context, shareID: controller.share?.recordID) }
        }
        func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {
            Task { await family.sharingStopped(context, shareID: controller.share?.recordID) }
        }
    }
}
