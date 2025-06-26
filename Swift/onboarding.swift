// Licensed under the Any Distance Source-Available License
//
//  OnboardingView.swift
//  ADAC
//
//  Created by Daniel Kuntz on 11/8/22.
//

import SwiftUI

fileprivate struct GradientAnimation: View {
    @Binding var animate: Bool
    @Binding var pageIdx: Int

    private var firstPageColors: [Color] {
        return [Color(hexadecimal: "#F98425"),
                Color(hexadecimal: "#E82840"),
                Color(hexadecimal: "#4A0D21"),
                Color(hexadecimal: "#B12040"),
                Color(hexadecimal: "#F4523B")]
    }

    private var secondPageColors: [Color] {
        return [Color(hexadecimal: "#B7F6FE"),
                Color(hexadecimal: "#32A0FB"),
                Color(hexadecimal: "#034EE7"),
                Color(hexadecimal: "#0131A1"),
                Color(hexadecimal: "#030C2F")]
    }

    private var thirdPageColors: [Color] {
        return [Color(hexadecimal: "#66E7FF"),
                Color(hexadecimal: "#04CFD5"),
                Color(hexadecimal: "#00A077"),
                Color(hexadecimal: "#00Af8B"),
                Color(hexadecimal: "#02251B")]
    }

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

    func gradient(withColors colors: [Color], seed: Int = 0) -> some View {
        return ZStack {
            let maxXOffset = Float(UIScreen.main.bounds.width) / 2
            let maxYOffset = Float(UIScreen.main.bounds.height) / 2
            ForEach(Array(0...9), id: \.self) { idx in
                let rands = rand18(idx + seed)
                let fill = colors[idx % colors.count]

                Ellipse()
                    .fill(fill)
                    .frame(width: CGFloat(rands[1] + 2) * 250, height: CGFloat(rands[2] + 2) * 250)
                    .blur(radius: 45 * 1 + CGFloat(rands[1] + rands[2]) / 2)
                    .opacity(1)
                    .offset(x: CGFloat(animate ? rands[3] * maxXOffset : rands[4] * maxXOffset),
                            y: CGFloat(animate ? rands[5] * maxYOffset : rands[6] * maxYOffset))
                    .animation(.easeInOut(duration: TimeInterval(rands[7] + 3) * 2.5).repeatForever(autoreverses: true),
                               value: animate)
            }
        }
        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height+100)
        .drawingGroup()
    }

    var body: some View {
        ZStack {
            gradient(withColors: firstPageColors, seed: 5)
                .opacity(pageIdx == 0 ? 1 : 0)
                .animation(.easeInOut(duration: 1.5), value: pageIdx)

            gradient(withColors: secondPageColors, seed: 5)
                .opacity(pageIdx == 1 ? 1 : 0)
                .animation(.easeInOut(duration: 1.5), value: pageIdx)

            gradient(withColors: thirdPageColors, seed: 6)
                .opacity(pageIdx == 2 ? 1 : 0)
                .animation(.easeInOut(duration: 1.5), value: pageIdx)

            Image("noise")
                .resizable(resizingMode: .tile)
                .scaleEffect(0.25)
                .ignoresSafeArea()
                .luminanceToAlpha()
                .frame(width: UIScreen.main.bounds.width * 4,
                       height: UIScreen.main.bounds.height * 5)
                .opacity(0.15)
        }
        .onAppear {
            animate = true
        }
    }
}

fileprivate struct InfiniteScroller<Content: View>: View {
    var contentWidth: CGFloat
    var reversed: Bool = true
    var content: (() -> Content)

    @State var xOffset: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                content()
                content()
            }
            .offset(x: xOffset, y: 0)
        }
        .disabled(true)
        .onAppear {
            if reversed {
                xOffset = -1 * contentWidth
            }
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                if reversed {
                    xOffset = 0
                } else {
                    xOffset = -contentWidth
                }
            }
        }
    }
}

fileprivate struct AppIcons: View {
    let iconWidth: CGFloat = 61
    let iconSpacing: CGFloat = 16

    var firstRow: some View {
        HStack(spacing: iconSpacing) {
            Image("icon_fitness")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_strava")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_garmin")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_nrc")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_peloton")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_runkeeper")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_wahoo")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_fitbod")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_ot")
                .frame(width: iconWidth, height: iconWidth)
            Rectangle()
                .frame(width: 0)
        }
    }

    var secondRow: some View {
        HStack(spacing: iconSpacing) {
            Image("icon_strava")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_fitbod")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_garmin")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_runkeeper")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_nrc")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_future")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_fitness")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_peloton")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_wahoo")
                .frame(width: iconWidth, height: iconWidth)
            Rectangle()
                .frame(width: 0)
        }
    }

    var thirdRow: some View {
        HStack(spacing: iconSpacing) {
            Image("icon_future")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_peloton")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_fitbod")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_garmin")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_nrc")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_runkeeper")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_ot")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_fitness")
                .frame(width: iconWidth, height: iconWidth)
            Image("icon_strava")
                .frame(width: iconWidth, height: iconWidth)
            Rectangle()
                .frame(width: 0)
        }
    }

    var body: some View {
        VStack {
            InfiniteScroller(contentWidth: iconWidth * 10 + iconSpacing * 10, reversed: true) {
                firstRow
            }
            .frame(height: iconWidth)
            InfiniteScroller(contentWidth: iconWidth * 10 + iconSpacing * 10, reversed: false) {
                secondRow
            }
            .frame(height: iconWidth)
            InfiniteScroller(contentWidth: iconWidth * 10 + iconSpacing * 10, reversed: true) {
                thirdRow
            }
            .frame(height: iconWidth)
            InfiniteScroller(contentWidth: iconWidth * 10 + iconSpacing * 10, reversed: false) {
                firstRow
            }
            .frame(height: iconWidth)
        }
        .mask {
            LinearGradient(colors: [.clear, .black, .black, .black, .black, .black, .clear],
                           startPoint: .leading,
                           endPoint: .trailing)
        }
    }
}

fileprivate var screenshotSize: CGSize {
    let aspect: CGFloat = 2.052
    let verticalSafeArea = (UIApplication.shared.topWindow?.safeAreaInsets.top ?? 0) +
                           (UIApplication.shared.topWindow?.safeAreaInsets.bottom ?? 0)
    let height = (UIScreen.main.bounds.height - verticalSafeArea) * 0.435
    return CGSize(width: height / aspect,
                  height: height)
}

fileprivate struct Carousel: View {
    @Binding var pageIdx: Int
    @Binding var dragging: Bool
    @State var offset: CGFloat = 0
    @State private var startOffset: CGFloat?

    fileprivate struct CarouselItem: View {
        var body: some View {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .frame(width: screenshotSize.width, height: screenshotSize.height)
                .foregroundColor(Color.black.opacity(0.5))
        }
    }

    var item: some View {
        GeometryReader { geo in
            CarouselItem()
                .scaleEffect((1 - ((geo.frame(in: .global).minX) / UIScreen.main.bounds.width * 0.3)).clamped(to: 0...1))
                .offset(x: pow(geo.frame(in: .global).minX / UIScreen.main.bounds.width, 2) * -60)
        }
        .frame(width: screenshotSize.width, height: screenshotSize.height)
    }

    func item(forScreen screen: Int) -> some View {
        GeometryReader { geo in
            ZStack {
                switch screen {
                case 1:
                    Image("onboarding-screen-1")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case 2:
                    LoopingVideoView(videoUrl: Bundle.main.url(forResource: "onboarding-screen-2", withExtension: "mp4")!,
                                     videoGravity: .resizeAspectFill)
                    EmptyView()
                case 3:
                    Image("onboarding-screen-3")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case 4:
                    LoopingVideoView(videoUrl: Bundle.main.url(forResource: "onboarding-screen-4", withExtension: "mp4")!,
                                     videoGravity: .resizeAspectFill)
                    EmptyView()
                case 5:
                    Image("onboarding-screen-5")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case 6:
                    Image("onboarding-screen-6")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    EmptyView()
                }
            }
            .frame(width: screenshotSize.width, height: screenshotSize.height)
            .cornerRadius(12, style: .continuous)
            .scaleEffect((1 - ((geo.frame(in: .global).minX) / UIScreen.main.bounds.width * 0.3)).clamped(to: 0...1))
            .offset(x: pow(geo.frame(in: .global).minX / UIScreen.main.bounds.width, 2) * -60)
        }
        .frame(width: screenshotSize.width, height: screenshotSize.height)
    }

    var contentWidth: CGFloat {
        return (screenshotSize.width * 6) + UIScreen.main.bounds.width + (16 * 7)
    }

    var secondPageOffset: CGFloat {
        return (screenshotSize.width * 3) + (16 * 3)
    }

    var thirdPageOffset: CGFloat {
        return (screenshotSize.width * 6) + (16 * 6)
    }

    var body: some View {
        HStack(spacing: 16) {
            item(forScreen: 1)
            item(forScreen: 2)
            item(forScreen: 3)
            item(forScreen: 4)
            item(forScreen: 5)
            item(forScreen: 6)
            AppIcons()
                .frame(width: UIScreen.main.bounds.width)
        }
        .id(0)
        .frame(height: screenshotSize.height)
        .offset(x: (contentWidth / 2) - (UIScreen.main.bounds.width / 2) - offset)
        .onChange(of: pageIdx) { newValue in
            print(newValue)
            withAnimation(smoothCurveAnimation) {
                switch newValue {
                case 0:
                    offset = 0
                case 1:
                    offset = secondPageOffset
                default:
                    offset = thirdPageOffset
                }
            }
        }
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    if startOffset == nil {
                        startOffset = offset
                    }
                    let gestureOffset = gesture.location.x - gesture.startLocation.x
                    offset = startOffset! - gestureOffset
                    dragging = true
                }
                .onEnded { gesture in
                    let finalOffset = startOffset! - (gesture.predictedEndLocation.x - gesture.startLocation.x)
                    let closestOffset = [0, secondPageOffset, thirdPageOffset].min(by: { abs($0 - finalOffset) < abs($1 - finalOffset) })!
                    let closestPage = [0, secondPageOffset, thirdPageOffset].firstIndex(of: closestOffset)!.clamped(to: (pageIdx-1)...(pageIdx+1))
                    let clampedClosestOffset = [0, secondPageOffset, thirdPageOffset][closestPage]
                    pageIdx = closestPage
                    withAnimation(.interactiveSpring(response: 0.6)) {
                        offset = clampedClosestOffset
                    }
                    startOffset = nil
                    dragging = false
                }
        )
    }
}

struct Onboarding2022View: View {
    @State private var animate: Bool = false
    @State private var pageIdx: Int = 0
    @State private var pageTimer: Timer?
    @State private var dragging: Bool = false

    private func setupPageTimer() {
        pageTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            pageIdx = (pageIdx + 1) % 3
        }
    }

    private func signInAction() {}

    private func getStartedAction() {
        let syncVC = UIStoryboard(name: "Onboarding", bundle: nil).instantiateViewController(withIdentifier: "sync")
        UIApplication.shared.topViewController?.present(syncVC, animated: true)
    }

    private func headlineText(forPageIdx pageIdx: Int) -> AttributedString {
        let string = ["**Privacy-driven**\nActivity Tracking and\n**safety-first** sharing.",
                      "Track your goals &\nearn **motivational\nCollectibles.**",
                      "**Easily Connect** the\nactive life apps\n**you already use.**"][pageIdx % 3]
        return try! AttributedString(markdown: string,
                                     options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    }

    private func subtitleText(forPageIdx pageIdx: Int) -> String {
        return ["No leaderboards. No comparison.\nAny Distance Counts.",
                "Celebrate your active lifestyle.",
                "Connect with Garmin, Wahoo,\nand Apple Health."][pageIdx % 3]
    }

    struct BlurModifier: ViewModifier {
        var radius: CGFloat

        func body(content: Content) -> some View {
            content.blur(radius: radius)
        }
    }

    var body: some View {
        ZStack {
            GradientAnimation(animate: $animate, pageIdx: $pageIdx)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading) {
                HStack {
                    Image("wordmark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 130)
                    Spacer()
                    Button(action: signInAction) {
                        Text("Sign In")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                    }
                }

                Spacer()

                HStack {
                    if #available(iOS 16.0, *) {
                        Text(headlineText(forPageIdx: pageIdx))
                            .font(.system(size: UIScreen.main.bounds.height * 0.041, weight: .regular))
                            .lineSpacing(0)
                            .tracking(-1)
                            .padding(.bottom, 1)
                    } else {
                        Text(headlineText(forPageIdx: pageIdx))
                            .font(.system(size: UIScreen.main.bounds.height * 0.041, weight: .semibold))
                            .lineSpacing(0)
                    }
                }
                .transition(.modifier(active: BlurModifier(radius: 8),
                                      identity: BlurModifier(radius: 0))
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.9))
                            .animation(smoothCurveAnimation))
                .id(pageIdx)

                Text(subtitleText(forPageIdx: pageIdx))
                    .font(.system(size: (UIScreen.main.bounds.height * 0.02).clamped(to: 0...14),
                                  weight: .semibold,
                                  design: .monospaced))
                    .foregroundColor(.white)
                    .opacity(0.7)
                    .transition(.modifier(active: BlurModifier(radius: 8),
                                          identity: BlurModifier(radius: 0))
                        .combined(with: .opacity)
                        .combined(with: .scale(scale: 0.9))
                        .animation(smoothCurveAnimation))
                    .id(pageIdx)

                Carousel(pageIdx: $pageIdx, dragging: $dragging)
                    .frame(width: UIScreen.main.bounds.width - 40)
                    .padding([.top, .bottom], 16)

                Button(action: getStartedAction) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white)
                        Text("Get Started")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black)
                    }
                    .frame(height: 55)
                }

                Text("No sign-up required unless you want to\nstore your goals and Collectibles.")
                    .font(.system(size: 14, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .opacity(0.7)
            }
            .padding([.leading, .trailing], 20)
        }
        .onAppear {
            animate = true
            setupPageTimer()
        }
        .onChange(of: dragging) { newValue in
            if newValue == true {
                pageTimer?.invalidate()
            } else {
                setupPageTimer()
            }
        }
    }
}

struct Onboarding2022View_Previews: PreviewProvider {
    static var previews: some View {
        Onboarding2022View()
    }
}