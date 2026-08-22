import XCTest
@testable import Marker

/// The app-hosted bundle is for assertions that need the built app: its Info.plist,
/// its registered document types, its embedded extension. Pure logic and source
/// scanning live in the package tests, which run without a host in milliseconds.
nonisolated final class AppBundleTests: XCTestCase {

    private var info: [String: Any] {
        Bundle.main.infoDictionary ?? [:]
    }

    func testDeclaresEveryMarkdownExtensionTheFAQPromises() throws {
        let imported = try XCTUnwrap(info["UTImportedTypeDeclarations"] as? [[String: Any]])
        let markdown = try XCTUnwrap(imported.first {
            $0["UTTypeIdentifier"] as? String == "net.daringfireball.markdown"
        })
        let tags = try XCTUnwrap(markdown["UTTypeTagSpecification"] as? [String: Any])
        let extensions = try XCTUnwrap(tags["public.filename-extension"] as? [String])
        XCTAssertEqual(Set(extensions), ["md", "markdown", "mdown", "mkd", "mkdn"])
    }

    func testOpensPlainTextJSONAndYAMLAsWell() throws {
        let types = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])
        let contentTypes = Set(types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
        XCTAssertTrue(contentTypes.isSuperset(of: [
            "net.daringfireball.markdown", "public.plain-text", "public.json", "public.yaml",
        ]))
    }

    func testEveryDocumentTypeResolvesToTheDocumentClass() throws {
        let types = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])
        for type in types {
            let name = type["NSDocumentClass"] as? String
            XCTAssertEqual(name, "Marker.MarkerDocument", "document class did not resolve")
            XCTAssertNotNil(NSClassFromString(try XCTUnwrap(name)), "document class not in the binary")
        }
    }

    func testQuickLookExtensionIsEmbeddedAndPreviewsTheSameTypes() throws {
        let appex = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
            .appendingPathComponent("MarkerQuickLook.appex")
        XCTAssertTrue(FileManager.default.fileExists(atPath: appex.path),
                      "the Quick Look extension is not embedded in the app")

        let plist = appex.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: plist)
        let info = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let extensionInfo = try XCTUnwrap(info["NSExtension"] as? [String: Any])
        XCTAssertEqual(extensionInfo["NSExtensionPointIdentifier"] as? String,
                       "com.apple.quicklook.preview")
        let attributes = try XCTUnwrap(extensionInfo["NSExtensionAttributes"] as? [String: Any])
        let supported = Set(try XCTUnwrap(attributes["QLSupportedContentTypes"] as? [String]))
        XCTAssertTrue(supported.contains("net.daringfireball.markdown"))
    }
}
