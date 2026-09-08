import Testing

@testable import LaravelMobileKit
import LaravelMobileKitAuth
import LaravelMobileKitCore
import LaravelMobileKitLaravel
import LaravelMobileKitUploads

@Suite("Module visibility")
struct ModuleVisibilityTests {
    @Test("Every module is importable and reports the kit version")
    func modulesAreVisible() {
        #expect(LaravelMobileKitCore.version == LaravelMobileKit.version)
        #expect(LaravelMobileKitLaravel.version == LaravelMobileKit.version)
        #expect(LaravelMobileKitAuth.version == LaravelMobileKit.version)
        #expect(LaravelMobileKitUploads.version == LaravelMobileKit.version)
    }
}
