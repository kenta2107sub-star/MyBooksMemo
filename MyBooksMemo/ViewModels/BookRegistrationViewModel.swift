import Foundation
import AVFoundation

/// SCR-02（スキャン）で表示しうる状態。requirements.md FR-01の正常系・異常系に対応する。
enum ScanState: Equatable {
    case scanning
    case permissionDenied
    case invalidFormat
    case offline
    case apiFailure
    case notFound
    /// このデバイス（主にシミュレータ）ではDataScannerViewControllerが利用できない場合の防御的な状態。
    /// requirements.md・basic_design.mdに定義はないが、VisionKitの仕様上クラッシュを避けるために必要
    /// （実装時の技術的判断。VisionKit公式ドキュメントで`isSupported`/`isAvailable`の事前確認が必須とされている）
    case unsupported

    /// requirements.md FR-01異常系の文言をそのまま使用（basic_design.md Section 7 ERR-01〜05）
    var message: String? {
        switch self {
        case .scanning:
            return nil
        case .permissionDenied:
            return "カメラへのアクセスが許可されていません。設定アプリから許可してください"
        case .invalidFormat:
            return "書籍のISBNバーコード（978または979で始まる13桁）を読み取ってください"
        case .offline:
            return "インターネットに接続されていません。手入力で登録しますか？"
        case .apiFailure:
            return "書籍情報の取得に失敗しました"
        case .notFound:
            return "該当する書籍情報が見つかりませんでした"
        case .unsupported:
            return "このデバイスではバーコードスキャンを利用できません"
        }
    }

    /// ERR-02（バーコード形式エラー）のみ、手入力ボタンを出さずスキャンを継続する
    var showsManualEntryFallback: Bool {
        switch self {
        case .scanning, .invalidFormat: return false
        default: return true
        }
    }

    /// 権限拒否・非対応デバイスのみカメラプレビュー自体を表示しない
    var hidesCameraPreview: Bool { self == .permissionDenied || self == .unsupported }

    /// ERR-02のみ画面下部に表示、その他は中央表示（basic_design.md Section 4/7の指定通り）
    var showsAtBottom: Bool { self == .invalidFormat }
}

// @MainActor：NDL API呼び出し後の状態更新を安全にUIスレッドで行うため、クラス全体をMainActorに隔離する。
@Observable
@MainActor
final class BookRegistrationViewModel {
    var state: ScanState = .scanning
    private(set) var isProcessing = false

    /// 唯一の呼び出し元`BarcodeScannerView`は`@MainActor`のViewのため、この初期化子を
    /// `nonisolated`にする必要はない（`nonisolated`はSwift 6の厳格な並行性チェックでは
    /// デフォルト値プロパティへの再代入とみなされ警告の原因になるため、あえて付けない）。
    init() {}

    /// SCR-02表示時にカメラ権限を確認する。未確定の場合はiOS標準の権限リクエストダイアログを表示する
    /// （requirements.md FR-01 Step2）
    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            state = .scanning
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    self?.state = granted ? .scanning : .permissionDenied
                }
            }
        case .denied, .restricted:
            state = .permissionDenied
        @unknown default:
            state = .permissionDenied
        }
    }

    /// requirements.md FR-01 Step3〜5：検出したバーコード文字列を処理し、成功時は書誌情報を返す。
    /// - Returns: SCR-04に渡す`BookDraft`（成功時）。失敗時はnil（`state`にエラー種別を反映する）
    func handleDetectedCode(_ code: String) async -> BookDraft? {
        guard !isProcessing else { return nil }

        // FR-01 Step3：978/979で始まる13桁のみISBN-13として扱う
        guard code.count == 13, code.allSatisfy(\.isNumber), code.hasPrefix("978") || code.hasPrefix("979") else {
            state = .invalidFormat
            return nil
        }

        guard NetworkReachability.isConnected else {
            state = .offline
            return nil
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            guard let info = try await NDLSearchService.fetchBookInfo(isbn: code) else {
                state = .notFound
                return nil
            }
            return BookDraft(title: info.title, author: info.author, coverImageData: info.coverImageData)
        } catch let error as APIError {
            switch error {
            case .network:
                state = .offline
            default:
                state = .apiFailure
            }
            return nil
        } catch {
            state = .apiFailure
            return nil
        }
    }
}
