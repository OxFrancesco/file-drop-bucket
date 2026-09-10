import AppKit

@main struct PasteboardTest {
    static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        precondition(board.writeObjects([url as NSURL]))
        precondition(board.types?.contains(.fileURL) == true)
        let read = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        precondition(read == [url])
        print("PASS: public.file-url native pasteboard round-trip: \(url.absoluteString)")
    }
}
