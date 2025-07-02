// Licensed under the Any Distance Source-Available License
//
//  AccessCodeField.swift
//  ADAC
//
//  Created by Daniel Kuntz on 3/1/23.
//

import SwiftUI

fileprivate struct GradientAnimation: View {
    @Binding var animate: Bool

    private func rand18(_ idx: Int) -> [Float] {
        let idxf = Float(idx)
        return [sin(idxf * 6.3),
                cos(idxf * 1.3 + 48),
                sin(idxf + 31.2),
                cos(idxf * 44.1),
                sin(idxf * 3333.2),
                cos(idxf + 1.12 * pow(idxf, 3)),
                sin(idxf * 22),
                cos(idxf * 34)]
    }

    var body: some View {
        ZStack {
            ForEach(Array(0...50), id: \.self) { idx in
                let rands = rand18(idx)
                let fill = Color(hue: sin(Double(idx) * 5.12) + 1.1, saturation: 1, brightness: 1)

                Ellipse()
                    .fill(fill)
                    .frame(width: CGFloat(rands[1] + 2.0) * 50.0, height: CGFloat(rands[2] + 2.0) * 40.0)
                    .blur(radius: 25.0 + CGFloat(rands[1] + rands[2]) / 2)
                    .opacity(0.8)
                    .offset(x: CGFloat(animate ? rands[3] * 150.0 : rands[4] * 150.0),
                            y: CGFloat(animate ? rands[5] * 50.0 : rands[6] * 50.0))
                    .animation(.easeInOut(duration: TimeInterval(rands[7] + 3.0) * 1.3).repeatForever(autoreverses: true),
                               value: animate)
            }
        }
        .offset(y: 0)
        .onAppear {
            animate = true
        }
    }
}

struct AccessCodeField: View {
    @Binding var accessCode: String
    var isFocused: FocusState<Bool>.Binding
    @State private var chars: [String] = [String](repeating: " ", count: 6)
    @State private var animateGradient: Bool = false
    @State private var showingPasteButton: Bool = false

    fileprivate struct CharacterText: View {
        @Binding var text: String
        var cursorVisible: Bool

        @State private var animateCursor: Bool = false

        var body: some View {
            ZStack {
                Text(text)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 29, weight: .light, design: .monospaced))
                    .foregroundColor(.white)
                    .maxHeight(.infinity)
                    .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: 1.5)
                    .frame(width: 3)
                    .frame(height: 40)
                    .opacity(animateCursor ? 1 : 0)
                    .opacity(cursorVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                               value: animateCursor)
            }
            .onAppear {
                animateCursor = true
            }
        }
    }

    struct GridSeparator: View {
        var body: some View {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(LinearGradient(colors: [.black, .clear, .clear, .black],
                                         startPoint: .leading,
                                         endPoint: .trailing))
                    .frame(height: 2)

                HStack(spacing: 0) {
                    Group {
                        Rectangle()
                            .fill(Color.black)
                        Rectangle()
                            .fill(Color.black.opacity(0.3))
                            .frame(width: 2)
                        Rectangle()
                            .fill(Color.black)
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 2)
                        Rectangle()
                            .fill(Color.black)
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 2)
                    }

                    Group {
                        Rectangle()
                            .fill(Color.black)
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 2)
                        Rectangle()
                            .fill(Color.black)
                        Rectangle()
                            .fill(Color.black.opacity(0.3))
                            .frame(width: 2)
                        Rectangle()
                            .fill(Color.black)
                    }
                }
            }
        }
    }

    var pasteButton: some View {
        Button {
            accessCode = String(UIPasteboard.general.string?.prefix(6) ?? "")
            showingPasteButton = false
        } label: {
            ZStack {
                VStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(white: 0.2))
                        .frame(width: 75, height: 40)
                    Rectangle()
                        .rotation(.degrees(45))
                        .fill(Color(white: 0.2))
                        .frame(width: 20, height: 20)
                        .offset(y: -25)
                }
                Text("Paste")
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .foregroundColor(.white)
                    .offset(y: -14)
            }
        }
        .opacity(showingPasteButton ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: showingPasteButton)
        .offset(y: -45)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                Image(uiImage: UIImage(named: "dot_bg")!.resized(withNewWidth: 4))
                    .resizable(resizingMode: .tile)
                    .opacity(0.15)
                    .mask {
                        GridSeparator()
                    }

                GradientAnimation(animate: $animateGradient)
                    .frame(height: 60.0)
                    .frame(maxWidth: .infinity)
                    .drawingGroup()
                    .saturation(1.2)
                    .brightness(0.1)
                    .mask {
                        LinearGradient(colors: [.black, .black.opacity(0.1)],
                                       startPoint: .top,
                                       endPoint: .bottom)
                    }
                    .onChange(of: isFocused.wrappedValue) { _ in
                        animateGradient = !animateGradient
                    }

                GridSeparator()
                    .opacity(0.45)

                TextField("", text: $accessCode)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.characters)
                    .focused(isFocused)
                    .opacity(0.01)

                HStack(spacing: 0) {
                    ForEach(Array(0...5), id: \.self) { idx in
                        CharacterText(text: .constant("0"), cursorVisible: false)
                            .frame(width: geo.size.width / 6, height: 60)
                    }
                }
                .opacity((isFocused.wrappedValue || !accessCode.isEmpty) ? 0.0 : 0.4)
                .allowsHitTesting(false)

                HStack(spacing: 0) {
                    ForEach(Array(0...5), id: \.self) { idx in
                        CharacterText(text: $chars[idx],
                                      cursorVisible: accessCode.count == idx && isFocused.wrappedValue)
                        .frame(width: geo.size.width / 6.0, height: 60.0)
                    }
                }
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.4) {
                    showingPasteButton = true
                }
                .simultaneousGesture(TapGesture().onEnded({ _ in
                    accessCode = ""
                    isFocused.wrappedValue = true
                    showingPasteButton = false
                }))
            }
        }
        .frame(height: 60.0)
        .mask {
            RoundedRectangle(cornerRadius: 12.0, style: .continuous)
        }
        .background {
            RoundedRectangle(cornerRadius: 12.0, style: .continuous)
                .fill(Color.white.opacity(0.25))
                .offset(y: 1.0)
        }
        .overlay {
            pasteButton
        }
        .onChange(of: accessCode) { newValue in
            if newValue.count >= 6 {
                isFocused.wrappedValue = false
            }
            showingPasteButton = false

            chars = newValue.padding(toLength: 6,
                                     withPad: " ",
                                     startingAt: 0).map { String($0).capitalized }
        }
    }
}

#Preview {
    @FocusState var focused: Bool
    AccessCodeField(accessCode: .constant(""), isFocused: $focused)
}