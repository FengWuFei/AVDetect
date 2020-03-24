import SwiftFFmpeg
import Foundation
import NIO

logSetCallback { log in }

struct LiveStream: DetectResource {
    var name: String
    var url: String
}

let streams = [LiveStream(name: "Test1", url: "udp://226.151.1.131:2000")]

let queue = DispatchQueue(label: "com.avdetect", attributes: .concurrent)

streams.forEach { stream in
    queue.async {
        do {
            let ctx = try AVDetectContext(with: stream)
            ctx.run().whenComplete { res in
                switch res {
                case .success(let res):
                    switch res.key {
                    case .freezeStart:
                        print(res.name + "静帧告警开始: " + res.value)
                    case .freezeEnd:
                        print(res.name + "静帧告警结束: " + res.value)
                    default:
                        break
                    }
                case .failure(let error):
                    print("warning: \(error)")
                }
            }
        } catch {
            print(error)
        }
    }
}

let lock = ConditionLock(value: 0)
lock.lock(whenValue: 1)
