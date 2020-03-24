import CFFmpeg

func callback(ptr: UnsafeMutableRawPointer?, level: Int32, fmt: UnsafePointer<Int8>?, ars: CVaListPointer) -> Void {
    if let data = fmt {
        let format = String.init(cString: data)
        var buffer: UnsafeMutablePointer<Int8>? = nil
        let str = format.withCString { cString -> String? in
            guard vasprintf(&buffer, cString, ars) != 0 else {
                return nil
            }
            return String(validatingUTF8: buffer!)
        }
        guard let log = str else { return }
        if let closure = avComplete {
            closure(log)
        }
    }
}

var avComplete: ((String) -> Void)? = nil

public func logSetCallback(complete: @escaping (String) -> Void) {
    avComplete = complete
    av_log_set_callback(callback)
}
