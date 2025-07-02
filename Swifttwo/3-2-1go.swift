// Licensed under the Any Distance Source-Available License
//
//  RecordingView.swift
//  ADAC
//
//  Created by Daniel Kuntz on 6/23/22.
//

import SwiftUI
import MapKit
import Combine
import SwiftUIX
import MessageUI
import Reachability
import Sentry
import AVFoundation
import PhotosUI
import StoreKit
import WeatherKit

// MARK: - Map

fileprivate struct MapView: UIViewRepresentable  {
    @ObservedObject var model: RecordingViewModel
    var drawerClosedHeight: CGFloat

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        updateVisibleRegion(model: model, mapView: mapView)
        mapView.mapType = .mutedStandard
        mapView.showsUserLocation = false
        mapView.showsBuildings = false
        mapView.isUserInteractionEnabled = false
        mapView.overrideUserInterfaceStyle = .dark
        mapView.pointOfInterestFilter = MKPointOfInterestFilter.excludingAll
        mapView.setUserTrackingMode(.none, animated: false)
        mapView.delegate = context.coordinator

        model.recorder.$currentLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak model] _ in
            updateVisibleRegion(model: model, mapView: mapView)
        }.store(in: &context.coordinator.subscribers)

        model.recorder.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak model] _ in
            updateVisibleRegion(model: model, mapView: mapView)
        }.store(in: &context.coordinator.subscribers)

        return mapView
    }

    private func addNewPolyline(_ mapView: MKMapView) {
        model.recorder.coordinates.withUnsafeBufferPointer { pointer in
            if let base = pointer.baseAddress {
                let newPolyline = MKPolyline(coordinates: base, count: model.recorder.coordinates.count)
                mapView.addOverlay(newPolyline)
            }
        }
    }

    private func updateVisibleRegion(model: RecordingViewModel?, mapView: MKMapView) {
        guard let model = model else {
            return
        }

        if let region = model.recorder.regionForCurrentRoute() {
            let rect = region.mapRect()
            let bottomInset = drawerClosedHeight + ((model.recorder.state == .saved && !model.isViewingLivePost) ? 70 : 0)
            let additionalTopInset: CGFloat = model.recorder.state == .saved ? 10 : 0
            mapView.setVisibleMapRect(rect,
                                      edgePadding: UIEdgeInsets(top: 60 + additionalTopInset, left: 0, bottom: bottomInset, right: 0),
                                      animated: model.hasScrolledToFirstLocation)
        }

        if let polyline = mapView.overlays.first(where: { $0 is MKPolyline }) as? MKPolyline {
            mapView.removeOverlay(polyline)
            addNewPolyline(mapView)
        } else {
            addNewPolyline(mapView)
        }
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var parent: MapView
        var subscribers: Set<AnyCancellable> = []

        init(parent: MapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let routePolyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: routePolyline)
                renderer.strokeColor = UIColor.white
                renderer.lineWidth = 3
                return renderer
            }

            return MKOverlayRenderer()
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.parent.model.hasScrolledToFirstLocation = self.parent.model.recorder.currentLocation != nil
            }
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            DispatchQueue.main.async {
                self.parent.model.visibleMapRect = mapView.visibleMapRect
            }
        }
        
        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            parent.model.hasRenderedMap = true
        }
    }
}

fileprivate struct UserLocationView: View {
    @ObservedObject var model: RecordingViewModel
    @State private var grow: Bool = false
    @State private var offset: CGPoint = .zero

    private func updateOffset() {
        if let rect = model.visibleMapRect,
           let location = model.recorder.currentLocation {

            let mapPoint = MKMapPoint(location.coordinate)
            let xP = (mapPoint.x - rect.origin.x) / rect.size.width
            let yP = (mapPoint.y - rect.origin.y) / rect.size.height

            offset = CGPoint(x: xP * UIScreen.main.bounds.width,
                             y: yP * UIScreen.main.bounds.height)
        }
    }

    var body: some View {
        ZStack {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let duration: CGFloat = 1.4
                    let time = timeline.date.timeIntervalSince1970.truncatingRemainder(dividingBy: duration) / duration
                    let diameter = 12.0 + (30.0 * time)
                    let rect = CGRect(x: 21.0 - (diameter / 2),
                                      y: 21.0 - (diameter / 2),
                                      width: diameter,
                                      height: diameter)
                    let shape = Circle().path(in: rect)
                    let color = Color.adOrangeLighter.opacity(1.0 - time)
                    context.fill(shape,
                                 with: .color(color))
                }
            }
            .frame(width: 42.0, height: 42.0)

            Circle()
                .fill(Color(UIColor.adOrangeLighter))
                .width(12.0)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 0)
        }
        .position(x: offset.x,
                  y: offset.y)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.08), value: offset)
        .opacity(model.recorder.currentLocation == nil ? 0 : 1)
        .onAppear {
            grow = true
        }
        .onChange(of: model.visibleMapRect) { _ in
            updateOffset()
        }
        .onChange(of: model.recorder.currentLocation) { _ in
            updateOffset()
        }
    }
}

// MARK: - Empty State

fileprivate struct NoLocationView: View {
    var drawerClosedHeight: CGFloat
    
    var body: some View {
        Image("dot_bg")
            .resizable(resizingMode: .tile)
            .opacity(0.1)
        .mask {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.2))
        }
        .mask {
            LinearGradient(colors: [.black, .clear], startPoint: UnitPoint(x: 0.5, y: 0.3), endPoint: .bottom)
        }
        .overlay {
            VStack {
                HStack {
                    Image(systemName: .exclamationmarkTriangleFill)
                        .font(.system(size: 24, weight: .regular, design: .default))
                        .foregroundColor(.adYellow)
                    Text("Location Permissions Needed")
                        .foregroundColor(.white)
                        .font(.system(size: 19, weight: .medium, design: .default))
                }
                .padding(.bottom, 20)
                
                Button {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                } label: {
                    Text("We need temporary permission to use your location to record your activity. Location data is never shared with anyone else.\n\nTap here to open Settings. Tap \"Location,\" then tap \"While Using the App.\"")
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .regular, design: .default))
                }
                .padding([.leading, .trailing], 30)
                .zIndex(Double.greatestFiniteMagnitude)
                
                Spacer()
                    .frame(height: drawerClosedHeight)
            }
            .shadow(color: .black, radius: 8, x: 0, y: 0)
        }
        .maxHeight(UIScreen.main.bounds.height)
        .maxWidth(UIScreen.main.bounds.width)
        .background(Color(white: 0.1))
    }
}

fileprivate struct NoInternetView: View {
    @ObservedObject var model: RecordingViewModel
    var drawerClosedHeight: CGFloat

    var labelText: String {
        switch model.recorder.state {
        case .saved:
            return "Maps won't display until you are connected to Wi-Fi or Cellular Data. Your workout route was still saved."
        case .ready, .locationPermissionNeeded, .waitingForGps:
            return "Maps won't display until you are connected to Wi-Fi or Cellular Data. Your workout will still be tracked."
        case .recording, .paused, .saving, .couldNotSave, .discarded:
            return "Maps won't display until you are connected to Wi-Fi or Cellular Data. Your workout is still being tracked."
        }
    }

    var body: some View {
        Image("dot_bg")
            .resizable(resizingMode: .tile)
            .opacity(0.1)
            .mask {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.2))
            }
            .mask {
                LinearGradient(colors: [.black, .clear], startPoint: UnitPoint(x: 0.5, y: 0.3), endPoint: .bottom)
            }
            .overlay {
                VStack {
                    HStack {
                        Image(systemName: .exclamationmarkTriangleFill)
                            .font(.system(size: 24, weight: .regular, design: .default))
                            .foregroundColor(.adYellow)
                        Text("No Internet Connection")
                            .foregroundColor(.white)
                            .font(.system(size: 19, weight: .medium, design: .default))
                    }
                    .padding(.bottom, 20)

                    Button {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    } label: {
                        Text(labelText)
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .regular, design: .default))
                    }
                    .padding([.leading, .trailing], 30)
                    .zIndex(Double.greatestFiniteMagnitude)

                    Spacer()
                        .frame(height: drawerClosedHeight)
                }
                .shadow(color: .black, radius: 8, x: 0, y: 0)
            }
            .maxHeight(UIScreen.main.bounds.height)
            .maxWidth(UIScreen.main.bounds.width)
            .background(Color(white: 0.1))
    }
}

// MARK: - 3D Route

fileprivate struct Route3DSwiftUIView: UIViewRepresentable {
    var coordinates: [CLLocation]

    func makeUIView(context: Context) -> Route3DView {
        let view = Route3DView(frame: .zero)
        view.renderLine(withCoordinates: coordinates)
        view.setZoom(0.8)
        return view
    }

    func updateUIView(_ uiView: Route3DView, context: Context) {}
}

fileprivate struct Route3DWithBackground: View {
    var coordinates: [CLLocation]
    var drawerClosedHeight: CGFloat

    var body: some View {
        ZStack {
            DotBackground()
            VStack {
                Route3DSwiftUIView(coordinates: coordinates)
                    .padding(.top, 20)
                Spacer()
                    .frame(height: drawerClosedHeight)
            }
        }
    }
}

fileprivate struct DotBackground: View {
    var body: some View {
        Image("dot_bg")
            .resizable(resizingMode: .tile)
            .ignoresSafeArea()
            .mask {
                Image("gradient_bottom_ease_in_out")
                    .renderingMode(.template)
                    .resizable(resizingMode: .stretch)
                    .frame(width: UIScreen.main.bounds.width,
                           height: UIScreen.main.bounds.height * 2.0)
                    .foregroundColor(.black)
                    .ignoresSafeArea()
            }
            .mask {
                Image("layout_top_gradient")
                    .renderingMode(.template)
                    .resizable(resizingMode: .stretch)
                    .frame(width: UIScreen.main.bounds.width,
                           height: UIScreen.main.bounds.height * 2.0)
                    .foregroundColor(.black)
                    .ignoresSafeArea()
            }
            .opacity(0.1)
            .background(Color(white: 0.1))
    }
}

fileprivate struct ActivityTypeGlyphAnimation: View {
    var type: ActivityType
    var drawerClosedHeight: CGFloat

    @StateObject private var manager = MotionManager()
    
    var items: [GridItem] {
        Array(repeating: .init(.fixed(50)), count: 30)
    }
    
    var body: some View {
        let colors: [Color] = stride(from: 0, to: 1, by: 0.1).map { n in
            return Color(hue: n, saturation: 0.3, brightness: 1)
        }
        
        DotBackground()
            .overlay {
                VStack {
                    ZStack {
                        LinearGradient(colors: colors,
                                       startPoint: .init(x: manager.roll - 0.25, y: 0.5),
                                       endPoint: .init(x: manager.roll + 1.25, y: 0.5))
                        .mask {
                            Image(type.glyphName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundColor(.white)
                                .frame(width: 90, height: 90)
                        }
                        .shadow(color: .black, radius: 8, x: 0, y: 0)
                    }

                    Spacer()
                        .frame(height: drawerClosedHeight)
                }
            }
            .maxHeight(UIScreen.main.bounds.height)
            .maxWidth(UIScreen.main.bounds.width)
            .offset(y: 16)
            .animation(.easeInOut(duration: 0.4), value: drawerClosedHeight)
    }
}

fileprivate struct RecordingLabel: View {
    var state: iPhoneActivityRecordingState

    struct RecordingCircle: View {
        @State var grow: Bool = false

        var body: some View {
            Circle()
                .foregroundColor(Color(hexadecimal: "30D158"))
                .frame(width: 16)
                .overlay {
                    Circle()
                        .foregroundColor(.black)
                        .frame(width: 6)
                }
                .background {
                    Circle()
                        .foregroundColor(Color(hexadecimal: "30D158"))
                        .scaleEffect(grow ? 2.0 : 1.0)
                        .opacity(grow ? 0.0 : 1.0)
                        .animation(.linear(duration: 1.3).repeatForever(autoreverses: false),
                                   value: grow)
                }
                .onAppear {
                    grow = true
                }
        }
    }

    var body: some View {
        HStack {
            switch state {
            case .ready, .locationPermissionNeeded:
                EmptyView()
            case .recording:
                RecordingCircle()
            case .paused:
                Circle()
                    .foregroundColor(Color(UIColor.adOrangeLighter))
                    .frame(width: 16)
                    .overlay {
                        Image(systemName: .pauseFill)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(.black)
                            .frame(width: 7)
                    }
            case .saving, .waitingForGps:
                ProgressView()
                    .tint(.adOrangeLighter)
                    .brightness(0.25)
                    .scaleEffect(0.8)
                    .background {
                        DarkBlurView()
                            .mask(Circle())
                    }
                    .offset(x: -1)
            case .saved:
                Circle()
                    .foregroundColor(Color(hexadecimal: "30D158"))
                    .frame(width: 16)
                    .overlay {
                        Image(systemName: .checkmark)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(.black)
                            .font(.system(size: 10, weight: .black, design: .default))
                            .frame(width: 8)
                    }
            case .discarded, .couldNotSave:
                Image(systemName: .infoCircleFill)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(Color(UIColor.adOrangeLighter))
                    .frame(width: 16)
            }
            Text(state.displayName.capitalized)
                .foregroundColor(Color(state.displayColor))
                .font(.system(size: 16, weight: .semibold, design: .default))
                .shadow(color: Color(white: 0.1), radius: 8)
                .shadow(color: Color(white: 0.1), radius: 8)
                .shadow(color: Color(white: 0.1), radius: 8)
        }
        .id(state)
        .modifier(BlurOpacityTransition(speed: 1.75))
    }
}

fileprivate struct RouteTypeSwitcher: View, Equatable {
    @ObservedObject var model: RecordingViewModel
    @Binding var routeType: RouteType
    private let impactGenerator = UIImpactFeedbackGenerator(style: .heavy)

    static func == (lhs: RouteTypeSwitcher, rhs: RouteTypeSwitcher) -> Bool {
        return lhs.routeType == rhs.routeType
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            if !model.post.mediaUrls.isEmpty {
                Button {
                    routeType = .photoWith2DRoute
                    impactGenerator.impactOccurred()
                } label: {
                    Image(systemName: .photo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 25, height: 25)
                        .tintColor(routeType == .photoWith2DRoute ? .adOrangeLighter : .white)
                        .padding()
                }
            }
            Button {
                routeType = .threeD
                impactGenerator.impactOccurred()
            } label: {
                Image("glyph_graphs_route3d")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .tintColor(routeType == .threeD ? .adOrangeLighter : .white)
                    .padding()
            }

            if !model.isViewingLivePost ||
                (model.isViewingLivePost && !model.post.hiddenStatTypes.contains(Post.HiddenStatType.location.rawValue)) {
                Button {
                    routeType = .map
                    impactGenerator.impactOccurred()
                } label: {
                    Image("glyph_graphs_route2d")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .tintColor(routeType == .map ? .adOrangeLighter : .white)
                        .padding()
                        .overlay {
                            ZStack {
                                if model.post.hiddenStatTypes.contains(Post.HiddenStatType.location.rawValue) {
                                    Image("glyph_eye_slash")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .foregroundColor(.white)
                                        .frame(width: 12, height: 12)
                                        .transition(.scale.animation(.easeInOut(duration: 0.15)))
                                } else {
                                    EmptyView()
                                }
                            }
                            .offset(x: 22.0, y: -14.0)
                        }
                }
            }
            Spacer()
        }
        .shadow(color: .black, radius: 8)
    }
}

// MARK: - Toast / Overlay

fileprivate struct CountdownView: View {
    private let impactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let startGenerator = UINotificationFeedbackGenerator()

    @State private var animationStep: CGFloat = 4
    @State private var animationTimer: Timer?
    @State private var isFinished: Bool = false
    @Binding var skip: Bool
    var drawerClosedHeight: CGFloat
    var finishedAction: () -> Void

    func hStackXOffset() -> CGFloat {
        let clampedStep = animationStep.clamped(to: 0...3)
        if clampedStep > 0 {
            return 60 * (clampedStep - 1) - 10
        } else {
            return -90
        }
    }

    func startTimer() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true, block: { _ in
            if animationStep == 0 {
                withAnimation(.easeIn(duration: 0.15)) {
                    isFinished = true
                }
                finishedAction()
                animationTimer?.invalidate()
            }

            withAnimation(.easeInOut(duration: animationStep == 4 ? 0.3 : 0.4)) {
                animationStep -= 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if animationStep < 4 && animationStep > 0 {
                    impactGenerator.impactOccurred()
                } else if animationStep == 0 {
                    startGenerator.notificationOccurred(.success)
                }
            }
        })
    }

    var body: some View {
        VStack {
            ZStack {
                DarkBlurView()

                HStack(alignment: .center, spacing: 0) {
                    Text("3")
                        .font(.system(size: 89, weight: .semibold, design: .default))
                        .frame(width: 60)
                        .opacity(animationStep >= 3 ? 1 : 0.6)
                        .scaleEffect(animationStep >= 3 ? 1 : 0.6)
                    Text("2")
                        .font(.system(size: 89, weight: .semibold, design: .default))
                        .frame(width: 60)
                        .opacity(animationStep == 2 ? 1 : 0.6)
                        .scaleEffect(animationStep == 2 ? 1 : 0.6)
                    Text("1")
                        .font(.system(size: 89, weight: .semibold, design: .default))
                        .frame(width: 60)
                        .opacity(animationStep == 1 ? 1 : 0.6)
                        .scaleEffect(animationStep == 1 ? 1 : 0.6)
                    Text("GO")
                        .font(.system(size: 65, weight: .bold, design: .default))
                        .frame(width: 100)
                        .opacity(animationStep == 0 ? 1 : 0.6)
                        .scaleEffect(animationStep == 0 ? 1 : 0.6)
                }
                .offset(x: hStackXOffset())
            }
            .mask {
                RoundedRectangle(cornerRadius: 65)
                    .frame(width: 130, height: 200)
            }
            .opacity(isFinished ? 0 : 1)
            .scaleEffect(isFinished ? 1.2 : 1)
            .blur(radius: isFinished ? 6.0 : 0.0)
            .opacity(animationStep < 4 ? 1 : 0)
            .scaleEffect(animationStep < 4 ? 1 : 0.8)

            Spacer()
                .frame(height: 300.0)
        }
        .onChange(of: skip) { newValue in
            if newValue == true {
                animationTimer?.invalidate()
                withAnimation(.easeIn(duration: 0.15)) {
                    isFinished = true
                }
                finishedAction()
            }
        }
        .onAppear {
            guard animationStep == 4 else {
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.startTimer()
            }
        }
    }
}

fileprivate struct ToastText: View {
    var text: String
    var icon: Image
    var iconIncludesCircle: Bool = false
    var foregroundColor: Color = .white

    var body: some View {
        HStack {
            ZStack {
                if iconIncludesCircle {
                    icon
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 25)
                } else {
                    Circle()
                        .frame(width: 25)
                    icon
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 9)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
            .foregroundColor(foregroundColor)

            Text(text)
                .lineLimit(1)
                .foregroundColor(foregroundColor)
                .font(.system(size: 19, weight: .medium, design: .default))
        }
    }
}

fileprivate struct RecordingToastView: View {
    var text: String
    var icon: Image
    var iconIncludesCircle: Bool = false
    var foregroundColor: Color = .white
    var drawerClosedHeight: CGFloat
    @Binding var isVisible: Bool

    var body: some View {
        VStack {
            ZStack {
                DarkBlurView()
                    .mask(RoundedRectangle(cornerRadius: 30))
                ToastText(text: text,
                          icon: icon,
                          iconIncludesCircle: iconIncludesCircle,
                          foregroundColor: foregroundColor)
                    .padding([.leading, .trailing], 15)
                    .padding([.top, .bottom], 16)
            }
            .fixedSize()
            .opacity(isVisible ? 1.0 : 0.0)
            .scaleEffect(isVisible ? 1.0 : 1.1)
            .blur(radius: isVisible ? 0.0 : 6.0)
            .animation(isVisible ? .easeOut(duration: 0.15) : .easeIn(duration: 0.15), value: isVisible)
            Spacer()
                .height(drawerClosedHeight)
        }
    }
}

fileprivate struct TapAndHoldToStopView: View {
    @Binding var isPressed: Bool
    @State private var isVisible: Bool = false
    var drawerClosedHeight: CGFloat

    var body: some View {
        VStack {
            ZStack {
                Group {
                    DarkBlurView()
                        .mask(RoundedRectangle(cornerRadius: 30))
                    ToastText(text: "Tap and hold to stop",
                              icon: Image(systemName: .stopFill),
                              iconIncludesCircle: false)
                }

                ZStack {
                    BlurView(style: .systemUltraThinMaterialLight, intensity: 0.3)
                        .brightness(0.2)
                        .mask(RoundedRectangle(cornerRadius: 30))
                    ToastText(text: "Tap and hold to stop",
                              icon: Image(systemName: .stopFill),
                              iconIncludesCircle: false,
                              foregroundColor: .black)
                }
                .mask {
                    GeometryReader { geo in
                        HStack {
                            Rectangle()
                                .frame(width: isPressed ? geo.size.width : 0)
                            Spacer()
                        }
                    }
                }
            }
            .frame(width: 260)
            .opacity(isVisible ? 1.0 : 0.0)
            .scaleEffect(isVisible ? 1.0 : 1.1)
            .frame(height: 60)
            .onChange(of: isPressed) { _ in
                withAnimation(isPressed ? .easeOut(duration: 0.15) : .easeIn(duration: 0.15)) {
                    isVisible = isPressed
                }
            }

            Spacer()
                .height(drawerClosedHeight)
        }
        .ignoresSafeArea()
    }
}

struct HowWeCalculatePopup: View {
    @ObservedObject var model: HowWeCalculatePopupModel
    var drawerClosedHeight: CGFloat
    
    var body: some View {
        VStack {
            Spacer()
            
            VStack {
                VStack(alignment: .leading) {
                    HStack(spacing: 6) {
                        Image(systemName: .infoCircle)
                            .foregroundColor(Color(uiColor: model.statCalculationType.color))
                        
                        Text("Calculating \(model.statCalculationType.fullDisplayName)")
                            .foregroundColor(.white)
                            .font(.system(size: 17, weight: .semibold, design: .default))
                        
                        Spacer()
                        
                        Button {
                            model.hideStatCalculationInfo()
                        } label: {
                            ZStack {
                                Circle()
                                    .frame(width: 25, height: 25)
                                    .foregroundColor(.white.opacity(0.1))
                                Image(systemName: .xmark)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .font(.system(size: 17), weight: .bold)
                                    .foregroundColor(.white)
                                    .frame(width: 10)
                            }
                        }
                    }
                    .padding(.top, -3)
                    .padding(.bottom, 4)
                    
                    Text(model.statCalculationType.calculationExplanation)
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .padding(.leading, 2)
                }
                .padding()
                .background {
                    DarkBlurView()
                        .cornerRadius(12, style: .continuous)
                }
                .padding([.leading, .trailing], 15)
            }
            .offset(x: 0, y: model.statCalculationInfoVisible ? 0 : 12)
            .opacity(model.statCalculationInfoVisible ? 1 : 0)
            
            if drawerClosedHeight > 0 {
                Spacer()
                    .height(drawerClosedHeight + 10)
            }
        }
    }
}

// MARK: - Drawer

fileprivate struct DrawerView<Content: View>: View {
    @ObservedObject var model: RecordingViewModel
    @StateObject var user: ADUser = .current
    @Binding var routeType: RouteType
    @Binding var scrollViewOffset: CGFloat
    @Binding var scrollViewContentSize: CGSize
    @FocusState var focusedField: PostFocusedField?
    var backAction: (() -> Void)?
    @State var showingDiscardModal: Bool = false
    @State private var uiScrollView: UIScrollView?
    @State private var keyboardHeight: CGFloat = 0.0
    @State private var keyboardAnimation: Animation = .easeInOut(duration: 0.3)
    @State private var contentOffset: CGFloat = 0.0
    @State private var showingGearSelect: Bool = false

    var content: Content
    let closedHeight: CGFloat
    let addToStorySplit = NSUbiquitousKeyValueStore.default.split(for: AddToStoryButtonVisibility.self)

    init(model: RecordingViewModel,
         closedHeight: CGFloat,
         scrollOffset: Binding<CGFloat>,
         contentSize: Binding<CGSize>,
         focusedField: FocusState<PostFocusedField?>,
         routeType: Binding<RouteType>,
         backAction: (() -> Void)?,
         @ViewBuilder content: () -> Content) {
        self.content = content()
        self.closedHeight = closedHeight
        self._scrollViewOffset = scrollOffset
        self._scrollViewContentSize = contentSize
        self._focusedField = focusedField
        self.model = model
        self.backAction = backAction
        self._routeType = routeType
    }

    var shareAndDots: some View {
        HStack(spacing: 0) {
            if model.recorder.state == .saved {
                if model.post.creatorIsSelf &&
                    model.isViewingLivePost {
                    Menu {
                        Button(role: .destructive) {
                            model.makePostPrivate()
                        } label: {
                            Label("Make Private", image: "glyph_eye_slash")
                        }

                        Button("Edit", systemImage: .pencil) {
                            model.post.isEditing = true
                        }

                        Button("Share", systemImage: .squareAndArrowUp) {
                            model.showDesigner()
                        }

                        if ADUser.current.isTeamADAC {
                            Button("Export Debug Data", systemImage: .squareAndArrowUp) {
                                model.exportPostDebugData()
                            }
                        }
                    } label: {
                        Image(systemName: .ellipsisCircleFill)
                            .font(.system(size: 26, weight: .medium))
                            .foregroundColor(.white)
                            .padding(8)
                    }
                } else if model.post.creatorIsSelf {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        model.showDesigner()
                    } label: {
                        HStack(spacing: 6.0) {
                            Image("icon_instagram")
                                .resizable()
                                .frame(width: 18, height: 18)
                                .saturation(1.05)
                            Text("Add to Story")
                        }
                        .font(.system(size: 14.0, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding([.leading, .trailing], 12)
                        .padding([.top, .bottom], 6)
                        .background {
                            RoundedRectangle(cornerRadius: 40.0)
                                .fill(Color(white: 0.2))
                        }
                    }
                    .padding(.trailing, 10.0)
                }

                if !model.post.creatorIsSelf && ADUser.current.isTeamADAC {
                    Menu {
                        Button("Export Debug Data", systemImage: .squareAndArrowUp) {
                            model.exportPostDebugData()
                        }
                    } label: {
                        Image(systemName: .ellipsisCircleFill)
                            .font(.system(size: 26, weight: .medium))
                            .foregroundColor(.white)
                            .padding(8)
                    }
                }
            }
        }
        .padding(.top, 2.0)
        .padding(.trailing, 6.0)
        .onAppear {
            addToStorySplit.sendAnalytics()
        }
    }

    var header: some View {
        ZStack {
            HStack {
                if model.recorder.state == .saved {
                    Button {
                        backAction?()
                    } label: {
                        if UIApplication.shared.topViewController is UITabBarController {
                            Text("Done")
                                .font(.system(size: 15.0, weight: .medium))
                                .foregroundColor(.white)
                                .padding()
                        } else {
                            Image(systemName: .xmarkCircleFill)
                                .font(.system(size: 26.0, weight: .medium))
                                .foregroundColor(.white)
                                .padding()
                        }
                    }
                } else {
                    Text(model.recorder.activityType.displayName)
                        .font(.system(size: 24.0, weight: .semibold, design: .default))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 12.0)
                        .padding(.leading, 15.0)
                        .offset(y: 5.0)
                }

                Spacer()
                Button {
                    showingDiscardModal = true
                } label: {
                    HStack(spacing: 4.0) {
                        Text("Discard")
                            .font(.system(size: 15.0, weight: .medium, design: .default))
                            .foregroundColor(.white)
                        ZStack {
                            Circle()
                                .fill(Color.black)
                                .scaleEffect(0.8)
                                .layoutPriority(-1)
                            Image(systemName: .trashCircleFill)
                                .foregroundColor(Color(uiColor: RecordingGoalType.time.color))
                                .font(.system(size: 21.0, weight: .medium, design: .default))
                        }
                    }
                    .padding()
                }
                .offset(y: 8.0)
                .shadow(color: .black, radius: 8.0, x: 0.0, y: 0.0)
                .opacity((model.recorder.state == .paused) || (model.recorder.state == .ready && !model.networkConnected) ? 1.0 : 0.0)
                .animation(.linear(duration: 0.2), value: model.recorder.state)

                shareAndDots
            }

            postAuthor
                .frame(width: UIScreen.main.bounds.width)
        }
        .opacity(1.0 - ((scrollViewOffset + 55.0) / -350.0))
        .blur(radius: 10 * ((scrollViewOffset + 55.0) / -350.0))
    }

    var preRecordingHeader: some View {
        HStack {
            var selectedGearName: String {
                if let gearID = model.recorder.selectedGearID,
                   let gear = user.gear.first(where: { $0.id == gearID }) {
                    return gear.name.isEmpty ? "Shoes" : gear.name
                }
                return "Select Shoes"
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showingGearSelect = true
            } label: {
                HStack(spacing: 6.0) {
                    Image("activity_steps")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20.0, height: 20.0)
                        .foregroundColor(.white)
                    Text(selectedGearName)
                        .font(.system(size: 15.0, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.leading, 10.0)
                .padding(.trailing, 13.0)
                .padding([.top, .bottom], 7.5)
                .background {
                    DarkBlurView()
                        .brightness(0.1)
                        .cornerRadius(40.0)
                }
                .padding(15.0)
                .contentShape(Rectangle())
            }
            .opacity(user.gear.isEmpty ? 0.0 : 1.0)

            Spacer()
        }
        .opacity(1.0 - ((scrollViewOffset + 55.0) / -350.0))
        .blur(radius: 10 * ((scrollViewOffset + 55.0) / -350.0))
        .fullScreenCover(isPresented: $showingGearSelect) {
            GearSelectView(selectedGearID: model.recorder.selectedGearID) { gearID in
                model.recorder.selectedGearID = gearID
                NSUbiquitousKeyValueStore.default.selectedGearForTypes[.shoes] = gearID
                NSUbiquitousKeyValueStore.default.synchronize()
            }
            .background(BackgroundClearView())
        }
    }

    var postAuthor: some View {
        ZStack {
            if model.isViewingLivePost,
               let author = model.post.cachedAuthor() {
                Button {
                    Analytics.logEvent("Top profile tapped", model.screenName, .buttonTap)
                    model.showProfile(for: author)
                } label: {
                    VStack {
                        Text(author.name)
                            .font(.system(size: 16, weight: .semibold))
                        Text("@" + (author.username ?? ""))
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .opacity(0.6)
                    }
                    .foregroundColor(.white)
                    .shadow(radius: 6)
                    .shadow(radius: 6)
                }
                .buttonStyle(ScalingPressButtonStyle())
            }
        }
    }

    var arButton: some View {
        Button {
            let vc = ARRouteViewController(model.post.coordinates?.compactMap({ CLLocation(wrapper: $0) }) ?? [],
                                           canvas: nil,
                                           palette: .dark,
                                           showRecordingControls: model.post.creatorIsSelf,
                                           showRouteControls: false)
            UIApplication.shared.topViewController?.present(vc, animated: true, completion: nil)
            Analytics.logEvent("AR Tapped", model.screenName, .buttonTap)
        } label: {
            ZStack {
                Circle()
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                Image(systemName: .arkit)
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundColor(.black)
            }
            .padding(16)
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
    }

    func animation(from notification: Notification) -> Animation? {
        guard
            let info = notification.userInfo,
            let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
            let curveValue = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int,
            let uiKitCurve = UIView.AnimationCurve(rawValue: curveValue)
        else {
            return nil
        }

        let timing = UICubicTimingParameters(animationCurve: uiKitCurve)
        if let springParams = timing.springTimingParameters,
           let mass = springParams.mass,
           let stiffness = springParams.stiffness,
           let damping = springParams.damping {
            return Animation
                .interpolatingSpring(mass: mass, stiffness: stiffness, damping: damping)
                .speed(1.1)
        } else {
            return Animation.easeOut(duration: duration) // this is the closest fallback
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ReadableScrollView(offset: $scrollViewOffset,
                               contentSize: $scrollViewContentSize,
                               showsIndicators: false) {
                LazyVStack {
                    let viewHeight = UIScreen.main.bounds.height
                    Spacer()
                        .frame(height: viewHeight - closedHeight - UIScreen.main.safeAreaInsets.bottom)
                    ZStack {
                        GeometryReader { scrollProxy in
                            let offset = scrollProxy.frame(in: .named("scroll2")).minY
                            let drawerOffset = offset < 0 ? -1 * offset : 0
                            let headerOffset = -1 * offset - 6
                            let switcherOffset: CGFloat = {
                                var offset = -1 * offset + (viewHeight - closedHeight) - 75 - UIScreen.main.safeAreaInsets.top - UIScreen.main.safeAreaInsets.bottom
                                if model.isViewingLivePost {
                                    offset += 46
                                }
                                return offset
                            }()

                            ZStack {
                                VStack(spacing: 0.0) {
                                    DarkBlurView()
                                        .brightness(-0.1)
                                        .mask {
                                            Image("gradient_bottom_ease_in_out")
                                                .renderingMode(.template)
                                                .resizable(resizingMode: .stretch)
                                                .frame(width: UIScreen.main.bounds.width, height: closedHeight + 60.0)
                                                .foregroundColor(.black)
                                        }
                                        .frame(width: UIScreen.main.bounds.width, height: closedHeight)
                                        .overlay {
                                            ZStack {
                                                Image("gradient_bottom_ease_in_out")
                                                    .renderingMode(.template)
                                                    .resizable(resizingMode: .stretch)
                                                VariableBlurView(maxBlurRadius: 3,
                                                                 direction: .blurredBottomClearTop)
                                                .offset(y: 40.0)
                                            }
                                            .frame(width: UIScreen.main.bounds.width,
                                                   height: closedHeight + 60.0)
                                            .foregroundColor(.black)
                                            .offset(y: 90.0)
                                        }
                                    Color.black
                                        .padding(.bottom, -1000.0)
                                }
                                .offset(y: -80.0)
                            }
                            .ignoresSafeArea()
                            .offset(y: contentOffset + drawerOffset)

                            ZStack {
                                if model.recorder.state == .saved && model.recorder.hasCoordinates {
                                    RouteTypeSwitcher(model: model, routeType: $routeType)
                                        .equatable()
                                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                                        .overlay {
                                            HStack {
                                                Spacer()
                                                if routeType == .threeD {
                                                    arButton
                                                }
                                            }
                                        }
                                        .offset(y: switcherOffset)
                                }

                                if !model.isViewingLivePost {
                                    HStack {
                                        Spacer()
                                        RecordingLabel(state: model.recorder.state)
                                        Spacer()
                                    }
                                    .frame(height: 90)
                                    .offset(y: switcherOffset + 40)
                                }
                            }
                            .opacity(1.0 - ((scrollViewOffset + 55.0) / -250.0))
                            .blur(radius: 10 * ((scrollViewOffset + 55.0) / -250.0))

                            ZStack {
                                if model.recorder.state != .ready &&
                                   model.recorder.state != .locationPermissionNeeded {
                                    header
                                        .modifier(BlurOpacityTransition(speed: 1.5))
                                } else {
                                    preRecordingHeader
                                        .modifier(BlurOpacityTransition(speed: 1.5))
                                }
                            }
                            .offset(y: headerOffset)
                        }

                        VStack(alignment: .center, spacing: 0) {
                            Spacer()
                                .frame(height: model.recorder.state == .saved ? 30.0 : 12.0)
                            content

                            if model.recorder.state != .ready &&
                               model.recorder.state != .locationPermissionNeeded {
                                Spacer()
                                    .frame(height: UIScreen.main.safeAreaInsets.bottom)
                            }

                            if focusedField == .title || focusedField == .description {
                                Spacer()
                                    .frame(height: keyboardHeight + 20.0)
                            }
                        }
                        .maxWidth(.infinity)
                        .mask {
                            GeometryReader { scrollProxy in
                                let offset = scrollProxy.frame(in: .named("scroll2")).minY
                                let drawerOffset = offset < 0 ? -1 * offset : 0

                                VStack(spacing: 0) {
                                    Image("layout_gradient")
                                        .resizable(resizingMode: .stretch)
                                        .frame(width: UIScreen.main.bounds.width, height: 30)
                                    Color.black
                                }
                                .offset(x: 0, y: drawerOffset)
                            }
                        }
                        .offset(y: contentOffset)
                    }
                    .id(1)
                }
                .maxHeight(.infinity)
                .ignoresSafeArea()
            }
           .introspectScrollView { scrollView in
               scrollView.setValue(0.3, forKeyPath: "contentOffsetAnimationDuration")
               scrollView.delaysContentTouches = false
               scrollView.contentInsetAdjustmentBehavior = .never
               scrollView.showsVerticalScrollIndicator = false
               DispatchQueue.main.async {
                   if self.uiScrollView == nil {
                       self.uiScrollView = scrollView
                   }
               }
           }
           .scrollDisabled(model.recorder.state != .saved)
           .ignoresSafeArea()
           .onChange(of: model.recorder.state) { newValue in
               if newValue == .saved && (model.recorder.graphDataSource?.hasData ?? false || model.showDistanceStats) {
                   DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                       withAnimation {
                           proxy.scrollTo(1, anchor: .top)
                       }
                   }
               }
           }
           .onChange(of: model.post.comments) { _ in
               guard let scrollView = uiScrollView else {
                   return
               }
               let y = scrollView.contentSize.height - scrollView.frame.height
               uiScrollView?.setContentOffset(CGPoint(x: 0.0, y: y), animated: true)
           }
           .onChange(of: model.postCommentDraftText) { _ in
               guard let scrollView = uiScrollView else {
                   return
               }
               let y = scrollView.contentSize.height - scrollView.frame.height
               uiScrollView?.setContentOffset(CGPoint(x: 0.0, y: y), animated: true)
           }
           .onChange(of: focusedField) { [oldValue = focusedField] newValue in
               guard let scrollView = uiScrollView else {
                   return
               }

               if (newValue == .title || newValue == .description) && oldValue == nil {
                   scrollView.setContentOffset(CGPoint(x: 0.0, y: UIScreen.main.heightMinusSafeArea() - closedHeight), animated: true)
               }

               if newValue == nil && oldValue != nil {
                   withAnimation(self.keyboardAnimation) {
                       self.contentOffset = 0.0
                   }
               }
           }
        }
        .coordinateSpace(name: "scroll2")
        .alert("Discard activity", isPresented: $showingDiscardModal) {
            Button("Discard activity", role: .destructive) {
                model.recorder.stopAndDiscardActivity()
            }
        } message: {
            Text("Are you sure you want to discard this activity?")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.keyboardWillShowNotification)) { notification in
            if let keyboardFrame: NSValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
                let keyboardRectangle = keyboardFrame.cgRectValue
                self.keyboardHeight = keyboardRectangle.height - UIScreen.main.safeAreaInsets.bottom
                self.keyboardAnimation = animation(from: notification) ?? .easeInOut(duration: 0.3)
                if focusedField == .commentBox {
                    withAnimation(self.keyboardAnimation) {
                        self.contentOffset = -1 * keyboardHeight
                    }
                }
            }
        }
    }
}

private extension UISpringTimingParameters {
    var mass: Double? {
        value(forKey: "mass") as? Double
    }
    var stiffness: Double? {
        value(forKey: "stiffness") as? Double
    }
    var damping: Double? {
        value(forKey: "damping") as? Double
    }
}

fileprivate struct ControlBar: View {
    @ObservedObject var model: RecordingViewModel
    @Binding var showingPhotoTakenToast: Bool

    var stopAction: () -> Void
    var playPauseAction: () -> Void
    var shareAction: () -> Void
    var postAction: () -> Void

    private let tapAndHoldToStopDuration: TimeInterval = 1.0
    @Binding var isStopButtonPressed: Bool
    @State private var pressTimer: Timer?

    @State private var showingCamera: Bool = false
    @State private var latestCameraPhoto: UIImage?

    private func showCamera() {
        Analytics.logEvent("Tap Camera", model.screenName, .buttonTap)
        showingCamera = true
    }

    private func dragGesture() -> some Gesture {
        return DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { _ in
                guard !isStopButtonPressed &&
                        model.recorder.state == .paused else {
                    return
                }

                pressTimer?.invalidate()
                pressTimer = Timer.scheduledTimer(withTimeInterval: tapAndHoldToStopDuration, repeats: false, block: { timer in
                    if isStopButtonPressed {
                        stopAction()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            pressTimer?.invalidate()
                            isStopButtonPressed = false
                        }
                    }
                })

                withAnimation(.linear(duration: tapAndHoldToStopDuration)) {
                    isStopButtonPressed = true
                }
            }
            .onEnded { _ in
                var delay: CGFloat = 0.0
                if (pressTimer?.fireDate.timeIntervalSince(Date()) ?? 0) > (tapAndHoldToStopDuration - 0.3) {
                    delay = 0.3
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.easeOut(duration: 0.35)) {
                        isStopButtonPressed = false
                    }
                }
            }
    }

    var bottomGradient: some View {
        Image("gradient_bottom_ease_in_out")
            .renderingMode(.template)
            .resizable(resizingMode: .stretch)
            .foregroundColor(.black)
            .frame(width: UIScreen.main.bounds.width)
            .padding(.bottom, -100)
    }

    var body: some View {
        GeometryReader { geo in
            VStack {
                Spacer()
                    .frame(height: geo.size.height - 100)
                ZStack {
                    if model.recorder.state == .saved && ADUser.current.hasRegistered {
                        bottomGradient
                        bottomGradient
                        bottomGradient

                        VStack(spacing: 10) {
                            Button(action: postAction) {
                                ZStack {
                                    let scale = model.isPosting ? 0.9 : 1.0
                                    RoundedRectangle(cornerRadius: 10.0, style: .continuous)
                                        .fill(.white)
                                        .scaleEffect(x: scale, y: scale)
                                        .opacity(model.isPosting ? 0.6 : 1.0)
                                    Text(model.post.isWithinThisActiveClubWeek ? "Post to Active Club" : "Post to your profile")
                                        .foregroundColor(.black)
                                        .font(.system(size: 17.0, weight: .semibold, design: .default))
                                        .opacity(model.isPosting ? 0.0 : 1.0)
                                    ProgressView()
                                        .tint(Color.black)
                                        .opacity(model.isPosting ? 1.0 : 0.0)
                                }
                            }
                            .frame(height: 50)
                            .allowsHitTesting(!model.isPosting)
                            .allowsHitTesting(model.currentMediaUploadIndices.isEmpty)
                            .opacity(model.currentMediaUploadIndices.isEmpty ? 1.0 : 0.6)

                            if !model.post.isWithinThisActiveClubWeek {
                                HStack(spacing: 3) {
                                    Image(systemName: .infoCircle)
                                        .font(.system(size: 13, weight: .medium))
                                    Text("This won't contribute to this week's Active Club stats")
                                        .font(.system(size: 13, weight: .medium))
                                        .multilineTextAlignment(.center)
                                }
                                .foregroundColor(.white)
                                .opacity(0.6)
                            }
                        }
                        .padding()
                    } else if model.recorder.state != .saved {
                        bottomGradient
                        bottomGradient
                        bottomGradient

                        HStack {
                            Circle()
                                .frame(width: 45)
                                .foregroundColor(.white)
                                .overlay {
                                    Image(systemName: .stopFill)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 14)
                                        .foregroundColor(.black)
                                }
                                .padding([.leading, .trailing], 30)
                                .opacity(model.recorder.state == .paused ? 1 : 0)
                                .scaleEffect(model.recorder.state == .paused ? 1 : 0.8)
                                .opacity(isStopButtonPressed ? 0.5 : 1.0)
                                .animation(.linear(duration: 0.08), value: isStopButtonPressed)
                                .animation(.easeInOut(duration: 0.1), value: model.recorder.state)
                                .contentShape(Rectangle())
                                .gesture(dragGesture())
                            Spacer()

                            Button(action: playPauseAction) {
                                Circle()
                                    .frame(width: 73)
                                    .foregroundColor(Color(UIColor.adOrangeLighter))
                                    .overlay {
                                        Image(systemName: (model.recorder.state == .recording) ? .pauseFill : .playFill)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 23)
                                            .offset(x: (model.recorder.state == .recording) ? 0.0 : 2.5)
                                            .foregroundColor(.black)
                                    }
                            }
                            .opacity(model.recorder.state != .discarded ? 1 : 0)
                            .scaleEffect(model.recorder.state != .discarded ? 1 : 0.8)
                            .id(model.recorder.state.playPauseButtonID)
                            .modifier(BlurOpacityTransition(speed: 2.0))
                            .offset(x: -15)
                            Spacer()

                            ZStack {
                                if let latestCameraPhoto = latestCameraPhoto {
                                    Image(uiImage: latestCameraPhoto)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 45.0, height: 45.0)
                                        .cornerRadius(8.0, style: .continuous)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 8.0, style: .continuous)
                                                .stroke(Color.white, lineWidth: 2.0)
                                        }
                                        .modifier(BlurOpacityTransition(speed: 2.0, delay: 1.0))
                                } else {
                                    Button(action: showCamera) {
                                        Circle()
                                            .frame(width: 45)
                                            .foregroundColor(.white)
                                            .overlay {
                                                Image(systemName: .cameraFill)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fit)
                                                    .frame(width: 28)
                                                    .offset(y: -1.0)
                                                    .foregroundColor(.black)
                                            }
                                    }
                                    .modifier(BlurOpacityTransition(speed: 2.0, delay: 1.0))
                                }
                            }
                            .opacity(model.recorder.state != .discarded ? 1 : 0)
                            .scaleEffect(model.recorder.state != .discarded ? 1 : 0.8)
                            .animation(.easeInOut(duration: 0.1), value: model.recorder.state)
                            .padding(.trailing, 30)
                        }
                        .animation(.linear(duration: 0.2), value: model.recorder.state)
                        .allowsHitTesting(!(model.recorder.state == .ready && !model.networkConnected))
                    }
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            NativeCamera(image: $latestCameraPhoto, sourceType: .camera)
                .background(Color.black)
        }
        .onChange(of: latestCameraPhoto) { photo in
            if let photo = photo {
                Analytics.logEvent("Workout Photo Taken", model.screenName, .otherEvent)
                Task(priority: .userInitiated) {
                    if let url = try? await model.uploadPostMedia(photo) {
                        ParallelImageLoader.loadImage(with: url.imgixURL)
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    showingPhotoTakenToast = true
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    latestCameraPhoto = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        showingPhotoTakenToast = false
                    }
                }
            }
        }
    }
}

fileprivate extension iPhoneActivityRecordingState {
    var playPauseButtonID: Int {
        switch self {
        case .recording:
            return 0
        case .paused, .saving, .saved:
            return 1
        default:
            return 2
        }
    }
}

// MARK: - Stats

fileprivate struct StatText: View {
    enum StatValueFormatting {
        case decimal
        case decimalOnePlace
        case timestamp
        case integer
    }

    let label: String
    let value: Double
    let formatting: StatValueFormatting
    var unit: String = ""
    var isBold: Bool = false
    var bigFontSize: CGFloat = 38
    var boldColor: UIColor = .adYellow
    var editButtonVisible: Bool = false
    var editAction: (() -> Void)? = nil
    var showVisibilityIndicator: Bool = false
    @Binding var isVisible: Bool

    private var valueString: String {
        switch formatting {
        case .decimal:
            return "\(value.rounded(toPlaces: 2))".zeroPadded(to: 4, front: false)
        case .decimalOnePlace:
            return "\(value.rounded(toPlaces: 1))".zeroPadded(to: 3, front: false)
        case .timestamp:
            return TimeInterval(value).timeFormatted()
        case .integer:
            return "\(Int(value.rounded()))".zeroPadded(to: 3, front: true)
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack(alignment: .top, spacing: 6) {
                    Text(valueString)
                        .font(.system(size: bigFontSize,
                                      weight: isBold ? .semibold : .regular,
                                      design: .monospaced))
                        
                    Text(unit)
                        .font(.system(size: 13.5,
                                      weight: isBold ? .black : .bold,
                                      design: .monospaced))
                        .offset(y: 7)
                }
                .fixedSize()
                .if(showVisibilityIndicator) { view in
                    view
                        .opacity(isVisible ? 1.0 : 0.5)
                        .animation(.easeInOut(duration: 0.2), value: isVisible)
                }

                HStack {
                    Text(label)
                        .font(.presicav(size: 13, weight: isBold ? .bold : .regular))
                        .if(showVisibilityIndicator) { view in
                            view
                                .opacity(isVisible ? 1.0 : 0.5)
                                .animation(.easeInOut(duration: 0.2), value: isVisible)
                        }

                    if editButtonVisible, let action = editAction {
                        Button(action: action) {
                            Image(systemName: "pencil.circle.fill")
                        }
                    } else if showVisibilityIndicator {
                        Spacer()
                            .frame(width: 20)
                            .overlay {
                                Image(isVisible ? "glyph_eye" : "glyph_eye_slash")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 12, height: 12)
                            }
                            .id(isVisible ? 0 : 1)
                            .transition(.scale.animation(.easeInOut(duration: 0.3)))
                    }
                }
            }
            .foregroundColor(isBold ? Color(boldColor) : .white)
            Spacer()
        }
        .background(Color.black.opacity(0.01))
    }
}

fileprivate struct ActivityTypeGoalSelector: View {
    @ObservedObject var model: RecordingViewModel
    @State private var showingGoalSelection: Bool = false
    @State private var formattedGoalTarget: String = ""

    var body: some View {
        HStack {
            ActivityTypeSearchButton(activityType: $model.recorder.activityType)

            Button {
                showingGoalSelection = true
                Analytics.logEvent("Tap goal type", model.screenName, .buttonTap)
            } label: {
                HStack(spacing: 5.0) {
                    if let image = model.recorder.goal.type.glyph(forDistanceUnit: model.recorder.unit) {
                        Image(uiImage: image)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(Color(uiColor: model.recorder.goal.type.lighterColor))
                            .frame(width: 17.0, height: 17.0)
                    }
                    Text(formattedGoalTarget)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(uiColor: model.recorder.goal.type.lighterColor))
                    Image(systemName: .chevronRight)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 10.0, height: 10.0)
                        .fontWeight(.bold)
                        .foregroundColor(Color(uiColor: model.recorder.goal.type.lighterColor))
                }
                .padding([.top, .bottom], 12.0)
                .padding([.leading, .trailing], 18.0)
                .background {
                    ZStack {
                        DarkBlurView()
                        Color(uiColor: model.recorder.goal.type.color)
                            .opacity(0.15)
                    }
                    .frame(height: 48.0)
                    .cornerRadius(24.0, style: .continuous)
                }
            }
            .id(model.recorder.goal.type.displayName)
            .modifier(BlurOpacityTransition(speed: 1.8))
        }
        .offset(y: 10.0)
        .padding([.leading, .trailing], 15.0)
        .onAppear {
            formattedGoalTarget = model.recorder.goal.lowercasedFormattedTargetWithUnit
        }
        .onChange(of: model.recorder.goal) { _ in
            formattedGoalTarget = model.recorder.goal.lowercasedFormattedTargetWithUnit
        }
        .onReceive(model.recorder.goal.objectWillChange) {
            formattedGoalTarget = model.recorder.goal.lowercasedFormattedTargetWithUnit
        }
        .onChange(of: model.recorder.activityType) { activityType in
            model.hasScrolledToFirstLocation = !activityType.showsRoute
            if !model.recorder.activityType.isDistanceBased && model.recorder.goal.type == .distance {
                model.recorder.goal = RecordingGoal(type: .open,
                                                    unit: model.recorder.unit,
                                                    target: 0.0)
            }

        }
        .fullScreenCover(isPresented: $showingGoalSelection) {
            RecordingGoalSelectionView(activityType: model.recorder.activityType,
                                       goal: $model.recorder.goal)
            .background(BackgroundClearView())
        }
    }
}

fileprivate struct AndiLocation: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        VStack(spacing: 20.0) {
            Image("andi-location")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 110.0)
            Text("To track your route, tap \"Next\" and allow location permissions. Your location remains private and stays on your device.")
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .font(.system(size: 16.0))
            Button {
                if model.recorder.locationManager.authorizationStatus == .denied {
                    Analytics.logEvent("Location open settings", model.screenName, .buttonTap)
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                } else {
                    Analytics.logEvent("Request loocation", model.screenName, .buttonTap)
                    model.recorder.requestLocationAuthorization()
                }
            } label: {
                let text = model.recorder.locationManager.authorizationStatus == .denied ? "Open Settings" : "Next"
                RoundedWhiteButtonLabel(text: text)
                    .frame(width: text == "Next" ? 120.0 : 150.0, height: 36.0)
            }
        }
        .padding([.leading, .trailing], 30.0)
    }
}

fileprivate struct AndiIntro: View {
    @ObservedObject var model: RecordingViewModel
    @StateObject var weatherFetcher: WeatherFetcher = WeatherFetcher.shared
    @State var showingSafetyMessageView: Bool = false
    @State private var animate: Bool = false
    @State private var videoPlaying: Bool = true
    var drawerClosedHeight: CGFloat

    var andiVideoURL: URL? = {
        let videoName = "andi-loop-\(Int.random(in: 1...4)).mp4"
        return URL(string: "https://anydistancecounts.s3-us-east-2.amazonaws.com/andi-loops/" + videoName)
    }()

    func locationAuthorized() -> Bool {
        return CLLocationManager().authorizationStatus == .authorizedWhenInUse ||
               CLLocationManager().authorizationStatus == .authorizedAlways
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack {
                Spacer()
                LoopingVideoView(videoUrl: andiVideoURL,
                                 isPlaying: videoPlaying)
                    .frame(width: 200.0, height: 200.0)
                    .onDisappear {
                        videoPlaying = false
                    }
                    .onAppear {
                        videoPlaying = true
                    }
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0.0),
                                               .init(color: .black, location: 0.25),
                                               .init(color: .black, location: 0.75),
                                               .init(color: .clear, location: 1.0)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0.0),
                                               .init(color: .black, location: 0.25)],
                                       startPoint: .top, endPoint: .bottom)
                    }
            }
            .offset(y: -36.0)

            VStack {
                Spacer()
                VStack {
                    if !model.hasTappedStart {
                        VStack(spacing: 10.0) {
                            Text("Great to see you!")
                                .font(.greedMedium(size: 28.0))
                                .offset(y: locationAuthorized() ? 0.0 : -50.0)

                            if locationAuthorized() {
                                if weatherFetcher.weather != nil {
                                    WeatherView(weather: $weatherFetcher.weather)
                                        .modifier(BlurOpacityTransition(speed: 1.8))
                                } else {
                                    VStack(spacing: 13.0) {
                                        DarkBlurView()
                                            .cornerRadius(6.0, style: .continuous)
                                            .frame(width: 130.0, height: 18.0)
                                    }
                                    .brightness(animate ? 0.15 : 0.07)
                                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                                               value: animate)
                                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                                    .onAppear {
                                        animate = true
                                    }
                                }
                            }
                        }
                        .frame(width: UIScreen.main.bounds.width)
                        .modifier(BlurOpacityTransition(speed: 1.5))
                        .multilineTextAlignment(.center)
                        .offset(y: locationAuthorized() ? -20.0 : 50.0)
                    } else {
                        Text("Get Ready!")
                            .font(.greedMedium(size: 28.0))
                            .modifier(BlurOpacityTransition(speed: 1.5))
                            .offset(y: -80.0)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(.white)

                Spacer()

                if !model.hasTappedStart {
                    ActivityTypeGoalSelector(model: model)
                        .padding(.bottom, 12.0)
                        .modifier(BlurOpacityTransition(speed: 1.5))

                    Button {
                        Analytics.logEvent("Start", model.screenName, .buttonTap)
                        if NSUbiquitousKeyValueStore.default.defaultRecordingSettings.showSafetyMessagePrompt {
                            showingSafetyMessageView = true
                        } else {
                            model.prepareToStartActivity()
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 30.0, style: .continuous)
                                .fill(Color.white)
                            Text("Start")
                                .font(.system(size: 17.0, weight: .semibold))
                                .foregroundColor(.black)
                        }
                    }
                    .frame(height: 55.0)
                    .padding([.leading, .trailing], 15.0)
                    .modifier(BlurOpacityTransition(speed: 1.5))
                }
            }
            .frame(width: UIScreen.main.bounds.width)
        }
        .frame(height: 360.0)
        .fullScreenCover(isPresented: $showingSafetyMessageView) {
            SafetyMessageView(type: .startingActivity,
                              activityType: model.recorder.activityType,
                              goal: model.recorder.goal) { result in
                model.recorder.didSendSafetyMessageAtStart = result == .sent
                model.prepareToStartActivity()
                showingSafetyMessageView = false
            }
            .background(BackgroundClearView())
        }
        .onAppear {
            weatherFetcher.requestNewWeather()
        }
    }
}

fileprivate struct WeatherView: View {
    @Binding var weather: Weather?

    var body: some View {
        ZStack {
            if let weather = weather {
                HStack(spacing: 16.0) {
                    HStack(spacing: 4.0) {
                        Image(systemName: weather.currentWeather.temperatureIconName)
                            .font(.system(size: 16.0))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(weather.currentWeather.temperatureColor,
                                             weather.currentWeather.temperatureColor.opacity(0.6))
                        Text(weather.currentWeather.temperature.formatted(.measurement(width: .abbreviated,
                                                                                       usage: .weather,
                                                                                       numberFormatStyle: .number.precision(.fractionLength(0)))))
                            .font(.system(size: 12.0, weight: .medium, design: .monospaced))
                    }

                    HStack(spacing: 4.0) {
                        Image(systemName: weather.currentWeather.condition.iconName)
                            .font(.system(size: 15.0))
                            .if(weather.currentWeather.condition.secondaryIconColor != nil) { view in
                                view
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(weather.currentWeather.condition.iconColor,
                                                     weather.currentWeather.condition.secondaryIconColor!)
                            }
                            .if(weather.currentWeather.condition.secondaryIconColor == nil) { view in
                                view
                                    .foregroundColor(weather.currentWeather.condition.iconColor)
                            }
                        Text(weather.currentWeather.condition.rawValue.camelCaseToWords().capitalized)
                            .font(.system(size: 12.0, weight: .medium, design: .monospaced))
                    }
                }
            }
        }
        .frame(height: 18.0)
    }
}

fileprivate struct Stats: View {
    @ObservedObject var model: RecordingViewModel

    @State private var distanceVisible: Bool
    @State private var speedVisible: Bool
    @State private var paceVisible: Bool
    @State private var durationVisible: Bool
    @State private var caloriesVisible: Bool

    init(model: RecordingViewModel) {
        self.model = model
        self.distanceVisible = model.post.statTypeIsVisible(.distance)
        self.speedVisible = model.post.statTypeIsVisible(.averageSpeed)
        self.paceVisible = model.post.statTypeIsVisible(.pace)
        self.durationVisible = model.post.statTypeIsVisible(.movingTime)
        self.caloriesVisible = model.post.statTypeIsVisible(.activeCalories)
    }
    
    var statTextFontSize: CGFloat {
        return model.recorder.duration >= 3600 ? 35 : 38
    }
    
    var durationLabelString: String {
        switch model.recorder.duration {
        case 0..<60:
            return "SECONDS"
        case 60..<3600:
            return "MINUTES"
        default:
            return "HOURS"
        }
    }

    var body: some View {
        let statWidth = (UIScreen.main.bounds.width / 2) - 15
        let showVisibilityIndicator = (model.recorder.state == .saved && model.post.isDraft && ADUser.current.hasRegistered)
        VStack(alignment: .center, spacing: 16) {
            if showVisibilityIndicator {
                HStack(spacing: 3.0) {
                    Image(systemName: .infoCircle)
                        .font(.system(size: 13, weight: .medium))
                    Text("Tap stats to hide them from your friends")
                        .font(.system(size: 13.0, weight: .medium))
                    Spacer()
                }
                .opacity(0.7)
                .padding([.leading], 12.0)
            }

            if model.showDistanceStats {
                HStack {
                    Spacer()
                    StatText(label: "DISTANCE",
                             value: model.recorder.distanceInUnit,
                             formatting: .decimal,
                             unit: model.recorder.unit.abbreviation.uppercased(),
                             isBold: model.recorder.goal.type == .distance,
                             bigFontSize: statTextFontSize,
                             boldColor: model.recorder.state == .ready ? .white : RecordingGoalType.distance.color,
                             editButtonVisible: false, // TODO: support this
                             showVisibilityIndicator: showVisibilityIndicator,
                             isVisible: $distanceVisible)
                    .frame(width: statWidth)
                    .onTapGesture {
                        if model.recorder.state == .saved {
                            distanceVisible = !distanceVisible
                        } else {
                            model.howWeCalculatePopupModel.showStatCalculation(for: .distance)
                        }
                    }
                    Spacer()
                    if model.recorder.activityType.shouldShowSpeedInsteadOfPace {
                        StatText(label: "AVG SPEED",
                                 value: model.recorder.avgSpeed,
                                 formatting: .decimalOnePlace,
                                 unit: model.recorder.unit.speedAbbreviation.uppercased(),
                                 bigFontSize: statTextFontSize,
                                 showVisibilityIndicator: showVisibilityIndicator,
                                 isVisible: $speedVisible)
                        .frame(width: statWidth)
                        .onTapGesture {
                            if model.recorder.state == .saved {
                                speedVisible = !speedVisible
                            } else {
                                model.howWeCalculatePopupModel.showStatCalculation(for: .pace)
                            }
                        }
                    } else {
                        StatText(label: "PACE",
                                 value: model.recorder.pace,
                                 formatting: .timestamp,
                                 unit: "/\(model.recorder.unit.abbreviation.uppercased())",
                                 bigFontSize: statTextFontSize,
                                 showVisibilityIndicator: showVisibilityIndicator,
                                 isVisible: $paceVisible)
                        .frame(width: statWidth)
                        .onTapGesture {
                            if model.recorder.state == .saved {
                                paceVisible = !paceVisible
                            } else {
                                model.howWeCalculatePopupModel.showStatCalculation(for: .pace)
                            }
                        }
                    }
                    Spacer()
                }
            }

            HStack {
                Spacer()
                StatText(label: durationLabelString,
                         value: model.recorder.duration,
                         formatting: .timestamp,
                         isBold: model.recorder.goal.type == .time,
                         bigFontSize: statTextFontSize,
                         boldColor: model.recorder.state == .ready ? .white : RecordingGoalType.time.color,
                         showVisibilityIndicator: showVisibilityIndicator,
                         isVisible: $durationVisible)
                .frame(width: statWidth)
                .onTapGesture {
                    if model.recorder.state == .saved {
                        durationVisible = !durationVisible
                    } else {
                        model.howWeCalculatePopupModel.showStatCalculation(for: .time)
                    }
                }
                Spacer()
                StatText(label: "ACTIVE CAL",
                         value: model.recorder.totalCalories,
                         formatting: .integer,
                         isBold: model.recorder.goal.type == .calories,
                         bigFontSize: statTextFontSize,
                         boldColor: model.recorder.state == .ready ? .white : RecordingGoalType.calories.color,
                         showVisibilityIndicator: showVisibilityIndicator,
                         isVisible: $caloriesVisible)
                .frame(width: statWidth)
                .onTapGesture {
                    if model.recorder.state == .saved {
                        caloriesVisible = !caloriesVisible
                    } else {
                        model.howWeCalculatePopupModel.showStatCalculation(for: .activeCal)
                    }
                }
                Spacer()
            }
        }
        .offset(x: 14)
        .opacity(model.recorder.state == .ready ? 0.6 : 1)
        .animation(.linear(duration: 0.2), value: model.recorder.state)
        .onChange(of: distanceVisible) { visible in
            model.post.setVisible(visible, for: .distance)
            model.cacheDraftedPost()
        }
        .onChange(of: speedVisible) { visible in
            model.post.setVisible(visible, for: .averageSpeed)
            model.cacheDraftedPost()
        }
        .onChange(of: paceVisible) { visible in
            model.post.setVisible(visible, for: .pace)
            model.cacheDraftedPost()
        }
        .onChange(of: durationVisible) { visible in
            model.post.setVisible(visible, for: .movingTime)
            model.cacheDraftedPost()
        }
        .onChange(of: caloriesVisible) { visible in
            model.post.setVisible(visible, for: .activeCalories)
            model.cacheDraftedPost()
        }
    }
}

fileprivate struct LiveStats: View {
    @ObservedObject var model: RecordingViewModel

    var statTextFontSize: CGFloat {
        return model.recorder.duration >= 3600 ? 35 : 38
    }

    var durationLabelString: String {
        switch model.recorder.duration {
        case 0..<60:
            return "SECONDS"
        case 60..<3600:
            return "MINUTES"
        default:
            return "HOURS"
        }
    }

    func distance(with statWidth: CGFloat) -> AnyView {
        AnyView(StatText(label: "DISTANCE",
                         value: model.recorder.distanceInUnit,
                         formatting: .decimal,
                         unit: model.recorder.unit.abbreviation.uppercased(),
                         isBold: model.recorder.goal.type == .distance,
                         bigFontSize: statTextFontSize,
                         boldColor: model.recorder.state == .ready ? .white : RecordingGoalType.distance.color,
                         showVisibilityIndicator: false,
                         isVisible: .constant(true))
        .frame(width: statWidth))
    }

    func speed(with statWidth: CGFloat) -> AnyView {
        AnyView(StatText(label: "AVG SPEED",
                         value: model.recorder.avgSpeed,
                         formatting: .decimalOnePlace,
                         unit: model.recorder.unit.speedAbbreviation.uppercased(),
                         bigFontSize: statTextFontSize,
                         showVisibilityIndicator: false,
                         isVisible: .constant(true))
        .frame(width: statWidth))
    }

    func pace(with statWidth: CGFloat) -> AnyView {
        AnyView(StatText(label: "PACE",
                         value: model.recorder.pace,
                         formatting: .timestamp,
                         unit: "/\(model.recorder.unit.abbreviation.uppercased())",
                         bigFontSize: statTextFontSize,
                         showVisibilityIndicator: false,
                         isVisible: .constant(true))
        .frame(width: statWidth))
    }

    func duration(with statWidth: CGFloat) -> AnyView {
        AnyView(StatText(label: durationLabelString,
                         value: model.recorder.duration,
                         formatting: .timestamp,
                         isBold: model.recorder.goal.type == .time,
                         bigFontSize: statTextFontSize,
                         boldColor: model.recorder.state == .ready ? .white : RecordingGoalType.time.color,
                         showVisibilityIndicator: false,
                         isVisible: .constant(true))
        .frame(width: statWidth))
    }

    func activeCal(with statWidth: CGFloat) -> AnyView {
        AnyView(StatText(label: "ACTIVE CAL",
                         value: model.recorder.totalCalories,
                         formatting: .integer,
                         isBold: model.recorder.goal.type == .calories,
                         bigFontSize: statTextFontSize,
                         boldColor: model.recorder.state == .ready ? .white : RecordingGoalType.calories.color,
                         showVisibilityIndicator: false,
                         isVisible: .constant(true))
        .frame(width: statWidth))
    }

    var filteredViews: [AnyView] {
        let statWidth: CGFloat = (UIScreen.main.bounds.width / 2) - 15
        var filteredViews: [AnyView] = []
        if model.recorder.distanceInUnit > 0 && model.post.statTypeIsVisible(.distance) {
            let view = distance(with: statWidth)
            filteredViews.append(view)
        }

        if model.recorder.activityType.shouldShowSpeedInsteadOfPace {
            if model.recorder.avgSpeed > 0 && model.post.statTypeIsVisible(.averageSpeed) {
                let view = speed(with: statWidth)
                filteredViews.append(view)
            }
        } else {
            if model.recorder.paceMeters > 0 && model.post.statTypeIsVisible(.pace) {
                let view = pace(with: statWidth)
                filteredViews.append(view)
            }
        }

        if model.recorder.duration > 0 && model.post.statTypeIsVisible(.movingTime) {
            let view = duration(with: statWidth)
            filteredViews.append(view)
        }

        if model.recorder.totalCalories > 0 && model.post.statTypeIsVisible(.activeCalories) {
            let view = activeCal(with: statWidth)
            filteredViews.append(view)
        }

        return filteredViews
    }

    var body: some View {
        GeometryReader { geo in
            let statWidth: CGFloat = (UIScreen.main.bounds.width / 2) - 15
            VStack(alignment: .center, spacing: 16) {
                HStack {
                    Spacer()
                    if filteredViews.count > 0 {
                        filteredViews[0]
                    }
                    Spacer()
                    if filteredViews.count > 1 {
                        filteredViews[1]
                    } else {
                        Spacer()
                            .frame(width: statWidth)
                    }
                    Spacer()
                }

                HStack {
                    Spacer()
                    if filteredViews.count > 2 {
                        filteredViews[2]
                    }
                    Spacer()
                    if filteredViews.count > 3 {
                        filteredViews[3]
                    } else {
                        Spacer()
                            .frame(width: statWidth)
                    }
                    Spacer()
                }

                if !filteredViews.isEmpty {
                    Spacer()
                        .frame(height: 600)
                }
            }
            .offset(x: 14)
        }
        .frame(height: filteredViews.count > 2 ? 140 : 60)
    }
}

fileprivate struct GoalProgressBar: View {
    @ObservedObject var model: RecordingViewModel

    private var goalColor: Color {
        return Color(model.recorder.goal.type.color)
    }

    private var lighterGoalColor: Color {
        return Color(model.recorder.goal.type.color.darker(by: 20) ?? model.recorder.goal.type.color)
    }

    var body: some View {
        HStack {
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 4)
                    .maxWidth(.infinity)
                    .overlay {
                        GeometryReader { geo in
                            ZStack {
                                HStack(spacing: 0.0) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(
                                            LinearGradient(colors: [lighterGoalColor, goalColor],
                                                           startPoint: .leading,
                                                           endPoint: .trailing)
                                        )
                                    Spacer()
                                        .frame(width: CGFloat(1 - model.recorder.goalProgress) * geo.size.width)
                                }
                                .frame(height: 4)
                                .offset(y: -4)

                                Circle()
                                    .fill(goalColor)
                                    .frame(width: 12, height: 12)
                                    .overlay {
                                        Circle()
                                            .fill(goalColor)
                                            .frame(width: 28, height: 28)
                                            .blur(radius: 8)
                                            .opacity(0.5)
                                    }
                                    .offset(x: CGFloat(model.recorder.goalProgress - 0.5) * geo.size.width,
                                            y: -4)
                            }
                        }
                    }
            }

            Text(model.recorder.goal.shortFormattedTargetWithUnit)
                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
        }
        .padding([.leading, .trailing], 24)
        .animation(.easeInOut(duration: 0.15), value: model.recorder.goalProgress)
    }
}

// MARK: - Posts

fileprivate struct ActivityTypeTimeHeader: View {
    @ObservedObject var model: RecordingViewModel

    var dateString: String {
        let format = "MMMM d"
        if let finishedWorkout = model.recorder.finishedWorkout {
            return finishedWorkout.startDate.formatted(withFormat: format)
        } else {
            return model.post.activityStartDateUTC.formatted(withFormat: format)
        }
    }

    var timeString: String {
        let format = "h:mma"
        if let finishedWorkout = model.recorder.finishedWorkout {
            return finishedWorkout.startDate.formatted(withFormat: format) +
            " - " +
            finishedWorkout.endDate.formatted(withFormat: format)
        } else {
            return model.post.activityStartDateUTC.formatted(withFormat: format) +
            " - " +
            model.post.activityEndDateUTC.formatted(withFormat: format)
        }
    }

    var body: some View {
        HStack {
            HStack {
                Image(model.post.activityType.glyphName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 27.0, height: 27.0)
                Text(model.post.activityType.displayName)
                    .lineLimit(10)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white)
            }
            .foregroundColor(.white)

            Spacer()

            HStack(spacing: 4) {
                Text(dateString)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(timeString)
                    .fontWeight(.regular)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.system(size: 11))
            .opacity(0.7)
        }
        .padding([.leading, .trailing], 15)
    }
}

fileprivate struct LocationHideToggle: View {
    @ObservedObject var model: RecordingViewModel
    @State var locationVisible: Bool = false

    var body: some View {
        ZStack {
            HStack {
                Text("Location visible to friends")
                    .font(.system(size: 14.0, weight: .medium))
                    .lineLimit(1)
                Spacer()
            }

            HStack {
                Spacer()
                Toggle("", isOn: $locationVisible)
                    .scaleEffect(x: 0.8, y: 0.8, anchor: .trailing)
            }
        }
        .padding([.leading, .trailing], 12.0)
        .padding([.top, .bottom], 8.0)
        .background {
            RoundedRectangle(cornerRadius: 10.0, style: .continuous)
                .fill(Color.white.opacity(0.1))
        }
        .onAppear {
            locationVisible = !model.post.hiddenStatTypes.contains(Post.HiddenStatType.location.rawValue)
        }
        .onChange(of: locationVisible) { _ in
            if locationVisible {
                model.post.hiddenStatTypes.removeAll(where: { $0 == Post.HiddenStatType.location.rawValue })
            } else {
                model.post.hiddenStatTypes.append(Post.HiddenStatType.location.rawValue)
            }
        }
    }
}

fileprivate struct PostHeader: View {
    @ObservedObject var model: RecordingViewModel
    @FocusState var focusedField: PostFocusedField?

    private let lrPadding: CGFloat = 24.0

    @State var descriptionHeight: CGFloat? = 16.0
    @State var attributedPostDescription: AttributedString?

    private func decodePostDescriptionTags() {
        guard !model.post.postDescription.isEmpty else {
            attributedPostDescription = nil
            return
        }

        self.attributedPostDescription = TagCoder.decodeTags(for: model.post.postDescription,
                                                             withBaseFontSize: 14.0).attributedString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.post.isDraft || !model.post.title.isEmpty {
                TextField("New post", text: $model.post.title, axis: .vertical)
                    .onSubmit {
                        focusedField = .description
                    }
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
                    .tint(.adOrangeLighter)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.next)
                    .allowsHitTesting(model.post.isDraft)
                    .frame(minHeight: 30.0)
                    .if(model.post.isDraft) { view in
                        view
                            .padding([.leading, .trailing], 10)
                            .modifier(EditingAnimationBorder())
                    }
            }

            if model.post.isDraft {
                TaggableTextField(placeholder: "Write an optional caption about your activity.",
                                  text: $model.post.postDescription,
                                  axis: .vertical,
                                  returnKeyType: .default,
                                  font: UIFont.systemFont(ofSize: 14))
                .font(.system(size: 14))
                .multilineTextAlignment(.leading)
                .foregroundColor(.white)
                .tint(.adOrangeLighter)
                .focused($focusedField, equals: .description)
                .submitLabel(.return)
                .allowsHitTesting(model.post.isDraft)
                .padding([.leading, .trailing], 10)
                .padding([.top, .bottom], 6)
                .modifier(EditingAnimationBorder())
            } else if let attributedPostDescription = attributedPostDescription {
                let maxWidth = UIScreen.main.bounds.width - (lrPadding * 2.0)
                UsernameTappableAttributedText(attributedText: attributedPostDescription,
                                               maxWidth: maxWidth,
                                               layoutWidth: .constant(nil),
                                               layoutHeight: $descriptionHeight)
                .frame(height: descriptionHeight)
                .frame(maxWidth: maxWidth)
            }

            let showLocation: Bool = {
                return !model.isViewingLivePost ||
                       (model.isViewingLivePost && !model.post.hiddenStatTypes.contains(Post.HiddenStatType.location.rawValue))
            }()

            if showLocation,
               let coords = model.post.coordinates,
                !coords.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: .locationFill)
                        .foregroundColor(.white)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))

                    Text(model.post.cityAndState ?? "")
                        .foregroundColor(.white)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .id(model.post.cityAndState ?? "none")
                        .modifier(BlurOpacityTransition(speed: 1.6))

                    if model.post.hiddenStatTypes.contains(Post.HiddenStatType.location.rawValue) {
                        Image("glyph_eye_slash")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(.white)
                            .frame(width: 10.0, height: 10.0)
                            .transition(.scale.animation(.easeInOut(duration: 0.15)))
                    }
                    Spacer()
                }
                .opacity(0.6)
            }

            if model.post.isDraft && model.post.activityType.showsRoute {
                LocationHideToggle(model: model)
            }
        }
        .padding([.leading, .trailing], lrPadding)
        .onChange(of: model.post.title) { newValue in
            if let last = newValue.last, last.isNewline {
                focusedField = .description
                model.post.title = String(model.post.title.dropLast())
            }
        }
        .onChange(of: model.post.postDescription) { newValue in
            decodePostDescriptionTags()
        }
        .onAppear {
            decodePostDescriptionTags()
        }
    }
}

fileprivate struct PostCommentReactionHeader: View {
    @ObservedObject var model: RecordingViewModel
    @State var showingInlineReactions: Bool = false
    @State var inlineHeartFilled: Bool = false
    @State var showReactButton: Bool = false
    @State var isReactable: Bool = false

    var body: some View {
        ZStack {
            HStack {
                HStack(spacing: 12) {
                    let reactions = model.post.talliedReactions
                        .map { $0 }
                        .sorted(by: \.key.rawValue)

                    ForEach(reactions, id: \.key.rawValue) { reactionType, count in
                        HStack(spacing: 2) {
                            Text(reactionType.emoji)
                                .font(.system(size: 12, design: .monospaced))
                            Text(String(count))
                                .font(.system(size: 17, design: .monospaced))
                        }
                    }
                }
                .padding(.leading, showReactButton ? 34.0 : 0.0)
                .opacity(showingInlineReactions ? 0.0 : 1.0)
                .animation(.easeInOut(duration: 0.08), value: showingInlineReactions)
                .drawingGroup()
                .id(model.post.reactions.count)
                .modifier(BlurOpacityTransition(speed: 2.0))

                Spacer()

                HStack {
                    LightBlurGlyph(symbolName: "message.fill", size: 16)
                    Text(String(model.post.comments.count))
                        .font(.system(size: 17, design: .monospaced))
                }
                .padding(.leading, 2)
            }
            .padding([.leading, .trailing], 24)

            HStack {
                InlineReactionPicker(heartFilled: $inlineHeartFilled,
                                     showingInlineReactions: $showingInlineReactions,
                                     onReact: { type in
                    self.model.react(with: type)
                    isReactable = false
                })
                .opacity(showReactButton ? 1.0 : 0.0)
                .allowsHitTesting(isReactable)

                Spacer()
            }
        }
        .background {
            Color.black
                .opacity(0.01)
                .onTapGesture {
                    showingInlineReactions = false
                }
        }
        .onAppear {
            if model.post.creatorIsSelf {
                isReactable = false
                showReactButton = false
            } else {
                isReactable = model.post.isReactable
                inlineHeartFilled = !model.post.isReactable
                showReactButton = true
            }
        }
    }
}

fileprivate struct GraphsAndCollectibles: View {
    @ObservedObject var model: RecordingViewModel
    @ObservedObject var dataSource: GraphCollectibleDataSource
    var shareAction: (GraphType) -> Void

    @State private var gearForDetail: Gear?
    @State private var showingGearSelect: Bool = false

    struct HeaderModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(.presicav(size: 16))
                .foregroundColor(.white)
        }
    }

    var shareButtonImage: some View {
        Image(systemName: .squareAndArrowUp)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 17, height: 17)
            .font(.system(size: 17, weight: .bold, design: .default))
            .padding()
            .foregroundColor(.white.opacity(0.5))
    }

    var body: some View {
        VStack(spacing: 0) {
            if !ADUser.current.gear.isEmpty {
                let gear = model.recorder.finishedWorkout?.gearIDs.compactMap({ id in
                    return ADUser.current.gear.first(where: { $0.id == id })
                }) ?? []

                HStack {
                    SectionHeaderText(text: "Shoes")
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        showingGearSelect = true
                    } label: {
                        HStack {
                            Image(systemName: gear.isEmpty ? .plus : .pencil)
                            Text(gear.isEmpty ? "Add" : "Edit")
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
                .padding([.leading, .trailing], 20)
                .padding(.bottom, 8)

                if gear.isEmpty {
                    GearEmptyState(text: "No shoes added for this activity")
                        .fixedSize(horizontal: false, vertical: true)
                        .padding([.leading, .trailing], 20)
                } else {
                    ForEach(gear, id: \.id) { gear in
                        GearCell(gear: gear, gearForDetail: $gearForDetail)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding([.leading, .trailing], 20)
                    }
                }

                Spacer()
                    .frame(height: 32)
            }

            if !dataSource.collectibles.isEmpty {
                SectionHeaderText(text: "Achievements")
                    .padding([.leading, .trailing], 20)
                    .padding(.bottom, 16)

                CollectiblesCarousel(collectibles: dataSource.collectibles,
                                     areCurrentUsersCollectibles: model.post.creatorIsSelf)
                    .frame(height: 164)
                    .frame(width: UIScreen.main.bounds.width)

                Spacer()
                    .frame(height: 32)
            }

            if let splitsGraphImage = dataSource.splitsGraphImage {
                SectionHeaderText(text: "Splits")
                    .padding([.leading, .trailing], 20)
                    .padding(.bottom, 16)

                Image(uiImage: splitsGraphImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .maxWidth(UIScreen.main.bounds.width)
                    .padding([.leading, .trailing], 20)

                Spacer()
                    .frame(height: 32)
            }

            if let elevationGraphImage = dataSource.elevationGraphImage {
                SectionHeaderText(text: "Elevation")
                    .padding([.leading, .trailing], 20)
                    .padding(.bottom, 8)

                Image(uiImage: elevationGraphImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: UIScreen.main.bounds.width)
                    .padding([.leading, .trailing], -4)

                Spacer()
                    .frame(height: 32)
            }

            if let heartRateGraphImage = dataSource.heartRateGraphImage {
                SectionHeaderText(text: "Heart Rate")
                    .padding([.leading, .trailing], 20)
                    .padding(.bottom, 8)
                    .padding(.top, 16)

                Image(uiImage: heartRateGraphImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: UIScreen.main.bounds.width)
            }
        }
        .fullScreenCover(item: $gearForDetail) { gearForDetail in
            GearDetailView(gear: gearForDetail,
                           showsEdit: false)
            .background(BackgroundClearView())
        }
        .fullScreenCover(isPresented: $showingGearSelect) {
            GearSelectView(selectedGearID: model.recorder.finishedWorkout?.gearIDs.first) { selectedID in
                model.recorder.finishedWorkout?.gearIDs = [selectedID].compactMap { $0 }
                model.objectWillChange.send()
            }
            .background(BackgroundClearView())
        }
    }
}

fileprivate struct PostCommentCell: View {
    @ObservedObject var model: RecordingViewModel
    var comment: PostComment
    @State private var creator: ADUser?
    @State private var loadedCreator: Bool = false
    @State private var commentMaxWidth: CGFloat = 0.0

    @State private var commentBubbleWidth: CGFloat? = 40.0
    @State private var commentBubbleHeight: CGFloat? = 32.0

    let profilePicBubbleSpacing: CGFloat = 8.0
    let cellLrPadding: CGFloat = 24.0
    let profilePicWidth: CGFloat = 28.0

    var creatorIsSelf: Bool {
        if !loadedCreator {
            return true
        }
        return (creator?.id ?? "") == ADUser.current.id
    }

    var usernameAndDate: some View {
        HStack(spacing: 1.0) {
            if let creator = creator {
                Text("@\(creator.username ?? "") - ")
                    .font(.system(size: 11.0, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            if let creationDate = comment.creationDate {
                Text(creationDate.formatted(withFormat: "MMM d h:mm a"))
                    .font(.system(size: 10.0, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                Text("SENDING")
                    .font(.system(size: 10.0, weight: .medium, design: .monospaced))
            }
        }
        .background(Color.black.opacity(0.01))
        .onTapGesture {
            Analytics.logEvent("Profile in comment tapped", model.screenName, .buttonTap)
            if let creator = creator {
                model.showProfile(for: creator)
            }
        }
    }

    var menu: some View {
        Menu {
            Button("Delete", systemImage: .trashFill) {
                if let id = comment.id {
                    model.deleteComment(with: id)
                }
            }
        } label: {
            Image(systemName: .ellipsis)
                .font(.system(size: 20.0))
        }
    }

    var profilePicture: some View {
        ProfileImageView(profilePictureURL: creator?.profilePhotoUrl,
                         name: creator?.name ?? "",
                         width: profilePicWidth)
        .onTapGesture {
            Analytics.logEvent("Profile in comment tapped", model.screenName, .buttonTap)
            if let creator = creator {
                model.showProfile(for: creator)
            }
        }
    }

    var commentBubble: some View {
        ZStack {
            let baseColor = UIColor.black
            let taggedColor = UIColor(white: 0.1, alpha: 1.0)
            let attrString = TagCoder.decodeTags(for: comment.body,
                                                 withBaseFontSize: 13.0,
                                                 baseColor: baseColor,
                                                 taggedColor: taggedColor).attributedString
            let lrPadding: CGFloat = 12.0
            let maxWidth = UIScreen.main.bounds.width - (lrPadding * 2.0) - profilePicBubbleSpacing - (cellLrPadding * 2.0) - profilePicWidth

            UsernameTappableAttributedText(attributedText: attrString,
                                           maxWidth: maxWidth,
                                           taggedColor: taggedColor,
                                           layoutWidth: $commentBubbleWidth,
                                           layoutHeight: $commentBubbleHeight)
                .foregroundColor(.black)
                .frame(width: commentBubbleWidth, height: commentBubbleHeight)
                .padding([.leading, .trailing], lrPadding)
                .padding([.top, .bottom], 10)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .foregroundColor(.white)
                }
        }
    }

    var body: some View {
        ZStack {
            if creatorIsSelf {
                HStack(alignment: .bottom, spacing: profilePicBubbleSpacing) {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 10) {
                            Spacer()
                            usernameAndDate
                            if model.post.creatorIsSelf || comment.wasCreatedBySelf {
                                menu
                            }
                        }
                        .foregroundColor(.white)
                        .opacity(0.6)
                        .padding([.leading, .trailing], 8)

                        commentBubble
                    }
                    profilePicture
                }
            } else {
                HStack(alignment: .bottom) {
                    profilePicture
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            if model.post.creatorIsSelf || comment.wasCreatedBySelf {
                                menu
                            }
                            usernameAndDate
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .opacity(0.6)
                        .padding([.leading, .trailing], 8)

                        commentBubble
                    }
                    Spacer()
                }
            }
        }
        .modifier(BlurOpacityTransition(speed: 1.8))
        .onAppear {
            Task {
                creator = await comment.author()
                loadedCreator = true
            }
        }
    }
}

fileprivate struct PostCommentBox: View {
    @ObservedObject var model: RecordingViewModel
    @FocusState var focusedField: PostFocusedField?

    private func postCommentAction() {
        model.postComment()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ProfileImageView(profilePictureURL: ADUser.current.profilePhotoUrl,
                             name: ADUser.current.name,
                             width: 34)
            .animation(.spring(response: 0.2, dampingFraction: 0.6),
                       value: model.postCommentDraftText)

            TaggableTextField(placeholder: "Add a comment as @\(ADUser.current.username ?? "")",
                              text: $model.postCommentDraftText,
                              axis: .vertical,
                              returnKeyType: .default,
                              font: .systemFont(ofSize: 13, weight: .medium))
            .focused($focusedField, equals: .commentBox)
            .padding([.leading, .trailing])
            .padding([.top, .bottom], 10)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, 40)
            .background {
                HStack {
                    Spacer()
                    VStack {
                        Spacer()
                        let scale = model.postCommentDraftText.isEmpty ? 0.5 : 1.0
                        Button(action: postCommentAction) {
                            ZStack {
                                Circle()
                                    .fill(Color.adOrangeLighter)
                                    .frame(width: 32, height: 32)
                                Image(systemName: .paperplaneFill)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)
                                    .offset(x: -1, y: 1)
                                    .foregroundColor(.black)
                            }
                        }
                        .padding([.bottom, .trailing], 7.5)
                        .opacity(model.postCommentDraftText.isEmpty ? 0.0 : 1.0)
                        .scaleEffect(x: scale, y: scale)
                        .animation(.spring(response: 0.2, dampingFraction: 0.6),
                                   value: model.postCommentDraftText)
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                        .animation(.spring(response: 0.2, dampingFraction: 0.6),
                                   value: model.postCommentDraftText)
                }
            }
            .offset(y: -5)
        }
    }
}

fileprivate struct PostComments: View {
    @ObservedObject var model: RecordingViewModel
    @FocusState var focusedField: PostFocusedField?

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 14) {
                ForEach(model.post.comments, id: \.id) { comment in
                    PostCommentCell(model: model, comment: comment)
                }
            }

            PostCommentBox(model: model, focusedField: _focusedField)
        }
        .padding([.leading, .trailing], 24)
        .padding(.bottom, 16)
        .animation(.easeInOut(duration: 0.2), value: model.post.comments)
    }
}

fileprivate struct MediaUploadCell: View {
    enum MediaUploadState: Int {
        case noMedia
        case uploading
        case uploaded
    }

    @ObservedObject var model: RecordingViewModel
    var idx: Int = 0
    var frameSize: CGFloat
    @State var mediaURL: URL?
    @State var state: MediaUploadState = .noMedia
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var offset: CGSize = .zero

    var body: some View {
        ZStack {
            switch state {
            case .noMedia:
                PhotosPicker(selection: $selectedPhotos,
                             maxSelectionCount: 4 - model.post.mediaUrls.count,
                             matching: .images) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.clear)
                        .overlay {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                                .opacity(0.5)
                        }
                }
                .onChange(of: selectedPhotos) { photos in
                    for newItem in photos {
                        Task {
                            if let data = try? await newItem.loadTransferable(type: Data.self) {
                                if let image = UIImage(data: data) {
                                    do {
                                        try await model.uploadPostMedia(image)
                                        self.selectedPhotos = []
                                    } catch {
                                        self.selectedPhotos = []
                                    }
                                }
                            }
                        }
                    }
                }
            case .uploading:
                Color.white.opacity(0.01)
                ProgressView()
                    .tint(.white)
                    .opacity(0.5)
            case .uploaded:
                if let mediaURL = mediaURL {
                    ZStack {
                        Color.white.opacity(0.01)
                        ProgressView()
                            .tint(.white)
                            .opacity(0.5)

                        AsyncCachedImage(url: mediaURL,
                                         showsLoadingIndicator: false)
                        .frame(width: frameSize, height: frameSize)
                        .mask {
                            RoundedRectangle(cornerRadius: 8)
                        }

                        HStack {
                            VStack {
                                Button {
                                    model.deleteMedia(with: mediaURL)
                                    self.mediaURL = nil
                                    state = .noMedia
                                } label: {
                                    Image(systemName: .xmarkCircleFill)
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.white)
                                        .background {
                                            Circle()
                                                .fill(Color.black)
                                                .padding(4)
                                        }
                                }
                                .padding(3)
                                .buttonStyle(ScalingPressButtonStyle())
                                Spacer()
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .modifier(EditingAnimationBorder())
        .id(state.rawValue)
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        .offset(x: offset.width, y: offset.height)
        .onChange(of: model.post.mediaUrls) { newValue in
            if let url = newValue[safe: idx] {
                self.mediaURL = url
                self.state = .uploaded
            } else {
                self.mediaURL = nil
                self.state = .noMedia
            }
        }
        .onChange(of: model.currentMediaUploadIndices) { newValue in
            if newValue.contains(idx) {
                self.state = .uploading
            }
        }
    }
}

fileprivate struct MediaUpload: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        let spacing: CGFloat = 16.0
        let size: CGFloat = (UIScreen.main.bounds.width - 23 - (spacing * 3)) / 4
        HStack {
            ForEach(0...3, id: \.self) { idx in
                let mediaUrl = model.post.mediaUrls[safe: idx]
                let state: MediaUploadCell.MediaUploadState = (mediaUrl == nil) ? .noMedia : .uploaded
                MediaUploadCell(model: model,
                                idx: idx,
                                frameSize: size,
                                mediaURL: mediaUrl,
                                state: state)
                .frame(width: size, height: size)
                .id(model.post.mediaUrls[safe: idx]?.absoluteString ?? "0")
            }
        }
    }
}

fileprivate struct LiveMediaImage: View {
    var url: URL
    var roundedCorners: [RectangleCorner] = []
    @State var loadedImage: UIImage?
    @Binding var showingFullscreenMedia: Bool
    @Binding var fullscreenMediaImage: UIImage?

    var body: some View {
        Button {
            guard let loadedImage = loadedImage else {
                return
            }

            fullscreenMediaImage = loadedImage
            showingFullscreenMedia = true
        } label: {
            Color.white.opacity(0.01)
                .overlay {
                    AsyncCachedImage(url: url, loadedImage: $loadedImage)
                        .clipped()
                        .allowsHitTesting(false)
                }
                .cornerRadius(roundedCorners, 18)
        }
        .buttonStyle(ScalingPressButtonStyle())
    }
}

fileprivate struct LiveMedia: View {
    @ObservedObject var model: RecordingViewModel
    @Binding var showingFullscreenMedia: Bool
    @Binding var fullscreenMediaImage: UIImage?
    let height: CGFloat = 240.0

    var body: some View {
        ZStack {
            switch model.post.mediaUrls.count {
            case 1:
                LiveMediaImage(url: model.post.mediaUrls[0],
                               roundedCorners: [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing],
                               showingFullscreenMedia: $showingFullscreenMedia,
                               fullscreenMediaImage: $fullscreenMediaImage)
            case 2:
                HStack(spacing: 0) {
                    LiveMediaImage(url: model.post.mediaUrls[0],
                                   roundedCorners: [.topLeading, .bottomLeading],
                                   showingFullscreenMedia: $showingFullscreenMedia,
                                   fullscreenMediaImage: $fullscreenMediaImage)
                    LiveMediaImage(url: model.post.mediaUrls[1],
                                   roundedCorners: [.topTrailing, .bottomTrailing],
                                   showingFullscreenMedia: $showingFullscreenMedia,
                                   fullscreenMediaImage: $fullscreenMediaImage)
                }
            case 3:
                HStack(spacing: 0) {
                    LiveMediaImage(url: model.post.mediaUrls[0],
                                   roundedCorners: [.topLeading, .bottomLeading],
                                   showingFullscreenMedia: $showingFullscreenMedia,
                                   fullscreenMediaImage: $fullscreenMediaImage)
                        .frame(width: UIScreen.main.bounds.width / 2, height: height)
                    VStack(spacing: 0) {
                        LiveMediaImage(url: model.post.mediaUrls[1],
                                       roundedCorners: [.topTrailing],
                                       showingFullscreenMedia: $showingFullscreenMedia,
                                       fullscreenMediaImage: $fullscreenMediaImage)
                            .frame(height: height / 2)
                        LiveMediaImage(url: model.post.mediaUrls[2],
                                       roundedCorners: [.bottomTrailing],
                                       showingFullscreenMedia: $showingFullscreenMedia,
                                       fullscreenMediaImage: $fullscreenMediaImage)
                            .frame(height: height / 2)
                    }
                }
            case 4:
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        LiveMediaImage(url: model.post.mediaUrls[0],
                                       roundedCorners: [.topLeading],
                                       showingFullscreenMedia: $showingFullscreenMedia,
                                       fullscreenMediaImage: $fullscreenMediaImage)
                            .frame(height: height / 2)
                        LiveMediaImage(url: model.post.mediaUrls[1],
                                       roundedCorners: [.bottomLeading],
                                       showingFullscreenMedia: $showingFullscreenMedia,
                                       fullscreenMediaImage: $fullscreenMediaImage)
                            .frame(height: height / 2)
                    }
                    VStack(spacing: 0) {
                        LiveMediaImage(url: model.post.mediaUrls[2],
                                       roundedCorners: [.topTrailing],
                                       showingFullscreenMedia: $showingFullscreenMedia,
                                       fullscreenMediaImage: $fullscreenMediaImage)
                            .frame(height: height / 2)
                        LiveMediaImage(url: model.post.mediaUrls[3],
                                       roundedCorners: [.bottomTrailing],
                                       showingFullscreenMedia: $showingFullscreenMedia,
                                       fullscreenMediaImage: $fullscreenMediaImage)
                            .frame(height: height / 2)
                    }
                }
            default:
                EmptyView()
            }
        }
        .frame(height: model.post.mediaUrls.isEmpty ? 0.0 : height)
        .padding(.bottom, model.post.mediaUrls.isEmpty ? 0.0 : 30.0)
        .padding([.leading, .trailing], 15)
    }
}

fileprivate struct FullscreenMediaDetail: View {
    @Binding var isPresented: Bool
    var image: UIImage

    @State private var presentAnimate: Bool = false
    @State private var blurAnimateOut: Bool = false
    @State private var dragOffset: CGSize = .zero

    private func dismiss() {
        presentAnimate = false
        blurAnimateOut = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isPresented = false
        }
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(presentAnimate ? 0.9 : 0.0)
                .animation(.easeInOut(duration: 0.4), value: presentAnimate)
            .ignoresSafeArea()

            ZoomableScrollView {
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(16, style: .continuous)
                }
                .maxWidth(UIScreen.main.bounds.width - 40)
                .maxHeight(UIScreen.main.bounds.height - 100)
                .scaleEffect(x: presentAnimate ? 1.0 : 0.5,
                             y: presentAnimate ? 1.0 : 0.5)
                .opacity(presentAnimate ? 1.0 : 0.0)
                .blur(radius: presentAnimate ? 0.0 : 10.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.65), value: presentAnimate)
            }
            .ignoresSafeArea()
            .offset(x: dragOffset.width * 0.5,
                    y: dragOffset.height * 0.5)
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { _ in
                        if dragOffset.height > 100.0 {
                            dismiss()
                        } else {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                                dragOffset = .zero
                            }
                        }
                    }
            )

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: .xmarkCircleFill)
                            .font(.system(size: 26, weight: .medium))
                            .foregroundColor(.white)
                            .padding()
                    }
                    .offset(y: -12.0)
                    .opacity(presentAnimate ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.25).delay(0.1), value: presentAnimate)

                    Spacer()
                }
                Spacer()
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                presentAnimate = true
            }
        }
    }
}

fileprivate struct PostCoverPhotoWith2DRoute: View {
    @ObservedObject var model: RecordingViewModel
    @Binding var drawerScrollOffset: CGFloat
    var drawerClosedHeight: CGFloat

    private var photoScale: CGFloat {
        guard let vc = UIApplication.shared.topViewController,
              !vc.isBeingPresented, !vc.isBeingDismissed else {
            return 1.0
        }

        let offset = drawerScrollOffset + UIScreen.main.safeAreaInsets.top
        let defaultHeight = UIScreen.main.bounds.height - drawerClosedHeight + 40
        return ((defaultHeight + offset) / defaultHeight).clamped(to: 1...10)
    }

    var body: some View {
        ZStack {
            VStack {
                if let url = model.post.mediaUrls.first {
                    AsyncCachedImage(url: url)
                        .frame(width: UIScreen.main.bounds.width)
                        .clipped()
                        .overlay {
                            VStack {
                                Image("layout_top_gradient")
                                    .renderingMode(.template)
                                    .resizable(resizingMode: .stretch)
                                    .frame(width: UIScreen.main.bounds.width,
                                           height: UIScreen.main.bounds.height / 4.0)
                                    .foregroundColor(.black)
                                    .opacity(0.5)
                                Spacer()
                            }
                        }
                        .parallaxEffect()
                        .brightness(-0.1)
                        .scaleEffect(x: photoScale, y: photoScale, anchor: .top)
                        .animation(.easeInOut(duration: 0.05), value: photoScale)
                        .id(model.post.mediaUrls.first?.absoluteString ?? "0")
                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                } else {
                    DotBackground()
                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                }
            }

            VStack {
                if let routeImage = model.routeImage {
                    Image(uiImage: routeImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: UIScreen.main.bounds.width - 70)
                        .padding(.top, 60 + UIScreen.main.safeAreaInsets.top)
                    Spacer()
                        .frame(height: drawerClosedHeight + 70.0)
                    if model.post.isDraft {
                        Spacer()
                            .frame(height: 25.0)
                    }
                }
            }
            .id(model.routeImage == nil ? 0 : 1)
            .modifier(BlurOpacityTransition(speed: 1.5))
        }
        .onAppear {
            model.loadRouteImage()
        }
    }
}

struct RouteClipNotice: View {
    @ObservedObject var model: RecordingViewModel

    var privacyNotice: some View {
        HStack(spacing: 3) {
            Image(systemName: .lockFill)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 11)
                .foregroundColor(.white)
            Text("Privacy Notice")
                .font(.system(size: 13, weight: .semibold))
        }
    }

    var body: some View {
        ZStack {
            if model.recorder.state == .saved && model.recorder.hasCoordinates {
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        if model.isViewingLivePost {
                            privacyNotice
                            Text("To safeguard privacy, the route is edited.")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .opacity(0.6)
                        } else if NSUbiquitousKeyValueStore.default.defaultRecordingSettings.clipRoute && ADUser.current.hasRegistered {
                            privacyNotice
                            Text("For privacy, your route will be clipped by \(NSUbiquitousKeyValueStore.default.defaultRecordingSettings.routeClipPercentageString) on both sides when you post this activity. You can adjust this in Settings.")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.leading)
                                .opacity(0.6)
                        }
                    }
                    Spacer()
                }
            } else {
                EmptyView()
                    .frame(height: 0.0)
            }
        }
        .frame(maxWidth: .infinity)
        .padding([.leading, .trailing], 25)
    }
}

struct DeleteButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: .trashFill)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(Color(uiColor: RecordingGoalType.time.color))
                Text("Delete Activity")
                    .foregroundColor(Color(uiColor: RecordingGoalType.time.color))
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: RecordingGoalType.time.color))
                    .opacity(0.2)
            }
        }
    }
}

struct RecordingView: View {
    @ObservedObject var model: RecordingViewModel
    @Environment(\.presentationMode) var presentationMode

    private let impactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let feedbackGenerator = UINotificationFeedbackGenerator()

    @State private var drawerScrollOffset: CGFloat = 0.0
    @State private var drawerContentSize: CGSize = .zero
    @State private var isStopButtonPressed: Bool = false
    @State private var goalReachedToastVisible: Bool = false
    @State private var goalHalfwayToastVisible: Bool = false
    @State private var gpsAcquiredToastVisible: Bool = false
    @State private var photoTakenToastVisible: Bool = false
    @State private var showingSafetyMessageView: Bool = false
    @State private var editDistanceViewVisible: Bool = false
    @State private var skipCountdown: Bool = false
    @State private var showingDeleteAlert: Bool = false
    @State private var showingFullscreenMedia: Bool = false
    @State private var fullscreenMediaImage: UIImage?
    @State private var showingReactions: Bool = false
    @State private var reactionsTouchingDown: Bool = false

    @FocusState fileprivate var focusedField: PostFocusedField?

    private var drawerClosedHeight: CGFloat {
        let goalHeight: CGFloat = model.recorder.goal.type == .open ? 0.0 : 35.0
        let finishedHeight: CGFloat = model.recorder.state == .saved ? 50.0 : 0.0
        if model.recorder.state == .ready || model.recorder.state == .locationPermissionNeeded {
            return 460.0
        } else if model.recorder.activityType.showsRoute {
            return 285.0 + goalHeight + finishedHeight + 40.0
        } else {
            return 210.0 + goalHeight + finishedHeight + 40.0
        }
    }

    private func stopAction() {
        if model.recorder.didSendSafetyMessageAtStart {
            // prompt to send ending safety message
            showingSafetyMessageView = true
        }
        
        impactGenerator.impactOccurred()
        
        if model.recorder.duration <= 5.0 {
            model.recorder.stopAndDiscardActivity()
        } else {
            if model.recorder.activityType.shouldPromptToAddDistance {
                editDistanceViewVisible = true
            } else {
                Task(priority: .background) {
                    await model.recorder.finish()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if let windowScene = UIApplication.shared.windows.first?.windowScene {
                            SKStoreReviewController.requestReview(in: windowScene)
                            Analytics.logEvent("Review Requested", model.screenName, .otherEvent)
                        }
                    }
                }
            }
        }
    }

    private func playPauseAction() {
        impactGenerator.impactOccurred()
        Task(priority: .userInitiated) {
            switch model.recorder.state {
            case .ready:
                model.hasTappedStart = true
            case .recording:
                try await model.recorder.pause()
            case .paused:
                try await model.recorder.resume()
            default: break
            }
        }
    }

    private func shareAction(with graphType: GraphType?) {
        presentationMode.dismiss()
        let recordingShare = RecordingShare(activityId: model.recorder.finishedWorkout?.id ?? "",
                                            graphType: graphType)
        NotificationCenter.default.post(name: Notification.recordingShareActivity.name,
                                        object: recordingShare)
    }

    private func showDeleteAlertAction() {
        showingDeleteAlert = true
    }

    private func backAction() {
        func back() {
            model.post.isEditing = false
            model.cacheDraftedPost()

            if UIApplication.shared.topViewController is UITabBarController {
                model.reset()
            } else {
                presentationMode.dismiss()
            }
        }

        if model.post.isEditing {
            let alert = UIAlertController(title: "Discard edits",
                                          message: "Going back will discard your edits. Are you sure?",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Stay here", style: .default))
            alert.addAction(UIAlertAction(title: "Go back and discard", style: .destructive, handler: { _ in
                back()
            }))
            UIApplication.shared.topViewController?.present(alert, animated: true)
        } else {
            back()
        }
    }

    var body: some View {
        ZStack {
            if model.recorder.hasCoordinates || (model.recorder.activityType.showsRoute && model.recorder.state != .saved) {
                if !model.networkConnected  {
                    NoInternetView(model: model,
                                   drawerClosedHeight: drawerClosedHeight)
                } else {
                    ZStack {
                        switch model.finishedRouteType {
                        case .photoWith2DRoute:
                            PostCoverPhotoWith2DRoute(model: model,
                                                      drawerScrollOffset: $drawerScrollOffset,
                                                      drawerClosedHeight: drawerClosedHeight)
                            .ignoresSafeArea()
                        case .map:
                            MapView(model: model,
                                    drawerClosedHeight: drawerClosedHeight)
                            .ignoresSafeArea()
                            .saturation(0.0)
                            .contrast(1.45)
                            .brightness(0.08)
                            .mask {
                                LinearGradient(colors: [.black.opacity(0.5), .black],
                                               startPoint: .top,
                                               endPoint: UnitPoint(x: 0.5, y: 0.2))
                                .ignoresSafeArea()
                            }
                            .opacity(model.hasRenderedMap ? 1.0 : 0.0)
                            .background(Color(white: 0.08))
                            .animation(.easeInOut(duration: 0.2), value: model.hasRenderedMap)
                        case .threeD:
                            if model.recorder.state == .saved && model.recorder.hasCoordinates {
                                Route3DWithBackground(coordinates: model.recorder.locations,
                                                      drawerClosedHeight: drawerClosedHeight)
                            }
                        }
                    }
                    .id(model.finishedRouteType.rawValue)
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    .blur(radius: (6.0 * ((drawerScrollOffset + 100.0) / -500.0)).clamped(to: 0...6.0))
                    
                    if !model.hasRenderedMap && model.finishedRouteType == .map {
                        VStack {
                            ProgressView()
                            Spacer()
                                .frame(height: drawerClosedHeight)
                        }
                    }
                    
                    if model.recorder.state != .saved {
                        UserLocationView(model: model)
                            .opacity(model.hasRenderedMap ? 1.0 : 0.0)
                            .animation(.easeInOut(duration: 0.2), value: model.hasRenderedMap)
                    }
                }
            } else {
                if !model.post.mediaUrls.isEmpty {
                    PostCoverPhotoWith2DRoute(model: model,
                                              drawerScrollOffset: $drawerScrollOffset,
                                              drawerClosedHeight: drawerClosedHeight)
                    .ignoresSafeArea()
                } else {
                    ActivityTypeGlyphAnimation(type: model.recorder.activityType,
                                               drawerClosedHeight: drawerClosedHeight)
                    .ignoresSafeArea()
                }
            }
            
            Group {
                if !model.isViewingLivePost &&
                   model.hasScrolledToFirstLocation &&
                   !model.recorder.wasRestoredFromSavedState &&
                   model.hasTappedStart &&
                   model.recorder.state == .ready {
                    CountdownView(skip: $skipCountdown,
                                  drawerClosedHeight: drawerClosedHeight) {
                        try? model.recorder.start()
                    }
                }
                RecordingToastView(text: "Halfway Point",
                                   icon: Image("glyph_halfway_point"),
                                   iconIncludesCircle: true,
                                   drawerClosedHeight: drawerClosedHeight,
                                   isVisible: $goalHalfwayToastVisible)
                RecordingToastView(text: "Goal Reached",
                                   icon: Image("glyph_check_circle"),
                                   iconIncludesCircle: true,
                                   drawerClosedHeight: drawerClosedHeight,
                                   isVisible: $goalReachedToastVisible)
                RecordingToastView(text: "GPS Connected",
                                   icon: Image(systemName: .antennaRadiowavesLeftAndRightCircleFill),
                                   iconIncludesCircle: true,
                                   drawerClosedHeight: drawerClosedHeight,
                                   isVisible: $gpsAcquiredToastVisible)
                RecordingToastView(text: "Photo Saved",
                                   icon: Image("glyph_check_circle"),
                                   iconIncludesCircle: true,
                                   drawerClosedHeight: drawerClosedHeight,
                                   isVisible: $photoTakenToastVisible)
                TapAndHoldToStopView(isPressed: $isStopButtonPressed,
                                     drawerClosedHeight: drawerClosedHeight)
            }
            
            DrawerView(model: model,
                       closedHeight: drawerClosedHeight,
                       scrollOffset: $drawerScrollOffset,
                       contentSize: $drawerContentSize,
                       focusedField: _focusedField,
                       routeType: $model.finishedRouteType,
                       backAction: backAction) {
                VStack(spacing: 20.0) {
                    VStack(spacing: 20.0) {
                        if model.recorder.state == .saved {
                            ActivityTypeTimeHeader(model: model)
                            if ADUser.current.hasRegistered {
                                PostHeader(model: model, focusedField: _focusedField)
                            }
                        }

                        if model.isViewingLivePost && !model.post.mediaUrls.isEmpty {
                            LiveMedia(model: model,
                                      showingFullscreenMedia: $showingFullscreenMedia,
                                      fullscreenMediaImage: $fullscreenMediaImage)
                        }

                        if model.isViewingLivePost {
                            PostCommentReactionHeader(model: model)
                                .padding(.top , -32.0)
                                .padding(.bottom, -16.0)
                        }
                    }
                    
                    if model.post.isDraft && model.recorder.state == .saved && ADUser.current.hasRegistered {
                        MediaUpload(model: model)
                            .padding([.leading, .trailing], 20.0)
                    }
                    
                    if model.isViewingLivePost {
                        LiveStats(model: model)
                            .allowsHitTesting(focusedField == nil)
                    } else if model.recorder.state == .locationPermissionNeeded {
                        AndiLocation(model: model)
                            .modifier(BlurOpacityTransition(speed: 1.5))
                    } else if model.recorder.state == .ready {
                        AndiIntro(model: model, drawerClosedHeight: drawerClosedHeight)
                            .modifier(BlurOpacityTransition(speed: 1.5))
                    } else {
                        Stats(model: model)
                            .allowsHitTesting(focusedField == nil)
                            .modifier(BlurOpacityTransition(speed: 1.5))
                    }
                    
                    if model.recorder.goal.type != .open &&
                       model.recorder.state != .ready &&
                       model.recorder.state != .locationPermissionNeeded {
                        GoalProgressBar(model: model)
                            .modifier(BlurOpacityTransition(speed: 1.5))
                    }
                    
                    if let dataSource = model.recorder.graphDataSource,
                       dataSource.hasData {
                        GraphsAndCollectibles(model: model,
                                              dataSource: dataSource,
                                              shareAction: shareAction(with:))
                            .transition(.opacity)
                            .padding(.top, 20.0)
                    }
                    
                    RouteClipNotice(model: model)
                    
                    if model.isViewingLivePost {
                        PostComments(model: model, focusedField: _focusedField)
                            .onChange(of: drawerScrollOffset) { newValue in
                                if focusedField == .commentBox && drawerScrollOffset > -1 * (drawerContentSize.height - 900.0) {
                                    focusedField = nil
                                }
                            }
                    }
                    
                    if model.recorder.graphDataSource != nil &&
                       !model.isViewingLivePost &&
                       !model.post.isEditing &&
                       (model.recorder.finishedWorkout?.workoutSource ?? .appleHealth) == .anyDistance {
                        DeleteButton(action: showDeleteAlertAction)
                            .padding(.top, 30.0)
                    }

                    if !model.isViewingLivePost {
                        Spacer()
                            .frame(height: 100.0 + UIScreen.main.safeAreaInsets.bottom)
                    }
                }
                .background {
                    Color.black
                        .opacity(0.01)
                        .onTapGesture {
                            focusedField = nil
                        }
                }
            }
            
            HowWeCalculatePopup(model: model.howWeCalculatePopupModel,
                                drawerClosedHeight: drawerClosedHeight)
            
            if !model.isViewingLivePost &&
               model.recorder.state != .ready &&
               model.recorder.state != .locationPermissionNeeded {
                ControlBar(model: model,
                           showingPhotoTakenToast: $photoTakenToastVisible,
                           stopAction: stopAction,
                           playPauseAction: playPauseAction,
                           shareAction: { shareAction(with: nil) },
                           postAction: model.postToActiveClub,
                           isStopButtonPressed: $isStopButtonPressed)
                .modifier(BlurOpacityTransition(speed: 1.5))
            }
            
            ConfettiSwiftUIView(confettiColors: DistanceMedal.mi_1000.confettiColors,
                                isStarted: $goalReachedToastVisible)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if let image = fullscreenMediaImage,
               showingFullscreenMedia {
                FullscreenMediaDetail(isPresented: $showingFullscreenMedia, image: image)
            }
        }
        .onChange(of: model.recorder.goalMet) { newValue in
            if newValue == true {
                feedbackGenerator.notificationOccurred(.success)
                goalReachedToastVisible = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    goalReachedToastVisible = false
                }
            }
        }
        .onChange(of: model.recorder.goalHalfwayPointReached) { newValue in
            if newValue == true {
                feedbackGenerator.notificationOccurred(.success)
                goalHalfwayToastVisible = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    goalHalfwayToastVisible = false
                }
            }
        }
        .onChange(of: model.recorder.state) { [oldValue = model.recorder.state] newValue in
            guard !showingSafetyMessageView else { return }
            
            if newValue == .discarded || newValue == .couldNotSave {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    model.reset()
                }
            } else if newValue == .saved {
                impactGenerator.impactOccurred()
            } else if oldValue == .waitingForGps && newValue == .recording {
                feedbackGenerator.notificationOccurred(.success)
                gpsAcquiredToastVisible = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    gpsAcquiredToastVisible = false
                }
            }
        }
        .onTapGesture {
            if !skipCountdown {
                skipCountdown = true
            }
        }
        .sheet(isPresented: $editDistanceViewVisible) {
            UpdateDistanceView(distance: model.recorder.distanceInUnit,
                               unit: model.recorder.unit.fullName) { distance in
                let distance = UnitConverter.value(distance, inUnitToMeters: model.recorder.unit)
                Task {
                    await model.recorder.finish(manualDistance: distance)
                }
            }
                               .background(BackgroundClearView())
        }
        .sheet(isPresented: $showingSafetyMessageView) {
            SafetyMessageView(type: .endingActivity,
                              activityType: model.recorder.activityType,
                              goal: model.recorder.goal) { result in
                if result == .sent {
                    showingSafetyMessageView = false
                }
                
                if model.recorder.state == .discarded ||
                    model.recorder.state == .couldNotSave {
                    presentationMode.dismiss()
                }
            }
            .background(BackgroundClearView())
        }
        .alert("Delete Activity", isPresented: $showingDeleteAlert) {
            Button(role: .destructive) {
                model.deleteActivity()
            } label: {
                Text("Delete Activity")
            }
        } message: {
            Text("Deleting this activity will remove its data from Any Distance and Apple Health.")
        }
        .alert("Error Deleting Activity",
               isPresented: $model.showingDeleteErrorAlert,
               presenting: model.deleteError) { error in
            Button("Ok") {
                showingDeleteAlert = false
            }
        } message: { error in
            Text(error.localizedDescription + " Contact us at support@anydistance.club")
        }
        .overlay {
            ZStack {
                DarkBlurView()
                    .ignoresSafeArea()
                ProgressView()
            }
            .opacity(model.deletingActivity ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: model.deletingActivity)
        }
        .onDisappear {
            model.recorder.stopUpdatingLocationIfNecessary()
        }
        .onAppear {
            model.recorder.startUpdatingLocationIfNecessary()

            if !iAPManager.shared.hasSuperDistanceFeatures &&
               UIApplication.shared.topViewController is ADTabBarController {
                let vc = UIHostingController(rootView: SuperDistanceView())
                vc.modalPresentationStyle = .overFullScreen
                UIApplication.shared.topViewController?.present(vc, animated: true)
                NSUbiquitousKeyValueStore.default.hasShownInitialPurchaseScreen = true
            }
        }
    }
}

struct RecordingView_Previews: PreviewProvider {
    static var previews: some View {
        let recorder = ActivityRecorder(activityType: .bikeRide,
                                        goal: RecordingGoal(type: .open, unit: .miles, target: 600.0),
                                        unit: .miles,
                                        settings: RecordingSettings())
        TabView {
            RecordingView(model: RecordingViewModel(recorder: recorder))
                .tabItem {
                    Label("Track", systemImage: .plusCircleFill)
                }
        }
        .previewDevice("iPhone 13 Pro")
    }
}

extension MKMapRect: Equatable {
    public static func == (lhs: MKMapRect, rhs: MKMapRect) -> Bool {
        return lhs.origin.x == rhs.origin.x &&
               lhs.origin.y == rhs.origin.y &&
               lhs.size.width == rhs.size.width &&
               lhs.size.height == rhs.size.height
    }
}