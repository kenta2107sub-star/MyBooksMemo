import Foundation

// architecture.md 7.1・detailed_design.md 2-4：国立国会図書館サーチAPI（SRU、dcndl形式）を
// 呼び出し、XMLレスポンスをパースして書誌情報を取得する。認証不要（NF-02）。
//
// pre-implementation-check（実機/実環境からの確認、2026-08-26実施）で判明した事実：
// - `dc:title`はネストされたRDF構造（rdf:Description/rdf:value）を持ち単純な平文要素ではないため、
//   平文で取得できる`dcterms:title`をタイトル抽出に使う（内容は`dc:title`配下の`rdf:value`と同一）。
// - `dc:creator`は平文の著者表記（例："岸見一郎, 古賀史健著"）であり、そのまま利用できる。
// - 書影は国立国会図書館サーチのサムネイル専用API
//   （`https://ndlsearch.ndl.go.jp/thumbnail/{ISBN}.jpg`）から取得できる。
//   detailed_design.mdが懸念していた「ISBNをそのまま渡すと取得できない」問題は実際には発生せず、
//   ISBN-13をそのまま渡せば取得できることを確認した。ただし`Referer`ヘッダーが
//   `https://ndlsearch.ndl.go.jp/`ドメイン由来であることをCloudFront側が要求しており、
//   このヘッダーを付与しないリクエストは（User-Agentの値に関わらず）一律403で拒否される
//   （ボット・ホットリンク対策とみられる）。書影が存在しない書誌はHTTP 404を返す。
enum NDLSearchService {
    struct BookInfo {
        let title: String
        let author: String
        let coverImageData: Data?
    }

    /// ISBN（13桁の数字文字列。978/979判定は呼び出し元のFR-01 Step3で実施済み）から
    /// 書誌情報を取得する。
    /// - Returns: 検索結果が1件以上ある場合はその先頭1件（FR-01 Step5）。
    ///            検索結果0件、またはXMLパース不能な場合はnil（FR-01異常系：検索結果0件と同様に扱う）。
    /// - Throws: `APIError`（タイムアウト・ネットワーク接続なし・5xx等の通信エラー）。
    static func fetchBookInfo(isbn: String) async throws -> BookInfo? {
        guard let url = buildSRUURL(isbn: isbn) else { return nil }

        let (data, _) = try await APIClient.send(URLRequest(url: url), timeout: 10)

        guard let parsed = parseFirstRecord(from: data), let title = parsed.title else {
            return nil
        }

        let author = normalizeAuthor(parsed.author) ?? "著者不明"
        let coverImageData = await fetchCoverImage(isbn: isbn)
        return BookInfo(title: title, author: author, coverImageData: coverImageData)
    }

    // MARK: - SRU API呼び出し

    private static func buildSRUURL(isbn: String) -> URL? {
        URL(string: "https://ndlsearch.ndl.go.jp/api/sru?operation=searchRetrieve&query=isbn%3D\(isbn)&recordSchema=dcndl&recordPacking=xml")
    }

    private static func parseFirstRecord(from data: Data) -> (title: String?, author: String?)? {
        let delegate = DCNDLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        if delegate.title == nil && delegate.author == nil { return nil }
        return (delegate.title, delegate.author)
    }

    /// NDLの`dc:creator`は"氏名1, 氏名2著"のように末尾に役割表記（著／編等）が
    /// 付与されることが多い（pre-implementation-checkで確認）。FR-01の表示例
    /// （「著者：岸見一郎, 古賀史健」）に合わせ、末尾の役割表記1文字を取り除く。
    private static func normalizeAuthor(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        let roleSuffixes: [Character] = ["著", "編"]
        if let last = value.last, roleSuffixes.contains(last) {
            value.removeLast()
        }
        return value.isEmpty ? nil : value
    }

    // MARK: - 書影取得（サムネイルAPI。ベストエフォート）

    /// 書影取得の失敗（404含む）は例外を投げず`nil`を返す。FR-01「書影URLがレスポンスに
    /// 含まれない場合はプレースホルダー画像を表示する」に対応するため、この呼び出しが
    /// 全体の書誌情報取得を失敗させることはない。
    private static func fetchCoverImage(isbn: String) async -> Data? {
        guard let url = URL(string: "https://ndlsearch.ndl.go.jp/thumbnail/\(isbn).jpg") else { return nil }
        var request = URLRequest(url: url)
        // CloudFront側がRefererヘッダーの有無で403/200を切り分けているため必須（pre-implementation-check参照）
        request.setValue("https://ndlsearch.ndl.go.jp/", forHTTPHeaderField: "Referer")
        do {
            let (data, _) = try await APIClient.send(request, timeout: 10)
            return data
        } catch {
            return nil
        }
    }
}

/// dcndl形式XMLの先頭`record`から`dcterms:title`・`dc:creator`（いずれも平文要素）を抽出する。
/// `dc:title`はネスト構造（rdf:Description/rdf:value）を持つため使用しない。
private final class DCNDLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var title: String?
    private(set) var author: String?

    private var buffer = ""
    private var isInFirstRecord = false
    private var hasFinishedFirstRecord = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        buffer = ""
        if elementName == "record", !hasFinishedFirstRecord {
            isInFirstRecord = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""

        if elementName == "record", isInFirstRecord {
            isInFirstRecord = false
            hasFinishedFirstRecord = true
            return
        }

        guard isInFirstRecord, !trimmed.isEmpty else { return }

        switch elementName {
        case "dcterms:title":
            if title == nil { title = trimmed }
        case "dc:creator":
            if author == nil { author = trimmed }
        default:
            break
        }
    }
}
