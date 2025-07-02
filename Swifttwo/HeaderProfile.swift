// Licensed under the Any Distance Source-Available License
//
//  ProfileView.swift
//  ADAC
//
//  Created by Daniel Kuntz on 2/23/23.
//

import SwiftUI
import HealthKit
import Combine
import PhotosUI
import SwiftUIX
import SDWebImage

/// View modifier that flashes a white border around the parent; used when editing name, bio, etc.
struct EditingAnimationBorder: ViewModifier {
    var verticalOutset: CGFloat = 0.0
    var cornerRadius: CGFloat = 8.0
    var opacity: CGFloat = 1.0
    @State var editingAnimation: Bool = false

    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
                    .padding([.top, .bottom], verticalOutset)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(editingAnimation ? Color.white : Color.white.opacity(0.5))
                            .opacity(opacity)
                    }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    editingAnimation = !editingAnimation
                }
            }
    }
}

/// Vertical stack that shows a friend's posts
struct UserPosts: View {
    @ObservedObject var model: ProfileViewModel

    var body: some View {
        if !model.postCellModels.isEmpty {
            LazyVStack(spacing: 12) {
                ForEach(model.postCellModels, id: \.post.id) { model in
                    PostCell(model: model)
                        .modifier(BlurOpacityTransition(speed: 1.5))
                }

                Spacer()
            }
            .padding([.leading, .trailing], 15)
            .padding(.top, 15)
        } else {
            if model.user.isSelf {
                AndiEmptyState(text: "You have not posted any activities yet.")
                    .padding(.top, 30)
            } else {
                AndiEmptyState(text: "@\(model.user.username ?? "") has not posted any activities yet.")
                    .padding(.top, 30)
            }
            Spacer()
        }
    }
}

fileprivate struct TitleView: View {
    @Binding var scrollViewOffset: CGFloat

    func showSettings() {
        let vc = SettingsViewController()
        vc.modalPresentationStyle = .overFullScreen
        vc.showCloseButton = true
        UIApplication.shared.topViewController?.present(vc, animated: true)
    }

    var body: some View {
        VStack(alignment: .leading) {
            Spacer()
                .frame(height: 45.0)

            let p = (scrollViewOffset / -80.0)
            let col = Double(0.6 + ((1.0 - p) * 0.4)).clamped(to: 0.6...1.0)

            HStack {
                Image("wordmark")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(Color(white: col))
                    .frame(width: 160)
                    .scaleEffect((0.6 + ((1.0 - p) * 0.4)).clamped(to: 0.6...1.0),
                                 anchor: .leading)
                    .offset(y: scrollViewOffset < 0 ? 0 : (0.3 * scrollViewOffset))
                    .offset(y: (-22.0 * p).clamped(to: -22.0...0.0))
                Spacer()
            }
            .overlay {
                HStack {
                    Spacer()
                    Button {
                        showSettings()
                    } label: {
                        Image(systemName: .gear)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24.0, height: 24.0)
                            .foregroundStyle(Color.white)
                            .padding()
                            .contentShape(Rectangle())
                            .opacity((1.0 - (scrollViewOffset / -70)).clamped(to: 0...1) * 0.6)
                            .blur(radius: (10 * scrollViewOffset / -70).clamped(to: 0...10))
                    }
                    .offset(x: 16.0)
                    .offset(y: scrollViewOffset < 0 ? 0 : (0.3 * scrollViewOffset))
                }
            }
        }
        .padding(.top, -22.5)
        .padding([.leading, .trailing], 20.0)
    }
}

fileprivate struct TopGradient: View {
    @Binding var scrollViewOffset: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.black
                .frame(height: UIApplication.shared.topViewController?.view.safeAreaInsets.top ?? 0.0)
            Image("gradient_bottom_ease_in_out")
                .resizable(resizingMode: .stretch)
                .scaleEffect(y: -1)
                .frame(width: UIScreen.main.bounds.width, height: 60.0)
                .overlay {
                    VariableBlurView()
                        .offset(y: -10)
                }
            Spacer()
        }
        .opacity((1.0 - (scrollViewOffset / 50.0)).clamped(to: 0...1))
        .ignoresSafeArea()
    }
}

fileprivate struct SuperDistanceCell: View {
    let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        Button {
            feedbackGenerator.impactOccurred()
            let vc = UIHostingController(rootView: SuperDistanceView())
            vc.modalPresentationStyle = .overFullScreen
            UIApplication.shared.topViewController?.present(vc, animated: true)
        } label: {
            HStack {
                Text("Try")
                Image("glyph_superdistance_white")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100.0)
                    .modifier(GradientEffect())
                Text("for free")
                Spacer()
                Image(systemName: .arrowRightCircleFill)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Color.white)
                    .opacity(0.3)
            }
            .foregroundColor(.white)
            .font(.system(size: 15.0, weight: .medium))
            .padding(22.0)
            .background(Color.white.opacity(0.1))
            .cornerRadius(18, style: .continuous)
        }
        .buttonStyle(ScalingPressButtonStyle())
        .padding([.leading, .trailing], 15.0)
    }
}

/// Cell that shows a private activity that has not been posted
struct ActivityCell: View {
    @StateObject var user = ADUser.current
    var activity: Activity
    var showNewActivityLabel: Bool = false
    var onTap: (() -> Void)?
    @State private var graphImage: UIImage?
    @State private var mapRouteImage: UIImage?
    @State private var bigLabelString: String = ""
    @State private var smallLabelString: String = ""

    func computeBigLabelString() -> String {
        if activity is DailyStepCount,
           let stepCount = activity.stepCount {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return (formatter.string(from: NSNumber(value: stepCount)) ?? "\(stepCount)") + " steps"
        } else if activity.distance > 0.0 {
            return "\(activity.distanceInUserSelectedUnit.rounded(toPlaces: 1))\(ADUser.current.distanceUnit.abbreviation)"
        } else if activity.movingTime > 0.0 {
            return activity.movingTime.timeFormatted(includeSeconds: true, includeAbbreviations: true)
        } else if activity.activeCalories > 0.0 {
            return "\(Int(activity.activeCalories))cal"
        } else {
            return ""
        }
    }

    func computeSmallLabelString() -> String {
        if Calendar.current.isDateInToday(activity.startDateLocal) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(activity.startDateLocal) {
            return "Yesterday"
        }
        return activity.startDateLocal.formatted(withStyle: .medium)
    }

    func loadGraphImage() {
        Task(priority: .userInitiated) {
            if activity is DailyStepCount {
                graphImage = await activity.tinyStepCountsGraphImage()?.byPreparingForDisplay()
            } else {
                graphImage = try? await activity.routeImageMini?.byPreparingForDisplay()
            }
        }
    }

    func loadMapImage() {
        Task(priority: .userInitiated) {
            self.mapRouteImage = await activity.mapRouteImage?.byPreparingForDisplay()
        }
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            ZStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 12) {
                        Image(activity.activityType.glyphName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(bigLabelString)
                                .font(.presicav(size: 21))
                                .foregroundColor(.white)
                            if !showNewActivityLabel {
                                Text(smallLabelString)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white)
                                    .opacity(0.6)
                            }
                        }
                        Spacer()

                        if let graphImage = graphImage {
                            Image(uiImage: graphImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 40, height: 40)
                                .opacity(0.6)
                                .padding(.trailing, 8)
                                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                        }
                    }

                    if showNewActivityLabel {
                        Text("New activity: Tap to post")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .opacity(0.45)
                    }
                }
                .padding(22)
                .background {
                    Color.white
                        .opacity(0.1)
                        .overlay {
                            ZStack {
                                if let mapImage = mapRouteImage {
                                    Image(uiImage: mapImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .saturation(0.0)
                                        .contrast(1.45)
                                        .brightness(0.08)
                                        .opacity(0.8)
                                        .mask {
                                            Image("layout_gradient_left")
                                                .resizable(resizingMode: .stretch)
                                        }
                                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                                }
                            }
                            .allowsHitTesting(false)
                        }
                        .cornerRadius(18, style: .continuous)
                }
                .padding([.leading, .trailing], 15)
            }
        }
        .buttonStyle(ScalingPressButtonStyle())
        .onAppear {
            if bigLabelString == "" && smallLabelString == "" {
                bigLabelString = computeBigLabelString()
                smallLabelString = computeSmallLabelString()
            }

            if activity.activityType.isDistanceBased && mapRouteImage == nil {
                loadMapImage()
            } else if graphImage == nil {
                loadGraphImage()
            }
        }
        .onDisappear {
            mapRouteImage = nil
            graphImage = nil
        }
        .onReceive(user.$distanceUnit) { _ in
            bigLabelString = computeBigLabelString()
            smallLabelString = computeSmallLabelString()
        }
    }
}

struct CollectibleCell: View {
    var collectible: Collectible
    var onTap: (() -> Void)?

    @State private var medalImage: UIImage?

    func loadMedalImage() {
        Task(priority: .userInitiated) {
            medalImage = await collectible.medalImage?.byPreparingForDisplay()
        }
    }

    var smallLabelString: String {
        if Calendar.current.isDateInToday(collectible.dateEarned) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(collectible.dateEarned) {
            return "Yesterday"
        }
        return collectible.dateEarned.formatted(withStyle: .medium)
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 12) {
                    Image(uiImage: medalImage ?? UIImage())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 54)
                        .padding(.trailing, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(collectible.description)
                            .font(.presicav(size: 21))
                            .foregroundColor(.white)
                        Text(collectible.typeDescription)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .opacity(0.6)
                    }
                    Spacer()

                    Image(systemName: .arrowRightCircleFill)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .foregroundStyle(Color.white)
                        .opacity(0.3)
                }
            }
            .padding([.leading, .trailing], 22)
            .padding([.top, .bottom], 18)
            .background {
                Color.white
                    .opacity(0.1)
            }
            .overlay {
                ConfettiSwiftUIView(confettiColors: collectible.type.confettiColors,
                                    style: .small,
                                    beginAtTimeZero: false,
                                    isStarted: .constant(true))
                .allowsHitTesting(false)
            }
            .cornerRadius(18, style: .continuous)
            .padding([.leading, .trailing], 15)
        }
        .buttonStyle(ScalingPressButtonStyle())
        .onAppear {
            loadMedalImage()
        }
        .onDisappear {
            medalImage = nil
        }
    }
}

struct MilestoneCell: View {
    var milestone: Milestone
    var onTap: (() -> Void)?

    @State private var image: UIImage?

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 12) {
                    if let imageName = milestone.imageName {
                        Image(imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36, height: 54)
                            .padding(.trailing, 2)
                    } else {
                        Image(uiImage: image ?? UIImage())
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36, height: 54)
                            .padding(.trailing, 2)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(milestone.description)
                            .font(.presicav(size: 19))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Next Milestone")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .opacity(0.6)
                    }
                    Spacer()

                    Image(systemName: .arrowRightCircleFill)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .foregroundStyle(Color.white)
                        .opacity(0.3)
                }
            }
            .padding([.leading, .trailing], 22)
            .padding([.top, .bottom], 18)
            .background {
                Color.white
                    .opacity(0.1)
            }
            .cornerRadius(18, style: .continuous)
            .padding([.leading, .trailing], 15)
        }
        .buttonStyle(ScalingPressButtonStyle())
        .onAppear {
            if let imageURL = milestone.imageURL {
                SDWebImageManager.shared.loadImage(with: imageURL, progress: nil) { loadedImage, _, _, _, _, _ in
                    image = loadedImage
                }
            }
        }
        .onDisappear {
            image = nil
        }
    }
}

private struct ActivityStatText: View {
    var numerator: Double
    var denominator: Double
    var unitLabel: String
    var bottomLabel: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .bottom, spacing: 0.0) {
                Text(String(Int(numerator)))
                Text("/")
                Text(String(Int(denominator)))
                Text(unitLabel)
                    .font(.system(size: 16, design: .monospaced))
                    .padding(.leading, 1.0)
                    .offset(y: -1.5)
            }
            .font(.system(size: 22, design: .monospaced))
            .foregroundColor(color)

            Text(bottomLabel)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.white)
                .opacity(0.5)
        }
    }
}

fileprivate extension Color {
    static let ringActiveEnergyColor = Color(hexadecimal: "F72467")!
    static let ringExerciseColor = Color(hexadecimal: "A5FA00")!
    static let ringStandColor = Color(hexadecimal: "00F7D1")!
}

fileprivate struct DailyActivity: View {
    @State private var ringData: HKActivitySummary?
    @State private var hasRingsAuthorization = HealthKitActivitiesStore.shared.hasRequestedRingsAuthorization()

    var body: some View {
        VStack(spacing: 12.0) {
            ZStack {
                if !hasRingsAuthorization {
                    HStack(alignment: .center, spacing: 16.0) {
                        Image("rings_empty_state")
                            .frame(width: 138.0, height: 138.0)

                        VStack(spacing: 10.0) {
                            Text("See your Move, Exercise, and Stand rings from Fitness.")
                                .font(.system(size: 11.5, weight: .medium))
                                .multilineTextAlignment(.center)
                            Button {
                                HealthKitActivitiesStore.shared.requestAuthorization(with: "Progress") {
                                    hasRingsAuthorization = true
                                }
                            } label: {
                                RoundedWhiteButtonLabel(text: "Next")
                            }
                            .frame(width: 100.0, height: 35.0)
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 16.0) {
                        ActivityRingView(summary: $ringData)
                            .frame(width: 138.0, height: 138.0)
                            .mask(Circle())
                            .mask(ShapeWithHole(cutout: CGSize(width: 48.0, height: 48.0)))

                        VStack(alignment: .leading) {
                            ActivityStatText(numerator: ringData?.activeEnergyBurned.doubleValue(for: .kilocalorie()) ?? 0.0,
                                             denominator: ringData?.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()) ?? 0.0,
                                             unitLabel: "CAL",
                                             bottomLabel: "Move",
                                             color: .ringActiveEnergyColor)
                            Spacer()
                                .maxWidth(.infinity)
                            ActivityStatText(numerator: ringData?.appleExerciseTime.doubleValue(for: .minute()) ?? 0.0,
                                             denominator: ringData?.exerciseTimeGoal?.doubleValue(for: .minute()) ?? 0.0,
                                             unitLabel: "MIN",
                                             bottomLabel: "Exercise",
                                             color: .ringExerciseColor)
                            Spacer()
                            ActivityStatText(numerator: ringData?.appleStandHours.doubleValue(for: .count()) ?? 0.0,
                                             denominator: ringData?.standHoursGoal?.doubleValue(for: .count()) ?? 0.0,
                                             unitLabel: "HRS",
                                             bottomLabel: "Stand",
                                             color: .ringStandColor)
                        }
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 18.0)
                    .foregroundColor(.white)
                    .opacity(0.1)
            }
        }
        .padding([.leading, .trailing], 15)
        .task {
            guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else {
                ringData = HKActivitySummary()
                return
            }
            ringData = try? await HealthKitHealthDataLoader().getActivityRingData(for: Date())
        }
    }
}

/// Vertical stack of current user posts and activities, interleaved and sorted by date
struct UserPostsAndActivities: View {
    @ObservedObject var model: ProfileViewModel
    var isToday: Bool = false
    var cellData: [CellModel]
    let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    let startOfDay = Calendar.current.startOfDay(for: Date())
    let startOfYesterday = Calendar.current.date(byAdding: DateComponents(day: -1),
                                                 to: Calendar.current.startOfDay(for: Date()))!
    let startOfWeek = Calendar.current.startOfWeek(for: Date())

    func cells(with cellData: [CellModel]) -> some View {
        ForEach(cellData, id: \.id) { data in
            if let postModel = data.postModel {
                PostCell(model: postModel)
                    .padding([.leading, .trailing], 15)
                    .padding(.top, 0.1)
                    .modifier(BlurOpacityTransition(speed: 2.5))
            } else if let activity = data.activity {
                ActivityCell(activity: activity) {
                    feedbackGenerator.impactOccurred()
                    if !(activity is DailyStepCount) {
                        UIApplication.shared.topViewController?.showPostDraft(for: activity)
                    } else {
                        let storyboard = UIStoryboard(name: "Activities", bundle: nil)
                        guard let vc = storyboard.instantiateViewController(withIdentifier: "design") as? DesignViewController else {
                            return
                        }
                        vc.viewModel = ActivityDesignViewModel(activity: activity)
                        let navigationVC = UINavigationController(rootViewController: vc)
                        navigationVC.modalPresentationStyle = .fullScreen
                        UIApplication.shared.topViewController?.present(navigationVC, animated: true)
                    }
                }
                .border(Color.clear) // fixes a touch down tap target bug with ScalingPressButtonStyle()
                .modifier(BlurOpacityTransition(speed: 2.5))
            } else if let collectible = data.collectible {
                CollectibleCell(collectible: collectible) {
                    feedbackGenerator.impactOccurred()
                    let storyboard = UIStoryboard(name: "Collectibles", bundle: nil)
                    guard let vc = storyboard.instantiateViewController(withIdentifier: "collectibleDetail") as? CollectibleDetailViewController else {
                        return
                    }

                    vc.collectible = collectible
                    vc.collectibleEarned = ADUser.current.collectibles
                        .contains(where: { $0.type.rawValue == collectible.type.rawValue })
                    UIApplication.shared.topViewController?.present(vc, animated: true)
                    Analytics.logEvent("Collectible tapped", model.screenName, .buttonTap)
                }
                .border(Color.clear) // fixes a touch down tap target bug with ScalingPressButtonStyle()
            } else if let milestone = data.milestone {
                MilestoneCell(milestone: milestone) {
                    feedbackGenerator.impactOccurred()
                    Analytics.logEvent("Milestone tapped", model.screenName, .buttonTap,
                                       withParameters: ["milestone": milestone.description])
                    milestone.action()
                }
                .border(Color.clear) // fixes a touch down tap target bug with ScalingPressButtonStyle()
                .modifier(BlurOpacityTransition(speed: 2.5))
            } else {
                EmptyView()
            }
        }
    }

    var body: some View {
        let categorizedData: ([CellModel], [CellModel], [CellModel], [CellModel]) = cellData
            .reduce(into: ([], [], [], [])) { result, cell in
            if cell.sortDate >= startOfDay {
                result.0.append(cell)
            } else if cell.sortDate >= startOfYesterday {
                result.1.append(cell)
            } else if cell.sortDate >= startOfWeek {
                result.2.append(cell)
            } else {
                result.3.append(cell)
            }
        }

        let (todayData, yesterdayData, thisWeekData, earlierData) = categorizedData

        if !todayData.isEmpty {
            SectionHeaderText(text: "Today")
                .padding(.leading, 15)
                .padding(.top, 16)
                .id("todayHeader")
                .modifier(BlurOpacityTransition(speed: 2.5))
            cells(with: todayData)
        }
        if !yesterdayData.isEmpty {
            SectionHeaderText(text: "Yesterday")
                .padding(.leading, 15)
                .padding(.top, 16)
                .id("yesterdayHeader")
                .modifier(BlurOpacityTransition(speed: 2.5))
            cells(with: yesterdayData)
        }

        if !thisWeekData.isEmpty {
            SectionHeaderText(text: "This Week")
                .padding(.leading, 15)
                .padding(.top, 16)
                .id("thisWeekHeader")
                .modifier(BlurOpacityTransition(speed: 2.5))
            cells(with: thisWeekData)
        }

        if !earlierData.isEmpty {
            SectionHeaderText(text: "Earlier")
                .padding(.leading, 15)
                .padding(.top, 16)
                .id("earlierHeader")
                .modifier(BlurOpacityTransition(speed: 2.5))
            cells(with: earlierData)
        }

        Spacer()
            .frame(height: 25)
            .id("userPostsAndActivitiesSpacer")
    }
}

/// Empty state view that shows if profile is current user and user hasn't granted Apple Health
/// permission
struct ProfileConnectHealth: View {
    @ObservedObject var model: ProfileViewModel

    var body: some View {
        VStack(spacing: 14.0) {
            Image("glyph_phone_privacy_health")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120.0, height: 120.0)
            Text("Sync your past activities by giving Any Distance access to Apple Health.")
                .multilineTextAlignment(.center)
                .font(.system(size: 16))
                .foregroundColor(.white)
            ADWhiteButton(title: "Authorize Health",
                          action: model.authorizeHealth)
            Button {
                UIApplication.shared.open(Links.privacyCommitment)
            } label: {
                Text("Our Privacy Commitment →")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .padding(10)
            }
        }
        .padding([.leading, .trailing], 30)
        .padding(.top, 30)
        .padding(.bottom, 50)
    }
}

/// Convenience button view used across ProfileView
fileprivate struct ProfileViewButton: View {
    var title: String
    var symbolName: SFSymbolName?
    var backgroundColor: Color
    var textColor: Color
    var action: (() -> Void)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(textColor)
                    .fixedSize(horizontal: true, vertical: false)
                if let symbolName = symbolName {
                    Image(systemName: symbolName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 10, height: 10)
                        .foregroundColor(textColor)
                }
            }
            .padding([.top, .bottom], 9)
            .padding([.leading, .trailing], 15)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .foregroundColor(backgroundColor)
            }
        }
    }
}

struct MedalCarousel: View {
    @ObservedObject var user: ADUser

    var body: some View {
        VStack(alignment: .center, spacing: 12.0) {
            HStack {
                SectionHeaderText(text: "Achievements")

                if user.isSelf {
                    Spacer()
                    Button {
                        let storyboard = UIStoryboard(name: "Collectibles", bundle: nil)
                        let vc = storyboard.instantiateViewController(withIdentifier: "UINavigationController-NT8-MA-SsK")
                        vc.modalPresentationStyle = .overFullScreen
                        UIApplication.shared.topViewController?.present(vc, animated: true)
                        Analytics.logEvent("All collectibles tapped", "Medal Carousel", .buttonTap)
                    } label: {
                        HStack {
                            Text("View all")
                            Image(systemName: .chevronRight)
                        }
                        .font(.system(size: 15.0, weight: .medium))
                        .foregroundStyle(Color.white)
                        .padding([.leading, .trailing], 12)
                        .padding([.top, .bottom], 7.5)
                        .background {
                            RoundedRectangle(cornerRadius: 40.0)
                                .fill(Color.white.opacity(0.1))
                        }
                    }
                }
            }
            .padding([.leading, .trailing], 15)

            let medalWidth: CGFloat = 48.0
            let medalSpacing: CGFloat = 10.0
            let first30Medals = user.medals(first: 30, unique: true)

            HorizontalImageRow(imageSize: CGSize(width: medalWidth, height: medalWidth * 1.525),
                               imageSpacing: medalSpacing,
                               collectibles: first30Medals,
                               alwaysAnimate: true) { collectible in
                let storyboard = UIStoryboard(name: "Collectibles", bundle: nil)
                guard let vc = storyboard.instantiateViewController(withIdentifier: "collectibleDetail") as? CollectibleDetailViewController else {
                    return
                }

                vc.collectible = collectible
                vc.collectibleEarned = ADUser.current.collectibles
                    .contains(where: { $0.type.rawValue == collectible.type.rawValue })
                UIApplication.shared.topViewController?.present(vc, animated: true)
                Analytics.logEvent("Collectible tapped", "Medal Carousel", .buttonTap)
            }
           .frame(height: medalWidth * 1.525)
           .mask {
               GeometryReader { geo in
                   HStack(spacing: 0) {
                       Image("layout_gradient_left")
                           .resizable(resizingMode: .stretch)
                           .frame(width: geo.size.width * 0.05)
                       Color.black
                       Image("layout_gradient_right")
                           .resizable(resizingMode: .stretch)
                           .frame(width: geo.size.width * 0.05)
                   }
               }
           }
        }
    }
}

struct ActivityTypeSegmentedControl: View {
    var activityTypes: [ActivityType]
    var fontSize: CGFloat = 15.0
    var showBg: Bool = true
    @Binding var selectedActivityType: ActivityType
    @Namespace private var segmentAnimation
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        HStack(spacing: -8.0) {
            ForEach(activityTypes.enumerated().map { $0 }, id: \.element) { (idx, activityType) in
                Button {
                    selectedActivityType = activityType
                    feedbackGenerator.impactOccurred()
                } label: {
                    HStack(spacing: 5.0) {
                        Image(activityType.glyphName)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20.0, height: 20.0)
                            .foregroundColor(activityType == selectedActivityType ? .black : .white)
                            .offset(x: 17.0)

                        Text(activityType.displayName)
                            .font(.system(size: fontSize, weight: .medium))
                            .foregroundColor(activityType == selectedActivityType ? .black : .white)
                            .padding([.leading, .trailing], fontSize * 1.46)
                            .padding([.top, .bottom], fontSize * 0.86)
                            .background {
                                Color.black.opacity(0.01)
                                    .padding([.top, .bottom], -20.0)
                            }
                    }
                }
                .background {
                    ZStack {
                        if activityType == selectedActivityType {
                            RoundedRectangle(cornerRadius: 30.0, style: .continuous)
                                .foregroundColor(.white)
                                .matchedGeometryEffect(id: "rect", in: segmentAnimation)
                        } else {
                            EmptyView()
                        }
                    }
                    .padding(0.24 * fontSize)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.5),
                           value: selectedActivityType)
                .id(activityType.rawValue)
            }
        }
        .background {
            if showBg {
                DarkBlurView()
                    .brightness(0.1)
                    .cornerRadius(24.0, style: .continuous)
            } else {
                EmptyView()
            }
        }
    }
}


/// Screen that shows a user profile (current user or other user) with editing capability if it's the
/// current user
struct ProfileView: View {
    @ObservedObject var model: ProfileViewModel
    @StateObject var iapManager: iAPManager = .shared
    var presentedInSheet: Bool = false
    @State var cellData: [CellModel] = []
    @State var activityTypes: [ActivityType] = []
    @State var selectedActivityType: ActivityType = NSUbiquitousKeyValueStore.default.profileSelectedActivityType
    @State var isInitialLoading: Bool = false
    @State var scrollViewOffset: CGFloat = 0.0
    @State var isRefreshing: Bool = false
    @State private var selectedProfilePhoto: PhotosPickerItem? = nil
    @State private var selectedCoverPhoto: PhotosPickerItem? = nil
    @State private var hasHealthAuthoriztion = HealthKitActivitiesStore.shared.hasRequestedAuthorization()
    @State private var dimView: Bool = false

    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    private func load() {
        guard model.user.isSelf && hasHealthAuthoriztion else {
            return
        }

        let currentUserId = ADUser.current.id
        let userPosts = PostCache.shared.posts(forUserID: currentUserId)
        let userPostIds = Set(userPosts.compactMap { $0.localHealthKitID })

        var newCellData = ActivitiesData.shared.activities.compactMap { activity -> CellModel? in
            guard userPostIds.contains(activity.id) == false else { return nil }
            if selectedActivityType != .all && activity.activity.activityType != selectedActivityType {
                return nil
            }
            return CellModel(activity: activity.activity)
        }

        if selectedActivityType == .all {
            newCellData += ADUser.current.collectibles.map { CellModel(collectible: $0) }
            if let nextMilestone = ADUser.current.nextMilestone() {
                newCellData.append(CellModel(milestone: nextMilestone))
            }
        }

        newCellData += model.postCellModels
            .filter { model in
                if selectedActivityType != .all {
                    return model.post.activityType == selectedActivityType
                }
                return true
            }
            .map { CellModel(postModel: $0) }

        newCellData.sort(by: { $0.sortDate > $1.sortDate })

        self.cellData = newCellData
    }

    private func loadActivityTypes() {
        let activities = ActivitiesData.shared.activities

        var activityTypeMap: [ActivityType: Int] = [:]
        for activity in activities {
            if activityTypeMap[activity.activity.activityType] == nil {
                activityTypeMap[activity.activity.activityType] = 1
            } else {
                activityTypeMap[activity.activity.activityType]! += 1
            }
        }

        activityTypes = [.all] + Array(activityTypeMap)
            .sorted(by: { v1, v2 in
                if v1.value != v2.value {
                    return v1.value > v2.value
                }
                return v1.key.rawValue < v2.key.rawValue
            })
            .map { $0.key }
    }

    var headerHeight: CGFloat {
        return model.user.hasRegistered ? 140.0 : 0.0
    }

    var scrollReader: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(key: CGFloatPreferenceKey.self,
                            value: geometry.frame(in: .named("scroll")).minY)
        }
    }

    var coverImageAndNameAnimation: some View {
        ZStack {
            let scale = ((scrollViewOffset + 200) * 0.005).clamped(to: 1.0...5.0)
            let blur = (10.0 * (-scrollViewOffset / 110)).clamped(to: 0...10.0)
            VStack {
                if model.user.isBlocked {
                    Color(white: 0.1)
                } else {
                    AsyncCachedImage(url: model.user.coverPhotoUrl)
                        .frame(height: 200)
                        .opacity(0.5)
                        .scaleEffect(x: scale, y: scale, anchor: .top)
                        .blur(radius: (scale - 1) * 10)
                        .blur(radius: blur)
                        .id(model.user.coverPhotoUrl?.absoluteString ?? "")
                        .parallaxEffect()
                }
                Spacer()
            }
            .ignoresSafeArea()
            .maxWidth(UIScreen.main.bounds.width)

            VStack {
                if !model.isEditing {
                    let longNameScale = model.user.name.count >= 20 ? 0.7 : 1.0

                    CurvedTextAnimationView(text: model.user.name.uppercased(), radius: 100)
                        .scaleEffect(x: longNameScale, y: longNameScale, anchor: .top)
                        .frame(height: 300)
                        .scaleEffect(x: scale, y: scale, anchor: .top)
                        .blur(radius: (scale - 1) * 10)
                        .blur(radius: blur)
                        .offset(y: isRefreshing ? 30.0 : 0.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isRefreshing)
                }

                Spacer()
            }
            .padding(.top, 25)
            .id(model.isEditing ? 1 : 0)
            .modifier(BlurOpacityTransition(speed: 1.7))
        }
        .opacity((1.0 - (scrollViewOffset / -110)).clamped(to: 0...1))
        .if(presentedInSheet) { view in
            view
                .background(Color.black)
                .cornerRadius([.topLeading, .topTrailing], 35)
        }
    }

    var profilePicture: some View {
        ZStack {
            let offset = scrollViewOffset + headerHeight
            let drawerOffset = offset < -200 ? -1 * offset : 0
            let profilePictureScale: CGFloat = ((offset + 30) / headerHeight).clamped(to: 0.0...1.0)
            let profilePictureBlur: CGFloat = 10 * (1 - ((offset + 30) / headerHeight).clamped(to: 0.0...1.0))

            ZStack {
                VStack(spacing: 0) {
                    Image("gradient_bottom_ease_in_out")
                        .renderingMode(.template)
                        .resizable(resizingMode: .stretch)
                        .frame(width: UIScreen.main.bounds.width, height: 110)
                        .foregroundColor(.black)
                        .offset(y: drawerOffset)
                    Color.black
                        .padding(.bottom, -800)
                }
                .offset(y: -70)

                VStack {
                    PhotosPicker(selection: $selectedProfilePhoto, matching: .images) {
                        UserProfileImageView(user: model.user,
                                             showsLoadingIndicator: true,
                                             width: 76)
                        .scaleEffect(x: profilePictureScale,
                                     y: profilePictureScale,
                                     anchor: UnitPoint(x: 0.5, y: 0.6))
                        .blur(radius: profilePictureBlur)
                    }
                    .allowsHitTesting(model.isEditing)
                    .onChange(of: selectedProfilePhoto) { newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                if let image = UIImage(data: data) {
                                    model.setProfilePicture(image)
                                }
                            }
                        }
                    }
                    .overlay {
                        Color.black
                            .opacity(0.01)
                            .if(model.isEditing) { view in
                                view.modifier(EditingAnimationBorder(verticalOutset: 20,
                                                                     cornerRadius: 38.0))
                            }
                            .allowsHitTesting(false)
                    }
                    Spacer()
                }
                .padding(.top, -68)
                .offset(y: drawerOffset)
            }
            .ignoresSafeArea(edges: .bottom)
            .padding(.top, headerHeight)
        }
        .offset(y: scrollViewOffset * 0.8)
    }

    var usernameBioLocation: some View {
        VStack(spacing: 12) {
            Text("@" + (model.user.username ?? ""))
                .font(.system(size: 13, weight: .medium, design: .monospaced))

            if !model.user.isBlocked {
                ZStack {
                    if model.isEditing {
                        TextField("", text: $model.bioPendingEdit, axis: .vertical)
                            .font(.system(size: 13))
                            .multilineTextAlignment(.center)
                            .submitLabel(.done)
                            .tint(.adOrangeLighter)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 20)
                            .modifier(EditingAnimationBorder(verticalOutset: 20))
                            .overlay {
                                HStack {
                                    Text("Write a bio...")
                                        .font(.system(size: 13))
                                        .opacity(model.bioPendingEdit.isEmpty ? 0.4 : 0.0)
                                    Spacer()
                                }
                                .padding(.leading, 12)
                            }
                    } else if !model.user.bio.isEmpty || model.user.isSelf {
                        Text(model.user.bio.isEmpty && model.user.isSelf ? "Tap \"Edit\" to add a bio" : model.user.bio)
                            .font(.system(size: 13))
                            .multilineTextAlignment(.center)
                            .frame(minHeight: 20)
                            .opacity(model.user.bio.isEmpty && model.user.isSelf ? 0.6 : 1.0)
                    }
                }

                ZStack {
                    if model.isEditing {
                        TextField("Location", text: $model.locationPendingEdit) {
                            //
                        }
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .submitLabel(.done)
                        .tint(.adOrangeLighter)
                        .modifier(EditingAnimationBorder(verticalOutset: 12))
                        .frame(height: 25)
                    } else if !model.user.location.isEmpty {
                        HStack {
                            Image(systemName: .locationFill)
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                            Text(model.user.location)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                        }
                        .frame(height: 25)
                    }
                }
            }
        }
        .padding([.leading, .trailing], 50)
        .padding(.top, headerHeight + 60)
        .padding(.bottom, 20)
    }

    var editingHeader: some View {
        ZStack {
            let blur = (10.0 * (-scrollViewOffset / 110)).clamped(to: 0...10.0)
            let opacity = (1.0 - (blur / 10.0)).clamped(to: 0...1)
            VStack {
                HStack {
                    ZStack {
                        if model.isEditing {
                            Button {
                                Analytics.logEvent("Discard changes", model.screenName, .buttonTap)
                                model.isEditing = false
                                model.resetPendingEdits()
                                model.discardMediaEdits()
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Discard")
                                }
                                .font(.system(size: 16, weight: .medium, design: .default))
                                .foregroundColor(.white)
                            }
                        } else {
                            EmptyView()
                        }
                    }
                    .id(model.isEditing ? 1 : 0)
                    .modifier(BlurOpacityTransition(speed: 1.7))

                    Spacer()

                    ZStack {
                        if model.isEditing {
                            Button {
                                Analytics.logEvent("Save changes", model.screenName, .buttonTap)
                                model.isEditing = false
                                model.saveUser()
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Save")
                                    Image(systemName: .checkmarkCircleFill)
                                        .foregroundColor(.green)
                                }
                                .font(.system(size: 16, weight: .medium, design: .default))
                                .foregroundColor(.white)
                            }
                        } else {
                            HStack {
                                Spacer()
                                Button {
                                    Analytics.logEvent("Edit", model.screenName, .buttonTap)
                                    model.isEditing = true
                                    model.stageCurrentUserMedia()
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("Edit")
                                        Image(systemName: .pencilCircleFill)
                                    }
                                    .font(.system(size: 16, weight: .medium, design: .default))
                                    .foregroundColor(.white)
                                }
                            }
                        }
                    }
                    .id(model.isEditing ? 1 : 0)
                    .modifier(BlurOpacityTransition(speed: 1.7))
                }
                Spacer()
            }
            .blur(radius: blur)
            .opacity(opacity)
            .padding([.leading, .trailing], 20)
        }
    }

    var notSelfHeader: some View {
        ZStack {
            let blur = (10.0 * (-scrollViewOffset / 110)).clamped(to: 0...10.0)
            let opacity = (1.0 - (blur / 10.0)).clamped(to: 0...1)
            VStack(spacing: 16) {
                HStack {
                    if presentedInSheet {
                        Button {
                            Analytics.logEvent("X tapped", model.screenName, .buttonTap)
                            UIApplication.shared.topViewController?.dismiss(animated: true)
                        } label: {
                            Image(systemName: .xmarkCircleFill)
                                .font(.system(size: 26, weight: .medium))
                                .foregroundColor(.white)
                                .padding(8)
                        }
                    }
                    Spacer()
                    Menu {
                        if model.user.isFriend {
                            Button {
                                Analytics.logEvent("Unfriend tapped", model.screenName, .buttonTap)
                                model.unfriendUser()
                            } label: {
                                Label("Unfriend @\(model.user.username ?? "")",
                                      systemImage: .personCropCircleFillBadgeMinus)
                            }
                        }

                        if model.user.isBlocked {
                            Button {
                                Analytics.logEvent("Unblock tapped", model.screenName, .buttonTap)
                                model.unblockUser()
                            } label: {
                                Label("Unblock @\(model.user.username ?? "")",
                                      systemImage: .personCropCircleFillBadgeXmark)
                            }
                        } else {
                            Button(role: .destructive) {
                                Analytics.logEvent("Block tapped", model.screenName, .buttonTap)
                                model.blockUser()
                            } label: {
                                Label("Block @\(model.user.username ?? "")",
                                      systemImage: .personCropCircleFillBadgeXmark)
                            }
                        }

                        Button(role: .destructive) {
                            Analytics.logEvent("Report tapped", model.screenName, .buttonTap)
                            model.reportUser()
                        } label: {
                            Label("Report @\(model.user.username ?? "")",
                                  systemImage: .exclamationmarkTriangleFill)
                        }
                    } label: {
                        Image(systemName: .ellipsisCircleFill)
                            .font(.system(size: 26, weight: .medium))
                            .foregroundColor(.white)
                            .padding(8)
                    }
                }
                Spacer()
            }
            .blur(radius: blur)
            .opacity(opacity)
            .padding([.leading, .trailing], 8)
            .padding(.top, 5)
        }
    }

    var emptyStateFriendActions: some View {
        VStack {
            if model.user.hasRequestedYou {
                AndiEmptyState(text: "@\(model.user.username ?? "") sent you a friend request.")
                    .padding(.top, 40)
                    .modifier(BlurOpacityTransition(speed: 1.8))
                HStack {
                    ProfileViewButton(title: "Approve", symbolName: .checkmark, backgroundColor: .adDarkGreen, textColor: .white) {
                        model.approveFriendRequest()
                    }

                    ProfileViewButton(title: "Deny", symbolName: .xmark, backgroundColor: .adRed, textColor: .white) {
                        model.denyFriendRequest()
                    }
                }
                .modifier(BlurOpacityTransition(speed: 1.8))
            } else if model.user.youRequestedThem {
                AndiEmptyState(text: "@\(model.user.username ?? "") hasn't approved your friend request yet.")
                    .padding(.top, 40)
                    .modifier(BlurOpacityTransition(speed: 1.8))
                ProfileViewButton(title: "Cancel Request",
                                  backgroundColor: .white,
                                  textColor: .black) {
                    model.cancelFriendRequest()
                }
                .modifier(BlurOpacityTransition(speed: 1.8))
            } else {
                AndiEmptyState(text: "Add @\(model.user.username ?? "") as a friend to see their posts.")
                    .padding(.top, 40)
                    .modifier(BlurOpacityTransition(speed: 1.8))
                ProfileViewButton(title: "Add Friend",
                                  symbolName: .plus,
                                  backgroundColor: .white,
                                  textColor: .black) {
                    model.sendFriendRequest()
                }
                .modifier(BlurOpacityTransition(speed: 1.8))
            }
        }
    }

    var body: some View {
        ZStack {
            if model.user.hasRegistered {
                coverImageAndNameAnimation
            }

            if model.user.hasRegistered {
                profilePicture
            }

            RefreshableScrollView(offset: $scrollViewOffset,
                                  isRefreshing: $isRefreshing,
                                  presentedInSheet: presentedInSheet) {
                if isInitialLoading && hasHealthAuthoriztion {
                    VStack(spacing: 18.0) {
                        Spacer()
                            .frame(height: UIScreen.main.bounds.height * 0.3)
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .scaleEffect(x: 1.5, y: 1.5)
                        Text(model.user.isSelf ? "Securely reading\nyour activity history" : "Just a sec!")
                            .font(.system(size: 12, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                            .opacity(0.6)
                    }
                } else {
                    // Views are id'd for LazyVStack performance
                    if model.user.hasRegistered {
                        usernameBioLocation
                            .fixedSize(horizontal: false, vertical: true)
                            .id("usernameBioLocation")
                    } else {
                        Spacer()
                            .frame(height: 68.0)
                            .id("topSpacer")
                    }

                    if !iapManager.hasSuperDistanceFeatures && hasHealthAuthoriztion && model.user.isSelf {
                        SuperDistanceCell()
                            .padding(.bottom, 12.0)
                    }

                    if !model.user.isBlocked && !model.user.isSelf {
                        MedalCarousel(user: model.user)
                            .padding(.bottom, 16)
                            .id("medalCarousel")
                    }

                    if model.user.isFriend {
                        UserPosts(model: model)
                    } else if model.user.isSelf {
                        if hasHealthAuthoriztion {
                            ScrollViewReader { proxy in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    ActivityTypeSegmentedControl(activityTypes: activityTypes,
                                                                 fontSize: 14,
                                                                 showBg: false,
                                                                 selectedActivityType: $selectedActivityType)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding([.leading, .trailing], 15.0)
                                }
                                .animation(.none, value: cellData)
                                .onChange(of: activityTypes) { _ in
                                    proxy.scrollTo(selectedActivityType.rawValue, anchor: .center)
                                }
                                .onChange(of: selectedActivityType) { _ in
                                    withAnimation(.timingCurve(0.42, 0.27, 0.34, 0.96, duration: 0.2)) {
                                        proxy.scrollTo(selectedActivityType.rawValue, anchor: .center)
                                    }
                                }
                            }

                            UserPostsAndActivities(model: model,
                                                   isToday: false,
                                                   cellData: cellData)
                        } else {
                            ProfileConnectHealth(model: model)
                        }
                    } else if model.user.isBlocked {
                        Text("User blocked")
                            .font(.system(size: 27.0, weight: .semibold))
                            .foregroundColor(.white)
                            .opacity(0.4)
                        Spacer()
                    } else {
                        emptyStateFriendActions
                    }
                }
            }
            .animation(.timingCurve(0.42, 0.27, 0.34, 0.96, duration: 0.3), value: cellData)

            if !ADUser.current.hasRegistered {
                ZStack {
                    TopGradient(scrollViewOffset: $scrollViewOffset)
                    VStack {
                        TitleView(scrollViewOffset: $scrollViewOffset)
                            .offset(y: isRefreshing ? 30.0 : 0.0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: isRefreshing)
                        Spacer()
                    }
                }
            } else {
                TopGradient(scrollViewOffset: $scrollViewOffset)
                    .offset(y: -20)
                    .opacity((scrollViewOffset / -110).clamped(to: 0...1))
            }

            if model.user.isSelf && model.user.hasRegistered && !presentedInSheet {
                editingHeader
            } else if !model.user.isSelf {
                notSelfHeader
            }
            
            VStack {
                ZStack {
                    if model.isEditing {
                        TextField("NAME", text: $model.namePendingEdit)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                            .frame(height: 35)
                            .tint(.adOrangeLighter)
                            .modifier(EditingAnimationBorder())
                    }
                }
                .padding([.leading, .trailing], 50)
                .id(model.isEditing ? 1 : 0)
                .modifier(BlurOpacityTransition(speed: 1.7))
                
                Spacer()
            }
            .padding(.top, 30)
            
            VStack {
                HStack {
                    PhotosPicker(selection: $selectedCoverPhoto, matching: .images) {
                        Image(systemName: .photoFill)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 25, height: 25)
                            .padding()
                            .background(Color.black.opacity(0.01))
                            .foregroundColor(.white)
                    }
                    .onChange(of: selectedCoverPhoto) { newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                if let image = UIImage(data: data) {
                                    model.setCoverPhoto(image)
                                }
                            }
                        }
                    }
                    .opacity(model.isEditing ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: model.isEditing)
                    Spacer()
                }
                
                Spacer()
            }
            .padding(.top, 80)
            .padding(.leading, 12)
        }
        .background {
            Color.black
                .ignoresSafeArea()
                .if(presentedInSheet) { view in
                    view.cornerRadius([.topLeading, .topTrailing], 35)
                }
        }
        .opacity(dimView ? 0.6 : 1.0)
        .blur(radius: dimView ? 10.0 : 0.0)
        .animation(.easeInOut(duration: 0.3), value: dimView)
        .onChange(of: isRefreshing) { newValue in
            if newValue == true {
                Task(priority: .userInitiated) {
                    await Edge.loadInitialAppState(loadFriendFinderState: false)
                    await MainActor.run {
                        isRefreshing = false
                    }
                }
            }
        }
        .onChange(of: model.postCellModels) { _ in
            load()
            isInitialLoading = false
        }
        .onChange(of: selectedActivityType) { type in
            NSUbiquitousKeyValueStore.default.profileSelectedActivityType = type
            load()
            isInitialLoading = false
        }
        .onReceive(ActivitiesData.shared.activitiesReloadedPublisher) { _ in
            loadActivityTypes()
            load()
            isInitialLoading = false
        }
        .onReceive(ReloadPublishers.healthKitAuthorizationChanged) { _ in
            self.hasHealthAuthoriztion = HealthKitActivitiesStore.shared.hasRequestedAuthorization()
            isInitialLoading = true
            Task {
                await ActivitiesData.shared.load()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            if isInitialLoading {
                return
            }

            Task {
                await ActivitiesData.shared.load()
            }
        }
        .onAppear {
            Analytics.logEvent(model.screenName, model.screenName, .screenViewed)

            UNUserNotificationCenter.current().getNotificationSettings { settings in
                switch settings.authorizationStatus {
                case .notDetermined:
                    if !NSUbiquitousKeyValueStore.default.hasAskedForNotificationsPermission {
                        let pushVC = PushNotificationsViewController()
                        pushVC.isModalInPresentation = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            guard UIApplication.shared.topViewController is UITabBarController else {
                                return
                            }
                            UIApplication.shared.topViewController?.present(pushVC, animated: true)
                            NSUbiquitousKeyValueStore.default.hasAskedForNotificationsPermission = true
                        }
                    }
                default: break
                }
            }

            loadActivityTypes()
            load()
            if cellData.filter({ $0.activity != nil }).isEmpty {
                isInitialLoading = true
                Task {
                    await ActivitiesData.shared.load()
                }
            }
        }
    }
}

struct CellModel: Equatable {
    var postModel: PostCellModel?
    var activity: Activity?
    var collectible: Collectible?
    var milestone: Milestone?

    var id: String {
        if let postModel = postModel {
            return postModel.post.id
        }

        if let collectible = collectible {
            return collectible.description + "_" + String(collectible.dateEarned.timeIntervalSince1970)
        }

        if let activity = activity {
            return activity.id + (activity is CachedActivity ? "_cached" : "")
        }

        return milestone?.description ?? UUID().uuidString
    }

    var sortDate: Date {
        return postModel?.post.creationDate ?? activity?.startDate ?? collectible?.dateEarned ?? Date()
    }

    static func == (lhs: CellModel, rhs: CellModel) -> Bool {
        return lhs.id == rhs.id
    }
}

fileprivate extension NSUbiquitousKeyValueStore {
    var profileSelectedActivityType: ActivityType {
        get {
            if let rawValue = string(forKey: "profileSelectedActivityType"),
               let type = ActivityType(rawValue: rawValue) {
                return type
            }
            return .all
        }

        set {
            set(newValue.rawValue, forKey: "profileSelectedActivityType")
        }
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var model: ProfileViewModel {
        let model = ProfileViewModel(controller: ProfileViewController())
        model.user.username = "dan"
        model.user.name = "Daniel Kuntz"
        model.user.bio = "Co-founder, CTO / CMO (Chief Meme Officer) @anydistanceclub 💨"
        model.user.location = "Atlanta, GA"
        model.user.profilePhotoUrl = URL(string: "https://pbs.twimg.com/profile_images/1527675361693208576/ns7gOdxP_400x400.jpg")
        model.user.coverPhotoUrl = URL(string: "https://pbs.twimg.com/profile_banners/1970184937/1660065274/1500x500")
        model.user.collectibles = [
            Collectible(type: .activity(.mi_1), dateEarned: Date()),
            Collectible(type: .location(.atlanta), dateEarned: Date()),
            Collectible(type: .location(.austin), dateEarned: Date()),
            Collectible(type: .totalDistance(.km_1400), dateEarned: Date()),
            Collectible(type: .special(.day1), dateEarned: Date()),
            Collectible(type: .activity(.mi_10), dateEarned: Date()),
            Collectible(type: .location(.beijing), dateEarned: Date()),
            Collectible(type: .location(.bristol), dateEarned: Date()),
            Collectible(type: .totalDistance(.km_1500), dateEarned: Date()),
            Collectible(type: .activity(.mi_20), dateEarned: Date()),
            Collectible(type: .location(.cardiff), dateEarned: Date()),
            Collectible(type: .location(.denver), dateEarned: Date()),
            Collectible(type: .totalDistance(.km_30), dateEarned: Date()),
            Collectible(type: .activity(.mi_50), dateEarned: Date()),
            Collectible(type: .location(.buenos_aires), dateEarned: Date()),
            Collectible(type: .location(.brooklyn), dateEarned: Date()),
            Collectible(type: .totalDistance(.km_1800), dateEarned: Date())
        ]
        return model
    }

    static var previews: some View {
        ProfileView(model: model, cellData: [])
    }
}
