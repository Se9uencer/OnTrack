import SwiftUI
import UIKit

// Shared design language: dark, rounded cards, big pill CTAs.

/// Food row thumbnail: the meal photo if we have one, else a tinted source icon.
struct FoodThumbnail: View {
    let imageFilename: String?
    let source: String?
    var size: CGFloat = 56

    var body: some View {
        // ponytail: loads from disk per render — fine for short meal lists;
        // cache with NSCache if this ever backs a long scrolling list.
        Group {
            if let file = imageFilename, let ui = ImageStore.load(file) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: size < 44 ? 10 : 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .overlay(Image(systemName: icon).font(size < 44 ? .subheadline : .title3)
                        .foregroundStyle(Color.accentColor))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size < 44 ? 10 : 14, style: .continuous))
    }

    private var icon: String {
        switch source {
        case "photo": return "camera.fill"
        case "openFoodFacts", "usda": return "barcode.viewfinder"
        default: return "fork.knife"
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.bold())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentColor, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 24
    func body(content: Content) -> some View {
        content
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func card(cornerRadius: CGFloat = 24) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }

    /// Adds a "Done" button above the keyboard so number pads (which have no
    /// return key) can be dismissed. Safe — doesn't intercept any other taps.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                }
            }
        }
    }
}
