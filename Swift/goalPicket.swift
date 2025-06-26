// Licensed under the Any Distance Source-Available License
//
//  RecordingQuickLaunchView.swift
//  ADAC
//
//  Created by Daniel Kuntz on 6/29/22.
//

import SwiftUI

fileprivate struct CancelHeader: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var showingSettings: Bool
    @Binding var isPresented: Bool

    var body: some View {
        HStack {
            Button {
                showingSettings = true
            } label: {
                Text("Settings")
                    .foregroundColor(.white)
                    .fontWeight(.medium)
                    .frame(width: 95, height: 50)
            }
            Spacer()
            Button {
                UIApplication.shared.topViewController?.dismiss(animated: true)
                isPresented = false
            } label: {
                Text("Cancel")
                    .foregroundColor(.white)
                    .fontWeight(.medium)
                    .frame(width: 90, height: 50)
            }
        }
    }
}

fileprivate struct TitleView: View {
    var activityType: ActivityType
    var goalType: RecordingGoalType

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(activityType.displayName)
                    .font(.system(size: 28, weight: .semibold, design: .default))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(goalType.promptText)
                    .font(.system(size: 18, weight: .regular, design: .default))
                    .foregroundColor(.white.opacity(0.6))
                    .id(goalType.promptText)
                    .modifier(BlurOpacityTransition(speed: 1.75))
            }
            Spacer()
            Image(activityType.glyphName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 53, height: 53)
        }
    }
}

fileprivate struct GoalTypeSelector: View {
    var types: [RecordingGoalType] = []
    @Binding var selectedIdx: Int

    private var scrollViewAnchor: UnitPoint {
        switch selectedIdx {
        case RecordingGoalType.allCases.count - 1:
            return .trailing
        default:
            return .center
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Array(types.enumerated()),
                            id: \.element.rawValue) { (idx, goalType) in
                        GoalTypeButton(idx: idx,
                                       goalType: goalType,
                                       selectedIdx: $selectedIdx)
                    }
                }
                .padding([.leading, .trailing], 15)
            }
            .introspectScrollView { scrollView in
                scrollView.setValue(0.25, forKeyPath: "contentOffsetAnimationDuration")
            }
            .onChange(of: selectedIdx) { newValue in
                withAnimation {
                    proxy.scrollTo(RecordingGoalType.allCases[selectedIdx].rawValue,
                                   anchor: scrollViewAnchor)
                }
            }
            .onAppear {
                proxy.scrollTo(RecordingGoalType.allCases[selectedIdx].rawValue,
                               anchor: scrollViewAnchor)
            }
        }
    }

    struct GoalTypeButton: View {
        var idx: Int
        var goalType: RecordingGoalType
        @Binding var selectedIdx: Int

        var isSelected: Bool {
            return selectedIdx == idx
        }

        func animation(for idx: Int) -> Animation {
            return idx == 0 ? .timingCurve(0.33, 1, 0.68, 1, duration: 0.35) :
                              .timingCurve(0.25, 1, 0.5, 1, duration: 0.4)
        }

        var body: some View {
            Button {
                let request = FrameRateRequest(duration: 0.5)
                request.perform()

                withAnimation(animation(for: idx)) {
                    selectedIdx = idx
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 40, style: .circular)
                        .fill(isSelected ? Color(goalType.color) : Color(white: 0.2))
                        .frame(height: 50)

                    HStack(alignment: .center, spacing: 6) {
                        let unit = ADUser.current.distanceUnit
                        if let glyph = goalType.glyph(forDistanceUnit: unit) {
                            Image(uiImage: glyph)
                        }
                        Text(goalType.displayName)
                            .font(.system(size: 18, weight: .semibold, design: .default))
                            .foregroundColor((isSelected && goalType == .open) ? .black : .white)
                    }
                    .padding([.leading, .trailing], 20)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 50)
                }
                .contentShape(Rectangle())
                .background(Color.black.opacity(0.01))
                .animation(.none, value: isSelected)
            }
        }
    }
}

fileprivate struct SetTargetView: View {
    @ObservedObject var goal: RecordingGoal
    @ObservedObject var howWeCalculateModel: HowWeCalculatePopupModel
    @State private var originalGoalTarget: Float = -1
    @State private var dragStartPoint: CGPoint?
    private let generator = UISelectionFeedbackGenerator()

    private var bgRectangle: some View {
        Rectangle()
            .padding(.top, 35)
            .opacity(0.001)
            .onTapGesture(count: 2) {
                goal.setTarget(goal.type.defaultTarget)
                generator.selectionChanged()
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { data in
                        if originalGoalTarget == -1 {
                            originalGoalTarget = goal.target
                        }

                        let prevTarget = goal.target
                        var xOffset = -1 * (data.location.x - (dragStartPoint?.x ?? data.startLocation.x))
                        let minDistance: CGFloat = 10.0

                        if abs(xOffset) < minDistance && dragStartPoint == nil {
                            return
                        }

                        if dragStartPoint == nil {
                            dragStartPoint = data.location
                            xOffset = 0.0
                        }

                        let delta = goal.type.slideIncrement * Float((xOffset / 8).rounded())
                        let newTarget = ((originalGoalTarget + delta) / goal.type.slideIncrement).rounded() * goal.type.slideIncrement
                        goal.setTarget(newTarget)

                        if goal.target != prevTarget {
                            generator.selectionChanged()
                        }
                    }
                    .onEnded { _  in
                        originalGoalTarget = -1
                        dragStartPoint = nil
                    }
            )
    }

    var dotBg: some View {
        ZStack {
            Color.black

            Image("dot_bg")
                .resizable(resizingMode: .tile)
                .renderingMode(.template)
                .foregroundColor(Color(goal.type.lighterColor))
                .opacity(0.15)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black, lineWidth: 18)
                .blur(radius: 16)

            VStack {
                Rectangle()
                    .fill(
                        LinearGradient(colors: [.clear, Color(goal.type.color), .clear],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )
                    .frame(height: 90)
                    .offset(y: -30)

                Spacer()
            }
            .scaleEffect(x: 1.8, y: 3)
            .blur(radius: 25)
            .opacity(0.45)

            VStack {
                Rectangle()
                    .fill(
                        LinearGradient(colors: [.clear, Color(goal.type.color), Color(goal.type.color), .clear],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )
                    .frame(height: 1.8)

                Spacer()
            }
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(goal.formattedUnitString)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color(goal.type.lighterColor))
                .shadow(color: Color(goal.type.color), radius: 6, x: 0, y: 0)
                .shadow(color: Color.black, radius: 5, x: 0, y: 0)
                .allowsHitTesting(false)
            HStack {
                Button {
                    goal.setTarget(goal.target - goal.type.buttonIncrement)
                    generator.selectionChanged()
                } label: {
                    Image("glyph_digital_minus")
                        .foregroundColor(Color(white: 0.9))
                        .frame(width: 70, height: 70)
                }
                .padding(.leading, 5)
                .offset(y: -3)

                Spacer()

                Text(goal.formattedTarget)
                    .font(.custom("Digital-7", size: 73))
                    .foregroundColor(Color(goal.type.lighterColor))
                    .shadow(color: Color(goal.type.color), radius: 6, x: 0, y: 0)
                    .allowsHitTesting(false)

                Spacer()

                Button {
                    goal.setTarget(goal.target + goal.type.buttonIncrement)
                    generator.selectionChanged()
                } label: {
                    Image("glyph_digital_plus")
                        .foregroundColor(Color(white: 0.9))
                        .frame(width: 70, height: 70)
                }
                .padding(.trailing, 5)
                .offset(y: -3)
            }

            SlideToAdjust(color: goal.type.lighterColor)
                .shadow(color: Color(goal.type.color), radius: 6, x: 0, y: 0)
                .allowsHitTesting(false)
        }
        .padding([.top, .bottom], 16)
        .overlay {
            HStack {
                VStack {
                    Button {
                        howWeCalculateModel.showStatCalculation(for: goal.type.statisticType)
                    } label: {
                        Image(systemName: .infoCircleFill)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 13)
                            .foregroundColor(Color(goal.type.lighterColor))
                            .padding(16)
                    }
                    .shadow(color: Color(goal.type.color), radius: 7, x: 0, y: 0)
                    .shadow(color: Color.black, radius: 5, x: 0, y: 0)
                    
                    Spacer()
                }
                Spacer()
            }
        }
        .maxWidth(.infinity)
        .background(bgRectangle)
        .background(dotBg)
        .mask(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.2))
                .offset(y: 1)
        }
    }

    struct SlideToAdjust: View {
        var color: UIColor

        var body: some View {
            HStack(spacing: 18) {
                Arrows(color: color)
                Text("SLIDE TO ADJUST")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(color))
                Arrows(color: color)
                    .scaleEffect(x: -1, y: 1, anchor: .center)
            }
        }

        struct Arrows: View {
            let color: UIColor
            let animDuration: Double = 0.8
            @State private var animate: Bool = false

            var body: some View {
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { idx in
                        Image(systemName: .chevronLeft)
                            .font(Font.system(size: 10, weight: .heavy))
                            .foregroundColor(Color(color))
                            .opacity(animate ? 0.2 : 1)
                            .animation(
                                .easeIn(duration: animDuration)
                                .repeatForever(autoreverses: true)
                                .delay(-1 * Double(idx) * animDuration / 5),
                                value: animate)
                    }
                }
                .onAppear {
                    animate = true
                }
            }
        }
    }
}

fileprivate struct TargetOpacityAnimation: AnimatableModifier {
    var progress: CGFloat = 0

    var animatableData: CGFloat {
        get {
            return progress
        }

        set {
            progress = newValue
        }
    }

    func body(content: Content) -> some View {
        let scaledProgress = ((progress - 0.3) * 1.5).clamped(to: 0...1)
        let easedProgress = easeInCubic(scaledProgress)
        content
            .opacity(easedProgress)
            .maxHeight(progress * 140)
    }

    func easeInCubic(_ x: CGFloat) -> CGFloat {
        return x * x * x;
    }
}

struct RecordingGoalSelectionView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject var howWeCalculatePopupModel = HowWeCalculatePopupModel()
    var activityType: ActivityType
    @Binding var goal: RecordingGoal
    @State var hasSetup: Bool = false
    @State var isPresented: Bool = true
    @State var hasRecordingViewAppeared: Bool = false
    @State var showingWeightEntryView: Bool = false
    @State var showingRecordingSettings: Bool = false
    @State var selectedGoalTypeIdx: Int = 1
    @State var prevSelectedGoalTypeIdx: Int = 1
    @State var goals: [RecordingGoal] = []
    
    private let generator = UIImpactFeedbackGenerator(style: .heavy)
    private let screenName = "Tracking Goal Select"

    func goal(for idx: Int) -> RecordingGoal {
        return goals[idx]
    }
    
    func setTargetGoal(for idx: Int) -> RecordingGoal {
        if selectedGoalTypeIdx == 0 {
            return goal(for: prevSelectedGoalTypeIdx)
        } else {
            return goal(for: idx)
        }
    }

    var body: some View {
        ZStack {
            BlurView(style: .systemUltraThinMaterialDark,
                     intensity: 0.55,
                     animatesIn: true,
                     animateOut: !isPresented)
                .padding(.top, -1500)
                .opacity(hasRecordingViewAppeared ? 0 : 1)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                    presentationMode.dismiss()
                }
            
            VStack {
                HowWeCalculatePopup(model: howWeCalculatePopupModel, drawerClosedHeight: 0)
                
                VStack(spacing: 16) {
                    CancelHeader(showingSettings: $showingRecordingSettings,
                                 isPresented: $isPresented)
                        .zIndex(20)
                        .padding(.bottom, -12)
                        .padding(.top, 6)
                        .padding([.leading, .trailing], 8)
                    
                    if !goals.isEmpty {
                        VStack(spacing: 16) {
                            TitleView(activityType: activityType,
                                      goalType: goal.type)
                            GoalTypeSelector(types: goals.map { $0.type },
                                             selectedIdx: $selectedGoalTypeIdx)
                                .zIndex(20)
                                .padding([.leading, .trailing], -21)
                            SetTargetView(goal: goal,
                                          howWeCalculateModel: howWeCalculatePopupModel)
                                .animation(.none)
                                .modifier(TargetOpacityAnimation(progress: selectedGoalTypeIdx > 0 ? 1.0 : 0.0))
                            Button {
                                generator.impactOccurred()
                                isPresented = false
                                presentationMode.wrappedValue.dismiss()
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(UIColor.adOrangeLighter))

                                    Text("Set Goal")
                                        .foregroundColor(.black)
                                        .semibold()
                                }
                                .frame(height: 56)
                                .maxWidth(.infinity)
                            }
                            .padding(.top, 2)
                            .zIndex(20)
                        }
                        .padding(.bottom, 15)
                        .padding([.leading, .trailing], 21)
                    }
                }
                .background(
                    Color(white: 0.05)
                        .cornerRadius(35, corners: [.topLeft, .topRight])
                        .ignoresSafeArea()
                )
            }
        }
        .background(Color.clear)
        .onAppear {
            goals = NSUbiquitousKeyValueStore.default.goals(for: activityType)
            goals.forEach { goal in
                goal.unit = ADUser.current.distanceUnit
            }
            selectedGoalTypeIdx = goals.firstIndex(where: { $0.type == goal.type }) ?? 0
            goals[selectedGoalTypeIdx] = goal
            if !NSUbiquitousKeyValueStore.default.hasSetBodyMass && ADUser.current.totalDistanceTracked > 0.0 {
                showingWeightEntryView = true
            }

            hasSetup = true
        }
        .onDisappear {
            NSUbiquitousKeyValueStore.default.setGoals(goals, for: activityType)
            NSUbiquitousKeyValueStore.default.setSelectedGoalIdx(selectedGoalTypeIdx, for: activityType)
            Analytics.logEvent("Dismiss", screenName, .buttonTap)
        }
        .onChange(of: selectedGoalTypeIdx) { [selectedGoalTypeIdx] newValue in
            guard hasSetup else {
                return
            }

            goal = goal(for: newValue)
            goal.objectWillChange.send()
            prevSelectedGoalTypeIdx = selectedGoalTypeIdx
            if howWeCalculatePopupModel.statCalculationInfoVisible {
                howWeCalculatePopupModel.showStatCalculation(for: goals[newValue].type.statisticType)
            }
        }
        .fullScreenCover(isPresented: $showingWeightEntryView) {
            WeightEntryView()
                .background(BackgroundClearView())
        }
        .fullScreenCover(isPresented: $showingRecordingSettings) {
            RecordingSettingsView()
                .background(BackgroundClearView())
        }
    }
}