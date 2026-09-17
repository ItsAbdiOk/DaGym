import PassKit
import SwiftUI

/// The Wallet controls under a card face: "Add to Apple Wallet" until the pass is in the
/// lifter's Wallet, then a smaller "Open in Wallet" link. Builds and signs the pass once per
/// card (off the main actor) and hides itself entirely when the service isn't available.
struct GymCardWalletRow: View {
    var card: GymCardInfo
    var service: WalletPassService

    @State private var phase: Phase = .idle
    @State private var presented: PresentedPass?
    @State private var failure: String?

    private enum Phase: Equatable {
        case idle, building, notAdded, added
    }

    var body: some View {
        VStack(spacing: DGSpace.s2) {
            switch phase {
            case .idle, .building:
                ProgressView()
                    .controlSize(.small)
                    .frame(height: DGTap.min)
            case .notAdded:
                AddToWalletButton { add() }
                    .frame(maxWidth: .infinity)
                    .frame(height: DGTap.min)
                if !card.symbology.isWalletNative {
                    Text(Self.substituteNote)
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier(A11yID.walletNote)
                }
            case .added:
                Button {
                    service.openInWallet(card: card)
                } label: {
                    Label("Open in Wallet", systemImage: "wallet.pass")
                        .font(DGFont.condensedLabel(13))
                        .foregroundStyle(DGColor.coralText)
                        .frame(height: DGTap.min)
                }
                .accessibilityIdentifier(A11yID.walletOpen)
            }
        }
        .task(id: card) { await prepare() }
        .sheet(item: $presented) { item in
            AddPassesSheet(pass: item.pass) {
                presented = nil
                refreshAdded()
            }
            .ignoresSafeArea()
        }
        .alert("Couldn't Add to Wallet", isPresented: failureBinding, presenting: failure) { _ in
            Button("OK", role: .cancel) { failure = nil }
        } message: { reason in
            Text(reason)
        }
    }

    static let substituteNote =
        "Wallet shows this as Code 128, so it may not scan at every gym — the number is shown too."

    private var failureBinding: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }

    private func prepare() async {
        phase = .building
        do {
            _ = try await service.pass(for: card)
            guard !Task.isCancelled else { return }
            refreshAdded()
        } catch {
            guard !Task.isCancelled else { return }
            walletLogger.error("Pass build failed: \(error.localizedDescription, privacy: .public)")
            failure = error.localizedDescription
            phase = .notAdded
        }
    }

    private func refreshAdded() {
        phase = service.isAlreadyAdded(card: card) ? .added : .notAdded
    }

    private func add() {
        Task {
            do {
                let data = try await service.pass(for: card)
                presented = PresentedPass(pass: try service.wrap(data))
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

/// A pass queued for Wallet's add sheet.
private struct PresentedPass: Identifiable {
    let id = UUID()
    let pass: PKPass
}
