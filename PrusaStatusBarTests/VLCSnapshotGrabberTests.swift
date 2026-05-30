#if !PROTOTYPE_MODE
    import AppKit
    @testable import PrusaStatusBar
    import Testing

    /// Spec coverage:
    /// - `notifications` Requirement: Notification snapshot grabber owns its
    ///   off-screen window safely
    ///
    /// Regression guard for the crash where the snapshot grabber's transient
    /// off-screen window was released twice (AppKit `isReleasedWhenClosed`
    /// default of `true` plus the ARC-owned local), detonating on the
    /// main-thread autorelease pool drain. The window factory must hand back a
    /// window ARC alone owns, and closing it must not over-release.
    @MainActor
    struct VLCSnapshotGrabberTests {
        @Test func offscreenWindowIsNotReleasedOnClose() {
            let window = VLCSnapshotGrabber.makeOffscreenVideoWindow(contentView: NSView())
            #expect(window.isReleasedWhenClosed == false)
        }

        @Test func offscreenWindowAttachesContentView() {
            let view = NSView()
            let window = VLCSnapshotGrabber.makeOffscreenVideoWindow(contentView: view)
            #expect(window.contentView === view)
        }

        /// Exercises the same create -> orderFront -> close lifecycle the grabber
        /// runs in its `defer`. With the AppKit default this path over-releases;
        /// with the fix it completes cleanly (and trips NSZombie/ASan if the
        /// regression returns).
        @Test func closingOffscreenWindowDoesNotOverRelease() {
            let window = VLCSnapshotGrabber.makeOffscreenVideoWindow(contentView: NSView())
            window.orderFrontRegardless()
            window.orderOut(nil)
            window.close()
            // Reaching here without a crash is the assertion; ARC releases the
            // local on scope exit, which must be the one and only release.
            #expect(window.isReleasedWhenClosed == false)
        }

        @Test func snapshotSizeCapsLongestEdgeForLargeFrames() {
            let snap = VLCSnapshotGrabber.snapshotSize(for: CGSize(width: 3840, height: 2160))
            #expect(max(snap.width, snap.height) == 800)
            // Aspect ratio preserved (16:9 -> 800x450).
            #expect(snap.width == 800)
            #expect(snap.height == 450)
        }

        @Test func snapshotSizeDoesNotUpscaleSmallFrames() {
            let snap = VLCSnapshotGrabber.snapshotSize(for: CGSize(width: 640, height: 480))
            #expect(snap.width == 640)
            #expect(snap.height == 480)
        }

        @Test func snapshotSizeFallsBackToNativeWhenNoFrame() {
            let snap = VLCSnapshotGrabber.snapshotSize(for: .zero)
            #expect(snap.width == 0)
            #expect(snap.height == 0)
        }
    }
#endif
