import Foundation
import Metal

private let maxCommandQueues = 5
private let keyInUse = "InUse"
private let keyCommandQueue = "CommandQueue"

final class MetalDeviceCacheItem: NSObject {
    let gpuDevice: MTLDevice
    let pipelineState: MTLRenderPipelineState
    let pixelFormat: MTLPixelFormat
    var commandQueueCache: [[String: Any]]
    let commandQueueCacheLock: NSLock

    init(device newDevice: MTLDevice, pixelFormat pixFormat: MTLPixelFormat) throws {
        gpuDevice = newDevice
        commandQueueCache = []
        for _ in 0..<maxCommandQueues {
            commandQueueCache.append([
                keyInUse: false,
                keyCommandQueue: gpuDevice.makeCommandQueue() as Any
            ])
        }

        let defaultLibrary = gpuDevice.makeDefaultLibrary()
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "StabilizerTransform"
        descriptor.vertexFunction = defaultLibrary?.makeFunction(name: "vertexShader")
        descriptor.fragmentFunction = defaultLibrary?.makeFunction(name: "fragmentShader")
        descriptor.colorAttachments[0].pixelFormat = pixFormat
        pixelFormat = pixFormat
        pipelineState = try gpuDevice.makeRenderPipelineState(descriptor: descriptor)
        commandQueueCacheLock = NSLock()
    }

    func getNextFreeCommandQueue() -> MTLCommandQueue? {
        commandQueueCacheLock.lock()
        defer { commandQueueCacheLock.unlock() }

        for index in commandQueueCache.indices {
            let inUse = commandQueueCache[index][keyInUse] as? Bool ?? true
            if !inUse {
                commandQueueCache[index][keyInUse] = true
                return commandQueueCache[index][keyCommandQueue] as? MTLCommandQueue
            }
        }
        return nil
    }

    func returnCommandQueue(_ commandQueue: MTLCommandQueue) {
        commandQueueCacheLock.lock()
        defer { commandQueueCacheLock.unlock() }

        for index in commandQueueCache.indices {
            if (commandQueueCache[index][keyCommandQueue] as? MTLCommandQueue) === commandQueue {
                commandQueueCache[index][keyInUse] = false
                return
            }
        }
    }

    func containsCommandQueue(_ commandQueue: MTLCommandQueue) -> Bool {
        commandQueueCacheLock.lock()
        defer { commandQueueCacheLock.unlock() }

        return commandQueueCache.contains { item in
            (item[keyCommandQueue] as? MTLCommandQueue) === commandQueue
        }
    }
}

final class MetalDeviceCache: NSObject {
    static let deviceCache = MetalDeviceCache()

    private var deviceCaches: [MetalDeviceCacheItem]

    override init() {
        deviceCaches = []
        for device in MTLCopyAllDevices() {
            do {
                deviceCaches.append(try MetalDeviceCacheItem(device: device, pixelFormat: .rgba16Float))
            } catch {
                NSLog("Unable to create StabilizerFxPlug device cache.")
            }
        }
    }

    class func fxMTLPixelFormat(for imageTile: FxImageTile) -> MTLPixelFormat {
        switch imageTile.ioSurface.pixelFormat {
        case kCVPixelFormatType_128RGBAFloat:
            return .rgba32Float
        case kCVPixelFormatType_32BGRA:
            return .bgra8Unorm
        default:
            NSLog("Unexpected FxPlug IOSurface pixel format: 0x%08x", imageTile.ioSurface.pixelFormat)
            return .rgba16Float
        }
    }

    func device(with registryID: UInt64) -> MTLDevice? {
        return deviceCaches.first { $0.gpuDevice.registryID == registryID }?.gpuDevice
    }

    func pipelineState(with registryID: UInt64, pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        if let cache = deviceCaches.first(where: { $0.gpuDevice.registryID == registryID && $0.pixelFormat == pixelFormat }) {
            return cache.pipelineState
        }

        guard let device = MTLCopyAllDevices().first(where: { $0.registryID == registryID }) else {
            return nil
        }
        do {
            let cache = try MetalDeviceCacheItem(device: device, pixelFormat: pixelFormat)
            deviceCaches.append(cache)
            return cache.pipelineState
        } catch {
            NSLog("Unable to create StabilizerFxPlug pipeline state.")
            return nil
        }
    }

    func commandQueue(with registryID: UInt64, pixelFormat: MTLPixelFormat) -> MTLCommandQueue? {
        if let cache = deviceCaches.first(where: { $0.gpuDevice.registryID == registryID && $0.pixelFormat == pixelFormat }) {
            return cache.getNextFreeCommandQueue()
        }

        guard let device = MTLCopyAllDevices().first(where: { $0.registryID == registryID }) else {
            return nil
        }
        do {
            let cache = try MetalDeviceCacheItem(device: device, pixelFormat: pixelFormat)
            deviceCaches.append(cache)
            return cache.getNextFreeCommandQueue()
        } catch {
            NSLog("Unable to create StabilizerFxPlug command queue.")
            return nil
        }
    }

    func returnCommandQueueToCache(commandQueue: MTLCommandQueue) {
        for cache in deviceCaches where cache.containsCommandQueue(commandQueue) {
            cache.returnCommandQueue(commandQueue)
            return
        }
    }
}
