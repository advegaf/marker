// Prints the window numbers owned by a named process, largest window first.
//
// Used so evidence capture can be scoped to one window with `screencapture -l`.
// Full screen capture is never acceptable here: it photographs whatever else is
// on the machine, and this repository is public.
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? ""
guard !owner.isEmpty else {
    FileHandle.standardError.write(Data("usage: window-id.swift <process name>\n".utf8))
    exit(2)
}

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

let matches = windows.compactMap { info -> (Int, CGFloat)? in
    guard let name = info[kCGWindowOwnerName as String] as? String, name == owner,
          let number = info[kCGWindowNumber as String] as? Int,
          let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
          let width = bounds["Width"], let height = bounds["Height"],
          width > 200, height > 200
    else { return nil }
    return (number, width * height)
}.sorted { $0.1 > $1.1 }

guard let best = matches.first else { exit(1) }
print(best.0)
