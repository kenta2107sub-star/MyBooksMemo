import SwiftUI
import VisionKit

// SCR-02：本登録画面（スキャン）。
// 対応FR：FR-01
// VisionKitのDataScannerViewController（.barcode(symbologies: [.ean13])）でリアルタイムスキャンを行う。
// @MainActor：`BookRegistrationViewModel`が`@MainActor`のため、`body`以外の算出プロパティからも
// 安全に参照できるよう、View全体をMainActorに揃える。
@MainActor
struct BarcodeScannerView: View {
    @State private var viewModel = BookRegistrationViewModel()
    var onDetected: (BookDraft) -> Void
    var onManualEntryFallback: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: BookTheme.spacingUnit * 2)

            if viewModel.state.hidesCameraPreview {
                Spacer()
                errorCard(centered: true)
                Spacer()
            } else {
                cameraPreview
                    .padding(.horizontal, BookTheme.screenMargin * 1.5)

                Text("本のISBNバーコードを枠内に合わせてください")
                    .font(BookTheme.body)
                    .foregroundStyle(BookTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, BookTheme.spacingUnit * 2)
                    .padding(.horizontal, BookTheme.screenMargin)

                if viewModel.state.showsAtBottom, viewModel.state.message != nil {
                    errorCard(centered: false)
                        .padding(.top, BookTheme.spacingUnit)
                } else if !viewModel.state.showsAtBottom, viewModel.state.message != nil {
                    errorCard(centered: false)
                        .padding(.top, BookTheme.spacingUnit * 2)
                }

                if viewModel.isProcessing {
                    ProgressView("書籍情報を取得しています…")
                        .padding(.top, BookTheme.spacingUnit * 2)
                }

                Spacer()
                Spacer(minLength: BookTheme.spacingUnit * 2)
            }
        }
        .background(BookTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    onCancel()
                } label: {
                    Label("キャンセル", systemImage: "xmark")
                        .labelStyle(.titleOnly)
                }
                .foregroundStyle(BookTheme.primary)
            }
        }
        .onAppear {
            viewModel.checkCameraPermission()
        }
    }

    // カメラプレビュー領域。DataScannerViewControllerが利用できないデバイス（主にシミュレータ）では
    // 非対応メッセージを表示する（VisionKit公式仕様：isSupported/isAvailableの事前確認が必須）
    @ViewBuilder
    private var cameraPreview: some View {
        if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
            ZStack {
                // `handleDetection`は`@MainActor`（BarcodeScannerView自体が@MainActor）のため、
                // 非isolatedなクロージャ型として直接渡すとactor隔離情報が失われる。
                // デリゲートコールバックがどのスレッドから呼ばれても安全なよう、明示的にMainActorへホップする
                DataScannerRepresentable(onCodeDetected: { code in
                    Task { @MainActor in
                        handleDetection(code)
                    }
                })

                ScanGuideFrame()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 220, height: 130)
                    .shadow(color: Color.black.opacity(0.3), radius: 6)
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: BookTheme.cardCornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: BookTheme.cardCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BookTheme.primary.opacity(0.85), BookTheme.textPrimary.opacity(0.9)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(height: 280)
                .onAppear { viewModel.state = .unsupported }
        }
    }

    @ViewBuilder
    private func errorCard(centered: Bool) -> some View {
        if let message = viewModel.state.message {
            VStack(spacing: BookTheme.spacingUnit * 1.5) {
                Text(message)
                    .font(BookTheme.body)
                    .foregroundStyle(centered ? BookTheme.textPrimary : BookTheme.error)
                    .multilineTextAlignment(.center)

                if viewModel.state.showsManualEntryFallback {
                    Button("手入力で登録する") {
                        onManualEntryFallback()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(BookTheme.screenMargin)
            .background(centered ? BookTheme.cardBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: BookTheme.cardCornerRadius, style: .continuous))
            .bookCardShadow()
            .padding(.horizontal, BookTheme.screenMargin)
        }
    }

    private func handleDetection(_ code: String) {
        guard !viewModel.isProcessing else { return }
        Task {
            if let draft = await viewModel.handleDetectedCode(code) {
                onDetected(draft)
            }
        }
    }
}

/// VisionKitの`DataScannerViewController`をSwiftUIから使うためのラッパー（FR-01・architecture.md 4章）。
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    var onCodeDetected: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: false,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        guard !uiViewController.isScanning else { return }
        try? uiViewController.startScanning()
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeDetected: onCodeDetected)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCodeDetected: (String) -> Void

        init(onCodeDetected: @escaping (String) -> Void) {
            self.onCodeDetected = onCodeDetected
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue {
                    onCodeDetected(payload)
                }
            }
        }
    }
}

/// スキャンガイド枠（角の4隅だけを描く、カメラアプリでおなじみの「コーナーブラケット」形状）
private struct ScanGuideFrame: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let armLength = min(rect.width, rect.height) * 0.22
        let corners = [
            (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: 1, y: 1)),
            (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: -1, y: 1)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: 1, y: -1)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: -1, y: -1))
        ]
        for (corner, direction) in corners {
            path.move(to: CGPoint(x: corner.x + armLength * direction.x, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + armLength * direction.y))
        }
        return path
    }
}

#Preview("通常スキャン中") {
    NavigationStack {
        BarcodeScannerView(onDetected: { _ in }, onManualEntryFallback: {}, onCancel: {})
    }
}
