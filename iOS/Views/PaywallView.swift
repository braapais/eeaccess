import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var entitlement: EntitlementManager
    @Environment(\.dismiss) private var dismiss
    let trialEnded: Bool

    @State private var showRedeem = false
    @State private var redeemCode = ""
    @State private var redeemMessage: String?

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()
                appIcon
                heading
                features
                Spacer()
                actions
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
        }
        .task { await entitlement.loadProduct() }
        .alert("Redeem Code", isPresented: $showRedeem) {
            TextField("Code", text: $redeemCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Redeem") {
                if entitlement.redeem(code: redeemCode) {
                    dismiss()   // closes the sheet if presented; the root paywall swaps automatically
                } else {
                    redeemMessage = "That code isn't valid."
                }
                redeemCode = ""
            }
            Button("Cancel", role: .cancel) { redeemCode = "" }
        } message: {
            Text("Enter your access code.")
        }
    }

    // MARK: Subviews

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.10, blue: 0.22),
                Color(red: 0.07, green: 0.15, blue: 0.30)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var appIcon: some View {
        Group {
            if let img = UIImage(named: "AppIcon") {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white.opacity(0.1))
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }

    private var heading: some View {
        VStack(spacing: 10) {
            Text(trialEnded ? "Trial ended" : "Unlock EEAccess")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
            Text("Your loyalty cards on your wrist — without your iPhone. One-time payment, no subscription.")
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 10) {
            bullet("Unlimited cards on iPhone and Apple Watch")
            bullet("Standalone watch app — works without your phone")
            bullet("No accounts, no tracking, no subscription")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var actions: some View {
        VStack(spacing: 14) {
            Button(action: { Task { await entitlement.purchase() } }) {
                HStack {
                    if entitlement.purchaseInFlight {
                        ProgressView().tint(.white)
                    } else {
                        Text(buyTitle)
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.78, blue: 0.55),
                            Color(red: 0.10, green: 0.65, blue: 0.45)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(entitlement.product == nil || entitlement.purchaseInFlight)

            HStack(spacing: 18) {
                Button("Restore Purchases") {
                    Task { await entitlement.restore() }
                }
                Button("Redeem Code") {
                    redeemMessage = nil
                    redeemCode = ""
                    showRedeem = true
                }
            }
            .font(.footnote)
            .foregroundStyle(Color.white.opacity(0.7))

            if let redeemMessage {
                Text(redeemMessage)
                    .font(.caption)
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
                    .multilineTextAlignment(.center)
            }

            if let err = entitlement.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: Helpers

    private var buyTitle: String {
        if let price = entitlement.product?.displayPrice {
            return "Unlock for \(price)"
        }
        return "Unlock"
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.55))
            Text(text)
                .font(.callout)
                .foregroundStyle(.white)
        }
    }
}
