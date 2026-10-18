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
        print("Freewheel's desktop interface requires macOS 13 or later. Use the freewheel CLI for portable operations.")
        #endif
    }
}
