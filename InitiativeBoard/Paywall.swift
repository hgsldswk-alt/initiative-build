import SwiftUI

struct Paywall: View {
    @ObservedObject var access: StoreAccess
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader(key: "pro.title") { dismiss() }
                if access.value.purchasedPro {
                    Text(L.t("store.unlocked")).font(.title3.bold()).modifier(Panel(fill: Palette.tint))
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L.t(access.hasPro ? "store.trial.title" : "store.trial.end")).font(.title3.bold())
                        Text(L.t("store.trial.body")).foregroundStyle(Palette.muted)
                    }.modifier(Panel(fill: Palette.tint))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("store.pro.features")).font(.headline)
                    Text(L.t("store.pro.detail"))
                }.modifier(Panel())
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("store.free.features")).font(.headline)
                    Text(L.t("store.free.detail"))
                }.modifier(Panel())
                if !access.value.purchasedPro {
                    if access.mayClaimTrial {
                        BoardButton("store.claim", id: "paywall.trial", kind: .bordered) {
                            Task { await access.purchase(StoreAccess.trialID) }
                        }.disabled(access.working || access.pending || access.productsLoading)
                    }
                    BoardButton("store.buy", id: "paywall.buy", kind: .primary) {
                        Task { await access.purchase(StoreAccess.proID) }
                    }.disabled(access.working || access.pending || access.productsLoading)
                    if Launch.testing || access.price != nil {
                        Text(L.f("store.price", access.price ?? "$2.99")).font(.footnote)
                            .accessibilityIdentifier("paywall.price")
                    } else {
                        Text(L.t(access.productsLoading ? "loading" : "store.storePrice")).font(.footnote)
                    }
                }
                BoardButton("store.restore", id: "paywall.restore") {
                    Task { await access.restore() }
                }.disabled(access.working)
                if let message = access.message {
                    Text(L.t(message)).foregroundStyle(Palette.accent).accessibilityIdentifier("paywall.message")
                }
            }.padding(20)
        }.background(Palette.paper)
            .task { await access.loadProducts() }
    }
}

struct BoardSettings: View {
    @ObservedObject var store: BoardStore
    @ObservedObject var access: StoreAccess
    var onPro: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader(key: "settings") { dismiss() }
                Toggle(L.t("widget.showNames"), isOn: Binding(
                    get: { store.board.widgetNames },
                    set: { enabled in Task { _ = await store.save { $0.widgetNames = enabled } } }
                ))
                .frame(minHeight: 44).accessibilityIdentifier("settings.widgetNames").disabled(store.busy)
                Text(L.t("widget.privacy")).font(.footnote).foregroundStyle(Palette.muted)
                Divider()
                Text(L.t("theme.title")).font(.headline)
                HStack {
                    BoardButton("theme.paper", id: "settings.paper", kind: store.board.appearance == "paper" ? .primary : .bordered) {
                        apply("paper")
                    }
                    BoardButton("theme.rose", id: "settings.rose", kind: store.board.appearance == "rose" ? .primary : .bordered) {
                        if access.hasPro { apply("rose") } else { onPro() }
                    }
                }.disabled(store.busy)
            }.padding(20)
        }.background(Palette.paper)
    }

    private func apply(_ theme: String) {
        Task { _ = await store.save { $0.appearance = theme } }
    }
}
