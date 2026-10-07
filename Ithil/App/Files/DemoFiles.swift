import CoreGraphics
import CoreText
import Foundation
import ImageIO
import IthilCore
import os

private let logger = Logger(subsystem: "io.github.visaug36.Ithil", category: "DemoFiles")

/// Sample files for the `-demo` week, so screenshots and tests show events with real files in Finder.
///
/// Written once into the demo's temporary library (never anywhere else), through
/// `EventFolders.ensureFolder`, and never over a file that is already there. The contents are made on the
/// spot: one-page PDFs drawn with Core Graphics, a whiteboard photo encoded with ImageIO, and small text
/// files. Like `DemoLibrary`, the sample content is English data, not interface text.
enum DemoFiles {
    /// Creates the sample files for the demo events in `library` (as `DemoLibrary` makes it). Runs off the
    /// main actor; failures are logged and skipped.
    static func create(for library: Library, in folders: EventFolders, timeZone: TimeZone) async {
        let expander = OccurrenceExpander(displayTimeZone: timeZone)
        for sample in samples {
            guard let eventID = UUID(uuidString: sample.eventID), let event = library.event(withID: eventID),
                let occurrence = expander.occurrence(of: event, on: event.timing.startDate)
            else { continue }
            let folder: URL
            do {
                folder = try await folders.ensureFolder(for: occurrence)
            } catch {
                let reason = String(describing: error)
                logger.error("Could not make a demo folder: \(reason, privacy: .private)")
                continue
            }
            for file in sample.files {
                write(file, into: folder, folders: folders)
            }
        }
    }

    /// The same files as `EventFile`s in a folder that doesn't exist, with typical sizes, for SwiftUI
    /// previews. Touches no disk.
    static func previewFiles(for library: Library, timeZone: TimeZone) -> [Occurrence.ID: [EventFile]] {
        let expander = OccurrenceExpander(displayTimeZone: timeZone)
        let base = URL.temporaryDirectory.appending(component: "Ithil Preview", directoryHint: .isDirectory)
        var result: [Occurrence.ID: [EventFile]] = [:]
        for sample in samples {
            guard let eventID = UUID(uuidString: sample.eventID), let event = library.event(withID: eventID),
                let occurrence = expander.occurrence(of: event, on: event.timing.startDate)
            else { continue }
            let folder = base.appending(path: FolderNaming.relativePath(for: occurrence), directoryHint: .isDirectory)
            var files: [EventFile] = []
            for file in sample.files {
                let url = folder.appending(component: file.name, directoryHint: .notDirectory)
                let size = file.content.typicalByteCount
                let entry = EventFile(url: url, name: file.name, byteCount: size, modified: nil, isDirectory: false)
                files.append(entry)
            }
            result[occurrence.id] = files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return result
    }

    private static func write(_ file: DemoFile, into folder: URL, folders: EventFolders) {
        let url = folder.appending(component: file.name, directoryHint: .notDirectory)
        guard folders.contains(url), !FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = file.content.data() else {
            logger.error("Could not draw the demo file \(file.name, privacy: .private)")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            let reason = String(describing: error)
            logger.error("Could not write \(file.name, privacy: .private): \(reason, privacy: .private)")
        }
    }

    // MARK: - Samples

    /// The demo events that get files, by their fixed IDs in `DemoLibrary` (…0000000002NN is event NN).
    private static let samples: [DemoSample] = [
        DemoSample(eventID: "4954484C-DE30-4000-8000-000000000209", files: physicsLecture),
        DemoSample(eventID: "4954484C-DE30-4000-8000-000000000204", files: biologyLab),
        DemoSample(eventID: "4954484C-DE30-4000-8000-000000000207", files: tuesdaySeminar),
        DemoSample(eventID: "4954484C-DE30-4000-8000-000000000208", files: fridaySeminar),
    ]

    /// Physics Lecture, Tuesday 14:00.
    private static let physicsLecture: [DemoFile] = [
        DemoFile(name: "Lecture 7 – Rotational Motion.pdf", content: .pdf(lectureSlides)),
        DemoFile(name: "Problem Set 4.pdf", content: .pdf(problemSet)),
        DemoFile(name: "whiteboard.jpg", content: .whiteboard),
        DemoFile(name: "notes.md", content: .text(lectureNotes)),
    ]

    /// Biology Lab, Monday 13:00.
    private static let biologyLab: [DemoFile] = [
        DemoFile(name: "Lab 5 handout.pdf", content: .pdf(labHandout)),
        DemoFile(name: "results.csv", content: .text(labResults)),
    ]

    /// Literature Seminar, Tuesday 9:30.
    private static let tuesdaySeminar = [DemoFile(name: "Reading list.md", content: .text(readingList))]

    /// Literature Seminar, Friday 11:00.
    private static let fridaySeminar: [DemoFile] = [
        DemoFile(name: "Discussion questions.md", content: .text(discussionQuestions)),
        DemoFile(name: "Sonnet 73 close reading.pdf", content: .pdf(sonnetReading)),
        DemoFile(name: "Seminar notes.txt", content: .text(seminarNotes)),
    ]

    private static let lectureSlides = [
        "Lecture 7 – Rotational Motion",
        "Physics · Room B204",
        "",
        "1. Angular position, velocity and acceleration",
        "2. Moment of inertia: I = Σ m r²",
        "3. Torque: τ = r × F",
        "4. Rotational kinetic energy: K = ½ I ω²",
        "5. Rolling without slipping: v = ω r",
        "",
        "Reading: chapter 10, sections 1–5.",
    ]

    private static let problemSet = [
        "Problem Set 4",
        "Due Thursday, before the quiz.",
        "",
        "1. A wheel spins up from rest to 300 rpm in 4 s.",
        "    Find its angular acceleration.",
        "2. A 2 kg disc of radius 0.3 m spins at 10 rad/s.",
        "    Find its rotational kinetic energy.",
        "3. A ball rolls down a 1.5 m ramp without slipping.",
        "    How fast is it going at the bottom?",
    ]

    private static let lectureNotes = [
        "# Physics Lecture",
        "",
        "- Angular quantities mirror linear ones: θ ↔ x, ω ↔ v, α ↔ a.",
        "- I depends on how the mass is spread out, not just on how much there is.",
        "- Ask about problem 3 in office hours.",
        "- The quiz on Thursday covers chapters 4 and 5.",
    ]

    private static let labHandout = [
        "Lab 5 – Enzyme Activity",
        "Biology · Lab 3",
        "",
        "Goal: measure how temperature changes the rate of catalase.",
        "1. Prepare five water baths: 20, 30, 40, 50 and 60 °C.",
        "2. Add 2 ml of extract to 5 ml of hydrogen peroxide.",
        "3. Measure the oxygen released over 60 seconds.",
        "4. Repeat three times at each temperature.",
        "",
        "Hand in the results table at the end of the session.",
    ]

    private static let labResults = [
        "temperature_c,trial_1_ml,trial_2_ml,trial_3_ml",
        "20,1.2,1.1,1.3",
        "30,2.1,2.3,2.2",
        "40,3.4,3.2,3.5",
        "50,2.6,2.8,2.5",
        "60,0.9,1.0,0.8",
    ]

    private static let readingList = [
        "# Reading list",
        "",
        "1. Mary Shelley, *Frankenstein* (1818), volumes I and II",
        "2. William Shakespeare, Sonnets 18, 73 and 130",
        "3. Virginia Woolf, *A Room of One's Own*, chapter 1",
    ]

    private static let discussionQuestions = [
        "# Discussion questions",
        "",
        "- Who is the real monster in *Frankenstein*?",
        "- How does the frame narrative change what we believe?",
        "- What does Sonnet 73 say about time?",
    ]

    private static let sonnetReading = [
        "Sonnet 73 – Close Reading",
        "Three images of ending:",
        "1. Autumn: yellow leaves, or none, or few.",
        "2. Twilight: the day fading into night.",
        "3. A dying fire on the ashes of its youth.",
        "",
        "Couplet: love grows stronger because it must leave.",
    ]

    private static let seminarNotes = [
        "Seminar notes",
        "",
        "Bring two passages to compare. Essay outline due next week.",
    ]
}

/// The sample files of one demo event.
private struct DemoSample: Sendable {
    /// The event's fixed ID in `DemoLibrary`.
    var eventID: String
    var files: [DemoFile]
}

private struct DemoFile: Sendable {
    var name: String
    var content: DemoFileContent
}

private enum DemoFileContent: Sendable {
    /// A text file with these lines.
    case text([String])
    /// A one-page PDF: the first line is its title.
    case pdf([String])
    /// A JPEG photo of a whiteboard.
    case whiteboard

    /// About how big the file is on disk, for previews.
    var typicalByteCount: Int64 {
        switch self {
        case .text(let lines):
            return Int64(lines.joined(separator: "\n").utf8.count + 1)
        case .pdf(let lines):
            return 24_000 + Int64(lines.count) * 1_500
        case .whiteboard:
            return 186_000
        }
    }

    func data() -> Data? {
        switch self {
        case .text(let lines):
            return Data((lines.joined(separator: "\n") + "\n").utf8)
        case .pdf(let lines):
            return DemoDrawing.pdf(title: lines.first ?? "", lines: Array(lines.dropFirst()))
        case .whiteboard:
            return DemoDrawing.whiteboardJPEG()
        }
    }
}

/// Draws the demo PDFs and the whiteboard photo with Core Graphics and Core Text, which are safe to use
/// off the main thread.
private enum DemoDrawing {
    /// A one-page A4 handout: a bold title, an amber rule, and the lines below it.
    static func pdf(title: String, lines: [String]) -> Data? {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        context.beginPDFPage(nil)
        let ink = CGColor(srgbRed: 0.12, green: 0.13, blue: 0.18, alpha: 1)
        var baseline = mediaBox.height - 96
        draw(title, size: 24, bold: true, color: ink, at: CGPoint(x: 72, y: baseline), in: context)
        baseline -= 18
        context.setStrokeColor(CGColor(srgbRed: 0.85, green: 0.6, blue: 0.25, alpha: 1))
        context.setLineWidth(1.5)
        context.move(to: CGPoint(x: 72, y: baseline))
        context.addLine(to: CGPoint(x: mediaBox.width - 72, y: baseline))
        context.strokePath()
        baseline -= 34
        for line in lines {
            draw(line, size: 13, bold: false, color: ink, at: CGPoint(x: 72, y: baseline), in: context)
            baseline -= 22
        }
        context.endPDFPage()
        context.closePDF()
        return Data(referencing: data)
    }

    /// A photo of a whiteboard after a lecture on rotation: a wheel, its radius, an arrow for ω and two
    /// formulas, in marker colors.
    static func whiteboardJPEG() -> Data? {
        let width = 1200
        let height = 800
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmap = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: bitmapInfo)
        guard let context = bitmap else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.95, green: 0.95, blue: 0.93, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        drawWheel(in: context)
        let blue = CGColor(srgbRed: 0.13, green: 0.27, blue: 0.62, alpha: 1)
        let red = CGColor(srgbRed: 0.75, green: 0.18, blue: 0.16, alpha: 1)
        draw("ω = Δθ / Δt", size: 54, bold: true, color: blue, at: CGPoint(x: 680, y: 520), in: context)
        draw("K = ½ I ω²", size: 54, bold: true, color: red, at: CGPoint(x: 680, y: 400), in: context)
        draw("Quiz Thu!", size: 40, bold: false, color: blue, at: CGPoint(x: 680, y: 240), in: context)
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        // The JPEG type identifier (`UTType.jpeg`), written out to keep this file's imports small.
        let type = "public.jpeg" as CFString
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, type, 1, nil) else {
            return nil
        }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return Data(referencing: data)
    }

    /// The wheel: a circle, a radius with its label, and a curved arrow showing the rotation.
    private static func drawWheel(in context: CGContext) {
        let center = CGPoint(x: 340, y: 400)
        let radius: CGFloat = 200
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(8)
        context.setStrokeColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1))
        let rim = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.strokeEllipse(in: rim)
        context.move(to: center)
        context.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        context.strokePath()
        context.fillEllipse(in: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16))
        let green = CGColor(srgbRed: 0.12, green: 0.5, blue: 0.3, alpha: 1)
        draw("r", size: 44, bold: false, color: green, at: CGPoint(x: center.x + 90, y: center.y + 16), in: context)

        let red = CGColor(srgbRed: 0.75, green: 0.18, blue: 0.16, alpha: 1)
        let arcRadius: CGFloat = radius + 50
        let start: CGFloat = 0.35
        let end: CGFloat = 1.25
        context.setStrokeColor(red)
        context.setLineWidth(7)
        context.addArc(center: center, radius: arcRadius, startAngle: start, endAngle: end, clockwise: false)
        context.strokePath()
        // An arrowhead at the end of the arc, pointing along it (counterclockwise).
        let tip = CGPoint(x: center.x + arcRadius * cos(end), y: center.y + arcRadius * sin(end))
        let direction = CGPoint(x: -sin(end), y: cos(end))
        let wings: [CGFloat] = [2.6, -2.6]
        for angle in wings {
            let back = CGPoint(
                x: direction.x * cos(angle) - direction.y * sin(angle),
                y: direction.x * sin(angle) + direction.y * cos(angle))
            context.move(to: tip)
            context.addLine(to: CGPoint(x: tip.x + back.x * 34, y: tip.y + back.y * 34))
        }
        context.strokePath()
    }

    /// Draws one line of text with its baseline at `point`. Core Text falls back to other fonts for
    /// symbols Helvetica lacks.
    private static func draw(
        _ text: String,
        size: CGFloat,
        bold: Bool,
        color: CGColor,
        at point: CGPoint,
        in context: CGContext
    ) {
        guard !text.isEmpty else { return }
        let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(string as CFAttributedString)
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
