import SwiftUI
import UIKit

struct ShareCardView: View {
    let summary: Summary
    let total: Int
    @Environment(\.dismiss) private var dismiss
    @State private var showGroup = false
    @State private var showNames = false
    @State private var milestone = false
    @State private var preparing = false
    @State private var message: String?
    @State private var output: SharedImage?
    @State private var qr: CGImage?

    private var names: [String] {
        summary.encounter.participants.filter(\.visible).map(\.name)
    }
    private var card: ShareArtwork {
        ShareArtwork(round: summary.encounter.turn?.round ?? 1,
                     participants: summary.encounter.participants.count, milestone: milestone,
                     total: total, group: showGroup ? summary.encounter.name : nil,
                     names: showNames ? names : [], qr: qr)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                SheetHeader(key: "share.card") { dismiss() }
                ViewThatFits(in: .horizontal) {
                    card.scaleEffect(0.74).frame(width: 267, height: 333).frame(maxWidth: .infinity)
                    card.scaleEffect(0.58).frame(width: 210, height: 263).frame(maxWidth: .infinity)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L.t("share.preview"))
                .accessibilityIdentifier("share.preview")
                if summary.encounter.name != nil {
                    Toggle(L.t("share.group"), isOn: $showGroup).frame(minHeight: 44)
                        .accessibilityIdentifier("share.group")
                }
                if !names.isEmpty {
                    Toggle(L.t("share.names"), isOn: $showNames).frame(minHeight: 44)
                        .accessibilityIdentifier("share.names")
                }
                if summary.milestone {
                    Toggle(L.t("milestone.title"), isOn: $milestone).frame(minHeight: 44)
                        .accessibilityIdentifier("share.milestone")
                }
                BoardButton("share.image", id: "share.image", kind: .primary, action: share).disabled(preparing)
                BoardButton("share.caption.copy", id: "share.caption") {
                    if !Launch.testing { UIPasteboard.general.string = L.t("share.caption") }
                    message = "code.copied"
                }
                if let message {
                    Text(L.t(message)).font(.footnote)
                        .accessibilityIdentifier(message == "share.ready" ? "share.requested" : "share.message")
                }
            }.padding(20)
        }
        .background(Palette.paper)
        .sheet(item: $output) { image in
            ActivityView(items: [image.url, L.t("share.caption")])
                .onDisappear { Task.detached { try? FileManager.default.removeItem(at: image.url) } }
        }
        .task {
            milestone = summary.milestone
            let id = Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String ?? ""
            if let url = ShareQR.storeURL(id) {
                qr = await Task.detached { ShareQR.image(for: url) }.value
            }
        }
    }

    private func share() {
        guard !preparing else { return }
        preparing = true
        message = nil
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(width: 360, height: 450)
        renderer.scale = 3
        guard let image = renderer.uiImage, let pixels = image.cgImage,
              pixels.width == 1080, pixels.height == 1350 else {
            preparing = false
            message = "error.storage"
            return
        }
        Task {
            defer { preparing = false }
            do {
                let url = try await Task.detached {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("initiative-\(UUID().uuidString).png")
                    guard let png = image.pngData() else { throw BoardError.storage }
                    try png.write(to: url, options: .atomic)
                    return url
                }.value
                if Launch.testing {
                    try? FileManager.default.removeItem(at: url)
                    message = "share.ready"
                } else { output = SharedImage(url: url) }
            } catch { message = "error.storage" }
        }
    }

    private struct SharedImage: Identifiable { var url: URL; var id: URL { url } }

    private struct ActivityView: UIViewControllerRepresentable {
        let items: [Any]
        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: items, applicationActivities: nil)
        }
        func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
    }
}

private struct ShareArtwork: View {
    let round: Int
    let participants: Int
    let milestone: Bool
    let total: Int
    let group: String?
    let names: [String]
    let qr: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.t("app.title")).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.light)
            Text(L.t(milestone ? "milestone.title" : "results.title"))
                .font(.system(size: 35, weight: .bold)).lineLimit(2).minimumScaleFactor(0.65)
            if let group {
                Text(group).font(.system(size: 17, weight: .semibold)).lineLimit(1)
            }
            HStack {
                Text(milestone ? L.f("milestone.count", total) : L.f("round", round))
                Spacer()
                Text(L.f("participants", participants))
            }.font(.system(size: 17, weight: .semibold)).padding(12)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 10))
            if !names.isEmpty {
                Text(names.joined(separator: " · ")).font(.system(size: 15)).lineLimit(4)
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("share.tags")).font(.system(size: 13, weight: .semibold))
                    Text(L.t(qr == nil ? "share.qr.placeholder" : "share.qr.download"))
                        .font(.system(size: 11)).foregroundStyle(Palette.light)
                }
                Spacer(minLength: 8)
                if let qr {
                    Image(decorative: qr, scale: 1, orientation: .up).resizable().interpolation(.none)
                        .frame(width: 84, height: 84)
                } else {
                    Image(systemName: "qrcode").font(.system(size: 31, weight: .light)).foregroundStyle(Palette.accent)
                        .frame(width: 84, height: 84)
                        .background(.white, in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(width: 360, height: 450, alignment: .topLeading)
        .background(Palette.deep)
        .environment(\.dynamicTypeSize, .medium)
    }
}
