//
//  ThumbnailPicker.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

/// A row with its name (and a line under it) on the left and a control on the right, the control
/// centered against the name, as System Settings sets buttons and pictures beside a name.
struct CenteredRow<Label: View, Trailing: View>: View {
    var alignment = VerticalAlignment.center
    @ViewBuilder let label: Label
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: alignment, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Group(subviews: label) { lines in
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        if index == 0 {
                            line
                        } else {
                            line
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
    }
}

/// Groups as Settings' grouped forms draw them, measured from them: how round their corners are, how
/// tall a row is, and how far in its name starts. The welcome tour's groups, the preview above
/// Settings' pages and the controls sheet's picture are all made to them.
enum GroupMetrics {
    static let radius: CGFloat = 10
    static let rowHeight: CGFloat = 36
    static let inset: CGFloat = 10
}

extension View {
    /// A round control, as the notch draws its own: just its symbol, at the size given, with a
    /// circle behind it only while the pointer is over it.
    func hoverCircle(_ hovering: Bool, diameter: CGFloat) -> some View {
        frame(width: diameter, height: diameter)
            .background {
                Circle()
                    .fill(.primary.opacity(hovering ? 0.1 : 0))
                    .animation(.easeOut(duration: 0.15), value: hovering)
            }
    }
}

/// Choices shown as pictures with their names beneath, like the Light, Dark and Auto pictures in
/// System Settings: the chosen one ringed in the accent color. Across the whole row, four to a row
/// whatever the number of choices, so every such picture is the same size.
struct ThumbnailPicker<Value: Hashable, Thumbnail: View>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    /// Four across a row fill it; fewer sit beside the row's name. More choices than columns go on
    /// in rows under the first.
    var columns = 4
    /// The pictures' width, when not Settings' own: a narrower window fits four across with less.
    var column = Self.column
    @ViewBuilder let thumbnail: (Value) -> Thumbnail

    /// A quarter of a row's width, less the gaps.
    static var column: CGFloat { 102 }

    var body: some View {
        let rows = stride(from: 0, to: options.count, by: max(columns, 1)).map { Array(options[$0..<min($0 + columns, options.count)]) }
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(rows[row], id: \.value) { option in
                        choice(option.value, option.title)
                            .frame(width: column)
                    }
                }
            }
        }
        .frame(width: column * CGFloat(columns) + 12 * CGFloat(columns - 1), alignment: .leading)
        .padding(.bottom, 2)
    }

    private func choice(_ value: Value, _ title: String) -> some View {
        let selected = selection == value
        return Button {
            selection = value
        } label: {
            VStack(spacing: 6) {
                thumbnail(value)
                    .aspectRatio(1.6, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(.primary.opacity(0.15), lineWidth: 0.5)
                    }
                    .padding(3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2.5)
                    }
                // The chosen one's name bold and in the text color, white in dark mode and
                // black in light; the others' gray.
                Text(title)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    // Kept under its picture: a little smaller where the picture is.
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
