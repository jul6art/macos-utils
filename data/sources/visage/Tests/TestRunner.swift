import Foundation
import Testing

/// The tests' entry point: without SwiftPM, Swift Testing runs from this executable (build.sh --tests).
@main
enum TestRunner {
    static func main() async {
        let status: CInt = await Testing.__swiftPMEntryPoint()
        exit(status)
    }
}
