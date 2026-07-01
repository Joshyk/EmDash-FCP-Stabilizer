import CoreMedia
import Foundation
import os.log

private enum HostAnalysisValidationState {
    case notRequired
    case pending
    case validated
    case rejected
}

private enum HostAnalysisStatus {
    case needsAnalysis
    case externalAnalysisRequired
    case externalCacheManaged
    case requested
    case queued
    case analyzing
    case cacheLoaded
    case ready
    case cacheRejected
    case cacheUnsupported
    case cacheIncomplete
    case cacheCleared
    case projectCacheUnavailable
    case proxyRejected
    case proxyPreview
    case sourceMetadataUnconfirmedPreview
    case proxyNeedsOriginalValidation
    case sourceUnavailable
    case mediaLinkInvalid
    case loadedButNotRendering
    case cacheRangeMismatch
    case stabilizationActive
    case debugOverlayActive
}

private struct PersistedHostAnalysisCache: Codable {
    let schemaVersion: Int
    let createdAt: Double
    let clipLabel: String?
    let rangeStartSeconds: Double
    let rangeDurationSeconds: Double
    let rangeEndSeconds: Double?
    let frameDurationSeconds: Double
    let sampleWidth: Int
    let sampleHeight: Int
    let eventName: String?
    let frames: [PersistedHostAnalysisFrame]
    let residuals: [Float]?
    let rollMotion: [Float]?
    let pathX: [Float]?
    let pathY: [Float]?
    let pathRoll: [Float]?
    let footstepPathX: [Float]?
    let footstepPathY: [Float]?
    let footstepPathRoll: [Float]?
    let pathYaw: [Float]?
    let pathPitch: [Float]?
    let pathShearX: [Float]?
    let pathShearY: [Float]?
    let pathPerspectiveX: [Float]?
    let pathPerspectiveY: [Float]?
    let analysisConfidence: [Float]?
    let warpConfidence: [Float]?
    let acceptedBlockCounts: [Int32]?
    let totalBlockCounts: [Int32]?
    let blurAmounts: [Float]?
    let searchRadiusHitCounts: [Int32]?
    let searchRadiusTotalCounts: [Int32]?
}

private struct PersistedHostAnalysisSchemaHeader: Codable {
    let schemaVersion: Int
}

private struct PersistedHostAnalysisFrame: Codable {
    let time: Double
    let pixels: Data?
    let blurAmount: Float
    let fingerprint: String?
}

private struct PersistedHostAnalysisIndex: Codable {
    let schemaVersion: Int
    var entries: [PersistedHostAnalysisIndexEntry]
}

private struct PersistedHostAnalysisIndexEntry: Codable {
    let cacheFileName: String
    let createdAt: Double
    let clipLabel: String?
    let rangeStartSeconds: Double
    let rangeDurationSeconds: Double
    let rangeEndSeconds: Double?
    let frameDurationSeconds: Double
    let sampleWidth: Int
    let sampleHeight: Int
    let frameCount: Int
    let firstFingerprint: String
    let middleFingerprint: String
    let lastFingerprint: String
    let fingerprints: [String]?
    let cacheIdentity: String?
}

private struct PersistedRenderTimeOffsetIndex: Codable {
    let version: Int
    var entries: [PersistedRenderTimeOffsetEntry]
}

private struct PersistedRenderTimeOffsetEntry: Codable {
    let cacheIdentity: String
    let offsetSeconds: Double
    let savedAt: Double
    let renderSeconds: Double
    let analysisSeconds: Double
}

private struct LoadedPersistentHostAnalysisCache {
    let fileName: String
    let url: URL
    let cache: PersistedHostAnalysisCache
    let identity: String
    let frames: [StabilizerAnalysisFrame]
    let preparedAnalysis: StabilizerPreparedAnalysis
}

private struct PersistentCacheLoadTiming {
    let candidateCount: Int
    let decodeMilliseconds: Double
}

private enum PersistentCacheLoadAttempt {
    case loaded(LoadedPersistentHostAnalysisCache)
    case unusable(HostAnalysisStatus, String)
    case skipped
}

private struct HostAnalysisTimingAccumulator {
    var downsampleFrameCount = 0
    var downsampleMilliseconds = 0.0
    var blurMilliseconds = 0.0
    var motionPairCount = 0
    var globalShiftMilliseconds = 0.0
    var localBatchShiftMilliseconds = 0.0
    var pairMotionMilliseconds = 0.0
    var cacheCandidateCount = 0
    var cacheDecodeMilliseconds = 0.0
    var finishMilliseconds = 0.0
    var persistMilliseconds = 0.0

    mutating func record(sample: StabilizerAnalysisSample, metricsMilliseconds: Double) {
        downsampleFrameCount += 1
        downsampleMilliseconds += sample.downsampleMilliseconds
        blurMilliseconds += metricsMilliseconds
    }

    mutating func record(pairTiming: StabilizerPairMotionTiming) {
        motionPairCount += 1
        globalShiftMilliseconds += pairTiming.globalMilliseconds
        localBatchShiftMilliseconds += pairTiming.localBatchMilliseconds
        pairMotionMilliseconds += pairTiming.totalMilliseconds
    }

    mutating func record(cacheTiming: PersistentCacheLoadTiming) {
        cacheCandidateCount += cacheTiming.candidateCount
        cacheDecodeMilliseconds += cacheTiming.decodeMilliseconds
    }
}

struct StabilizerHostAnalysisInspectorSnapshot {
    let analysisInfoText: String
    let requestedSampleScalePercent: Double?
    let rangeStartSeconds: Double?
    let rangeEndSeconds: Double?
    let sampleWidth: Int?
    let sampleHeight: Int?
    let frameCount: Int?
}

struct StabilizerHostAnalysisRenderSnapshot {
    let hasCompletedAnalysis: Bool
    let hasPreparedAnalysis: Bool
    let revision: UInt64
    let renderInvalidationToken: Double
    let activeCacheIdentity: String?
}

final class StabilizerHostAnalysisStore {
    private typealias CompletedHostAnalysisSnapshot = (
        frames: [StabilizerAnalysisFrame],
        preparedAnalysis: StabilizerPreparedAnalysis?,
        activeRange: CMTimeRange,
        activeFrameDuration: CMTime,
        activeRequestedSampleScalePercent: Double,
        finished: Bool,
        validationState: HostAnalysisValidationState,
        status: HostAnalysisStatus,
        projectCacheUnavailableStatusText: String,
        projectCacheUnavailableReason: String?,
        latestSourceFrameInfo: StabilizerSourceFrameInfo?,
        latestSampleSize: (width: Int, height: Int)?,
        analysisInfoText: String,
        activePersistentCacheIdentity: String?
    )

    private struct CompletedMemoryHostAnalysis {
        let identity: String
        let rangeKey: String
        let snapshot: CompletedHostAnalysisSnapshot
    }

    private static let cacheSchemaVersion = 27
    private static let supportedCacheSchemaVersions: Set<Int> = [17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27]
    private static let persistentCacheGenerationLock = NSLock()
    private static var persistentCacheGeneration: UInt64 = 0
    private static let projectCacheDirectoryLock = NSLock()
    private static var projectBundleCacheDirectoryURL: URL?
    private static var projectBundleCacheEventName: String?
    private static var retainedSecurityScopedProjectURLs: [URL] = []
    private static let maxPersistentCacheEntriesPerSampleSize = 8
    private static let maxCompletedMemoryAnalyses = 8
    private static let maxPersistentCacheReadBytes = 629_145_600
    private static let cacheValidationMeanDifferenceThreshold: Float = 18.0
    private static let cacheFileName = "host-analysis-v2.json"
    private static let cacheIndexFileName = "host-analysis-index-v2.json"
    private static let renderTimeOffsetFileName = "host-analysis-render-offset-v2.json"
    private static let cacheStorageDirectoryName = "caches"
    private static let analysisScratchDirectoryName = "analysis-work"

    private let lock = NSLock()
    private let downsampleBufferPool = StabilizerDownsampleBufferPool()
    private var framesByTimeKey: [Int64: StabilizerAnalysisFrame] = [:]
    private var streamingAnalysisBuilder: StreamingStabilizationAnalysisBuilder?
    private var preparedAnalysis: StabilizerPreparedAnalysis?
    private var activeCompletedMemoryAnalysisIdentity: String?
    private var completedMemoryAnalysesByIdentity: [String: CompletedMemoryHostAnalysis] = [:]
    private var completedMemoryAnalysisIdentitiesByRangeKey: [String: [String]] = [:]
    private var completedMemoryAnalysisOrder: [String] = []
    private var rejectedCompletedMemoryAnalysisIdentities = Set<String>()
    private var persistentCachesByIdentity: [String: LoadedPersistentHostAnalysisCache] = [:]
    private var persistentCacheCandidates: [URL] = []
    private var activePersistentCacheFileName: String?
    private var activePersistentCacheIdentity: String?
    private var rejectedPersistentCacheFileNames = Set<String>()
    private var activeRange: CMTimeRange = .invalid
    private var activeFrameDuration: CMTime = .invalid
    private var activeRequestedSampleScalePercent = StabilizerSampleScale.defaultScale.percent
    private var renderToAnalysisOffsetSeconds: Double?
    private var renderToAnalysisOffsetProbeAttempted = false
    private var finished = false
    private var validationState: HostAnalysisValidationState = .notRequired
    private var status: HostAnalysisStatus = .needsAnalysis
    private var projectCacheUnavailableStatusText = stabilizerProjectCacheUnavailableMessage
    private var projectCacheUnavailableReason: String?
    private var analysisRevision: UInt64 = 0
    private var renderRevisionToken: Double = 0.0
    private var observedPersistentCacheGeneration: UInt64 = 0
    private var observedPersistentCacheSignature = ""
    private var latestSourceFrameInfo: StabilizerSourceFrameInfo?
    private var latestSampleSize: (width: Int, height: Int)?
    private var analysisInfoText = "No Analysis"
    private var analysisTiming = HostAnalysisTimingAccumulator()

    var frameCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return framesByTimeKey.count
    }

    var reusableDownsampleBufferPool: StabilizerDownsampleBufferPool {
        downsampleBufferPool
    }

    var revision: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return analysisRevision
    }

    var renderInvalidationToken: Double {
        lock.lock()
        defer { lock.unlock() }
        return renderRevisionToken
    }

    var infoText: String {
        lock.lock()
        defer { lock.unlock() }
        return analysisInfoText
    }

    var inspectorSnapshot: StabilizerHostAnalysisInspectorSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let preparedFrames = preparedAnalysis?.frames ?? []
        let frameCount: Int?
        if !preparedFrames.isEmpty {
            frameCount = preparedFrames.count
        } else if !framesByTimeKey.isEmpty {
            frameCount = framesByTimeKey.count
        } else {
            frameCount = nil
        }

        let preparedSample = preparedFrames.first.map { frame in
            (width: frame.sampleWidth, height: frame.sampleHeight)
        }
        let sourceDerivedSample: (width: Int, height: Int)?
        if let latestSourceFrameInfo {
            sourceDerivedSample = AutoStabilizationEstimator.sampleSize(
                sourceWidth: latestSourceFrameInfo.sourceWidth,
                sourceHeight: latestSourceFrameInfo.sourceHeight,
                scalePercent: activeRequestedSampleScalePercent
            )
        } else {
            sourceDerivedSample = nil
        }
        let sampleSize = latestSampleSize ?? preparedSample ?? sourceDerivedSample

        let rangeSeconds: (start: Double?, end: Double?)
        if activeRange.isValid {
            let startSeconds = CMTimeGetSeconds(activeRange.start)
            let durationSeconds = CMTimeGetSeconds(activeRange.duration)
            if startSeconds.isFinite,
               durationSeconds.isFinite,
               durationSeconds >= 0.0 {
                rangeSeconds = (startSeconds, startSeconds + durationSeconds)
            } else {
                rangeSeconds = (nil, nil)
            }
        } else {
            rangeSeconds = (nil, nil)
        }

        return StabilizerHostAnalysisInspectorSnapshot(
            analysisInfoText: analysisInfoText,
            requestedSampleScalePercent: activeRequestedSampleScalePercent.isFinite ? activeRequestedSampleScalePercent : nil,
            rangeStartSeconds: rangeSeconds.start,
            rangeEndSeconds: rangeSeconds.end,
            sampleWidth: sampleSize?.width,
            sampleHeight: sampleSize?.height,
            frameCount: frameCount
        )
    }

    var activeCacheIdentity: String? {
        lock.lock()
        defer { lock.unlock() }
        return activePersistentCacheIdentity
    }

    var renderSnapshot: StabilizerHostAnalysisRenderSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let hasRenderablePreparedAnalysis = validationState != .rejected && preparedAnalysis != nil
        return StabilizerHostAnalysisRenderSnapshot(
            hasCompletedAnalysis: finished && hasRenderablePreparedAnalysis,
            hasPreparedAnalysis: hasRenderablePreparedAnalysis,
            revision: analysisRevision,
            renderInvalidationToken: renderRevisionToken,
            activeCacheIdentity: activePersistentCacheIdentity
        )
    }

    var activeExpectedRange: HostAnalysisExpectedRange? {
        lock.lock()
        let range = activeRange
        let frameDuration = activeFrameDuration
        lock.unlock()
        let expectedRange = HostAnalysisExpectedRange(
            startSeconds: CMTimeGetSeconds(range.start),
            durationSeconds: CMTimeGetSeconds(range.duration),
            frameDurationSeconds: CMTimeGetSeconds(frameDuration)
        )
        return expectedRange.isValid ? expectedRange : nil
    }

    var projectCacheUnavailableReasonText: String? {
        lock.lock()
        defer { lock.unlock() }
        return projectCacheUnavailableReason
    }

    static func configureProjectBundleCacheDirectory(_ directoryURL: URL, securityScopedURL: URL?, eventName: String) {
        let standardizedDirectoryURL = directoryURL.standardizedFileURL
        projectCacheDirectoryLock.lock()
        let changed = projectBundleCacheDirectoryURL?.path != standardizedDirectoryURL.path
        projectBundleCacheDirectoryURL = standardizedDirectoryURL
        projectBundleCacheEventName = eventName
        if let securityScopedURL {
            let standardizedSecurityURL = securityScopedURL.standardizedFileURL
            if !retainedSecurityScopedProjectURLs.contains(where: { $0.path == standardizedSecurityURL.path }) {
                retainedSecurityScopedProjectURLs.append(standardizedSecurityURL)
            }
        }
        projectCacheDirectoryLock.unlock()
        if changed {
            bumpPersistentCacheGeneration()
        }
    }

    static func clearProjectBundleCacheDirectory(reason: String) {
        projectCacheDirectoryLock.lock()
        let hadConfiguredDirectory = projectBundleCacheDirectoryURL != nil
        let retainedURLs = retainedSecurityScopedProjectURLs
        projectBundleCacheDirectoryURL = nil
        projectBundleCacheEventName = nil
        retainedSecurityScopedProjectURLs = []
        projectCacheDirectoryLock.unlock()
        for retainedURL in retainedURLs {
            retainedURL.stopAccessingSecurityScopedResource()
        }
        if hadConfiguredDirectory {
            NSLog("TokyoWalkingStabilizer: cleared configured Event Host Analysis cache root because \(reason)")
            bumpPersistentCacheGeneration()
        }
    }

    private static var currentProjectBundleCacheEventName: String? {
        projectCacheDirectoryLock.lock()
        let eventName = projectBundleCacheEventName
        projectCacheDirectoryLock.unlock()
        return eventName
    }

    static var hasConfiguredProjectBundleCacheDirectory: Bool {
        projectCacheDirectoryLock.lock()
        let configured = projectBundleCacheDirectoryURL != nil
        projectCacheDirectoryLock.unlock()
        return configured
    }

    var statusText: String {
        lock.lock()
        let currentStatus = status
        let frameCount = framesByTimeKey.count
        let hasPreparedAnalysis = preparedAnalysis != nil
        let unavailableStatusText = projectCacheUnavailableStatusText
        lock.unlock()

        switch currentStatus {
        case .needsAnalysis:
            return "Needs Analysis"
        case .externalAnalysisRequired:
            return "External Analysis Required - Run Event Analyzer"
        case .externalCacheManaged:
            return "External Cache Managed - Use Event Analyzer"
        case .requested:
            return "Host Analysis Requested"
        case .queued:
            return "Queued Host Analysis"
        case .analyzing:
            return "Analyzing Host Frames (\(frameCount))"
        case .cacheLoaded:
            return "Cache Loaded (\(frameCount))"
        case .ready:
            if hasPreparedAnalysis {
                return "Ready (\(frameCount) frames)"
            }
            return "Needs Analysis"
        case .cacheRejected:
            return "Cache Rejected - Run Event Analyzer"
        case .cacheUnsupported:
            return "Cache Unsupported - Run Event Analyzer"
        case .cacheIncomplete:
            return "Cache Incomplete - Run Event Analyzer"
        case .cacheCleared:
            return "Cache Cleared"
        case .projectCacheUnavailable:
            if hasPreparedAnalysis {
                return "Ready Memory Only - \(unavailableStatusText)"
            }
            return unavailableStatusText
        case .proxyRejected:
            return "Proxy Media Rejected - Use Original Media"
        case .proxyPreview:
            if hasPreparedAnalysis {
                return "Original Analysis - Proxy Preview (\(frameCount) frames)"
            }
            return "Needs Analysis"
        case .sourceMetadataUnconfirmedPreview:
            if hasPreparedAnalysis {
                return "Original Analysis - Preview Unvalidated (\(frameCount) frames)"
            }
            return "Needs Analysis"
        case .proxyNeedsOriginalValidation:
            return "Proxy Cache Unvalidated - Use Original Media"
        case .sourceUnavailable:
            return "Source Media Unavailable - Check FCP Proxy"
        case .mediaLinkInvalid:
            return "Media Link Invalid"
        case .loadedButNotRendering:
            return "Loaded But Not Rendering"
        case .cacheRangeMismatch:
            return "Cache Range Mismatch"
        case .stabilizationActive:
            return "Stabilization Active (\(frameCount) frames)"
        case .debugOverlayActive:
            return "Debug Overlay Active (\(frameCount) frames)"
        }
    }

    var hasCompletedAnalysis: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished && validationState != .rejected && preparedAnalysis != nil
    }

    var hasRejectedPersistentCache: Bool {
        lock.lock()
        defer { lock.unlock() }
        return validationState == .rejected || status == .cacheRejected
    }

    func begin(range: CMTimeRange, frameDuration: CMTime, requestedSampleScalePercent: Double) {
        removeLegacyAnalysisScratchDirectory()
        lock.lock()
        framesByTimeKey.removeAll(keepingCapacity: true)
        streamingAnalysisBuilder = nil
        preparedAnalysis = nil
        activeCompletedMemoryAnalysisIdentity = nil
        persistentCacheCandidates.removeAll(keepingCapacity: false)
        activePersistentCacheFileName = nil
        activePersistentCacheIdentity = nil
        rejectedPersistentCacheFileNames.removeAll(keepingCapacity: true)
        activeRange = range
        activeFrameDuration = frameDuration
        activeRequestedSampleScalePercent = requestedSampleScalePercent
        renderToAnalysisOffsetSeconds = nil
        renderToAnalysisOffsetProbeAttempted = false
        finished = false
        validationState = .validated
        status = .analyzing
        projectCacheUnavailableStatusText = stabilizerProjectCacheUnavailableMessage
        projectCacheUnavailableReason = nil
        latestSourceFrameInfo = nil
        latestSampleSize = nil
        analysisInfoText = "Analyzing S\(Self.sampleScaleDescription(requestedSampleScalePercent))"
        analysisTiming = HostAnalysisTimingAccumulator()
        bumpRevisionLocked()
        lock.unlock()
    }

    func sampleSize(for sourceInfo: StabilizerSourceFrameInfo) -> (width: Int, height: Int) {
        lock.lock()
        let scalePercent = activeRequestedSampleScalePercent
        lock.unlock()
        return AutoStabilizationEstimator.sampleSize(
            sourceWidth: sourceInfo.sourceWidth,
            sourceHeight: sourceInfo.sourceHeight,
            scalePercent: scalePercent
        )
    }

    func markRequested(requestedSampleScalePercent: Double) {
        lock.lock()
        if preparedAnalysis == nil && status != .analyzing {
            status = .requested
            activeRequestedSampleScalePercent = requestedSampleScalePercent
            analysisInfoText = "Requested S\(Self.sampleScaleDescription(requestedSampleScalePercent))"
            bumpRevisionLocked()
        }
        lock.unlock()
    }

    func markQueued(position: Int, totalCount: Int, reason: String, requestedSampleScalePercent: Double) {
        lock.lock()
        if preparedAnalysis == nil {
            status = .queued
            activeRequestedSampleScalePercent = requestedSampleScalePercent
            let queueTotal = max(position, totalCount)
            analysisInfoText = "Queued #\(position)/\(queueTotal) S\(Self.sampleScaleDescription(requestedSampleScalePercent)): \(Self.compactReason(reason))"
            bumpRevisionLocked()
        }
        lock.unlock()
    }

    func markStartFailed(reason: String) {
        lock.lock()
        if preparedAnalysis == nil {
            status = .needsAnalysis
            analysisInfoText = "Start failed: \(Self.compactReason(reason))"
            bumpRevisionLocked()
        }
        lock.unlock()
    }

    func markExternalAnalysisRequired(reason: String) {
        lock.lock()
        if preparedAnalysis == nil {
            status = .externalAnalysisRequired
            analysisInfoText = "Run Event Analyzer: \(Self.compactReason(reason))"
            bumpRevisionLocked()
        }
        lock.unlock()
    }

    func markExternalCacheManaged(reason: String) {
        lock.lock()
        status = .externalCacheManaged
        analysisInfoText = "Use Event Analyzer: \(Self.compactReason(reason))"
        bumpRevisionLocked()
        lock.unlock()
    }

    func markProjectCacheUnavailable(reason: String) {
        lock.lock()
        let statusText = Self.projectCacheUnavailableStatusText(for: reason)
        projectCacheUnavailableReason = reason
        if preparedAnalysis == nil {
            status = .projectCacheUnavailable
            projectCacheUnavailableStatusText = statusText
            analysisInfoText = "\(statusText). \(reason)"
            bumpRevisionLocked()
        } else {
            projectCacheUnavailableStatusText = statusText
        }
        lock.unlock()
        NSLog("TokyoWalkingStabilizer: project bundle Host Analysis cache unavailable: \(reason)")
    }

    func noteProjectCacheUnavailable(reason: String) {
        lock.lock()
        projectCacheUnavailableStatusText = Self.projectCacheUnavailableStatusText(for: reason)
        projectCacheUnavailableReason = reason
        lock.unlock()
        NSLog("TokyoWalkingStabilizer: noted project bundle Host Analysis cache unavailable for active session: \(reason)")
    }

    private static func projectCacheUnavailableStatusText(for reason: String) -> String {
        if reason.localizedCaseInsensitiveContains("Ambiguous Event") {
            return stabilizerAmbiguousEventCacheUnavailableMessage
        }
        if reason.localizedCaseInsensitiveContains("Ambiguous active Final Cut libraries") {
            return stabilizerAmbiguousActiveLibrariesCacheUnavailableMessage
        }
        return stabilizerProjectCacheUnavailableMessage
    }

    func reset(removePersistentCache shouldRemovePersistentCache: Bool = false) {
        removeLegacyAnalysisScratchDirectory()
        lock.lock()
        framesByTimeKey.removeAll(keepingCapacity: true)
        streamingAnalysisBuilder = nil
        preparedAnalysis = nil
        activeCompletedMemoryAnalysisIdentity = nil
        persistentCacheCandidates.removeAll(keepingCapacity: false)
        activePersistentCacheFileName = nil
        activePersistentCacheIdentity = nil
        activeRange = .invalid
        activeFrameDuration = .invalid
        activeRequestedSampleScalePercent = StabilizerSampleScale.defaultScale.percent
        renderToAnalysisOffsetSeconds = nil
        renderToAnalysisOffsetProbeAttempted = false
        finished = false
        validationState = .notRequired
        status = .needsAnalysis
        projectCacheUnavailableStatusText = stabilizerProjectCacheUnavailableMessage
        projectCacheUnavailableReason = nil
        latestSourceFrameInfo = nil
        latestSampleSize = nil
        analysisInfoText = "No Analysis"
        analysisTiming = HostAnalysisTimingAccumulator()
        bumpRevisionLocked()
        lock.unlock()
        if shouldRemovePersistentCache {
            removePersistentCache(logFailures: true)
        }
    }

    func clearPersistentCache() {
        removeLegacyAnalysisScratchDirectory()
        lock.lock()
        framesByTimeKey.removeAll(keepingCapacity: true)
        streamingAnalysisBuilder = nil
        preparedAnalysis = nil
        activeCompletedMemoryAnalysisIdentity = nil
        completedMemoryAnalysesByIdentity.removeAll(keepingCapacity: false)
        completedMemoryAnalysisIdentitiesByRangeKey.removeAll(keepingCapacity: false)
        completedMemoryAnalysisOrder.removeAll(keepingCapacity: false)
        rejectedCompletedMemoryAnalysisIdentities.removeAll(keepingCapacity: false)
        persistentCachesByIdentity.removeAll(keepingCapacity: false)
        persistentCacheCandidates.removeAll(keepingCapacity: false)
        activePersistentCacheFileName = nil
        activePersistentCacheIdentity = nil
        rejectedPersistentCacheFileNames.removeAll(keepingCapacity: false)
        activeRange = .invalid
        activeFrameDuration = .invalid
        activeRequestedSampleScalePercent = StabilizerSampleScale.defaultScale.percent
        renderToAnalysisOffsetSeconds = nil
        renderToAnalysisOffsetProbeAttempted = false
        finished = false
        validationState = .notRequired
        status = .cacheCleared
        projectCacheUnavailableStatusText = stabilizerProjectCacheUnavailableMessage
        projectCacheUnavailableReason = nil
        latestSourceFrameInfo = nil
        latestSampleSize = nil
        analysisInfoText = "Cache Cleared"
        analysisTiming = HostAnalysisTimingAccumulator()
        bumpRevisionLocked()
        lock.unlock()
        removePersistentCache(logFailures: true)
        Self.bumpPersistentCacheGeneration()
        NSLog("TokyoWalkingStabilizer: cleared persisted Host Analysis cache set.")
    }

    func rejectProxyAnalysis(reason: String) {
        removeLegacyAnalysisScratchDirectory()
        lock.lock()
        framesByTimeKey.removeAll(keepingCapacity: true)
        streamingAnalysisBuilder = nil
        preparedAnalysis = nil
        activeCompletedMemoryAnalysisIdentity = nil
        persistentCacheCandidates.removeAll(keepingCapacity: false)
        activePersistentCacheFileName = nil
        activePersistentCacheIdentity = nil
        activeRange = .invalid
        activeFrameDuration = .invalid
        activeRequestedSampleScalePercent = StabilizerSampleScale.defaultScale.percent
        renderToAnalysisOffsetSeconds = nil
        renderToAnalysisOffsetProbeAttempted = false
        finished = false
        validationState = .notRequired
        status = .proxyRejected
        projectCacheUnavailableStatusText = stabilizerProjectCacheUnavailableMessage
        projectCacheUnavailableReason = nil
        analysisInfoText = "Proxy rejected. Use original media."
        analysisTiming = HostAnalysisTimingAccumulator()
        bumpRevisionLocked()
        lock.unlock()
        NSLog("TokyoWalkingStabilizer: rejected Host Analysis proxy media: \(reason)")
    }

    func append(_ sample: StabilizerAnalysisSample, sourceInfo: StabilizerSourceFrameInfo?) throws {
        let key = Self.timeKey(sample.time)
        lock.lock()
        if framesByTimeKey[key] != nil {
            lock.unlock()
            return
        }
        if streamingAnalysisBuilder == nil {
            streamingAnalysisBuilder = StreamingStabilizationAnalysisBuilder()
        }
        let builder = streamingAnalysisBuilder
        lock.unlock()

        guard let builder else {
            throw NSError(
                domain: "com.justadev.TokyoWalkingStabilizer",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: "Stabilizer streaming analysis builder was unavailable."]
            )
        }
        let appendResult = try builder.append(sample)

        lock.lock()
        analysisTiming.record(sample: sample, metricsMilliseconds: appendResult.metricsMilliseconds)
        if let pairTiming = appendResult.pairTiming {
            analysisTiming.record(pairTiming: pairTiming)
        }

        framesByTimeKey[key] = appendResult.frame.withoutRetainedPixels()
        latestSampleSize = (appendResult.frame.sampleWidth, appendResult.frame.sampleHeight)
        if let sourceInfo {
            latestSourceFrameInfo = sourceInfo
        }
        lock.unlock()
    }

    func finish() throws {
        let finishStartedAt = CFAbsoluteTimeGetCurrent()
        var persistMilliseconds = 0.0
        do {
            try rebuildPreparedAnalysis(markFinished: true)
            try validateCompletedFrameCoverage()
            markAnalysisCompleted()
            let persistStartedAt = CFAbsoluteTimeGetCurrent()
            persistIfCompleted()
            persistMilliseconds = (CFAbsoluteTimeGetCurrent() - persistStartedAt) * 1000.0
            releaseRetainedAnalysisPixels()
            removeLegacyAnalysisScratchDirectory()
            recordFinishTiming(
                finishMilliseconds: (CFAbsoluteTimeGetCurrent() - finishStartedAt) * 1000.0,
                persistMilliseconds: persistMilliseconds
            )
            logTimingSummary(label: "completed")
        } catch {
            lock.lock()
            preparedAnalysis = nil
            streamingAnalysisBuilder = nil
            finished = false
            status = error.localizedDescription.contains("incomplete frame coverage") ? .cacheIncomplete : .needsAnalysis
            analysisInfoText = "Analysis failed: \(Self.compactReason(error.localizedDescription))"
            bumpRevisionLocked()
            lock.unlock()
            removeLegacyAnalysisScratchDirectory()
            NSLog("TokyoWalkingStabilizer: Metal Host Analysis preparation failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func recordFinishTiming(finishMilliseconds: Double, persistMilliseconds: Double) {
        lock.lock()
        analysisTiming.finishMilliseconds = finishMilliseconds
        analysisTiming.persistMilliseconds = persistMilliseconds
        lock.unlock()
    }

    private func recordCacheLoadTiming(candidateCount: Int, decodeMilliseconds: Double) {
        lock.lock()
        analysisTiming.record(cacheTiming: PersistentCacheLoadTiming(
            candidateCount: candidateCount,
            decodeMilliseconds: decodeMilliseconds
        ))
        lock.unlock()
    }

    private func logTimingSummary(label: String) {
        lock.lock()
        let timing = analysisTiming
        lock.unlock()
        os_log(
            "Host Analysis timing summary %{public}@ frames=%{public}d downsample=%{public}.3f ms blur+fingerprint=%{public}.3f ms pairs=%{public}d global=%{public}.3f ms local=%{public}.3f ms pair=%{public}.3f ms cacheCandidates=%{public}d cacheDecode=%{public}.3f ms persist=%{public}.3f ms finish=%{public}.3f ms.",
            log: stabilizerHostAnalysisLog,
            type: .default,
            label,
            timing.downsampleFrameCount,
            timing.downsampleMilliseconds,
            timing.blurMilliseconds,
            timing.motionPairCount,
            timing.globalShiftMilliseconds,
            timing.localBatchShiftMilliseconds,
            timing.pairMotionMilliseconds,
            timing.cacheCandidateCount,
            timing.cacheDecodeMilliseconds,
            timing.persistMilliseconds,
            timing.finishMilliseconds
        )
        NSLog(
            "TokyoWalkingStabilizer: Host Analysis timing summary %@ frames=%d downsample=%.3f ms blur+fingerprint=%.3f ms pairs=%d global=%.3f ms local=%.3f ms pair=%.3f ms cacheCandidates=%d cacheDecode=%.3f ms persist=%.3f ms finish=%.3f ms.",
            label,
            timing.downsampleFrameCount,
            timing.downsampleMilliseconds,
            timing.blurMilliseconds,
            timing.motionPairCount,
            timing.globalShiftMilliseconds,
            timing.localBatchShiftMilliseconds,
            timing.pairMotionMilliseconds,
            timing.cacheCandidateCount,
            timing.cacheDecodeMilliseconds,
            timing.persistMilliseconds,
            timing.finishMilliseconds
        )
    }

    func installCompletedAnalysis(from completedStore: StabilizerHostAnalysisStore) {
        let snapshot = completedStore.completedAnalysisSnapshot()
        lock.lock()
        installCompletedAnalysisLocked(snapshot)
        activeCompletedMemoryAnalysisIdentity = retainCompletedMemoryAnalysisLocked(snapshot)
        bumpRevisionLocked()
        lock.unlock()
        NSLog("TokyoWalkingStabilizer: installed completed Host Analysis session with \(snapshot.frames.count) frame(s) into shared render store.")
    }

    private func installCompletedAnalysisLocked(
        _ snapshot: CompletedHostAnalysisSnapshot,
        validationStateOverride: HostAnalysisValidationState? = nil
    ) {
        framesByTimeKey = Dictionary(uniqueKeysWithValues: snapshot.frames.map { (Self.timeKey($0.time), $0) })
        streamingAnalysisBuilder = nil
        preparedAnalysis = snapshot.preparedAnalysis
        activeCompletedMemoryAnalysisIdentity = nil
        persistentCacheCandidates.removeAll(keepingCapacity: false)
        activePersistentCacheFileName = nil
        activePersistentCacheIdentity = snapshot.activePersistentCacheIdentity
        rejectedPersistentCacheFileNames.removeAll(keepingCapacity: true)
        activeRange = snapshot.activeRange
        activeFrameDuration = snapshot.activeFrameDuration
        activeRequestedSampleScalePercent = snapshot.activeRequestedSampleScalePercent
        renderToAnalysisOffsetSeconds = nil
        renderToAnalysisOffsetProbeAttempted = false
        finished = snapshot.finished
        validationState = validationStateOverride ?? snapshot.validationState
        status = snapshot.status
        projectCacheUnavailableStatusText = snapshot.projectCacheUnavailableStatusText
        projectCacheUnavailableReason = snapshot.projectCacheUnavailableReason
        latestSourceFrameInfo = snapshot.latestSourceFrameInfo
        latestSampleSize = snapshot.latestSampleSize
        analysisInfoText = snapshot.analysisInfoText
    }

    private func retainCompletedMemoryAnalysisLocked(_ snapshot: CompletedHostAnalysisSnapshot) -> String? {
        guard snapshot.finished,
              snapshot.preparedAnalysis != nil,
              snapshot.activePersistentCacheIdentity == nil,
              let rangeKey = Self.completedMemoryAnalysisRangeKey(range: snapshot.activeRange),
              let identity = Self.completedMemoryAnalysisIdentity(snapshot: snapshot, rangeKey: rangeKey)
        else {
            return nil
        }
        completedMemoryAnalysesByIdentity[identity] = CompletedMemoryHostAnalysis(
            identity: identity,
            rangeKey: rangeKey,
            snapshot: snapshot
        )
        var rangeIdentities = completedMemoryAnalysisIdentitiesByRangeKey[rangeKey] ?? []
        rangeIdentities.removeAll { $0 == identity }
        rangeIdentities.append(identity)
        completedMemoryAnalysisIdentitiesByRangeKey[rangeKey] = rangeIdentities
        completedMemoryAnalysisOrder.removeAll { $0 == identity }
        completedMemoryAnalysisOrder.append(identity)
        rejectedCompletedMemoryAnalysisIdentities.remove(identity)
        while completedMemoryAnalysisOrder.count > Self.maxCompletedMemoryAnalyses,
              let evictedIdentity = completedMemoryAnalysisOrder.first {
            completedMemoryAnalysisOrder.removeFirst()
            if let evicted = completedMemoryAnalysesByIdentity.removeValue(forKey: evictedIdentity) {
                completedMemoryAnalysisIdentitiesByRangeKey[evicted.rangeKey]?.removeAll { $0 == evictedIdentity }
                if completedMemoryAnalysisIdentitiesByRangeKey[evicted.rangeKey]?.isEmpty == true {
                    completedMemoryAnalysisIdentitiesByRangeKey.removeValue(forKey: evicted.rangeKey)
                }
            }
            rejectedCompletedMemoryAnalysisIdentities.remove(evictedIdentity)
        }
        return identity
    }

    private func activateCompletedMemoryAnalysisIfNeeded(expectedRange: HostAnalysisExpectedRange) -> Bool {
        guard let expectedKey = Self.completedMemoryAnalysisRangeKey(expectedRange: expectedRange) else {
            return false
        }
        lock.lock()
        if activePersistentCacheIdentity == nil,
           finished,
           preparedAnalysis != nil,
           Self.completedMemoryAnalysisRangeKey(range: activeRange) == expectedKey {
            lock.unlock()
            return true
        }
        guard let memoryAnalysis = nextCompletedMemoryAnalysisLocked(rangeKey: expectedKey) else {
            lock.unlock()
            return false
        }
        installCompletedAnalysisLocked(memoryAnalysis.snapshot, validationStateOverride: .pending)
        activeCompletedMemoryAnalysisIdentity = memoryAnalysis.identity
        bumpRevisionLocked()
        lock.unlock()
        os_log(
            "Activated in-memory Host Analysis for expected range key %{public}@ identity %{public}@.",
            log: stabilizerHostAnalysisLog,
            type: .default,
            expectedKey,
            memoryAnalysis.identity
        )
        return true
    }

    func preparedAnalysisForRender(
        validating sourceImage: FxImageTile,
        at renderTime: CMTime,
        preferredCacheIdentity: String?,
        expectedRange: HostAnalysisExpectedRange?
    ) -> StabilizerPreparedAnalysis? {
        if let unavailableReason = StabilizerOriginalMediaPolicy.sourceUnavailableReason(for: sourceImage) {
            markSourceUnavailableForRender(reason: unavailableReason)
            os_log(
                "Render could not validate Host Analysis cache because the source frame is unavailable. reason=%{public}@ expectedRange=%{public}@.",
                log: stabilizerHostAnalysisLog,
                type: .error,
                unavailableReason,
                Self.expectedRangeDescription(expectedRange)
            )
            NSLog("TokyoWalkingStabilizer: source frame unavailable during render: \(unavailableReason)")
            return nil
        }

        let preferredIdentity = preferredCacheIdentity?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let preferredIdentity,
           !preferredIdentity.isEmpty {
            _ = activatePersistentCache(identity: preferredIdentity, expectedRange: expectedRange, allowRangeMismatch: true)
        }
        if let expectedRange, expectedRange.isValid {
            _ = activateCompletedMemoryAnalysisIfNeeded(expectedRange: expectedRange)
        }

        while true {
            if shouldReloadPersistentCacheForConsumer(), loadPersistentCache(expectedRange: expectedRange, allowRangeMismatch: true) {
                continue
            }
            guard let analysis = preparedAnalysisSnapshot() else {
                guard activateNextPersistentCache(afterRejecting: nil, expectedRange: expectedRange, allowRangeMismatch: true)
                    || loadPersistentCache(expectedRange: expectedRange, allowRangeMismatch: true)
                else {
                    return nil
                }
                continue
            }

            let state = currentValidationState()
            if state == .rejected {
                return nil
            }

            let activeIdentity = activeCacheIdentity
            if let activeIdentity,
               !Self.cacheIdentity(activeIdentity, matches: expectedRange) {
                let explicitPreferredIdentityMatchesActive = preferredIdentity == activeIdentity
                if explicitPreferredIdentityMatchesActive,
                   Self.cacheIdentityDurationMatches(activeIdentity, expectedRange: expectedRange) {
                    installExplicitRenderTimeMappingIfNeeded(
                        renderTime: renderTime,
                        expectedRange: expectedRange,
                        analysis: analysis
                    )
                }
                if state == .validated || state == .notRequired {
                    markReadyAfterOriginalMediaReturnedIfNeeded()
                    return analysis
                }
                if let validationIssue = StabilizerOriginalMediaPolicy.originalMediaValidationIssue(for: sourceImage) {
                    let canUseExplicitPreferredIdentity = explicitPreferredIdentityMatchesActive
                        && Self.cacheIdentityDurationMatches(activeIdentity, expectedRange: expectedRange)
                    let mappedRenderSeconds = CMTimeGetSeconds(analysisRenderTime(for: renderTime, preparedAnalysis: analysis))
                    if (Self.cacheIdentityStartMatches(activeIdentity, expectedRange: expectedRange) || canUseExplicitPreferredIdentity),
                       Self.renderSeconds(mappedRenderSeconds, isInside: analysis.frames) {
                        if unvalidatedPreviewStatusIsAlreadyActive(isScaledProxy: validationIssue.isScaledProxy) {
                            return analysis
                        }
                        os_log(
                            "Using explicit range-mismatched Host Analysis cache before original-frame validation. identity=%{public}@ expectedRange=%{public}@ explicitPreferred=%{public}@ reason=%{public}@.",
                            log: stabilizerHostAnalysisLog,
                            type: .default,
                            activeIdentity,
                            Self.expectedRangeDescription(expectedRange),
                            canUseExplicitPreferredIdentity ? "yes" : "no",
                            validationIssue.reason
                        )
                        if validationIssue.isScaledProxy {
                            markProxyPreviewForRender(reason: validationIssue.reason)
                        } else {
                            markSourceMetadataUnconfirmedPreviewForRender(reason: validationIssue.reason)
                        }
                        return analysis
                    }
                    markProxyNeedsOriginalValidationForRender(reason: validationIssue.reason)
                    return nil
                }
                if let rejectionReason = persistentCacheRejectionReason(for: analysis, validating: sourceImage, at: renderTime) {
                    guard activateNextPersistentCache(afterRejecting: rejectionReason, expectedRange: expectedRange, allowRangeMismatch: true) else {
                        if let validationIssue = StabilizerOriginalMediaPolicy.originalMediaValidationIssue(for: sourceImage) {
                            let canUseExplicitPreferredIdentity = explicitPreferredIdentityMatchesActive
                                && Self.cacheIdentityDurationMatches(activeIdentity, expectedRange: expectedRange)
                            let mappedRenderSeconds = CMTimeGetSeconds(analysisRenderTime(for: renderTime, preparedAnalysis: analysis))
                            if (Self.cacheIdentityStartMatches(activeIdentity, expectedRange: expectedRange) || canUseExplicitPreferredIdentity),
                               Self.renderSeconds(mappedRenderSeconds, isInside: analysis.frames) {
                                os_log(
                                    "Using explicit range-mismatched Host Analysis cache before original-frame validation. identity=%{public}@ expectedRange=%{public}@ explicitPreferred=%{public}@ reason=%{public}@ validation=%{public}@.",
                                    log: stabilizerHostAnalysisLog,
                                    type: .default,
                                    activeIdentity,
                                    Self.expectedRangeDescription(expectedRange),
                                    canUseExplicitPreferredIdentity ? "yes" : "no",
                                    validationIssue.reason,
                                    rejectionReason
                                )
                                if validationIssue.isScaledProxy {
                                    markProxyPreviewForRender(reason: validationIssue.reason)
                                } else {
                                    markSourceMetadataUnconfirmedPreviewForRender(reason: validationIssue.reason)
                                }
                                return analysis
                            }
                            os_log(
                                "Range-mismatched Host Analysis cache could not be validated against the current source frame. identity=%{public}@ expectedRange=%{public}@ reason=%{public}@ validation=%{public}@.",
                                log: stabilizerHostAnalysisLog,
                                type: .error,
                                activeIdentity,
                                Self.expectedRangeDescription(expectedRange),
                                validationIssue.reason,
                                rejectionReason
                            )
                            markProxyNeedsOriginalValidationForRender(reason: validationIssue.reason)
                            return nil
                        }
                        rejectPersistentCache(reason: rejectionReason)
                        return nil
                    }
                    continue
                } else {
                    lock.lock()
                    validationState = .validated
                    if status != .projectCacheUnavailable {
                        status = .ready
                    }
                    bumpRevisionLocked()
                    lock.unlock()
                    os_log(
                        "Accepted range-mismatched Host Analysis cache after source-frame fingerprint validation. identity=%{public}@ expectedRange=%{public}@.",
                        log: stabilizerHostAnalysisLog,
                        type: .default,
                        activeIdentity,
                        Self.expectedRangeDescription(expectedRange)
                    )
                    releaseRetainedAnalysisPixels()
                    return analysis
                }
            }
            if activeIdentity == nil,
               let expectedRange,
               expectedRange.isValid,
               activeCompletedMemoryAnalysisDoesNotMatch(expectedRange: expectedRange) {
                deactivateActiveCompletedMemoryAnalysisForRangeMismatch()
                if activateCompletedMemoryAnalysisIfNeeded(expectedRange: expectedRange) {
                    continue
                }
                if activateNextPersistentCache(afterRejecting: nil, expectedRange: expectedRange, allowRangeMismatch: true) {
                    continue
                }
                if loadPersistentCache(expectedRange: expectedRange, allowRangeMismatch: true) {
                    continue
                }
                return nil
            }

            if let validationIssue = StabilizerOriginalMediaPolicy.originalMediaValidationIssue(for: sourceImage) {
                if let activeIdentity,
                   Self.cacheIdentity(activeIdentity, matches: expectedRange) {
                    if validationIssue.isScaledProxy {
                        markProxyPreviewForRender(reason: validationIssue.reason)
                    } else {
                        markSourceMetadataUnconfirmedPreviewForRender(reason: validationIssue.reason)
                    }
                    updateRenderTimeMappingIfNeeded(for: analysis, validating: sourceImage, at: renderTime)
                    NSLog("TokyoWalkingStabilizer: using range-matched Host Analysis cache before source-frame validation: \(validationIssue.reason)")
                    return analysis
                }
                if activeIdentity == nil,
                   hasCompletedInMemoryAnalysis {
                    if validationIssue.isScaledProxy {
                        markProxyPreviewForRender(reason: validationIssue.reason)
                    } else {
                        markSourceMetadataUnconfirmedPreviewForRender(reason: validationIssue.reason)
                    }
                    updateRenderTimeMappingIfNeeded(for: analysis, validating: sourceImage, at: renderTime)
                    os_log("Using in-memory Host Analysis for render before source-frame validation: %{public}@",
                           log: stabilizerHostAnalysisLog,
                           type: .default,
                           validationIssue.reason)
                    return analysis
                }

                markProxyNeedsOriginalValidationForRender(reason: validationIssue.reason)
                return nil
            }

            if state == .validated || state == .notRequired {
                markReadyAfterOriginalMediaReturnedIfNeeded()
                updateRenderTimeMappingIfNeeded(for: analysis, validating: sourceImage, at: renderTime)
                return analysis
            }

            if let rejectionReason = persistentCacheRejectionReason(for: analysis, validating: sourceImage, at: renderTime) {
                if activateNextCompletedMemoryAnalysis(afterRejecting: rejectionReason, expectedRange: expectedRange) {
                    continue
                }
                guard activateNextPersistentCache(afterRejecting: rejectionReason, expectedRange: expectedRange, allowRangeMismatch: true) else {
                    if activeIdentity == nil {
                        rejectActiveInMemoryAnalysis(reason: rejectionReason)
                        return nil
                    }
                    rejectPersistentCache(reason: rejectionReason)
                    return nil
                }
                continue
            }

            lock.lock()
            if validationState == .pending {
                validationState = .validated
                if status != .projectCacheUnavailable {
                    status = .ready
                }
                bumpRevisionLocked()
            }
            lock.unlock()
            NSLog("TokyoWalkingStabilizer: validated persisted Host Analysis cache with \(analysis.frames.count) frames.")
            releaseRetainedAnalysisPixels()
            return analysis
        }
    }

    func noteSourceUnavailableForRender(reason: String) {
        markSourceUnavailableForRender(reason: reason)
    }

    func noteMediaLinkInvalidForRender(reason: String) {
        markRenderStatus(.mediaLinkInvalid, info: "Media link invalid.", logReason: reason)
    }

    func noteLoadedButNotRenderingForRender(reason: String) {
        markRenderStatus(.loadedButNotRendering, info: "Loaded cache did not render.", logReason: reason)
    }

    func noteCacheRangeMismatchForRender(reason: String) {
        markRenderStatus(.cacheRangeMismatch, info: "Cache range mismatch.", logReason: reason)
    }

    private func installExplicitRenderTimeMappingIfNeeded(
        renderTime: CMTime,
        expectedRange: HostAnalysisExpectedRange?,
        analysis: StabilizerPreparedAnalysis
    ) {
        guard let expectedRange,
              expectedRange.isValid,
              !analysis.frames.isEmpty
        else {
            return
        }
        let renderSeconds = CMTimeGetSeconds(renderTime)
        guard renderSeconds.isFinite else {
            return
        }
        let mappedOffset: Double
        let mappingReason: String
        if Self.renderSeconds(renderSeconds, isInside: analysis.frames) {
            mappedOffset = 0.0
            mappingReason = "render time already inside analysis range"
        } else {
            let cacheRangeStart = CMTimeGetSeconds(activeRange.start)
            guard cacheRangeStart.isFinite,
                  expectedRange.startSeconds.isFinite
            else {
                return
            }
            mappedOffset = cacheRangeStart - expectedRange.startSeconds
            mappingReason = "render time outside analysis range; using expected source start"
        }
        let mappedSeconds = renderSeconds + mappedOffset
        guard Self.renderSeconds(mappedSeconds, isInside: analysis.frames) else {
            os_log(
                "Explicit Host Analysis render-time mapping rejected because mapped time is outside the prepared frame range. render=%.6f offset=%.6f mapped=%.6f expectedRange=%{public}@ reason=%{public}@.",
                log: stabilizerHostAnalysisLog,
                type: .error,
                renderSeconds,
                mappedOffset,
                mappedSeconds,
                Self.expectedRangeDescription(expectedRange),
                mappingReason
            )
            return
        }
        lock.lock()
        let previousOffset = renderToAnalysisOffsetSeconds
        let shouldPublish = previousOffset == nil || abs((previousOffset ?? 0.0) - mappedOffset) > 1e-9
        renderToAnalysisOffsetSeconds = mappedOffset
        renderToAnalysisOffsetProbeAttempted = true
        lock.unlock()
        if shouldPublish {
            os_log(
                "Installed explicit Host Analysis render-time mapping. render=%.6f offset=%.6f mapped=%.6f expectedRange=%{public}@ reason=%{public}@.",
                log: stabilizerHostAnalysisLog,
                type: .default,
                renderSeconds,
                mappedOffset,
                mappedSeconds,
                Self.expectedRangeDescription(expectedRange),
                mappingReason
            )
        }
    }

    func noteStabilizationActiveForRender(debugOverlayActive: Bool, reason: String) {
        markRenderStatus(
            debugOverlayActive ? .debugOverlayActive : .stabilizationActive,
            info: debugOverlayActive ? "Debug overlay active; prepared analysis rendering." : "Prepared analysis rendering.",
            logReason: reason
        )
    }

    func analysisRenderTime(for renderTime: CMTime, preparedAnalysis analysis: StabilizerPreparedAnalysis) -> CMTime {
        let renderSeconds = CMTimeGetSeconds(renderTime)
        guard renderSeconds.isFinite else {
            return renderTime
        }
        lock.lock()
        let offsetSeconds = renderToAnalysisOffsetSeconds
        lock.unlock()
        if let offsetSeconds, offsetSeconds.isFinite {
            let mappedSeconds = Self.clampedAnalysisSeconds(renderSeconds + offsetSeconds, frames: analysis.frames)
            let preferredTimescale = renderTime.timescale > 0 ? renderTime.timescale : CMTimeScale(600)
            return CMTime(seconds: mappedSeconds, preferredTimescale: preferredTimescale)
        }
        let mappedSeconds = mappedAnalysisSeconds(forRenderSeconds: renderSeconds, frames: analysis.frames)
        guard mappedSeconds.isFinite, abs(mappedSeconds - renderSeconds) > 1e-9 else {
            return renderTime
        }
        let preferredTimescale = renderTime.timescale > 0 ? renderTime.timescale : CMTimeScale(600)
        return CMTime(seconds: mappedSeconds, preferredTimescale: preferredTimescale)
    }

    @discardableResult
    func loadPersistentCache(expectedRange: HostAnalysisExpectedRange? = nil, allowRangeMismatch: Bool = false) -> Bool {
        defer {
            markCurrentPersistentCacheGenerationObserved()
        }
        var candidateURLs = filteredPersistentCacheCandidateURLs()
        var unusableCacheSummaries: [(status: HostAnalysisStatus, summary: String)] = []
        while !candidateURLs.isEmpty {
            let activeURL = candidateURLs.removeFirst()
            let candidateStartedAt = CFAbsoluteTimeGetCurrent()
            let loadAttempt = Self.loadPersistentCacheCandidate(at: activeURL)
            recordCacheLoadTiming(
                candidateCount: 1,
                decodeMilliseconds: (CFAbsoluteTimeGetCurrent() - candidateStartedAt) * 1000.0
            )
            let activeCandidate: LoadedPersistentHostAnalysisCache
            switch loadAttempt {
            case .loaded(let loadedCandidate):
                activeCandidate = loadedCandidate
            case .unusable(let status, let summary):
                unusableCacheSummaries.append((status, summary))
                continue
            case .skipped:
                continue
            }
            let matchesExpectedRange = Self.cache(activeCandidate.cache, matches: expectedRange)
            guard allowRangeMismatch || matchesExpectedRange else {
                NSLog("TokyoWalkingStabilizer: skipped Host Analysis cache \(activeCandidate.fileName) because its range does not match the active clip.")
                continue
            }
            if !matchesExpectedRange {
                os_log(
                    "Loaded range-mismatched Host Analysis cache %{public}@ for source-frame fingerprint validation. expectedRange=%{public}@.",
                    log: stabilizerHostAnalysisLog,
                    type: .default,
                    activeCandidate.fileName,
                    Self.expectedRangeDescription(expectedRange)
                )
            }
            lock.lock()
            installPersistentCacheLocked(activeCandidate)
            persistentCacheCandidates = candidateURLs
            analysisInfoText = Self.infoText(
                completedAt: Date(timeIntervalSince1970: activeCandidate.cache.createdAt),
                frameCount: activeCandidate.frames.count,
                sampleWidth: activeCandidate.cache.sampleWidth,
                sampleHeight: activeCandidate.cache.sampleHeight,
                requestedSampleScalePercent: nil,
                rangeStartSeconds: activeCandidate.cache.rangeStartSeconds,
                rangeEndSeconds: Self.rangeEndSeconds(for: activeCandidate.cache),
                sourceInfo: nil,
                prefix: "Loaded Cache",
                eventName: activeCandidate.cache.eventName ?? Self.currentProjectBundleCacheEventName,
                cacheIdentity: activeCandidate.identity
            )
            lock.unlock()
            NSLog("TokyoWalkingStabilizer: loaded persisted Host Analysis cache \(activeCandidate.fileName) with \(activeCandidate.frames.count) frames; \(candidateURLs.count) lazy alternate cache(s) available.")
            return true
        }
        if let unusableCacheSummary = unusableCacheSummaries.first {
            lock.lock()
            if preparedAnalysis == nil && status != .analyzing {
                status = unusableCacheSummary.status
                analysisInfoText = unusableCacheSummary.summary
                bumpRevisionLocked()
            }
            lock.unlock()
        }
        return false
    }

    func reloadPersistentCacheForConsumerIfNeeded(expectedRange: HostAnalysisExpectedRange? = nil, allowRangeMismatch: Bool = false) -> Bool {
        guard shouldReloadPersistentCacheForConsumer() else {
            return false
        }
        return loadPersistentCache(expectedRange: expectedRange, allowRangeMismatch: allowRangeMismatch)
    }

    func activatePersistentCache(identity: String, expectedRange: HostAnalysisExpectedRange? = nil, allowRangeMismatch: Bool = false) -> Bool {
        let trimmedIdentity = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentity.isEmpty else {
            return false
        }
        guard allowRangeMismatch || Self.cacheIdentity(trimmedIdentity, matches: expectedRange) else {
            return false
        }

        lock.lock()
        if activePersistentCacheIdentity == trimmedIdentity,
           preparedAnalysis != nil {
            lock.unlock()
            return true
        }
        if let cached = persistentCachesByIdentity[trimmedIdentity] {
            installPersistentCacheLocked(cached)
            lock.unlock()
            markCurrentPersistentCacheGenerationObserved()
            NSLog("TokyoWalkingStabilizer: reactivated Host Analysis cache \(cached.fileName) by saved clip identity.")
            return true
        }
        lock.unlock()

        for candidateURL in Self.persistentCacheCandidateURLs() {
            guard let candidate = Self.loadPersistentCache(at: candidateURL),
                  candidate.identity == trimmedIdentity,
                  (allowRangeMismatch || Self.cache(candidate.cache, matches: expectedRange))
            else {
                continue
            }
            lock.lock()
            installPersistentCacheLocked(candidate)
            persistentCacheCandidates.removeAll { $0.lastPathComponent == candidate.fileName }
            lock.unlock()
            markCurrentPersistentCacheGenerationObserved()
            NSLog("TokyoWalkingStabilizer: loaded Host Analysis cache \(candidate.fileName) by saved clip identity.")
            return true
        }
        return false
    }

    private func shouldReloadPersistentCacheForConsumer() -> Bool {
        let generation = Self.currentPersistentCacheGeneration()
        let signature = Self.currentPersistentCacheSignature()
        lock.lock()
        let cacheChanged = observedPersistentCacheSignature != signature
            || observedPersistentCacheGeneration < generation
        let needsInitialLoad = preparedAnalysis == nil
            && status != .cacheUnsupported
            && status != .cacheIncomplete
        let shouldReload = needsInitialLoad
            && (cacheChanged || persistentCacheCandidates.isEmpty)
            && status != .cacheRejected
        lock.unlock()
        return shouldReload
    }

    private func markCurrentPersistentCacheGenerationObserved() {
        let generation = Self.currentPersistentCacheGeneration()
        let signature = Self.currentPersistentCacheSignature()
        lock.lock()
        observedPersistentCacheGeneration = generation
        observedPersistentCacheSignature = signature
        lock.unlock()
    }

    private func markAnalysisCompleted() {
        let completedAt = Date()
        let snapshot: (
            frameCount: Int,
            sampleSize: (width: Int, height: Int)?,
            requestedSampleScalePercent: Double,
            range: CMTimeRange,
            sourceInfo: StabilizerSourceFrameInfo?
        ) = {
            lock.lock()
            let value = (
                framesByTimeKey.count,
                latestSampleSize,
                activeRequestedSampleScalePercent,
                activeRange,
                latestSourceFrameInfo
            )
            lock.unlock()
            return value
        }()
        let rangeStartSeconds = CMTimeGetSeconds(snapshot.range.start)
        let rangeDurationSeconds = CMTimeGetSeconds(snapshot.range.duration)
        let rangeEndSeconds = rangeStartSeconds + rangeDurationSeconds
        let info = Self.infoText(
            completedAt: completedAt,
            frameCount: snapshot.frameCount,
            sampleWidth: snapshot.sampleSize?.width,
            sampleHeight: snapshot.sampleSize?.height,
            requestedSampleScalePercent: snapshot.requestedSampleScalePercent,
            rangeStartSeconds: rangeStartSeconds,
            rangeEndSeconds: rangeEndSeconds,
            sourceInfo: snapshot.sourceInfo,
            prefix: "Analyzed"
        )
        lock.lock()
        analysisInfoText = info
        bumpRevisionLocked()
        lock.unlock()
    }

    private static func infoText(
        completedAt: Date,
        frameCount: Int,
        sampleWidth: Int?,
        sampleHeight: Int?,
        requestedSampleScalePercent: Double? = nil,
        rangeStartSeconds: Double? = nil,
        rangeEndSeconds: Double? = nil,
        sourceInfo: StabilizerSourceFrameInfo?,
        prefix: String,
        eventName: String? = nil,
        cacheIdentity: String? = nil
    ) -> String {
        let sampleText: String
        if let sampleWidth, let sampleHeight {
            sampleText = AutoStabilizationEstimator.sampleSizeDescription(width: sampleWidth, height: sampleHeight)
        } else {
            sampleText = "unknown"
        }
        var parts = [Self.compactPrefix(prefix), "\(frameCount)f", sampleText]
        if let requestedSampleScalePercent,
           requestedSampleScalePercent.isFinite {
            parts.append("S\(Self.sampleScaleDescription(requestedSampleScalePercent))")
        }
        return parts.joined(separator: " ")
    }

    private static func compactPrefix(_ prefix: String) -> String {
        switch prefix {
        case "Loaded Cache":
            return "Loaded"
        case "Saved Cache":
            return "Saved"
        default:
            return prefix
        }
    }

    private static func sampleScaleDescription(_ percent: Double) -> String {
        if percent.rounded() == percent {
            return String(format: "%.0f%%", percent)
        }
        return String(format: "%.2f%%", percent)
    }

    private static func clipRangeDescription(startSeconds: Double?, endSeconds: Double?) -> String? {
        guard let startSeconds,
              let endSeconds,
              startSeconds.isFinite,
              endSeconds.isFinite,
              endSeconds >= startSeconds
        else {
            return nil
        }
        return "\(compactSecondsDescription(startSeconds))-\(compactSecondsDescription(endSeconds))"
    }

    private static func compactSecondsDescription(_ seconds: Double) -> String {
        var text = String(format: "%.3f", seconds)
        while text.contains(".") && text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return "\(text)s"
    }

    private static func compactReason(_ reason: String, maxLength: Int = 48) -> String {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else {
            return trimmed
        }
        let index = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return String(trimmed[..<index]) + "..."
    }

    @discardableResult
    func persistCompletedAnalysisIfPossible() -> Bool {
        lock.lock()
        let shouldPersist = finished
            && preparedAnalysis != nil
            && activePersistentCacheIdentity == nil
            && validationState != .rejected
        lock.unlock()
        guard shouldPersist else {
            return false
        }
        return persistIfCompleted()
    }

    @discardableResult
    private func persistIfCompleted() -> Bool {
        let snapshot: (
            frames: [StabilizerAnalysisFrame],
            prepared: StabilizerPreparedAnalysis?,
            range: CMTimeRange,
            frameDuration: CMTime,
            requestedSampleScalePercent: Double,
            sourceInfo: StabilizerSourceFrameInfo?
        ) = {
            lock.lock()
            let frames = framesByTimeKey.values.sorted { $0.time < $1.time }
            let prepared = preparedAnalysis
            let range = activeRange
            let frameDuration = activeFrameDuration
            let requestedSampleScalePercent = activeRequestedSampleScalePercent
            let sourceInfo = latestSourceFrameInfo
            lock.unlock()
            return (frames, prepared, range, frameDuration, requestedSampleScalePercent, sourceInfo)
        }()

        guard let prepared = snapshot.prepared, prepared.frames.count >= 3 else {
            return false
        }
        guard let cacheDirectoryURL = Self.cacheDirectoryURL,
              let cacheStorageDirectoryURL = Self.cacheStorageDirectoryURL,
              let latestCacheURL = Self.cacheURL
        else {
            lock.lock()
            status = .projectCacheUnavailable
            let statusText = projectCacheUnavailableStatusText
            let reason = projectCacheUnavailableReason ?? "Host did not provide a writable Event Analysis Files cache root."
            analysisInfoText = "\(statusText): \(Self.compactReason(reason))"
            bumpRevisionLocked()
            lock.unlock()
            NSLog("TokyoWalkingStabilizer: failed to save Host Analysis cache because no FCP bundle cache root is configured.")
            return false
        }
        let framesToPersist = prepared.frames
        if snapshot.frames.count != framesToPersist.count {
            NSLog("TokyoWalkingStabilizer: persisting prepared Host Analysis frame set with \(framesToPersist.count) frames; retained frame map had \(snapshot.frames.count) frames.")
        }
        let firstFrameTime = framesToPersist.first?.time ?? 0.0
        let lastFrameTime = framesToPersist.last?.time ?? firstFrameTime
        let sampleWidth = framesToPersist.first?.sampleWidth ?? AutoStabilizationEstimator.defaultSampleWidth
        let sampleHeight = framesToPersist.first?.sampleHeight ?? AutoStabilizationEstimator.defaultSampleHeight
        let frameDurationSeconds = Self.validFrameDurationSeconds(snapshot.frameDuration, frames: framesToPersist)
        let suppliedRangeStartSeconds = CMTimeGetSeconds(snapshot.range.start)
        let suppliedRangeDurationSeconds = CMTimeGetSeconds(snapshot.range.duration)
        let rangeStartSeconds = suppliedRangeStartSeconds.isFinite ? suppliedRangeStartSeconds : firstFrameTime
        let rangeDurationSeconds = suppliedRangeDurationSeconds.isFinite
            ? suppliedRangeDurationSeconds
            : max(frameDurationSeconds, (lastFrameTime - firstFrameTime) + frameDurationSeconds)
        let rangeEndSeconds = rangeStartSeconds + rangeDurationSeconds
        let clipLabel = Self.defaultClipLabel
        let eventName = Self.currentProjectBundleCacheEventName

        let cache = PersistedHostAnalysisCache(
            schemaVersion: Self.cacheSchemaVersion,
            createdAt: Date().timeIntervalSince1970,
            clipLabel: clipLabel,
            rangeStartSeconds: rangeStartSeconds,
            rangeDurationSeconds: rangeDurationSeconds,
            rangeEndSeconds: rangeEndSeconds,
            frameDurationSeconds: frameDurationSeconds,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight,
            eventName: eventName,
            frames: framesToPersist.map {
                PersistedHostAnalysisFrame(
                    time: $0.time,
                    pixels: nil,
                    blurAmount: $0.blurAmount,
                    fingerprint: $0.fingerprint
                )
            },
            residuals: prepared.residuals,
            rollMotion: prepared.rollMotion,
            pathX: prepared.pathX,
            pathY: prepared.pathY,
            pathRoll: prepared.pathRoll,
            footstepPathX: prepared.footstepPathX,
            footstepPathY: prepared.footstepPathY,
            footstepPathRoll: prepared.footstepPathRoll,
            pathYaw: prepared.pathYaw,
            pathPitch: prepared.pathPitch,
            pathShearX: prepared.pathShearX,
            pathShearY: prepared.pathShearY,
            pathPerspectiveX: prepared.pathPerspectiveX,
            pathPerspectiveY: prepared.pathPerspectiveY,
            analysisConfidence: prepared.analysisConfidence,
            warpConfidence: prepared.warpConfidence,
            acceptedBlockCounts: prepared.acceptedBlockCounts,
            totalBlockCounts: prepared.totalBlockCounts,
            blurAmounts: prepared.blurAmounts,
            searchRadiusHitCounts: prepared.searchRadiusHitCounts,
            searchRadiusTotalCounts: prepared.searchRadiusTotalCounts
        )

        do {
            try FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cacheStorageDirectoryURL, withIntermediateDirectories: true)
            let cacheFileName = Self.persistentCacheFileName(for: cache, frames: framesToPersist)
            guard let cacheIdentity = Self.persistentCacheIdentity(for: cache, frames: framesToPersist) else {
                NSLog("TokyoWalkingStabilizer: failed to save Host Analysis cache because the prepared frame fingerprints were incomplete.")
                return false
            }
            let data = try JSONEncoder().encode(cache)
            let cacheURL = cacheStorageDirectoryURL.appendingPathComponent(cacheFileName, isDirectory: false)
            try data.write(to: cacheURL, options: .atomic)
            try data.write(to: latestCacheURL, options: .atomic)
            if let indexEntry = Self.indexEntry(for: cache, fileName: cacheFileName, frames: framesToPersist) {
                try Self.updatePersistentCacheIndex(with: indexEntry)
            }
            lock.lock()
            activePersistentCacheFileName = cacheFileName
            activePersistentCacheIdentity = cacheIdentity
            activeCompletedMemoryAnalysisIdentity = nil
            status = .ready
            projectCacheUnavailableStatusText = stabilizerProjectCacheUnavailableMessage
            projectCacheUnavailableReason = nil
            analysisInfoText = Self.infoText(
                completedAt: Date(timeIntervalSince1970: cache.createdAt),
                frameCount: framesToPersist.count,
                sampleWidth: sampleWidth,
                sampleHeight: sampleHeight,
                requestedSampleScalePercent: snapshot.requestedSampleScalePercent,
                rangeStartSeconds: cache.rangeStartSeconds,
                rangeEndSeconds: Self.rangeEndSeconds(for: cache),
                sourceInfo: snapshot.sourceInfo,
                prefix: "Saved Cache",
                eventName: eventName,
                cacheIdentity: cacheIdentity
            )
            bumpRevisionLocked()
            lock.unlock()
            Self.bumpPersistentCacheGeneration()
            NSLog("TokyoWalkingStabilizer: saved sample-size Host Analysis cache \(sampleWidth)x\(sampleHeight) with \(framesToPersist.count) prepared frames to \(cacheURL.path).")
            os_log(
                "Saved Host Analysis Event cache file %{public}@ for Event %{public}@ identity %{public}@.",
                log: stabilizerHostAnalysisLog,
                type: .default,
                cacheURL.lastPathComponent,
                eventName ?? "<unknown>",
                Self.shortCacheIdentity(cacheIdentity)
            )
            return true
        } catch {
            NSLog("TokyoWalkingStabilizer: failed to save Host Analysis cache: \(error.localizedDescription)")
            os_log("Failed to save Host Analysis Event cache: %{public}@.", log: stabilizerHostAnalysisLog, type: .error, error.localizedDescription)
            return false
        }
    }

    private func rebuildPreparedAnalysis(markFinished: Bool) throws {
        let snapshot: (frames: [StabilizerAnalysisFrame], builder: StreamingStabilizationAnalysisBuilder?) = {
            lock.lock()
            let value = (framesByTimeKey.values.sorted { $0.time < $1.time }, streamingAnalysisBuilder)
            lock.unlock()
            return value
        }()
        let prepared: StabilizerPreparedAnalysis?
        if snapshot.frames.count >= 3 {
            guard let builder = snapshot.builder else {
                throw NSError(
                    domain: "com.justadev.TokyoWalkingStabilizer",
                    code: Int(kFxError_AnalysisError),
                    userInfo: [NSLocalizedDescriptionKey: "Stabilizer streaming analysis was unavailable at finish."]
                )
            }
            prepared = try builder.preparedAnalysis()
        } else {
            prepared = nil
        }
        lock.lock()
        preparedAnalysis = prepared
        if markFinished {
            activePersistentCacheFileName = nil
            activePersistentCacheIdentity = nil
            streamingAnalysisBuilder = nil
        }
        if markFinished {
            finished = true
            status = prepared == nil ? .needsAnalysis : .ready
        }
        bumpRevisionLocked()
        lock.unlock()
    }

    private func releaseRetainedAnalysisPixels() {
        lock.lock()
        framesByTimeKey = framesByTimeKey.mapValues { $0.withoutRetainedPixels() }
        if let analysis = preparedAnalysis {
            preparedAnalysis = StabilizerPreparedAnalysis(
                frames: analysis.frames.map { $0.withoutRetainedPixels() },
                qualityModel: analysis.qualityModel,
                residuals: analysis.residuals,
                rollMotion: analysis.rollMotion,
                pathX: analysis.pathX,
                pathY: analysis.pathY,
                pathRoll: analysis.pathRoll,
                footstepPathX: analysis.footstepPathX,
                footstepPathY: analysis.footstepPathY,
                footstepPathRoll: analysis.footstepPathRoll,
                pathYaw: analysis.pathYaw,
                pathPitch: analysis.pathPitch,
                pathShearX: analysis.pathShearX,
                pathShearY: analysis.pathShearY,
                pathPerspectiveX: analysis.pathPerspectiveX,
                pathPerspectiveY: analysis.pathPerspectiveY,
                analysisConfidence: analysis.analysisConfidence,
                warpConfidence: analysis.warpConfidence,
                acceptedBlockCounts: analysis.acceptedBlockCounts,
                totalBlockCounts: analysis.totalBlockCounts,
                blurAmounts: analysis.blurAmounts,
                searchRadiusHitCounts: analysis.searchRadiusHitCounts,
                searchRadiusTotalCounts: analysis.searchRadiusTotalCounts
            )
        }
        lock.unlock()
    }

    private func preparedAnalysisSnapshot() -> StabilizerPreparedAnalysis? {
        lock.lock()
        let analysis = preparedAnalysis
        lock.unlock()
        return analysis
    }

    private func completedAnalysisSnapshot() -> CompletedHostAnalysisSnapshot {
        lock.lock()
        let snapshot = (
            frames: framesByTimeKey.values.sorted { $0.time < $1.time },
            preparedAnalysis: preparedAnalysis,
            activeRange: activeRange,
            activeFrameDuration: activeFrameDuration,
            activeRequestedSampleScalePercent: activeRequestedSampleScalePercent,
            finished: finished,
            validationState: validationState,
            status: status,
            projectCacheUnavailableStatusText: projectCacheUnavailableStatusText,
            projectCacheUnavailableReason: projectCacheUnavailableReason,
            latestSourceFrameInfo: latestSourceFrameInfo,
            latestSampleSize: latestSampleSize,
            analysisInfoText: analysisInfoText,
            activePersistentCacheIdentity: activePersistentCacheIdentity
        )
        lock.unlock()
        return snapshot
    }

    private func framesSnapshot() -> [StabilizerAnalysisFrame] {
        lock.lock()
        let frames = framesByTimeKey.values.sorted { $0.time < $1.time }
        lock.unlock()
        return frames
    }

    private var hasCompletedInMemoryAnalysis: Bool {
        lock.lock()
        let hasCompleted = finished
            && validationState != .rejected
            && preparedAnalysis != nil
            && activePersistentCacheIdentity == nil
        lock.unlock()
        return hasCompleted
    }

    private func currentValidationState() -> HostAnalysisValidationState {
        lock.lock()
        let state = validationState
        lock.unlock()
        return state
    }

    private func unvalidatedPreviewStatusIsAlreadyActive(isScaledProxy: Bool) -> Bool {
        lock.lock()
        let isActive = preparedAnalysis != nil
            && (isScaledProxy ? status == .proxyPreview : status == .sourceMetadataUnconfirmedPreview)
        lock.unlock()
        return isActive
    }

    private func markProxyMediaUnavailable(reason: String) {
        lock.lock()
        if status != .proxyRejected {
            status = .proxyRejected
            analysisInfoText = "Proxy rejected. Use original media."
            bumpRevisionLocked()
        }
        lock.unlock()
        NSLog("TokyoWalkingStabilizer: refusing proxy media frame: \(reason)")
    }

    private func markReadyAfterOriginalMediaReturnedIfNeeded() {
        lock.lock()
        if (status == .proxyRejected || status == .proxyPreview || status == .sourceMetadataUnconfirmedPreview || status == .proxyNeedsOriginalValidation || status == .sourceUnavailable),
           preparedAnalysis != nil {
            status = .ready
            bumpRevisionLocked()
        }
        lock.unlock()
    }

    private func markProxyPreviewForRender(reason: String) {
        lock.lock()
        let shouldMarkProxyPreview = preparedAnalysis != nil
            && status != .proxyPreview
        if shouldMarkProxyPreview {
            status = .proxyPreview
            analysisInfoText = "Original analysis; proxy preview."
            bumpRevisionLocked()
        }
        lock.unlock()
        if shouldMarkProxyPreview {
            NSLog("TokyoWalkingStabilizer: keeping prepared Host Analysis active for proxy preview before original-media validation: \(reason)")
        }
    }

    private func markSourceMetadataUnconfirmedPreviewForRender(reason: String) {
        lock.lock()
        let shouldMark = preparedAnalysis != nil
            && status != .sourceMetadataUnconfirmedPreview
        if shouldMark {
            status = .sourceMetadataUnconfirmedPreview
            analysisInfoText = "Original analysis; validation deferred."
            bumpRevisionLocked()
        }
        lock.unlock()
        if shouldMark {
            NSLog("TokyoWalkingStabilizer: keeping prepared Host Analysis active with unconfirmed source-frame metadata: \(reason)")
        }
    }

    private func markProxyNeedsOriginalValidationForRender(reason: String) {
        lock.lock()
        let shouldMark = status != .proxyNeedsOriginalValidation
        if shouldMark {
            status = .proxyNeedsOriginalValidation
            analysisInfoText = "Needs original validation."
            bumpRevisionLocked()
        }
        lock.unlock()
        if shouldMark {
            NSLog("TokyoWalkingStabilizer: refused unvalidated proxy Host Analysis cache selection: \(reason)")
        }
    }

    private func markSourceUnavailableForRender(reason: String) {
        lock.lock()
        let shouldMarkSourceUnavailable = status != .sourceUnavailable
        if shouldMarkSourceUnavailable {
            status = .sourceUnavailable
            analysisInfoText = "Source unavailable. Check FCP proxy."
            bumpRevisionLocked()
        }
        lock.unlock()
    }

    private func markRenderStatus(_ nextStatus: HostAnalysisStatus, info: String, logReason: String) {
        lock.lock()
        let shouldMark = status != nextStatus
        if shouldMark {
            status = nextStatus
            analysisInfoText = info
            bumpRevisionLocked()
        }
        lock.unlock()
        if shouldMark {
            NSLog("TokyoWalkingStabilizer: render status \(nextStatus): \(logReason)")
            os_log(
                "Render status %{public}@ reason=%{public}@.",
                log: stabilizerHostAnalysisLog,
                type: nextStatus == .loadedButNotRendering || nextStatus == .cacheRangeMismatch || nextStatus == .mediaLinkInvalid ? .error : .default,
                String(describing: nextStatus),
                logReason
            )
        }
    }

    private func rejectPersistentCache(reason: String) {
        lock.lock()
        let rejectedFileName = activePersistentCacheFileName
        if let rejectedFileName {
            rejectedPersistentCacheFileNames.insert(rejectedFileName)
        }
        framesByTimeKey.removeAll(keepingCapacity: true)
        streamingAnalysisBuilder = nil
        preparedAnalysis = nil
        activeCompletedMemoryAnalysisIdentity = nil
        persistentCacheCandidates.removeAll(keepingCapacity: false)
        activePersistentCacheFileName = nil
        activePersistentCacheIdentity = nil
        activeRange = .invalid
        activeFrameDuration = .invalid
        renderToAnalysisOffsetSeconds = nil
        renderToAnalysisOffsetProbeAttempted = false
        finished = false
        validationState = .rejected
        status = .cacheRejected
        projectCacheUnavailableStatusText = stabilizerProjectCacheUnavailableMessage
        projectCacheUnavailableReason = nil
        bumpRevisionLocked()
        lock.unlock()
        NSLog("TokyoWalkingStabilizer: rejected persisted Host Analysis cache \(rejectedFileName ?? "<unknown>"): \(reason).")
    }

    private func rejectActiveInMemoryAnalysis(reason: String) {
        lock.lock()
        let rejectedIdentity = activeCompletedMemoryAnalysisIdentity
        if let rejectedIdentity {
            rejectedCompletedMemoryAnalysisIdentities.insert(rejectedIdentity)
        }
        framesByTimeKey.removeAll(keepingCapacity: true)
        streamingAnalysisBuilder = nil
        preparedAnalysis = nil
        activeCompletedMemoryAnalysisIdentity = nil
        activePersistentCacheFileName = nil
        activePersistentCacheIdentity = nil
        activeRange = .invalid
        activeFrameDuration = .invalid
        finished = false
        validationState = .rejected
        status = .cacheRejected
        projectCacheUnavailableStatusText = stabilizerProjectCacheUnavailableMessage
        projectCacheUnavailableReason = nil
        analysisInfoText = "Memory analysis mismatch. Run again."
        bumpRevisionLocked()
        lock.unlock()
        NSLog("TokyoWalkingStabilizer: rejected in-memory Host Analysis \(rejectedIdentity ?? "<unknown>"): \(reason).")
    }

    private func persistentCacheRejectionReason(for analysis: StabilizerPreparedAnalysis, validating sourceImage: FxImageTile, at renderTime: CMTime) -> String? {
        let validationTime = analysisRenderTime(for: renderTime, preparedAnalysis: analysis)
        let currentFrame: StabilizerAnalysisFrame
        do {
            let sampleWidth = analysis.frames.first?.sampleWidth ?? AutoStabilizationEstimator.defaultSampleWidth
            let sampleHeight = analysis.frames.first?.sampleHeight ?? AutoStabilizationEstimator.defaultSampleHeight
            currentFrame = try AutoStabilizationEstimator.analysisFrame(
                from: sourceImage,
                at: validationTime,
                sampleWidth: sampleWidth,
                sampleHeight: sampleHeight
            )
        } catch {
            return "could not validate the persisted cache against the current source frame: \(error.localizedDescription)"
        }
        guard let matchedFrame = matchedAnalysisFrame(for: currentFrame, in: analysis.frames) else {
            return "persisted cache had no comparable frame"
        }
        updateRenderTimeMapping(renderTime: renderTime, matchedAnalysisFrame: matchedFrame)

        if matchedFrame.pixels.isEmpty {
            if matchedFrame.fingerprint != currentFrame.fingerprint {
                NSLog(
                    "TokyoWalkingStabilizer: accepted persisted Host Analysis cache by time proximity because retained validation pixels were not available; current fingerprint %@, cached fingerprint %@.",
                    currentFrame.fingerprint,
                    matchedFrame.fingerprint
                )
            }
            return nil
        }

        let meanDifference = Self.meanAbsoluteDifference(currentFrame.pixels, matchedFrame.pixels)
        guard meanDifference <= Self.cacheValidationMeanDifferenceThreshold else {
            return String(format: "current frame did not match the persisted cache (mean luma difference %.2f)", meanDifference)
        }
        return nil
    }

    private func updateRenderTimeMappingIfNeeded(for analysis: StabilizerPreparedAnalysis, validating sourceImage: FxImageTile, at renderTime: CMTime) {
        let renderSeconds = CMTimeGetSeconds(renderTime)
        guard renderSeconds.isFinite,
              !analysis.frames.isEmpty
        else {
            return
        }
        guard StabilizerOriginalMediaPolicy.proxyRejectionReason(for: sourceImage) == nil else {
            return
        }
        let renderTimeInsideAnalysisRange = Self.renderSeconds(renderSeconds, isInside: analysis.frames)
        lock.lock()
        let alreadyMapped = renderToAnalysisOffsetSeconds != nil
        let probeAttempted = renderToAnalysisOffsetProbeAttempted
        if !alreadyMapped, (!probeAttempted || !renderTimeInsideAnalysisRange) {
            renderToAnalysisOffsetProbeAttempted = true
        }
        lock.unlock()
        guard !alreadyMapped, !probeAttempted || !renderTimeInsideAnalysisRange else {
            return
        }

        do {
            let sampleWidth = analysis.frames.first?.sampleWidth ?? AutoStabilizationEstimator.defaultSampleWidth
            let sampleHeight = analysis.frames.first?.sampleHeight ?? AutoStabilizationEstimator.defaultSampleHeight
            let currentFrame = try AutoStabilizationEstimator.analysisFrame(
                from: sourceImage,
                at: renderTime,
                sampleWidth: sampleWidth,
                sampleHeight: sampleHeight
            )
            if let matchedFrame = matchedAnalysisFrame(for: currentFrame, in: analysis.frames) {
                updateRenderTimeMapping(renderTime: renderTime, matchedAnalysisFrame: matchedFrame)
            }
        } catch {
            NSLog("TokyoWalkingStabilizer: could not map trimmed render time to Host Analysis time: \(error.localizedDescription)")
        }
    }

    private func updateRenderTimeMapping(renderTime: CMTime, matchedAnalysisFrame: StabilizerAnalysisFrame) {
        let renderSeconds = CMTimeGetSeconds(renderTime)
        guard renderSeconds.isFinite, matchedAnalysisFrame.time.isFinite else {
            return
        }
        let offsetSeconds = matchedAnalysisFrame.time - renderSeconds
        lock.lock()
        renderToAnalysisOffsetSeconds = offsetSeconds
        renderToAnalysisOffsetProbeAttempted = true
        let cacheIdentity = activePersistentCacheIdentity
        lock.unlock()
        if let cacheIdentity {
            Self.saveRenderTimeOffset(
                cacheIdentity: cacheIdentity,
                offsetSeconds: offsetSeconds,
                renderSeconds: renderSeconds,
                analysisSeconds: matchedAnalysisFrame.time
            )
        }
    }

    private func matchedAnalysisFrame(for currentFrame: StabilizerAnalysisFrame, in frames: [StabilizerAnalysisFrame]) -> StabilizerAnalysisFrame? {
        if let fingerprintMatch = frames.first(where: { $0.fingerprint == currentFrame.fingerprint }) {
            return fingerprintMatch
        }
        guard let closestFrame = frames.min(by: { abs($0.time - currentFrame.time) < abs($1.time - currentFrame.time) }) else {
            return nil
        }
        if closestFrame.pixels.isEmpty {
            return nil
        }
        guard Self.meanAbsoluteDifference(currentFrame.pixels, closestFrame.pixels) <= Self.cacheValidationMeanDifferenceThreshold else {
            return nil
        }
        return closestFrame
    }

    private func deactivateActiveCacheForRangeMismatch() {
        lock.lock()
        let oldFileName = activePersistentCacheFileName
        framesByTimeKey.removeAll(keepingCapacity: true)
        streamingAnalysisBuilder = nil
        preparedAnalysis = nil
        activeCompletedMemoryAnalysisIdentity = nil
        activePersistentCacheFileName = nil
        activePersistentCacheIdentity = nil
        activeRange = .invalid
        activeFrameDuration = .invalid
        renderToAnalysisOffsetSeconds = nil
        renderToAnalysisOffsetProbeAttempted = false
        finished = false
        validationState = .notRequired
        status = .needsAnalysis
        analysisInfoText = "No matching cache for clip range."
        bumpRevisionLocked()
        lock.unlock()
        if let oldFileName {
            NSLog("TokyoWalkingStabilizer: deactivated Host Analysis cache \(oldFileName) because its range does not match the active clip.")
        }
    }

    private func activeCompletedMemoryAnalysisDoesNotMatch(expectedRange: HostAnalysisExpectedRange) -> Bool {
        guard let expectedKey = Self.completedMemoryAnalysisRangeKey(expectedRange: expectedRange) else {
            return false
        }
        lock.lock()
        let hasActiveMemoryAnalysis = activePersistentCacheIdentity == nil
            && preparedAnalysis != nil
            && finished
        let activeKey = Self.completedMemoryAnalysisRangeKey(range: activeRange)
        lock.unlock()
        return hasActiveMemoryAnalysis && activeKey != expectedKey
    }

    private func deactivateActiveCompletedMemoryAnalysisForRangeMismatch() {
        lock.lock()
        let oldIdentity = activeCompletedMemoryAnalysisIdentity
        framesByTimeKey.removeAll(keepingCapacity: true)
        streamingAnalysisBuilder = nil
        preparedAnalysis = nil
        activeCompletedMemoryAnalysisIdentity = nil
        activePersistentCacheFileName = nil
        activePersistentCacheIdentity = nil
        activeRange = .invalid
        activeFrameDuration = .invalid
        renderToAnalysisOffsetSeconds = nil
        renderToAnalysisOffsetProbeAttempted = false
        finished = false
        validationState = .notRequired
        status = .needsAnalysis
        analysisInfoText = "No matching memory analysis."
        bumpRevisionLocked()
        lock.unlock()
        if let oldIdentity {
            NSLog("TokyoWalkingStabilizer: deactivated in-memory Host Analysis \(oldIdentity) because its range does not match the active clip.")
        }
    }

    private func activateNextCompletedMemoryAnalysis(afterRejecting rejectionReason: String?, expectedRange: HostAnalysisExpectedRange?) -> Bool {
        guard let expectedRange,
              let rangeKey = Self.completedMemoryAnalysisRangeKey(expectedRange: expectedRange)
        else {
            return false
        }

        lock.lock()
        if let rejectionReason,
           let rejectedIdentity = activeCompletedMemoryAnalysisIdentity {
            rejectedCompletedMemoryAnalysisIdentities.insert(rejectedIdentity)
            NSLog("TokyoWalkingStabilizer: rejected in-memory Host Analysis \(rejectedIdentity): \(rejectionReason).")
        }
        guard let memoryAnalysis = nextCompletedMemoryAnalysisLocked(rangeKey: rangeKey) else {
            lock.unlock()
            return false
        }
        installCompletedAnalysisLocked(memoryAnalysis.snapshot, validationStateOverride: .pending)
        activeCompletedMemoryAnalysisIdentity = memoryAnalysis.identity
        bumpRevisionLocked()
        lock.unlock()
        NSLog("TokyoWalkingStabilizer: activated alternate in-memory Host Analysis \(memoryAnalysis.identity) for range \(rangeKey).")
        return true
    }

    private func nextCompletedMemoryAnalysisLocked(rangeKey: String) -> CompletedMemoryHostAnalysis? {
        guard let identities = completedMemoryAnalysisIdentitiesByRangeKey[rangeKey] else {
            return nil
        }
        for identity in identities.reversed() {
            guard identity != activeCompletedMemoryAnalysisIdentity,
                  !rejectedCompletedMemoryAnalysisIdentities.contains(identity),
                  let memoryAnalysis = completedMemoryAnalysesByIdentity[identity]
            else {
                continue
            }
            return memoryAnalysis
        }
        return nil
    }

    private func activateNextPersistentCache(
        afterRejecting rejectionReason: String?,
        expectedRange: HostAnalysisExpectedRange?,
        allowRangeMismatch: Bool = false
    ) -> Bool {
        while true {
            lock.lock()
            let rejectedFileName = activePersistentCacheFileName
            if rejectionReason != nil,
               let rejectedFileName {
                rejectedPersistentCacheFileNames.insert(rejectedFileName)
                persistentCacheCandidates.removeAll { $0.lastPathComponent == rejectedFileName }
            }
            guard !persistentCacheCandidates.isEmpty else {
                lock.unlock()
                if let rejectionReason {
                    NSLog("TokyoWalkingStabilizer: rejected persisted Host Analysis cache \(rejectedFileName ?? "<unknown>"): \(rejectionReason).")
                }
                return false
            }
            let nextURL = persistentCacheCandidates.removeFirst()
            let remainingURLCount = persistentCacheCandidates.count
            lock.unlock()

            guard let nextCandidate = Self.loadPersistentCache(at: nextURL) else {
                NSLog("TokyoWalkingStabilizer: skipped unavailable Host Analysis cache candidate \(nextURL.lastPathComponent); \(remainingURLCount) lazy alternate cache(s) remain.")
                continue
            }
            let matchesExpectedRange = Self.cache(nextCandidate.cache, matches: expectedRange)
            guard allowRangeMismatch || matchesExpectedRange else {
                NSLog("TokyoWalkingStabilizer: skipped Host Analysis cache candidate \(nextCandidate.fileName) because its range does not match the active clip.")
                continue
            }
            if !matchesExpectedRange {
                os_log(
                    "Activated range-mismatched Host Analysis cache candidate %{public}@ for source-frame fingerprint validation. expectedRange=%{public}@.",
                    log: stabilizerHostAnalysisLog,
                    type: .default,
                    nextCandidate.fileName,
                    Self.expectedRangeDescription(expectedRange)
                )
            }

            lock.lock()
            installPersistentCacheLocked(nextCandidate)
            let remainingCount = persistentCacheCandidates.count
            lock.unlock()
            markCurrentPersistentCacheGenerationObserved()

            if let rejectionReason {
                NSLog("TokyoWalkingStabilizer: rejected persisted Host Analysis cache \(rejectedFileName ?? "<unknown>"): \(rejectionReason); trying \(nextCandidate.fileName).")
            } else {
                NSLog("TokyoWalkingStabilizer: activating persisted Host Analysis cache \(nextCandidate.fileName).")
            }
            if remainingCount > 0 {
                NSLog("TokyoWalkingStabilizer: \(remainingCount) lazy alternate Host Analysis cache(s) remain available.")
            }
            return true
        }
    }

    private func installPersistentCacheLocked(_ loadedCache: LoadedPersistentHostAnalysisCache) {
        persistentCachesByIdentity[loadedCache.identity] = loadedCache
        framesByTimeKey = Dictionary(uniqueKeysWithValues: loadedCache.frames.map { (Self.timeKey($0.time), $0) })
        preparedAnalysis = loadedCache.preparedAnalysis
        activeCompletedMemoryAnalysisIdentity = nil
        activePersistentCacheFileName = loadedCache.fileName
        activePersistentCacheIdentity = loadedCache.identity
        activeRange = CMTimeRange(
            start: CMTime(seconds: loadedCache.cache.rangeStartSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: loadedCache.cache.rangeDurationSeconds, preferredTimescale: 600)
        )
        activeFrameDuration = CMTime(seconds: loadedCache.cache.frameDurationSeconds, preferredTimescale: 600)
        if let savedOffset = Self.savedRenderTimeOffset(for: loadedCache.identity) {
            renderToAnalysisOffsetSeconds = savedOffset
            renderToAnalysisOffsetProbeAttempted = true
        } else {
            renderToAnalysisOffsetSeconds = nil
            renderToAnalysisOffsetProbeAttempted = false
        }
        finished = true
        validationState = .pending
        status = .cacheLoaded
        projectCacheUnavailableStatusText = stabilizerProjectCacheUnavailableMessage
        projectCacheUnavailableReason = nil
        analysisInfoText = Self.infoText(
            completedAt: Date(timeIntervalSince1970: loadedCache.cache.createdAt),
            frameCount: loadedCache.frames.count,
            sampleWidth: loadedCache.cache.sampleWidth,
            sampleHeight: loadedCache.cache.sampleHeight,
            requestedSampleScalePercent: nil,
            rangeStartSeconds: loadedCache.cache.rangeStartSeconds,
            rangeEndSeconds: Self.rangeEndSeconds(for: loadedCache.cache),
            sourceInfo: nil,
            prefix: "Loaded Cache",
            eventName: loadedCache.cache.eventName ?? Self.currentProjectBundleCacheEventName,
            cacheIdentity: loadedCache.identity
        )
        observedPersistentCacheGeneration = Self.currentPersistentCacheGeneration()
        bumpRevisionLocked()
    }

    private func filteredPersistentCacheCandidateURLs() -> [URL] {
        let candidateURLs = Self.persistentCacheCandidateURLs()
        lock.lock()
        let rejectedFileNames = rejectedPersistentCacheFileNames
        lock.unlock()
        guard !rejectedFileNames.isEmpty else {
            return candidateURLs
        }
        let filteredURLs = candidateURLs.filter { !rejectedFileNames.contains($0.lastPathComponent) }
        let skippedCount = candidateURLs.count - filteredURLs.count
        if skippedCount > 0 {
            NSLog("TokyoWalkingStabilizer: skipped \(skippedCount) rejected Host Analysis cache candidate(s) before loading persistent cache.")
        }
        return filteredURLs
    }

    private static func currentPersistentCacheGeneration() -> UInt64 {
        persistentCacheGenerationLock.lock()
        let generation = persistentCacheGeneration
        persistentCacheGenerationLock.unlock()
        return generation
    }

    private static func currentPersistentCacheSignature() -> String {
        var components: [String] = []
        var seenPaths = Set<String>()

        func appendSignature(for url: URL) {
            let standardizedURL = url.standardizedFileURL
            guard seenPaths.insert(standardizedURL.path).inserted else {
                return
            }
            guard let values = try? standardizedURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modifiedAt = values.contentModificationDate
            else {
                return
            }
            let fileSize = values.fileSize ?? 0
            components.append("\(standardizedURL.path):\(modifiedAt.timeIntervalSince1970):\(fileSize)")
        }

        for directoryURL in cacheDirectoryURLs {
            appendSignature(for: cacheURL(in: directoryURL))
            appendSignature(for: cacheIndexURL(in: directoryURL))
            let storageURL = cacheStorageDirectoryURL(in: directoryURL)
            if let cacheURLs = try? FileManager.default.contentsOfDirectory(
                at: storageURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) {
                for url in cacheURLs where url.pathExtension == "json" {
                    appendSignature(for: url)
                }
            }
        }

        return components.sorted().joined(separator: "|")
    }

    private static func bumpPersistentCacheGeneration() {
        persistentCacheGenerationLock.lock()
        persistentCacheGeneration &+= 1
        persistentCacheGenerationLock.unlock()
    }

    private func mappedAnalysisSeconds(forRenderSeconds renderSeconds: Double, frames: [StabilizerAnalysisFrame]) -> Double {
        guard let firstFrameTime = frames.first?.time,
              let lastFrameTime = frames.last?.time,
              firstFrameTime.isFinite,
              lastFrameTime.isFinite
        else {
            return renderSeconds
        }

        let activeRangeSnapshot: CMTimeRange
        let activeFrameDurationSnapshot: CMTime
        lock.lock()
        activeRangeSnapshot = activeRange
        activeFrameDurationSnapshot = activeFrameDuration
        lock.unlock()

        let rangeStartSeconds = CMTimeGetSeconds(activeRangeSnapshot.start)
        let frameDurationSeconds = CMTimeGetSeconds(activeFrameDurationSnapshot)
        let padding = max(0.05, frameDurationSeconds.isFinite ? frameDurationSeconds * 2.0 : 0.05)
        var candidates = [renderSeconds, renderSeconds + firstFrameTime, renderSeconds - firstFrameTime]
        if rangeStartSeconds.isFinite {
            candidates.append(renderSeconds - rangeStartSeconds + firstFrameTime)
            candidates.append(renderSeconds + rangeStartSeconds - firstFrameTime)
        }

        var bestSeconds = renderSeconds
        var bestScore = Self.frameRangeDistance(renderSeconds, firstFrameTime: firstFrameTime, lastFrameTime: lastFrameTime, padding: padding)
        for candidate in candidates where candidate.isFinite {
            let clampedCandidate = min(max(candidate, firstFrameTime), lastFrameTime)
            let score = Self.frameRangeDistance(candidate, firstFrameTime: firstFrameTime, lastFrameTime: lastFrameTime, padding: padding)
                + abs(candidate - renderSeconds) * 1e-9
            if score < bestScore {
                bestScore = score
                bestSeconds = clampedCandidate
            }
        }
        return bestSeconds
    }

    private func bumpRevisionLocked() {
        analysisRevision &+= 1
        renderRevisionToken = Self.nextRenderInvalidationToken(after: renderRevisionToken)
    }

    private static func nextRenderInvalidationToken(after currentToken: Double) -> Double {
        let milliseconds = UInt64((Date().timeIntervalSinceReferenceDate * 1000.0).rounded())
        let nextToken = Double((milliseconds % 900_000) + 1_000)
        if abs(nextToken - currentToken) >= 0.5 {
            return nextToken
        }
        let incrementedToken = currentToken + 1.0
        return incrementedToken < 901_000.0 ? incrementedToken : 1_000.0
    }

    private func removePersistentCache(logFailures: Bool) {
        let urls = Self.cacheDirectoryURLs.flatMap { directoryURL in
            [
                Self.cacheURL(in: directoryURL),
                Self.cacheIndexURL(in: directoryURL),
                Self.renderTimeOffsetURL(in: directoryURL),
                Self.cacheStorageDirectoryURL(in: directoryURL)
            ]
        }
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                if logFailures {
                    NSLog("TokyoWalkingStabilizer: failed to remove Host Analysis cache \(url.path): \(error.localizedDescription)")
                }
            }
        }
    }

    private func removeLegacyAnalysisScratchDirectory() {
        for scratchDirectory in Self.cacheDirectoryURLs.map(Self.analysisScratchDirectoryURL(in:)) where FileManager.default.fileExists(atPath: scratchDirectory.path) {
            do {
                try FileManager.default.removeItem(at: scratchDirectory)
            } catch {
                NSLog("TokyoWalkingStabilizer: failed to remove legacy Host Analysis scratch directory \(scratchDirectory.path): \(error.localizedDescription)")
            }
        }
    }

    static func timeKey(_ seconds: Double) -> Int64 {
        Int64((seconds * 600.0).rounded())
    }

    private static func completedMemoryAnalysisRangeKey(range: CMTimeRange) -> String? {
        let startSeconds = CMTimeGetSeconds(range.start)
        let durationSeconds = CMTimeGetSeconds(range.duration)
        guard startSeconds.isFinite,
              durationSeconds.isFinite,
              durationSeconds > 0.0
        else {
            return nil
        }
        return "\(timeKey(startSeconds)):\(timeKey(durationSeconds))"
    }

    private static func completedMemoryAnalysisRangeKey(expectedRange: HostAnalysisExpectedRange) -> String? {
        guard expectedRange.isValid else {
            return nil
        }
        return "\(timeKey(expectedRange.startSeconds)):\(timeKey(expectedRange.durationSeconds))"
    }

    private static func completedMemoryAnalysisIdentity(snapshot: CompletedHostAnalysisSnapshot, rangeKey: String) -> String? {
        guard let preparedAnalysis = snapshot.preparedAnalysis,
              let firstFrame = preparedAnalysis.frames.first,
              let fingerprints = persistentCacheFingerprints(for: preparedAnalysis.frames)
        else {
            NSLog("TokyoWalkingStabilizer: could not retain completed in-memory Host Analysis because frame fingerprints were incomplete.")
            return nil
        }
        let frameDurationSeconds = CMTimeGetSeconds(snapshot.activeFrameDuration)
        guard frameDurationSeconds.isFinite else {
            return nil
        }
        return [
            "memory",
            "\(cacheSchemaVersion)",
            rangeKey,
            "\(timeKey(frameDurationSeconds))",
            "\(firstFrame.sampleWidth)",
            "\(firstFrame.sampleHeight)",
            "\(preparedAnalysis.frames.count)",
            fingerprints.first,
            fingerprints.middle,
            fingerprints.last
        ].joined(separator: ":")
    }

    static func cacheIdentity(_ identity: String, matches expectedRange: HostAnalysisExpectedRange?) -> Bool {
        guard let expectedRange, expectedRange.isValid else {
            return true
        }
        let parts = identity.split(separator: ":", omittingEmptySubsequences: false)
        let startIndex = parts.count >= 10 ? 1 : 0
        guard parts.count > startIndex + 1,
              let rangeStartKey = Int64(parts[startIndex]),
              let rangeDurationKey = Int64(parts[startIndex + 1])
        else {
            return false
        }
        return rangeStartKey == timeKey(expectedRange.startSeconds)
            && rangeDurationKey == timeKey(expectedRange.durationSeconds)
    }

    private static func cacheIdentityStartMatches(_ identity: String, expectedRange: HostAnalysisExpectedRange?) -> Bool {
        guard let expectedRange, expectedRange.isValid else {
            return true
        }
        let parts = identity.split(separator: ":", omittingEmptySubsequences: false)
        let startIndex = parts.count >= 10 ? 1 : 0
        guard parts.count > startIndex,
              let rangeStartKey = Int64(parts[startIndex])
        else {
            return false
        }
        return rangeStartKey == timeKey(expectedRange.startSeconds)
    }

    private static func cacheIdentityDurationMatches(_ identity: String, expectedRange: HostAnalysisExpectedRange?) -> Bool {
        guard let expectedRange, expectedRange.isValid else {
            return true
        }
        let parts = identity.split(separator: ":", omittingEmptySubsequences: false)
        let startIndex = parts.count >= 10 ? 1 : 0
        guard parts.count > startIndex + 1,
              let rangeDurationKey = Int64(parts[startIndex + 1])
        else {
            return false
        }
        return rangeDurationKey == timeKey(expectedRange.durationSeconds)
    }

    private static func expectedRangeDescription(_ expectedRange: HostAnalysisExpectedRange?) -> String {
        guard let expectedRange, expectedRange.isValid else {
            return "none"
        }
        return "start\(timeKey(expectedRange.startSeconds))-duration\(timeKey(expectedRange.durationSeconds))"
    }

    private static func cache(_ cache: PersistedHostAnalysisCache, matches expectedRange: HostAnalysisExpectedRange?) -> Bool {
        guard let expectedRange, expectedRange.isValid else {
            return true
        }
        return timeKey(cache.rangeStartSeconds) == timeKey(expectedRange.startSeconds)
            && timeKey(cache.rangeDurationSeconds) == timeKey(expectedRange.durationSeconds)
    }

    private static func validFrameDurationSeconds(_ frameDuration: CMTime, frames: [StabilizerAnalysisFrame]) -> Double {
        let supplied = CMTimeGetSeconds(frameDuration)
        if supplied.isFinite, supplied > 0.0 {
            return supplied
        }
        guard frames.count >= 2 else {
            return 1.0 / 30.0
        }
        let sortedTimes = frames.map(\.time).sorted()
        var deltas: [Double] = []
        for index in 1..<sortedTimes.count {
            let delta = sortedTimes[index] - sortedTimes[index - 1]
            if delta.isFinite, delta > 0.0 {
                deltas.append(delta)
            }
        }
        guard !deltas.isEmpty else {
            return 1.0 / 30.0
        }
        return deltas[deltas.count / 2]
    }

    private func validateCompletedFrameCoverage() throws {
        let snapshot: (frames: [StabilizerAnalysisFrame], range: CMTimeRange, frameDuration: CMTime) = {
            lock.lock()
            let frames = (preparedAnalysis?.frames ?? Array(framesByTimeKey.values)).sorted { $0.time < $1.time }
            let range = activeRange
            let frameDuration = activeFrameDuration
            lock.unlock()
            return (frames, range, frameDuration)
        }()
        let frameDurationSeconds = Self.validFrameDurationSeconds(snapshot.frameDuration, frames: snapshot.frames)
        let rangeDurationSeconds = CMTimeGetSeconds(snapshot.range.duration)
        guard let reason = Self.frameCoverageMismatchReason(
            frameCount: snapshot.frames.count,
            rangeDurationSeconds: rangeDurationSeconds,
            frameDurationSeconds: frameDurationSeconds
        ) else {
            return
        }
        throw NSError(
            domain: "com.justadev.TokyoWalkingStabilizer",
            code: Int(kFxError_AnalysisError),
            userInfo: [NSLocalizedDescriptionKey: "Host Analysis had incomplete frame coverage: \(reason)"]
        )
    }

    private static func persistentFrameCoverageMismatchReason(for cache: PersistedHostAnalysisCache, frameCount: Int) -> String? {
        frameCoverageMismatchReason(
            frameCount: frameCount,
            rangeDurationSeconds: cache.rangeDurationSeconds,
            frameDurationSeconds: cache.frameDurationSeconds
        )
    }

    private static func frameCoverageMismatchReason(
        frameCount: Int,
        rangeDurationSeconds: Double,
        frameDurationSeconds: Double
    ) -> String? {
        guard rangeDurationSeconds.isFinite,
              frameDurationSeconds.isFinite,
              rangeDurationSeconds > 0.0,
              frameDurationSeconds > 0.0
        else {
            return nil
        }
        let expectedFrameCount = max(1, Int((rangeDurationSeconds / frameDurationSeconds).rounded(.down)) + 1)
        guard expectedFrameCount > 3 else {
            return frameCount >= 3 ? nil : "only \(frameCount) frames for a short analyzed range"
        }
        let minimumFrameCount = max(3, Int((Double(expectedFrameCount) * 0.90).rounded(.down)))
        guard frameCount < minimumFrameCount else {
            return nil
        }
        return "only \(frameCount) frames for \(String(format: "%.2f", rangeDurationSeconds))s at \(String(format: "%.6f", frameDurationSeconds))s/frame; expected about \(expectedFrameCount)"
    }

    private static func plausiblePersistedFrameCountLimit(for cache: PersistedHostAnalysisCache) -> Int? {
        guard cache.rangeDurationSeconds.isFinite,
              cache.frameDurationSeconds.isFinite,
              cache.rangeDurationSeconds > 0.0,
              cache.frameDurationSeconds > 0.0
        else {
            return nil
        }
        let expectedFrameCount = Int((cache.rangeDurationSeconds / cache.frameDurationSeconds).rounded(.up)) + 2
        return max(120, expectedFrameCount * 3)
    }

    private static func persistentQualityModel(for cache: PersistedHostAnalysisCache) -> StabilizerAnalysisQualityModel {
        if cache.schemaVersion >= 18 {
            return .eventAnalyzerCache
        }
        if cache.schemaVersion == 17, looksLikeLegacyEventAnalyzerCache(cache) {
            return .eventAnalyzerCache
        }
        return .fxplugHostAnalysis
    }

    private static func qualityModelDescription(_ model: StabilizerAnalysisQualityModel) -> String {
        switch model {
        case .fxplugHostAnalysis:
            return "FxPlug Host Analysis"
        case .eventAnalyzerCache:
            return "Event Analyzer normalized residual"
        }
    }

    private static func looksLikeLegacyEventAnalyzerCache(_ cache: PersistedHostAnalysisCache) -> Bool {
        let frameCount = cache.frames.count
        guard frameCount > 0,
              cache.acceptedBlockCounts?.count == frameCount,
              cache.totalBlockCounts?.count == frameCount,
              cache.warpConfidence?.count == frameCount,
              cache.pathRoll?.count == frameCount,
              cache.footstepPathRoll?.count == frameCount
        else {
            return false
        }
        let allThreeBlockCounts = cache.acceptedBlockCounts?.allSatisfy { $0 == 3 } == true
            && cache.totalBlockCounts?.allSatisfy { $0 == 3 } == true
        let zeroRollAndWarp = allNearlyZero(cache.pathRoll)
            && allNearlyZero(cache.footstepPathRoll)
            && allNearlyZero(cache.warpConfidence)
        return allThreeBlockCounts && zeroRollAndWarp
    }

    private static func allNearlyZero(_ values: [Float]?) -> Bool {
        guard let values, !values.isEmpty else {
            return false
        }
        return values.allSatisfy { value in
            value.isFinite && abs(value) <= 1e-6
        }
    }

    private static func frameRangeDistance(_ seconds: Double, firstFrameTime: Double, lastFrameTime: Double, padding: Double) -> Double {
        if seconds < firstFrameTime - padding {
            return firstFrameTime - padding - seconds
        }
        if seconds > lastFrameTime + padding {
            return seconds - lastFrameTime - padding
        }
        return 0.0
    }

    private static func renderSeconds(_ seconds: Double, isInside frames: [StabilizerAnalysisFrame]) -> Bool {
        guard let firstFrameTime = frames.first?.time,
              let lastFrameTime = frames.last?.time,
              firstFrameTime.isFinite,
              lastFrameTime.isFinite
        else {
            return true
        }
        return seconds >= firstFrameTime && seconds <= lastFrameTime
    }

    private static func clampedAnalysisSeconds(_ seconds: Double, frames: [StabilizerAnalysisFrame]) -> Double {
        guard let firstFrameTime = frames.first?.time,
              let lastFrameTime = frames.last?.time,
              firstFrameTime.isFinite,
              lastFrameTime.isFinite
        else {
            return seconds
        }
        return min(max(seconds, firstFrameTime), lastFrameTime)
    }

    private static func preparedAnalysis(from cache: PersistedHostAnalysisCache, frames: [StabilizerAnalysisFrame]) throws -> StabilizerPreparedAnalysis {
        if let coverageReason = persistentFrameCoverageMismatchReason(for: cache, frameCount: frames.count) {
            throw NSError(
                domain: "com.justadev.TokyoWalkingStabilizer",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: "persisted Host Analysis cache frame coverage is incomplete: \(coverageReason)"]
            )
        }
        if let mismatchReason = preparedPathArrayMismatchReason(for: cache, frameCount: frames.count) {
            throw NSError(
                domain: "com.justadev.TokyoWalkingStabilizer",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: "persisted Host Analysis cache prepared paths are incomplete: \(mismatchReason)"]
            )
        }
        let floatArrays = [
            cache.residuals,
            cache.rollMotion,
            cache.pathX,
            cache.pathY,
            cache.pathRoll,
            cache.footstepPathX,
            cache.footstepPathY,
            cache.footstepPathRoll,
            cache.pathYaw,
            cache.pathPitch,
            cache.pathShearX,
            cache.pathShearY,
            cache.pathPerspectiveX,
            cache.pathPerspectiveY,
            cache.analysisConfidence,
            cache.warpConfidence,
            cache.blurAmounts
        ]
        let countArrays = [
            cache.acceptedBlockCounts,
            cache.totalBlockCounts,
            cache.searchRadiusHitCounts,
            cache.searchRadiusTotalCounts
        ]
        if floatArrays.allSatisfy({ $0?.count == frames.count }),
           countArrays.allSatisfy({ $0?.count == frames.count }),
           let residuals = cache.residuals,
           let rollMotion = cache.rollMotion,
           let pathX = cache.pathX,
           let pathY = cache.pathY,
           let pathRoll = cache.pathRoll,
           let footstepPathX = cache.footstepPathX,
           let footstepPathY = cache.footstepPathY,
           let footstepPathRoll = cache.footstepPathRoll,
           let pathYaw = cache.pathYaw,
           let pathPitch = cache.pathPitch,
           let pathShearX = cache.pathShearX,
           let pathShearY = cache.pathShearY,
           let pathPerspectiveX = cache.pathPerspectiveX,
           let pathPerspectiveY = cache.pathPerspectiveY,
           let analysisConfidence = cache.analysisConfidence,
           let warpConfidence = cache.warpConfidence,
           let acceptedBlockCounts = cache.acceptedBlockCounts,
           let totalBlockCounts = cache.totalBlockCounts,
           let blurAmounts = cache.blurAmounts,
           let searchRadiusHitCounts = cache.searchRadiusHitCounts,
           let searchRadiusTotalCounts = cache.searchRadiusTotalCounts {
            let qualityModel = persistentQualityModel(for: cache)
            NSLog("TokyoWalkingStabilizer: loaded Host Analysis cache schema \(cache.schemaVersion) using \(qualityModelDescription(qualityModel)) quality model.")
            return StabilizerPreparedAnalysis(
                frames: frames.sorted { $0.time < $1.time },
                qualityModel: qualityModel,
                residuals: residuals,
                rollMotion: rollMotion,
                pathX: pathX,
                pathY: pathY,
                pathRoll: pathRoll,
                footstepPathX: footstepPathX,
                footstepPathY: footstepPathY,
                footstepPathRoll: footstepPathRoll,
                pathYaw: pathYaw,
                pathPitch: pathPitch,
                pathShearX: pathShearX,
                pathShearY: pathShearY,
                pathPerspectiveX: pathPerspectiveX,
                pathPerspectiveY: pathPerspectiveY,
                analysisConfidence: analysisConfidence,
                warpConfidence: warpConfidence,
                acceptedBlockCounts: acceptedBlockCounts,
                totalBlockCounts: totalBlockCounts,
                blurAmounts: blurAmounts,
                searchRadiusHitCounts: searchRadiusHitCounts,
                searchRadiusTotalCounts: searchRadiusTotalCounts
            )
        }
        throw NSError(
            domain: "com.justadev.TokyoWalkingStabilizer",
            code: Int(kFxError_AnalysisError),
            userInfo: [NSLocalizedDescriptionKey: "persisted Host Analysis cache was missing prepared Metal motion paths"]
        )
    }

    private static func preparedPathArrayMismatchReason(for cache: PersistedHostAnalysisCache, frameCount: Int) -> String? {
        let floatArrays: [(String, [Float]?)] = [
            ("residuals", cache.residuals),
            ("rollMotion", cache.rollMotion),
            ("pathX", cache.pathX),
            ("pathY", cache.pathY),
            ("pathRoll", cache.pathRoll),
            ("footstepPathX", cache.footstepPathX),
            ("footstepPathY", cache.footstepPathY),
            ("footstepPathRoll", cache.footstepPathRoll),
            ("pathYaw", cache.pathYaw),
            ("pathPitch", cache.pathPitch),
            ("pathShearX", cache.pathShearX),
            ("pathShearY", cache.pathShearY),
            ("pathPerspectiveX", cache.pathPerspectiveX),
            ("pathPerspectiveY", cache.pathPerspectiveY),
            ("analysisConfidence", cache.analysisConfidence),
            ("warpConfidence", cache.warpConfidence),
            ("blurAmounts", cache.blurAmounts)
        ]
        let countArrays: [(String, [Int32]?)] = [
            ("acceptedBlockCounts", cache.acceptedBlockCounts),
            ("totalBlockCounts", cache.totalBlockCounts),
            ("searchRadiusHitCounts", cache.searchRadiusHitCounts),
            ("searchRadiusTotalCounts", cache.searchRadiusTotalCounts)
        ]
        for (name, values) in floatArrays {
            guard let values else {
                return "\(name) is missing"
            }
            if values.count != frameCount {
                return "\(name) has \(values.count) values but frames has \(frameCount)"
            }
        }
        for (name, values) in countArrays {
            guard let values else {
                return "\(name) is missing"
            }
            if values.count != frameCount {
                return "\(name) has \(values.count) values but frames has \(frameCount)"
            }
        }
        return nil
    }

    private static func persistentCacheCandidateURLs() -> [URL] {
        var candidateURLs: [URL] = []
        var seenPaths = Set<String>()

        func appendCandidateURL(_ url: URL) {
            guard FileManager.default.fileExists(atPath: url.path),
                  seenPaths.insert(url.path).inserted
            else {
                return
            }
            candidateURLs.append(url)
        }

        for directoryURL in cacheDirectoryURLs {
            let directoryCacheIndexURL = cacheIndexURL(in: directoryURL)
            let directoryCacheStorageURL = cacheStorageDirectoryURL(in: directoryURL)
            if FileManager.default.fileExists(atPath: directoryCacheIndexURL.path) {
                do {
                    let data = try Data(contentsOf: directoryCacheIndexURL)
                    let index = try JSONDecoder().decode(PersistedHostAnalysisIndex.self, from: data)
                    if !supportedCacheSchemaVersions.contains(index.schemaVersion) {
                        NSLog("TokyoWalkingStabilizer: ignoring Host Analysis cache index with unsupported schema \(index.schemaVersion) at \(directoryCacheIndexURL.path).")
                    } else {
                        for entry in index.entries {
                            appendCandidateURL(directoryCacheStorageURL.appendingPathComponent(entry.cacheFileName, isDirectory: false))
                        }
                    }
                } catch {
                    NSLog("TokyoWalkingStabilizer: failed to load Host Analysis cache index \(directoryCacheIndexURL.path): \(error.localizedDescription)")
                }
            }

            if let cacheURLs = try? FileManager.default.contentsOfDirectory(
                at: directoryCacheStorageURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) {
                let sortedCacheURLs = cacheURLs
                    .filter { $0.pathExtension == "json" }
                    .sorted {
                        let leftDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        let rightDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        return leftDate > rightDate
                    }
                for url in sortedCacheURLs {
                    appendCandidateURL(url)
                }
            }

            appendCandidateURL(cacheURL(in: directoryURL))
        }

        return candidateURLs
    }

    private static func loadPersistentCache(at url: URL) -> LoadedPersistentHostAnalysisCache? {
        guard case .loaded(let loadedCache) = loadPersistentCacheCandidate(at: url) else {
            return nil
        }
        return loadedCache
    }

    private static func unsupportedPersistentCacheSummary(schemaVersion: Int, fileName: String) -> String {
        let expectedSchema = supportedCacheSchemaVersions.sorted().map(String.init).joined(separator: ",")
        return "Cache Unsupported (schema \(schemaVersion), need \(expectedSchema)) | \(fileName)"
    }

    private static func incompletePersistentCacheSummary(for cache: PersistedHostAnalysisCache, fileName: String) -> String? {
        let frameCount = cache.frames.count
        guard frameCount >= 3 else {
            return "Cache Incomplete (only \(frameCount) frames) | \(fileName)"
        }
        if let coverageReason = persistentFrameCoverageMismatchReason(for: cache, frameCount: frameCount) {
            return "Cache Incomplete (\(coverageReason)) | \(fileName)"
        }
        if let mismatchReason = preparedPathArrayMismatchReason(for: cache, frameCount: frameCount) {
            return "Cache Incomplete (\(mismatchReason)) | \(fileName)"
        }
        return nil
    }

    private static func loadPersistentCacheCandidate(at url: URL) -> PersistentCacheLoadAttempt {
        do {
            if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               fileSize > maxPersistentCacheReadBytes {
                NSLog("TokyoWalkingStabilizer: ignoring oversized Host Analysis cache at \(url.path) (\(fileSize) bytes).")
                return .skipped
            }
            let data = try Data(contentsOf: url)
            let cache: PersistedHostAnalysisCache
            do {
                cache = try JSONDecoder().decode(PersistedHostAnalysisCache.self, from: data)
            } catch {
                if let header = try? JSONDecoder().decode(PersistedHostAnalysisSchemaHeader.self, from: data),
                   !supportedCacheSchemaVersions.contains(header.schemaVersion) {
                    let summary = unsupportedPersistentCacheSummary(schemaVersion: header.schemaVersion, fileName: url.lastPathComponent)
                    NSLog("TokyoWalkingStabilizer: ignoring Host Analysis cache with unsupported schema \(header.schemaVersion) at \(url.path).")
                    return .unusable(.cacheUnsupported, summary)
                }
                NSLog("TokyoWalkingStabilizer: failed to load Host Analysis cache \(url.path): \(error.localizedDescription)")
                return .skipped
            }
            guard supportedCacheSchemaVersions.contains(cache.schemaVersion) else {
                NSLog("TokyoWalkingStabilizer: ignoring Host Analysis cache with unsupported schema \(cache.schemaVersion) at \(url.path).")
                return .unusable(
                    .cacheUnsupported,
                    unsupportedPersistentCacheSummary(schemaVersion: cache.schemaVersion, fileName: url.lastPathComponent)
                )
            }
            if let maximumFrameCount = plausiblePersistedFrameCountLimit(for: cache),
               cache.frames.count > maximumFrameCount {
                NSLog("TokyoWalkingStabilizer: ignoring oversized Host Analysis cache at \(url.path): \(cache.frames.count) frames exceeded expected limit \(maximumFrameCount).")
                return .skipped
            }
            if let incompleteSummary = incompletePersistentCacheSummary(for: cache, fileName: url.lastPathComponent) {
                NSLog("TokyoWalkingStabilizer: ignoring incomplete Host Analysis cache at \(url.path): \(incompleteSummary).")
                return .unusable(.cacheIncomplete, incompleteSummary)
            }
            let frames = cache.frames.compactMap { persistedFrame -> StabilizerAnalysisFrame? in
                let pixels = persistedFrame.pixels.map { [UInt8]($0) } ?? []
                if !pixels.isEmpty, pixels.count != cache.sampleWidth * cache.sampleHeight {
                    return nil
                }
                let fingerprint = persistedFrame.fingerprint ?? (pixels.isEmpty ? nil : StabilizerAnalysisFrame.fingerprint(for: pixels))
                guard let fingerprint else {
                    return nil
                }
                return StabilizerAnalysisFrame(
                    time: persistedFrame.time,
                    pixels: pixels,
                    sampleWidth: cache.sampleWidth,
                    sampleHeight: cache.sampleHeight,
                    blurAmount: persistedFrame.blurAmount,
                    fingerprint: fingerprint
                )
            }
            guard frames.count >= 3 else {
                NSLog("TokyoWalkingStabilizer: ignoring Host Analysis cache with too few frames at \(url.path).")
                return .unusable(.cacheIncomplete, "Cache Incomplete (only \(frames.count) readable frames) | \(url.lastPathComponent)")
            }
            guard let cacheIdentity = persistentCacheIdentity(for: cache, frames: frames) else {
                NSLog("TokyoWalkingStabilizer: ignoring Host Analysis cache with incomplete fingerprints at \(url.path).")
                return .skipped
            }
            let prepared = try preparedAnalysis(from: cache, frames: frames)
            let lightweightCache = PersistedHostAnalysisCache(
                schemaVersion: cache.schemaVersion,
                createdAt: cache.createdAt,
                clipLabel: cache.clipLabel,
                rangeStartSeconds: cache.rangeStartSeconds,
                rangeDurationSeconds: cache.rangeDurationSeconds,
                rangeEndSeconds: cache.rangeEndSeconds,
                frameDurationSeconds: cache.frameDurationSeconds,
                sampleWidth: cache.sampleWidth,
                sampleHeight: cache.sampleHeight,
                eventName: cache.eventName,
                frames: [],
                residuals: cache.residuals,
                rollMotion: cache.rollMotion,
                pathX: cache.pathX,
                pathY: cache.pathY,
                pathRoll: cache.pathRoll,
                footstepPathX: cache.footstepPathX,
                footstepPathY: cache.footstepPathY,
                footstepPathRoll: cache.footstepPathRoll,
                pathYaw: cache.pathYaw,
                pathPitch: cache.pathPitch,
                pathShearX: cache.pathShearX,
                pathShearY: cache.pathShearY,
                pathPerspectiveX: cache.pathPerspectiveX,
                pathPerspectiveY: cache.pathPerspectiveY,
                analysisConfidence: cache.analysisConfidence,
                warpConfidence: cache.warpConfidence,
                acceptedBlockCounts: cache.acceptedBlockCounts,
                totalBlockCounts: cache.totalBlockCounts,
                blurAmounts: cache.blurAmounts,
                searchRadiusHitCounts: cache.searchRadiusHitCounts,
                searchRadiusTotalCounts: cache.searchRadiusTotalCounts
            )
            return .loaded(
                LoadedPersistentHostAnalysisCache(
                    fileName: url.lastPathComponent,
                    url: url,
                    cache: lightweightCache,
                    identity: cacheIdentity,
                    frames: frames,
                    preparedAnalysis: prepared
                )
            )
        } catch {
            NSLog("TokyoWalkingStabilizer: failed to load Host Analysis cache \(url.path): \(error.localizedDescription)")
            return .skipped
        }
    }

    private static func updatePersistentCacheIndex(with entry: PersistedHostAnalysisIndexEntry) throws {
        guard let cacheIndexURL else {
            throw NSError(
                domain: "com.justadev.TokyoWalkingStabilizer",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: stabilizerProjectCacheUnavailableMessage]
            )
        }
        var entries: [PersistedHostAnalysisIndexEntry] = []
        if FileManager.default.fileExists(atPath: cacheIndexURL.path) {
            do {
                let data = try Data(contentsOf: cacheIndexURL)
                let index = try JSONDecoder().decode(PersistedHostAnalysisIndex.self, from: data)
                if supportedCacheSchemaVersions.contains(index.schemaVersion) {
                    entries = index.entries
                }
            } catch {
                NSLog("TokyoWalkingStabilizer: rebuilding Host Analysis cache index after load failure: \(error.localizedDescription)")
            }
        }

        entries.removeAll { existing in
            existing.cacheFileName == entry.cacheFileName
                || (
                    existing.frameCount == entry.frameCount
                    && existing.sampleWidth == entry.sampleWidth
                    && existing.sampleHeight == entry.sampleHeight
                    && existing.rangeStartSeconds == entry.rangeStartSeconds
                    && existing.rangeDurationSeconds == entry.rangeDurationSeconds
                    && existing.firstFingerprint == entry.firstFingerprint
                    && existing.middleFingerprint == entry.middleFingerprint
                    && existing.lastFingerprint == entry.lastFingerprint
                )
        }
        entries.insert(entry, at: 0)
        entries.sort { $0.createdAt > $1.createdAt }

        var retainedEntries: [PersistedHostAnalysisIndexEntry] = []
        let entriesBySampleSize = Dictionary(grouping: entries) { entry in
            "\(entry.sampleWidth)x\(entry.sampleHeight)"
        }
        for sampleEntries in entriesBySampleSize.values {
            let sortedSampleEntries = sampleEntries.sorted { $0.createdAt > $1.createdAt }
            retainedEntries.append(contentsOf: sortedSampleEntries.prefix(maxPersistentCacheEntriesPerSampleSize))
        }
        retainedEntries.sort { $0.createdAt > $1.createdAt }
        let index = PersistedHostAnalysisIndex(schemaVersion: cacheSchemaVersion, entries: retainedEntries)
        let data = try JSONEncoder().encode(index)
        try data.write(to: cacheIndexURL, options: .atomic)
    }

    private static func indexEntry(for cache: PersistedHostAnalysisCache, fileName: String, frames: [StabilizerAnalysisFrame]) -> PersistedHostAnalysisIndexEntry? {
        guard let fingerprints = persistentCacheFingerprints(for: frames) else {
            return nil
        }
        return PersistedHostAnalysisIndexEntry(
            cacheFileName: fileName,
            createdAt: cache.createdAt,
            clipLabel: cache.clipLabel,
            rangeStartSeconds: cache.rangeStartSeconds,
            rangeDurationSeconds: cache.rangeDurationSeconds,
            rangeEndSeconds: Self.rangeEndSeconds(for: cache),
            frameDurationSeconds: cache.frameDurationSeconds,
            sampleWidth: cache.sampleWidth,
            sampleHeight: cache.sampleHeight,
            frameCount: frames.count,
            firstFingerprint: fingerprints.first,
            middleFingerprint: fingerprints.middle,
            lastFingerprint: fingerprints.last,
            fingerprints: [fingerprints.first, fingerprints.middle, fingerprints.last],
            cacheIdentity: persistentCacheIdentity(for: cache, frames: frames)
        )
    }

    private static func persistentCacheFileName(for cache: PersistedHostAnalysisCache, frames: [StabilizerAnalysisFrame]) -> String {
        let fingerprints = persistentCacheFingerprints(for: frames)
        let first = fingerprints?.first.prefix(12) ?? "unknown"
        let middle = fingerprints?.middle.prefix(12) ?? "unknown"
        let last = fingerprints?.last.prefix(12) ?? "unknown"
        let clipLabel = safeCacheFileComponent(cache.clipLabel ?? defaultClipLabel)
        return "host-analysis-v2-\(clipLabel)-start\(timeKey(cache.rangeStartSeconds))-end\(timeKey(rangeEndSeconds(for: cache)))-sample\(cache.sampleWidth)x\(cache.sampleHeight)-n\(frames.count)-\(first)-\(middle)-\(last).json"
    }

    private static func persistentCacheIdentity(for cache: PersistedHostAnalysisCache, frames: [StabilizerAnalysisFrame]) -> String? {
        guard let fingerprints = persistentCacheFingerprints(for: frames) else {
            return nil
        }
        return [
            "\(cache.schemaVersion)",
            "\(timeKey(cache.rangeStartSeconds))",
            "\(timeKey(cache.rangeDurationSeconds))",
            "\(timeKey(cache.frameDurationSeconds))",
            "\(cache.sampleWidth)",
            "\(cache.sampleHeight)",
            "\(frames.count)",
            fingerprints.first,
            fingerprints.middle,
            fingerprints.last,
            "end\(timeKey(rangeEndSeconds(for: cache)))",
            safeCacheFileComponent(cache.clipLabel ?? defaultClipLabel)
        ].joined(separator: ":")
    }

    private static var defaultClipLabel: String {
        "clip"
    }

    private static func rangeEndSeconds(for cache: PersistedHostAnalysisCache) -> Double {
        if let rangeEndSeconds = cache.rangeEndSeconds, rangeEndSeconds.isFinite {
            return rangeEndSeconds
        }
        return cache.rangeStartSeconds + cache.rangeDurationSeconds
    }

    private static func safeCacheFileComponent(_ rawValue: String, maxLength: Int = 48) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        var result = ""
        var previousWasSeparator = false
        for scalar in rawValue.unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                result.append("-")
                previousWasSeparator = true
            }
            if result.count >= maxLength {
                break
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        return trimmed.isEmpty ? defaultClipLabel : trimmed
    }

    private static func shortCacheIdentity(_ identity: String) -> String {
        let parts = identity.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 10 else {
            return String(identity.prefix(72))
        }
        let label = parts.count >= 12 ? parts[11] : defaultClipLabel
        let start = parts[1]
        let duration = parts[2]
        let sampleWidth = parts.count > 4 ? parts[4] : "?"
        let sampleHeight = parts.count > 5 ? parts[5] : "?"
        let first = String(parts[7].prefix(8))
        let last = String(parts[9].prefix(8))
        return "\(label) start\(start) duration\(duration) sample\(sampleWidth)x\(sampleHeight) \(first)-\(last)"
    }

    private static func savedRenderTimeOffset(for cacheIdentity: String) -> Double? {
        guard let renderTimeOffsetURL else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: renderTimeOffsetURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: renderTimeOffsetURL)
            let index = try JSONDecoder().decode(PersistedRenderTimeOffsetIndex.self, from: data)
            guard index.version == cacheSchemaVersion else {
                return nil
            }
            let entry = index.entries.first { $0.cacheIdentity == cacheIdentity }
            guard let offset = entry?.offsetSeconds, offset.isFinite else {
                return nil
            }
            return offset
        } catch {
            NSLog("TokyoWalkingStabilizer: failed to load render-time offset map: \(error.localizedDescription)")
            return nil
        }
    }

    private static func saveRenderTimeOffset(cacheIdentity: String, offsetSeconds: Double, renderSeconds: Double, analysisSeconds: Double) {
        guard offsetSeconds.isFinite,
              renderSeconds.isFinite,
              analysisSeconds.isFinite,
              let cacheDirectoryURL,
              let renderTimeOffsetURL
        else {
            return
        }
        var entries: [PersistedRenderTimeOffsetEntry] = []
        if FileManager.default.fileExists(atPath: renderTimeOffsetURL.path) {
            do {
                let data = try Data(contentsOf: renderTimeOffsetURL)
                let index = try JSONDecoder().decode(PersistedRenderTimeOffsetIndex.self, from: data)
                if index.version == cacheSchemaVersion {
                    entries = index.entries
                }
            } catch {
                NSLog("TokyoWalkingStabilizer: rebuilding render-time offset map after load failure: \(error.localizedDescription)")
            }
        }
        let entry = PersistedRenderTimeOffsetEntry(
            cacheIdentity: cacheIdentity,
            offsetSeconds: offsetSeconds,
            savedAt: Date().timeIntervalSince1970,
            renderSeconds: renderSeconds,
            analysisSeconds: analysisSeconds
        )
        entries.removeAll { $0.cacheIdentity == cacheIdentity }
        entries.insert(entry, at: 0)
        entries.sort { $0.savedAt > $1.savedAt }
        let index = PersistedRenderTimeOffsetIndex(version: cacheSchemaVersion, entries: Array(entries.prefix(32)))
        do {
            try FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(index)
            try data.write(to: renderTimeOffsetURL, options: .atomic)
        } catch {
            NSLog("TokyoWalkingStabilizer: failed to save render-time offset map: \(error.localizedDescription)")
        }
    }

    private static func persistentCacheFingerprints(for frames: [StabilizerAnalysisFrame]) -> (first: String, middle: String, last: String)? {
        guard let firstFrame = frames.first,
              let lastFrame = frames.last
        else {
            return nil
        }
        let middleFrame = frames[frames.count / 2]
        return (
            first: frameFingerprint(firstFrame),
            middle: frameFingerprint(middleFrame),
            last: frameFingerprint(lastFrame)
        )
    }

    private static func frameFingerprint(_ frame: StabilizerAnalysisFrame) -> String {
        frame.fingerprint
    }

    private static var cacheDirectoryURLs: [URL] {
        projectCacheDirectoryLock.lock()
        let url = projectBundleCacheDirectoryURL
        projectCacheDirectoryLock.unlock()
        return url.map { [$0] } ?? []
    }

    private static var cacheDirectoryURL: URL? {
        cacheDirectoryURLs.first
    }

    private static var cacheURL: URL? {
        cacheDirectoryURL.map(cacheURL(in:))
    }

    private static var cacheIndexURL: URL? {
        cacheDirectoryURL.map(cacheIndexURL(in:))
    }

    private static var renderTimeOffsetURL: URL? {
        cacheDirectoryURL.map(renderTimeOffsetURL(in:))
    }

    private static var cacheStorageDirectoryURL: URL? {
        cacheDirectoryURL.map(cacheStorageDirectoryURL(in:))
    }

    private static func analysisScratchDirectoryURL() -> URL? {
        cacheDirectoryURL.map(analysisScratchDirectoryURL(in:))
    }

    private static func cacheURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(cacheFileName, isDirectory: false)
    }

    private static func cacheIndexURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(cacheIndexFileName, isDirectory: false)
    }

    private static func renderTimeOffsetURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(renderTimeOffsetFileName, isDirectory: false)
    }

    private static func cacheStorageDirectoryURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(cacheStorageDirectoryName, isDirectory: true)
    }

    private static func analysisScratchDirectoryURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(analysisScratchDirectoryName, isDirectory: true)
    }

    private static func meanAbsoluteDifference(_ left: [UInt8], _ right: [UInt8]) -> Float {
        let count = min(left.count, right.count)
        guard count > 0, left.count == right.count else {
            return Float.greatestFiniteMagnitude
        }
        var total = 0
        for index in 0..<count {
            total += abs(Int(left[index]) - Int(right[index]))
        }
        return Float(total) / Float(count)
    }
}
