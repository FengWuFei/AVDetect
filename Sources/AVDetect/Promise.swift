public enum Result<Success, Failure> where Failure : Error {
    case success(Success)
    case failure(Failure)
}

class Promise<Value> {
    typealias Future = (Result<Value, Error>) -> Void
    typealias Work = (@escaping Future) -> Void

    var work: Work?
    var future: Future?
    var inputValue: Result<Value, Error>?
    
    init(_ work: Work? = nil) {
        self.work = work
    }
    
    func run() {
        guard let f = future else {
            return
        }
        work?(f)
    }
    
    func whenComplete(_ future: @escaping Future) {
        self.future = future
        run()
    }
    
    func then<NewValue>(_ callback: @escaping (Result<Value, Error>) -> Promise<NewValue>) -> Promise<NewValue> {
        return Promise<NewValue> { next in
            self.whenComplete { res in
                let p = callback(res)
                p.whenComplete { nextValue in
                    next(nextValue)
                }
            }
        }
    }
    
    func then<NewValue>(_ callback: @escaping (Value) -> Promise<NewValue>) -> Promise<NewValue> {
        return Promise<NewValue> { next in
            self.whenComplete { res in
                switch res {
                case .success(let v):
                    let p = callback(v)
                    p.whenComplete { nextValue in
                        next(nextValue)
                    }
                case .failure(let error):
                    next(.failure(error))
                }
            }
        }
    }
}
