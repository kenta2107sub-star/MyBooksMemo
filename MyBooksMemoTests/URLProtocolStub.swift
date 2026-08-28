import Foundation

// Phase 7 Step B（testing-runner）：CloudflareWorkersClientはURLSession.sharedを直接使うため、
// URLSession自体をDIできない。代わりにURLProtocol.registerClassで全リクエストを横取りし、
// 実際のネットワークに出さずにレスポンスをスタブする。
final class URLProtocolStub: URLProtocol {
    struct Stub {
        let statusCode: Int
        let data: Data
        let error: Error?
    }

    /// パス（例："/chat"）ごとのスタブ応答。テストごとにセットしてから使う
    static var stubs: [String: Stub] = [:]
    /// 呼び出されたパスの記録（何回・どのpathで呼ばれたか検証するため）
    static var requestedPaths: [String] = []

    static func reset() {
        stubs = [:]
        requestedPaths = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        URLProtocolStub.requestedPaths.append(path)

        guard let stub = URLProtocolStub.stubs[path] else {
            let error = NSError(domain: "URLProtocolStub", code: -1, userInfo: [NSLocalizedDescriptionKey: "No stub registered for \(path)"])
            client?.urlProtocol(self, didFailWithError: error)
            return
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
}
