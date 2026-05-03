import Foundation
@testable import PrusaStatusBar
import Testing
import UserNotifications

/// Spec coverage:
/// - `notifications` Requirement: Stub double records deliveries so other
///   tests can verify the polling loop talks to the notification service
///   without touching the real `UNUserNotificationCenter`.
struct StubNotificationServiceTests {
    @Test
    func grantsAuthorizationByDefault() async {
        let service = StubNotificationService()
        let granted = await service.requestAuthorization()
        #expect(granted)
    }

    @Test
    func deniesAuthorizationWhenConfigured() async {
        let service = StubNotificationService()
        service.grantAuthorization = false
        let granted = await service.requestAuthorization()
        #expect(!granted)
    }

    @Test
    func authorizationStatusReflectsGrantFlag() async {
        let service = StubNotificationService()
        let granted = await service.authorizationStatus()
        #expect(granted == .authorized)

        service.grantAuthorization = false
        let denied = await service.authorizationStatus()
        #expect(denied == .denied)
    }

    @Test
    func deliverRecordsAllFields() async {
        let service = StubNotificationService()
        let imageURL = URL(fileURLWithPath: "/tmp/test.jpg")
        await service.deliver(title: "T", body: "B", identifier: "id-1", imageURL: imageURL)

        #expect(service.delivered.count == 1)
        #expect(service.delivered.first == StubNotificationService.DeliveredNotification(
            title: "T",
            body: "B",
            identifier: "id-1",
            imageURL: imageURL
        ))
    }

    @Test
    func defaultDeliverOverloadOmitsImageURL() async {
        let service = StubNotificationService()
        await service.deliver(title: "T", body: "B", identifier: "id-2")

        #expect(service.delivered.count == 1)
        #expect(service.delivered.first?.imageURL == nil)
    }

    @Test
    func multipleDeliveriesPreserveOrder() async {
        let service = StubNotificationService()
        await service.deliver(title: "first", body: "b", identifier: "1", imageURL: nil)
        await service.deliver(title: "second", body: "b", identifier: "2", imageURL: nil)
        await service.deliver(title: "third", body: "b", identifier: "3", imageURL: nil)

        #expect(service.delivered.map(\.title) == ["first", "second", "third"])
    }
}
