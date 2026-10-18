#if os(macOS)
import AppKit
#else
import Foundation
#endif

@main
enum FreewheelApplication {
    @MainActor
    static func main() {
        #if os(macOS)
        let application = NSApplication.shared
        let controller = AppController()
        application.delegate = controller

        withExtendedLifetime(controller) {
            application.run()
        }
        #else
        print("Lemulip's desktop interface requires macOS 13 or later. Use the lemulip CLI for portable operations.")
        #endif
    }
}
