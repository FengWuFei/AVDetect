public protocol DetectProcesser {
    func detect(res: DetectResult)
}

class FreezeDetecter: DetectProcesser {
    enum State {
        case normal
        case freezed
    }
    
    var state: State = .normal
    
    init() {}
    
    func detect(res: DetectResult) {
        switch res.key {
        case .freezeStart:
            if state == .normal {
                print(res.name + "静帧告警开始: " + res.value)
                state = .freezed
            }
        case .freezeEnd:
            if state == .freezed {
                print(res.name + "静帧告警结束: " + res.value)
                state = .normal
            }
        default: break
        }
    }
}

class AVDetecterStream {
    enum DetectState {
        case noamal
        case warning
    }
    
    var resource: DetectResource
    var context: AVDetectContext
    var freezeState: DetectState = .noamal
    var silenceState: DetectState = .noamal
    
    init(resource: DetectResource) throws {
        self.resource = resource
        self.context = try AVDetectContext(with: resource)
    }
    
    func run() {
        
    }
}

class AVDetectManager {
    
}
