import Foundation

// Phase 7 Step B（testing-runner）：CloudflareWorkersClientはURLSession.sharedを直接使うため、
// URLSession自体をDIできない。代わりにURLProtocol.registerClassで全リクエストを横取りし、
// 実際のネットワークに出さずにレスポンスをスタブする。
final class URLProtocolStub: URLProtocol {
    struct Stub {
        let statusCode: Int
        let data: Data
        let error: Error?
        let delay: TimeInterval

        init(statusCode: Int, data: Data, error: Error?, delay: TimeInterval = 0) {
            self.statusCode = statusCode
            self.data = data
            self.error = error
            self.delay = delay
        }
    }

    private static let lock = NSLock()
    private static var storedStubs: [String: Stub] = [:]
    private static var storedRequestedPaths: [String] = []
    private static var storedRequestedBodies: [String: [Data]] = [:]

    /// パス（例："/chat"）ごとのスタブ応答。テストごとにセットしてから使う
    static var stubs: [String: Stub] {
        get { synchronized { storedStubs } }
        set { synchronized { storedStubs = newValue } }
    }

    /// 呼び出されたパスの記録（何回・どのpathで呼ばれたか検証するため）
    static var requestedPaths: [String] { synchronized { storedRequestedPaths } }
    static var requestedBodies: [String: [Data]] { synchronized { storedRequestedBodies } }

    static func reset() {
        synchronized {
            storedStubs = [:]
            storedRequestedPaths = []
            storedRequestedBodies = [:]
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        guard let stub = URLProtocolStub.record(request, path: path) else {
            let error = NSError(domain: "URLProtocolStub", code: -1, userInfo: [NSLocalizedDescriptionKey: "No stub registered for \(path)"])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        if stub.delay > 0 {
            Thread.sleep(forTimeInterval: stub.delay)
        }

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func record(_ request: URLRequest, path: String) -> Stub? {
        let body = request.httpBody ?? request.httpBodyStream.flatMap(readData)
        return synchronized {
            storedRequestedPaths.append(path)
            if let body {
                storedRequestedBodies[path, default: []].append(body)
            }
            return storedStubs[path]
        }
    }

    private static func readData(from stream: InputStream) -> Data? {
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { return nil }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    private static func synchronized<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
