import AppKit
import CoreGraphics
import CoreMedia
import Foundation
@preconcurrency import AVFoundation
@preconcurrency import ScreenCaptureKit

struct Options {
    var outputPath: String = ""
    var roi = CGRect.zero
    var durationSeconds: Double = 0.0
    var fps: Double = 60.0
    var bitRate: Int = 8_000_000
}

enum CaptureError: Error, CustomStringConvertible {
    case usage(String)
    case runtime(String)

    var description: String {
        switch self {
        case .usage(let message), .runtime(let message):
            return message
        }
    }
}

func usage() -> String {
    """
    Usage: screen_capturekit_roi.swift --output PATH --roi x,y,w,h --duration SECONDS [--fps 60] [--bit-rate 8000000]
    """
}

func parseROI(_ text: String) throws -> CGRect {
    let parts = text.split(separator: ",").map(String.init)
    guard parts.count == 4,
          let x = Double(parts[0]),
          let y = Double(parts[1]),
          let width = Double(parts[2]),
          let height = Double(parts[3]),
          width > 0,
          height > 0
    else {
        throw CaptureError.usage("invalid --roi \(text)\n\(usage())")
    }
    return CGRect(x: x, y: y, width: width, height: height)
}

func parseOptions() throws -> Options {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let name = arguments.removeFirst()
        func takeValue() throws -> String {
            guard !arguments.isEmpty else {
                throw CaptureError.usage("\(name) requires a value\n\(usage())")
            }
            return arguments.removeFirst()
        }
        switch name {
        case "--output":
            options.outputPath = try takeValue()
        case "--roi":
            options.roi = try parseROI(try takeValue())
        case "--duration":
            guard let value = Double(try takeValue()), value > 0 else {
                throw CaptureError.usage("--duration must be positive\n\(usage())")
            }
            options.durationSeconds = value
        case "--fps":
            guard let value = Double(try takeValue()), value > 0 else {
                throw CaptureError.usage("--fps must be positive\n\(usage())")
            }
            options.fps = value
        case "--bit-rate":
            guard let value = Int(try takeValue()), value > 0 else {
                throw CaptureError.usage("--bit-rate must be positive\n\(usage())")
            }
            options.bitRate = value
        case "-h", "--help":
            print(usage())
            exit(0)
        default:
            throw CaptureError.usage("unknown option: \(name)\n\(usage())")
        }
    }
    guard !options.outputPath.isEmpty else {
        throw CaptureError.usage("--output is required\n\(usage())")
    }
    guard !options.roi.isEmpty else {
        throw CaptureError.usage("--roi is required\n\(usage())")
    }
    guard options.durationSeconds > 0 else {
        throw CaptureError.usage("--duration is required\n\(usage())")
    }
    return options
}

func backingScaleFactor(for displayID: CGDirectDisplayID) -> Double {
    for screen in NSScreen.screens {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            continue
        }
        if CGDirectDisplayID(screenNumber.uint32Value) == displayID {
            return Double(screen.backingScaleFactor)
        }
    }
    return 1.0
}

final class CaptureOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let stateLock = NSLock()
    private var latestPixelBuffer: CVPixelBuffer?
    private var sourceFrameSerial = 0
    private var receivedFrameCount = 0

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else {
            return
        }
        guard isCompleteFrame(sampleBuffer) else {
            return
        }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        stateLock.withLock {
            latestPixelBuffer = imageBuffer
            sourceFrameSerial += 1
            receivedFrameCount += 1
        }
    }

    private func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[SCStreamFrameInfo.status] as? Int
        else {
            return true
        }
        return rawStatus == SCFrameStatus.complete.rawValue
    }

    func latestFrame() -> (pixelBuffer: CVPixelBuffer, serial: Int)? {
        stateLock.withLock {
            guard let latestPixelBuffer else {
                return nil
            }
            return (latestPixelBuffer, sourceFrameSerial)
        }
    }

    func sourceFrameCount() -> Int {
        stateLock.withLock { receivedFrameCount }
    }
}

func copyPixelBuffer(_ source: CVPixelBuffer, to destination: CVPixelBuffer) throws {
    CVPixelBufferLockBaseAddress(source, .readOnly)
    CVPixelBufferLockBaseAddress(destination, [])
    defer {
        CVPixelBufferUnlockBaseAddress(destination, [])
        CVPixelBufferUnlockBaseAddress(source, .readOnly)
    }

    guard let sourceBase = CVPixelBufferGetBaseAddress(source),
          let destinationBase = CVPixelBufferGetBaseAddress(destination)
    else {
        throw CaptureError.runtime("could not access CVPixelBuffer base address")
    }

    let height = min(CVPixelBufferGetHeight(source), CVPixelBufferGetHeight(destination))
    let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(source)
    let destinationBytesPerRow = CVPixelBufferGetBytesPerRow(destination)
    let copyBytesPerRow = min(sourceBytesPerRow, destinationBytesPerRow)
    for row in 0..<height {
        let sourceRow = sourceBase.advanced(by: row * sourceBytesPerRow)
        let destinationRow = destinationBase.advanced(by: row * destinationBytesPerRow)
        memcpy(destinationRow, sourceRow, copyBytesPerRow)
    }
}

func waitForFirstFrame(_ captureOutput: CaptureOutput, timeoutSeconds: Double) async throws {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while captureOutput.latestFrame() == nil {
        if Date() >= deadline {
            throw CaptureError.runtime("ScreenCaptureKit did not produce an initial frame before timeout")
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
}

func appendFixedCadenceFrames(
    captureOutput: CaptureOutput,
    adaptor: AVAssetWriterInputPixelBufferAdaptor,
    input: AVAssetWriterInput,
    fps: Double,
    durationSeconds: Double
) async throws -> (encodedFrames: Int, repeatedFrames: Int, backpressureWaits: Int) {
    guard let pixelBufferPool = adaptor.pixelBufferPool else {
        throw CaptureError.runtime("AVAssetWriter did not create a pixel buffer pool")
    }
    let targetFrameCount = max(1, Int(ceil(durationSeconds * fps)))
    let timeScale = CMTimeScale(fps.rounded())
    var encodedFrames = 0
    var repeatedFrames = 0
    var backpressureWaits = 0
    var lastSerial = -1
    let start = DispatchTime.now().uptimeNanoseconds

    for frameIndex in 0..<targetFrameCount {
        let target = start + UInt64((Double(frameIndex) / fps) * 1_000_000_000.0)
        let now = DispatchTime.now().uptimeNanoseconds
        if target > now {
            try await Task.sleep(nanoseconds: target - now)
        }

        try await waitForFirstFrame(captureOutput, timeoutSeconds: 2.0)
        guard let latest = captureOutput.latestFrame() else {
            throw CaptureError.runtime("ScreenCaptureKit latest frame disappeared while encoding")
        }
        if latest.serial == lastSerial {
            repeatedFrames += 1
        } else {
            lastSerial = latest.serial
        }

        while !input.isReadyForMoreMediaData {
            backpressureWaits += 1
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        var outputPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &outputPixelBuffer)
        guard status == kCVReturnSuccess, let outputPixelBuffer else {
            throw CaptureError.runtime("could not allocate AVAssetWriter pixel buffer: \(status)")
        }
        try copyPixelBuffer(latest.pixelBuffer, to: outputPixelBuffer)
        let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: timeScale)
        guard adaptor.append(outputPixelBuffer, withPresentationTime: presentationTime) else {
            throw CaptureError.runtime("AVAssetWriter adaptor append failed")
        }
        encodedFrames += 1
    }
    return (encodedFrames, repeatedFrames, backpressureWaits)
}

final class WriterBox: @unchecked Sendable {
    let writer: AVAssetWriter

    init(_ writer: AVAssetWriter) {
        self.writer = writer
    }
}

func finishWriter(_ writer: AVAssetWriter, input: AVAssetWriterInput) async throws {
    input.markAsFinished()
    let writerBox = WriterBox(writer)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        writerBox.writer.finishWriting {
            if let error = writerBox.writer.error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }
}

@main
struct ScreenCaptureKitROICapture {
    static func main() async {
        do {
            let options = try parseOptions()
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: options.outputPath).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(atPath: options.outputPath)

            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let mainDisplayID = CGMainDisplayID()
            guard let display = content.displays.first(where: { $0.displayID == mainDisplayID }) ?? content.displays.first else {
                throw CaptureError.runtime("ScreenCaptureKit did not report a capturable display")
            }

            let width = Int(options.roi.width.rounded(.down))
            let height = Int(options.roi.height.rounded(.down))
            guard width > 0, height > 0 else {
                throw CaptureError.runtime("ROI resolved to an empty capture size")
            }
            let backingScale = backingScaleFactor(for: display.displayID)
            let scaleX = backingScale
            let scaleY = backingScale
            let sourceRect = CGRect(
                x: options.roi.origin.x / max(0.001, scaleX),
                y: options.roi.origin.y / max(0.001, scaleY),
                width: options.roi.width / max(0.001, scaleX),
                height: options.roi.height / max(0.001, scaleY)
            )

            let outputURL = URL(fileURLWithPath: options.outputPath)
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            let compression: [String: Any] = [
                AVVideoAverageBitRateKey: options.bitRate,
                AVVideoExpectedSourceFrameRateKey: Int(options.fps.rounded()),
                AVVideoMaxKeyFrameIntervalKey: Int(options.fps.rounded()),
            ]
            let outputSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: compression,
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else {
                throw CaptureError.runtime("AVAssetWriter cannot add realtime video input")
            }
            writer.add(input)
            let pixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: pixelBufferAttributes
            )

            let captureOutput = CaptureOutput()

            let configuration = SCStreamConfiguration()
            configuration.width = width
            configuration.height = height
            configuration.sourceRect = sourceRect
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.fps.rounded()))
            configuration.queueDepth = 8
            configuration.showsCursor = false
            configuration.capturesAudio = false
            configuration.pixelFormat = kCVPixelFormatType_32BGRA

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            let sampleQueue = DispatchQueue(label: "tokyo.walking.stabilizer.e2e.screencapturekit")
            try stream.addStreamOutput(captureOutput, type: .screen, sampleHandlerQueue: sampleQueue)
            try await stream.startCapture()

            guard writer.startWriting() else {
                throw CaptureError.runtime("AVAssetWriter could not start: \(writer.error?.localizedDescription ?? "unknown error")")
            }
            writer.startSession(atSourceTime: .zero)
            try await waitForFirstFrame(captureOutput, timeoutSeconds: 2.0)
            let encodeResult = try await appendFixedCadenceFrames(
                captureOutput: captureOutput,
                adaptor: adaptor,
                input: input,
                fps: options.fps,
                durationSeconds: options.durationSeconds
            )
            try await stream.stopCapture()
            try await finishWriter(writer, input: input)
            if encodeResult.encodedFrames <= 0 {
                throw CaptureError.runtime("ScreenCaptureKit did not encode any video frames")
            }
            let encodedDuration = Double(encodeResult.encodedFrames) / options.fps
            let sourceFrames = captureOutput.sourceFrameCount()
            let sourceCoverage = Double(sourceFrames) / Double(max(1, encodeResult.encodedFrames))
            print(
                String(
                    format: "ScreenCaptureKit ROI captured encoded=%d source=%d repeated=%d backpressure=%d duration=%.3fs fps=%.2f sourceCoverage=%.3f scale=%.3fx%.3f output=%@",
                    encodeResult.encodedFrames,
                    sourceFrames,
                    encodeResult.repeatedFrames,
                    encodeResult.backpressureWaits,
                    encodedDuration,
                    options.fps,
                    sourceCoverage,
                    scaleX,
                    scaleY,
                    options.outputPath
                )
            )
        } catch {
            fputs("screen_capturekit_roi.swift: \(error)\n", stderr)
            exit(2)
        }
    }
}
