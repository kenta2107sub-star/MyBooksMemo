import Foundation

// architecture.md 8.3：ハードコードされたシークレットをコードに持たせないための唯一の読み取り窓口。
// Info.plist（xcconfig経由でBuild Settingsから注入された値）から取得する。
// architecture.md 8.3のサンプルコード通り、未設定時はfatalErrorとする。
// このプロパティはCloudflareWorkersClientのAI関連メソッド呼び出し時にのみ参照され、
// アプリ起動時やオフライン機能（FR-02・FR-03・FR-07等）の利用時には評価されない。
enum Config {
    static var cloudflareWorkersURL: URL {
        guard let string = Bundle.main.object(forInfoDictionaryKey: "CloudflareWorkersURL") as? String,
              let url = URL(string: string) else {
            fatalError("CloudflareWorkersURL が Info.plist に設定されていません")
        }
        return url
    }

    static var workersSharedSecret: String {
        Bundle.main.object(forInfoDictionaryKey: "WorkersSharedSecret") as? String ?? ""
    }
}
