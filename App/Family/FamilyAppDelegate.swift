import UIKit
import CloudKit
import Combine
import SwiftUI

@MainActor final class FamilyEvents: ObservableObject {
    static let shared = FamilyEvents()
    @Published var metadata: CKShare.Metadata?
    weak var coordinator: FamilySharingCoordinator?
}

final class FamilyAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = FamilySceneDelegate.self
        return configuration
    }
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        FamilyEvents.shared.metadata = metadata
    }
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo)?.containerIdentifier == CloudKitFamilyTransport.containerIdentifier else {
            completionHandler(.noData); return
        }
        Task { @MainActor in
            guard let family = FamilyEvents.shared.coordinator else { completionHandler(.noData); return }
            await family.synchronize()
            completionHandler(family.issue == nil ? .newData : .failed)
        }
    }
}

final class FamilySceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let metadata = options.cloudKitShareMetadata { FamilyEvents.shared.metadata = metadata }
    }
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        FamilyEvents.shared.metadata = metadata
    }
}

struct FamilyPresentation: ViewModifier {
    @EnvironmentObject var store: LibraryStore
    @ObservedObject var family: FamilySharingCoordinator
    @ObservedObject private var events = FamilyEvents.shared
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content
            .onAppear {
                events.coordinator = family
                if let metadata = events.metadata { family.receive(metadata); events.metadata = nil }
                family.scheduleSync(immediately: true)
            }
            .onReceive(events.$metadata) { metadata in
                if let metadata { family.receive(metadata); events.metadata = nil }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { family.scheduleSync(immediately: true) }
            }
            .sheet(isPresented: Binding(get: { family.invitation != nil }, set: { if !$0 && !family.busy { family.invitation = nil } })) {
                FamilyJoinView(family: family).environmentObject(store)
            }
    }
}
