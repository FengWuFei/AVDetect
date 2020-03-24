import SwiftFFmpeg
import Foundation

public protocol DetectResource {
    var url: String { get set }
    var name: String { get set }
}

enum DetectedKey: String, CaseIterable {
    case freezeStart = "lavfi.freezedetect.freeze_start"
    case freezeDuration = "lavfi.freezedetect.freeze_duration"
    case freezeEnd = "lavfi.freezedetect.freeze_end"
}

public struct DetectResult {
    var name: String
    var key: DetectedKey
    var value: String
}

public class AVDetectContext {
    var resource: DetectResource
    var formatCtx: AVFormatContext

    var videoStreamIndex: Int? {
        return formatCtx.findBestStream(type: .video)
    }
    var audioStreamIndex: Int? {
        return formatCtx.findBestStream(type: .audio)
    }
    var videoStream: AVStream? {
        guard let index = videoStreamIndex else {
            return nil
        }
        return formatCtx.streams[index]
    }
    var audioStream: AVStream? {
        guard let index = audioStreamIndex else {
            return nil
        }
        return formatCtx.streams[index]
    }
    
    var vidoDecoderCtx: AVCodecContext?
    var audioDecoderCtx: AVCodecContext?
    var videoFilterCtx: DetectFilterContext?
    var audioFilterCtx: DetectFilterContext?

    public init(with resource: DetectResource) throws {
        self.resource = resource
        formatCtx = try AVFormatContext(url: resource.url)
        try formatCtx.findStreamInfo()
        
        if let vStream = videoStream {
            vidoDecoderCtx = try createCodecContext(with: vStream)
            vidoDecoderCtx?.pktTimebase = vStream.timebase
            
            let videoArgs = """
            video_size=\(vidoDecoderCtx!.width)x\(vidoDecoderCtx!.height):\
            pix_fmt=\(vidoDecoderCtx!.pixelFormat.rawValue):\
            time_base=\(vStream.timebase.num)/\(vStream.timebase.den):\
            pixel_aspect=\(vidoDecoderCtx!.sampleAspectRatio.num)/\(vidoDecoderCtx!.sampleAspectRatio.den)
            """
            videoFilterCtx = try DetectFilterContext(type: .video, srcArgs: videoArgs, filters: "freezedetect=d=1")
        } else {
            print("\(resource.name) lost video stream")
        }
        if let aStream = audioStream {
            audioDecoderCtx = try createCodecContext(with: aStream)
            audioDecoderCtx?.pktTimebase = aStream.timebase
            
            let audioArgs = """
            time_base=\(audioDecoderCtx!.timebase.num)/\(audioDecoderCtx!.timebase.den):\
            sample_rate=\(audioDecoderCtx!.sampleRate):\
            sample_fmt=\(audioDecoderCtx!.sampleFormat.name!):\
            channel_layout=0x\(audioDecoderCtx!.channelLayout.rawValue)
            """
            audioFilterCtx = try DetectFilterContext(type: .audio, srcArgs: audioArgs, filters: "silencedetect")
        } else {
            print("\(resource.name) lost audio stream")
        }
    }
    
    func createCodecContext(with stream: AVStream) throws -> AVCodecContext {
        let decoder = AVCodec.findDecoderById(stream.codecParameters.codecId)!
        let decoderCtx = AVCodecContext(codec: decoder)
        decoderCtx.setParameters(stream.codecParameters)
        try decoderCtx.openCodec()
        return decoderCtx
    }
    
    func readPkt(into pkt: AVPacket, then complete: (AVPacket) throws -> Void) throws {
        while true {
            defer { pkt.unref() }
            try formatCtx.readFrame(into: pkt)
            try complete(pkt)
        }
    }
    
    func decodeFrame(pkt: AVPacket, then complete: (AVFrame, AVFilterContext, AVFilterContext) throws -> Void) throws {
        var decoderCtx: AVCodecContext
        var buffersrcCtx: AVFilterContext
        var buffersinkCtx: AVFilterContext

        if pkt.streamIndex == videoStreamIndex {
            guard let dCtx = vidoDecoderCtx, let srcCtx = videoFilterCtx?.buffersrcCtx, let sinkCtx = videoFilterCtx?.buffersinkCtx else {
                throw AVError.decoderNotFound
            }
            decoderCtx = dCtx
            buffersrcCtx = srcCtx
            buffersinkCtx = sinkCtx
        } else if pkt.streamIndex == audioStreamIndex {
            guard let dCtx = audioDecoderCtx, let srcCtx = audioFilterCtx?.buffersrcCtx, let sinkCtx = audioFilterCtx?.buffersinkCtx else {
                throw AVError.decoderNotFound
            }
            decoderCtx = dCtx
            buffersrcCtx = srcCtx
            buffersinkCtx = sinkCtx
        } else {
            return
        }
        
        let frame = AVFrame()
        try decoderCtx.sendPacket(pkt)
        while true {
            defer { frame.unref() }
            do {
                try decoderCtx.receiveFrame(frame)
            } catch let err as AVError where err == .tryAgain || err == .eof {
                frame.unref()
                break
            }
            try complete(frame, buffersrcCtx, buffersinkCtx)
        }
    }
    
    func filterFrame(frame: AVFrame, buffersrcCtx: AVFilterContext, buffersinkCtx: AVFilterContext, then complete: (AVFrame) throws -> Void) throws {
        let filterFrame = AVFrame()
        try buffersrcCtx.addFrame(frame, flags: .keepReference)
        while true {
            defer { filterFrame.unref() }
            do {
                try buffersinkCtx.getFrame(filterFrame)
            } catch let err as AVError where err == .tryAgain || err == .eof {
                filterFrame.unref()
                break
            }
            try complete(filterFrame)
        }
    }
    
    func readPkt() -> Promise<AVPacket> {
        let pkt = AVPacket()
        return Promise<AVPacket> { future in
            do {
                try self.readPkt(into: pkt) { pkt in
                    future(.success(pkt))
                }
            } catch {
                future(.failure(error))
            }
        }
    }
      
    func decodeFrame(pkt: AVPacket) -> Promise<(AVFrame, AVFilterContext, AVFilterContext)> {
        Promise<(AVFrame, AVFilterContext, AVFilterContext)> { future in
            do {
                try self.decodeFrame(pkt: pkt) { (frame, buffersrcCtx, buffersinkCtx) in
                    future(.success((frame, buffersrcCtx, buffersinkCtx)))
                }
            } catch {
                future(.failure(error))
            }
        }
    }
    
    func filterFrame(values: (AVFrame, AVFilterContext, AVFilterContext)) -> Promise<AVFrame> {
        Promise<AVFrame> { future in
            do {
                try self.filterFrame(frame: values.0, buffersrcCtx: values.1, buffersinkCtx: values.2) { filterFrame in
                    future(.success(filterFrame))
                }
            } catch {
                future(.failure(error))
            }
        }
    }
    
    func process(filterFrame: AVFrame) -> Promise<DetectResult> {
        Promise<DetectResult> { future in
            filterFrame.metadata.forEach { [unowned self] (key, value) in
                if let detectedKey = DetectedKey(rawValue: key) {
                    future(.success(DetectResult(name: self.resource.name, key: detectedKey, value: value)))
                }
            }
        }
    }
    
    func run() -> Promise<DetectResult> {
        readPkt()
            .then(decodeFrame)
            .then(filterFrame)
            .then(process)
    }
}

class DetectFilterContext {
    enum FilterType {
        case video, audio
    }
    
    var buffersrc: AVFilter
    var buffersink: AVFilter
    var buffersrcCtx: AVFilterContext
    var buffersinkCtx: AVFilterContext
    var inputs = AVFilterInOut()
    var outputs = AVFilterInOut()
    var filterGraph = AVFilterGraph()
    
    init(type: FilterType, srcArgs: String, filters: String) throws {
        switch type {
        case .video:
            buffersrc = AVFilter(name: "buffer")!
            buffersink = AVFilter(name: "buffersink")!
        case .audio:
            buffersrc = AVFilter(name: "abuffer")!
            buffersink = AVFilter(name: "abuffersink")!
        }
        
        buffersrcCtx = try filterGraph.addFilter(buffersrc, name: "in", args: srcArgs)
        buffersinkCtx = try filterGraph.addFilter(buffersink, name: "out", args: nil)

        outputs.name = "in"
        outputs.filterContext = buffersrcCtx
        outputs.padIndex = 0
        outputs.next = nil
        
        inputs.name = "out"
        inputs.filterContext = buffersinkCtx
        inputs.padIndex = 0
        inputs.next = nil
                
        try filterGraph.parse(filters: filters, inputs: inputs, outputs: outputs)
        try filterGraph.configure()
    }
}
