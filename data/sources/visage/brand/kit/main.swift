import Foundation

/// brandkit svg <directory>                 writes the brand files
/// brandkit iconset <directory.iconset>     renders the app icon, for `iconutil -c icns`
struct BrandError: Error, CustomStringConvertible {
    let description: String
}

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    switch arguments.first {
    case "svg":
        let directory = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : ".")
        for file in BrandSVG.files() {
            try file.content.write(to: directory.appending(path: file.name), atomically: true, encoding: .utf8)
            print(file.name)
        }
    case "iconset":
        guard arguments.count > 1 else { throw BrandError(description: "iconset needs a directory") }
        try AppIconRenderer.writeIconset(to: URL(fileURLWithPath: arguments[1]))
    default:
        print("usage: brandkit svg <directory> | brandkit iconset <directory.iconset>")
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("brandkit: \(error)\n".utf8))
    exit(1)
}
