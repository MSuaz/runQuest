// Licensed under the Any Distance Source-Available License
//
//  ACtivityProgressView.swift
//  ADAC
//
//  Created by Daniel Kuntz on 6/29/23.
//

import SwiftUI
import MapKit
import SwiftUIX
import HealthKit
import Combine

struct GradientEffect: ViewModifier {
    @StateObject private var manager = MotionManager()

    func body(content: Content) -> some View {
        ZStack {
            let colors: [Color] = stride(from: 0, to: 1, by: 0.1).map { n in
                return Color(hue: n, saturation: 0.3, brightness: 1)
            }

            content
                .opacity(0)
                .overlay(
                    LinearGradient(colors: colors,
                                   startPoint: .init(x: manager.roll - 0.25, y: 0.5),
                                   endPoint: .init(x: manager.roll + 1.25, y: 0.5))
                    .mask(content)
                    .frame(height: 75)
                )
        }
    }
}

fileprivate struct MapView: UIViewRepresentable  {
    @ObservedObject var model: ActivityProgressGraphModel
    @Binding var selectedClusterIdx: Int

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.mapType = .mutedStandard
        mapView.preferredConfiguration.elevationStyle = .flat
        mapView.isPitchEnabled = false
        mapView.showsUserLocation = false
        mapView.showsBuildings = false
        mapView.overrideUserInterfaceStyle = .dark
        mapView.pointOfInterestFilter = MKPointOfInterestFilter.excludingAll
        mapView.setUserTrackingMode(.none, animated: false)
        mapView.delegate = context.coordinator
        mapView.alpha = 0.0
        context.coordinator.mkView = mapView

        model.$coordinateClusters
            .receive(on: DispatchQueue.main)
            .sink { _ in
                selectedClusterIdx = 0
            }.store(in: &context.coordinator.subscribers)

        model.$viewVisible
            .receive(on: DispatchQueue.main)
            .sink { visible in
                if visible {
                    addPolylines(mapView)
                } else {
                    mapView.removeOverlays(mapView.overlays)
                }
            }.store(in: &context.coordinator.subscribers)

        return mapView
    }

    private func addPolylines(_ mapView: MKMapView) {
        if model.coordinateClusters.isEmpty {
            return
        }

        Task(priority: .userInitiated) {
            mapView.removeOverlays(mapView.overlays)
            model.coordinateClusters[selectedClusterIdx].coordinates.forEach { coordinates in
                coordinates.withUnsafeBufferPointer { pointer in
                    if let base = pointer.baseAddress {
                        let newPolyline = MKPolyline(coordinates: base, count: coordinates.count)
                        mapView.addOverlay(newPolyline)
                    }
                }
            }
        }
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        if model.coordinateClusters.count > selectedClusterIdx {
            addPolylines(uiView)
            let rect = model.coordinateClusters[selectedClusterIdx].rect
            if rect != context.coordinator.displayedRect {
                let edgePadding = UIEdgeInsets(top: 180.0,
                                               left: 25.0,
                                               bottom: UIScreen.main.bounds.height * 0.4,
                                               right: 25.0)
                uiView.setVisibleMapRect(rect,
                                         edgePadding: edgePadding,
                                         animated: context.coordinator.hasSetInitialRegion)
                context.coordinator.displayedRect = rect
                context.coordinator.resetAnimationTimer()
                context.coordinator.hasSetInitialRegion = true
            }

            context.coordinator.shouldAnimateIn = true
        } else if model.coordinateClusters.isEmpty {
            uiView.removeOverlays(uiView.overlays)
            if context.coordinator.hasSetInitialRegion && model.hasPerformedInitialLoad {
                context.coordinator.shouldAnimateIn = true
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var parent: MapView
        var mkView: MKMapView?
        var subscribers: Set<AnyCancellable> = []
        var hasSetInitialRegion: Bool = false
        var hasInitialFinishedRender: Bool = false
        var displayedRect: MKMapRect?
        var shouldAnimateIn: Bool = false
        var willRender: Bool = false
        private lazy var displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFire))
        private var polylineProgress: CGFloat = 0
        private let lineColor = UIColor.white.withAlphaComponent(0.6)

        init(parent: MapView) {
            self.parent = parent
            super.init()

            self.displayLink.add(to: .main, forMode: .common)
            self.displayLink.add(to: .main, forMode: .tracking)
            self.displayLink.isPaused = false
        }

        func resetAnimationTimer() {
            polylineProgress = -0.05
            displayLinkFire()
            displayLink.isPaused = true
        }

        @objc func displayLinkFire() {
            if polylineProgress <= 1 {
                for overlay in mkView!.overlays {
                    if !overlay.boundingMapRect.intersects(mkView?.visibleMapRect ?? MKMapRect()) {
                        continue
                    }

                    if let polylineRenderer = mkView!.renderer(for: overlay) as? MKPolylineRenderer {
                        polylineRenderer.strokeEnd = RouteScene.easeOutQuad(x: polylineProgress).clamped(to: 0...1)
                        polylineRenderer.strokeColor = polylineProgress <= 0.01 ? .clear : lineColor
                        polylineRenderer.blendMode = .destinationAtop
                        polylineRenderer.setNeedsDisplay()
                    }
                }
                
                polylineProgress += 0.01
            }
        }

        func lineWidth(for mapView: MKMapView) -> CGFloat {
            let visibleWidth = mapView.visibleMapRect.width
            return CGFloat(-0.00000975 * visibleWidth + 2.7678715).clamped(to: 1.5...2.5)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let stroke = lineWidth(for: mapView)
            if let routePolyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: routePolyline)
                renderer.strokeColor = displayLink.isPaused ? .clear : lineColor
                renderer.lineWidth = stroke
                renderer.strokeEnd = displayLink.isPaused ? 0 : 1
                renderer.blendMode = .destinationAtop
                renderer.lineJoin = .round
                renderer.lineCap = .round
                return renderer
            }

            return MKOverlayRenderer()
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            let stroke = lineWidth(for: mapView)
            for overlay in mkView!.overlays {
                if !overlay.boundingMapRect.intersects(mkView?.visibleMapRect ?? MKMapRect()) {
                    continue
                }

                if let polylineRenderer = mkView!.renderer(for: overlay) as? MKPolylineRenderer {
                    polylineRenderer.lineWidth = stroke
                }
            }
        }

        func mapViewWillStartRenderingMap(_ mapView: MKMapView) {
            willRender = true
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if willRender {
                return
            }

            displayLink.isPaused = false
        }

        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            if fullyRendered {
                displayLink.isPaused = false
                willRender = false

                if shouldAnimateIn {
                    UIView.animate(withDuration: 0.3) {
                        mapView.alpha = 1.0
                    }
                    shouldAnimateIn = false
                }
            }
        }
    }
}

fileprivate struct ProgressHeader: View {
    var scrollViewOffset: CGFloat

    var body: some View {
        HStack {
            VStack {
                Spacer()
                    .frame(height: 45.0)

                let p = (scrollViewOffset / -80.0)
                Text("Stats")
                    .font(.presicav(size: 31.0))
                    .scaleEffect((0.6 + ((1.0 - p) * 0.4)).clamped(to: 0.6...1.0),
                                 anchor: .leading)
                    .offset(y: scrollViewOffset < 0 ? (-1 * scrollViewOffset) : (-0.7 * scrollViewOffset))
                    .offset(y: (-22.0 * p).clamped(to: -22.0...0.0))
                    .opacity((0.6 + ((1.0 - p) * 0.4)).clamped(to: 0.6...1.0))
            }
            Spacer()
        }
        .padding(.top, -22.5)
    }
}

struct TimePeriodPicker: View {
    @ObservedObject var model: ActivityProgressGraphModel
    var fontSize: CGFloat = 15.0

    @State private var selectedSegmentIdx: Int = NSUbiquitousKeyValueStore.default.selectedTimePeriodSegment ?? 1
    @State private var selectedTimePeriodIndices: [Int] = NSUbiquitousKeyValueStore.default.selectedTimePeriodIndices
    @State private var arrowVisibility: [Bool] = [false, true, false]

    @Namespace private var segmentAnimation
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        HStack(spacing: -10) {
            ForEach(model.timePeriods.enumerated().map { $0 }, id: \.offset) { (segmentIdx, timePeriods) in
                ZStack {
                    HStack {
                        Text(timePeriods[selectedTimePeriodIndices[segmentIdx]].label)
                            .font(.system(size: fontSize, weight: .medium))
                            .foregroundColor(segmentIdx == selectedSegmentIdx ? .black : .white)
                            .padding([.top, .bottom], fontSize * 0.86)
                            .background {
                                Color.black.opacity(0.01)
                            }
                            .animation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.5),
                                       value: selectedSegmentIdx)
                            .id(timePeriods[selectedTimePeriodIndices[segmentIdx]].label)
                            .modifier(BlurOpacityTransition(speed: 1.8))

                        Image(systemName: .chevronDown)
                            .font(.system(size: fontSize * 0.75, weight: .semibold))
                            .foregroundStyle(Color.black)
                            .opacity(arrowVisibility[segmentIdx] ? 1.0 : 0.0)
                            .blur(radius: arrowVisibility[segmentIdx] ? 0.0 : 5.0)
                            .padding(.leading, arrowVisibility[segmentIdx] ? 0.0 : -15.0)
                            .opacity(model.loading && arrowVisibility[segmentIdx] ? 0.0 : 1.0)
                            .overlay {
                                ProgressView()
                                    .tint(Color.black)
                                    .scaleEffect(x: 0.6, y: 0.6)
                                    .opacity(model.loading && arrowVisibility[segmentIdx] ? 1.0 : 0.0)
                            }
                            .animation(.easeInOut(duration: 0.2), value: model.loading)
                    }
                    .padding([.leading, .trailing], fontSize * 1.46)
                    .padding([.top, .bottom], 20.0)
                    .fixedSize(horizontal: true, vertical: false)
                    .background {
                        ZStack {
                            if segmentIdx == selectedSegmentIdx {
                                RoundedRectangle(cornerRadius: 30.0, style: .continuous)
                                    .foregroundColor(.white)
                                    .matchedGeometryEffect(id: "rect", in: segmentAnimation)
                                    .padding([.top, .bottom], 20.0)
                            } else {
                                EmptyView()
                            }
                        }
                        .padding(0.24 * fontSize)
                    }

                    if segmentIdx != selectedSegmentIdx {
                        Button {
                            selectedSegmentIdx = segmentIdx
                            feedbackGenerator.impactOccurred()
                        } label: {
                            Color.black.opacity(0.01)
                        }
                        .padding([.leading, .trailing], 5.0)
                    } else {
                        Menu {
                            ForEach(model.timePeriods[segmentIdx].enumerated().map { $0 }, 
                                    id: \.offset) { (idx, timePeriod) in
                                Button {
                                    feedbackGenerator.impactOccurred()
                                    selectedTimePeriodIndices[segmentIdx] = idx
                                    model.timePeriod = timePeriod
                                    model.load()
                                } label: {
                                    if idx == selectedTimePeriodIndices[segmentIdx] {
                                        Label("\(timePeriod.label!)", systemImage: .checkmark)
                                    } else {
                                        Text("\(timePeriod.label)")
                                    }
                                }
                            }
                        } label: {
                            Color.black.opacity(0.01)
                        }
                        .padding([.leading, .trailing], 5.0)
                    }
                }
            }
        }
        .allowsHitTesting(!model.loading)
        .background {
            DarkBlurView()
                .brightness(0.1)
                .cornerRadius(24.0, style: .continuous)
                .padding([.top, .bottom], 20.0)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.5),
                   value: selectedSegmentIdx)
        .animation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.5),
                   value: selectedTimePeriodIndices)
        .animation(.easeInOut(duration: 0.2),
                   value: arrowVisibility)
        .onChange(of: selectedSegmentIdx) { idx in
            DispatchQueue.main.async {
                model.timePeriod = model.timePeriods[selectedSegmentIdx][selectedTimePeriodIndices[selectedSegmentIdx]]
                model.load()
            }

            arrowVisibility = [idx == 0, idx == 1, idx == 2]
            NSUbiquitousKeyValueStore.default.selectedTimePeriodSegment = idx
        }
        .onChange(of: selectedTimePeriodIndices) { indices in
            NSUbiquitousKeyValueStore.default.selectedTimePeriodIndices = indices
        }
        .onAppear {
            arrowVisibility = [selectedSegmentIdx == 0, selectedSegmentIdx == 1, selectedSegmentIdx == 2]
        }
    }
}

struct SmallActivityTypeSearchButton: View {
    @Binding var activityType: ActivityType
    @State private var showingActivityList: Bool = false

    var body: some View {
        Button {
            showingActivityList = true
        } label: {
            VStack(spacing: 0) {
                Spacer()
                HStack(spacing: 8.0) {
                    Image(activityType.glyphName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 19.0, height: 19.0)
                    Text(activityType.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.white)
                        .lineBreakMode(.byWordWrapping)
                    Spacer()
                    Image(systemName: .magnifyingglass)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13.0, height: 13.0)
                        .fontWeight(.medium)
                }
                .padding([.leading, .trailing], 17.0)
                .foregroundColor(.white)
                Spacer()
            }
            .background {
                DarkBlurView()
                    .brightness(0.1)
                    .cornerRadius(24.0, style: .continuous)
            }
        }
        .id(activityType.displayName)
        .modifier(BlurOpacityTransition(speed: 1.8))
        .fullScreenCover(isPresented: $showingActivityList) {
            RecordingActivityPickerView { activityType in
                self.activityType = activityType
                showingActivityList = false
            }
            .cornerRadius(18, corners: [.topLeft, .topRight])
            .background(BackgroundClearView())
        }
    }
}

fileprivate struct ProgressGraph: View {
    @ObservedObject var model: ActivityProgressGraphModel
    @Binding var showingOverlay: Bool
    @State private var selectedMetricData: ActivityProgressGraphModel.GraphRenderDataMetric?
    @State private var lineAnimationProgress: Float = 0.0
    @State private var dataSwipeIdx: Int = -1

    private let graphLrPadding: CGFloat = 12.0

    var body: some View {
        VStack(spacing: 14.0) {
            if let selectedMetricData = selectedMetricData,
               !selectedMetricData.isEmpty {
                ZStack {
                    ProgressLineGraph(data: selectedMetricData.defaultPrevPeriodData,
                                      dataMaxValue: selectedMetricData.defaultMaxValue,
                                      fullDataCount: selectedMetricData.fullDataCount,
                                      strokeStyle: StrokeStyle(lineWidth: 2.0, lineCap: .round, dash: [0.5, 4.0]),
                                      color: Color(white: 0.4),
                                      showVerticalLine: false,
                                      showDot: false,
                                      animateProgress: false,
                                      dataSwipeIdx: .constant(-1))

                    let color = ActivityProgressGraphModel.color(for: selectedMetricData.defaultPercentDifference,
                                                                 field: selectedMetricData.field)

                    ProgressLineGraph(data: selectedMetricData.defaultData,
                                      dataMaxValue: selectedMetricData.defaultMaxValue,
                                      fullDataCount: selectedMetricData.fullDataCount,
                                      strokeStyle: StrokeStyle(lineWidth: 3.5, lineCap: .round),
                                      color: color,
                                      showVerticalLine: true,
                                      showDot: true,
                                      animateProgress: true,
                                      dataSwipeIdx: $dataSwipeIdx)
                    .id(model.graphRenderData.id)
                    .transition(.opacity.animation(.easeInOut(duration: 0.1)))

                    ProgressLineGraphSwipeOverlay(field: selectedMetricData.field,
                                                  data: selectedMetricData.defaultData,
                                                  prevPeriodData: selectedMetricData.defaultPrevPeriodData,
                                                  dataFormat: selectedMetricData.dataFormat,
                                                  startDate: model.timePeriod.startDate,
                                                  endDate: model.timePeriod.endDate,
                                                  prevPeriodStartDate: model.timePeriod.prevPeriodStartDate,
                                                  prevPeriodEndDate: model.timePeriod.prevPeriodEndDate,
                                                  dataSwipeIdx: $dataSwipeIdx,
                                                  showingOverlay: $showingOverlay)
                    .id(selectedMetricData.defaultData.count)
                }
                .frame(height: 200.0)
                .padding([.leading, .trailing], graphLrPadding)
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            } else {
                VStack(spacing: 14.0) {
                    Image(model.activityType.glyphName)
                        .resizable()
                        .frame(width: 34.0, height: 34.0)
                    Text("No data for this time period")
                        .font(.system(size: 14.0, weight: .medium))
                }
                .foregroundColor(.white)
                .opacity(0.4)
                .frame(height: 200.0)
                .modifier(BlurOpacityTransition(speed: 1.8))
            }

            ZStack {
                if let fullCount = selectedMetricData?.fullDataCount {
                    let strings: [(idx: Int, string: String)] = (0...(fullCount - 1)).compactMap { idx in
                        if let label = model.graphRenderData.timebox.xLabel(for: idx) {
                            return (idx: idx, string: label)
                        }
                        return nil
                    }
                    ProgressLineGraphXLabels(labelStrings: strings,
                                             fullDataCount: fullCount,
                                             lrPadding: graphLrPadding)
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                } else {
                    Spacer()
                }
            }
            .frame(height: 24.0)
            .overlay {
                if let dailyAverage = selectedMetricData?.avg {
                    HStack {
                        Text("\(model.timePeriod.startDate.formatted(withFormat: "M/d/YY")) - \(model.timePeriod.endDate.formatted(withFormat: "M/d/YY"))")
                            .fixedSize(horizontal: true, vertical: true)
                            .font(.system(size: 12.0, weight: .medium, design: .monospaced))
                            .opacity(0.6)
                            .frame(height: 20.0)
                            .offset(y: 18.0)
                            .padding(.leading, graphLrPadding)
                            .id(Int(model.timePeriod.startDate.timeIntervalSince1970))
                            .transition(.opacity.animation(.easeInOut(duration: 0.1)))

                        if selectedMetricData?.field != \.paceInUserSelectedUnit {
                            Text("·")
                                .font(.system(size: 12.0, weight: .medium, design: .monospaced))
                                .opacity(0.6)
                                .frame(height: 20.0)
                                .offset(y: 18.0)
                        }

                        let string: String = {
                            if selectedMetricData?.field == \.paceInUserSelectedUnit {
                                return ""
                            } else {
                                return (selectedMetricData?.dataFormat(dailyAverage).uppercased() ?? "") + " DAILY AVG"
                            }
                        }()

                        Text(string)
                            .font(.system(size: 12.0, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .opacity(0.6)
                            .frame(height: 20.0)
                            .offset(y: 18.0)
                            .transition(.opacity.animation(.easeInOut(duration: 0.1)))

                        Spacer()
                    }
                } else {
                    EmptyView()
                }
            }
        }
        .onAppear {
            selectedMetricData = model.graphRenderData.metrics[model.selectedGraphMetric]
        }
        .onReceive(model.$selectedGraphMetric) { metric in
            selectedMetricData = model.graphRenderData.metrics[metric]
        }
        .onReceive(model.$graphRenderData) { data in
            selectedMetricData = data.metrics[model.selectedGraphMetric]
        }
    }
}

fileprivate struct Metrics: View {
    @ObservedObject var model: ActivityProgressGraphModel
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    func superscript(_ text: String, _ selected: Bool) -> some View {
        Text(text)
            .font(.system(size: 11.0, weight: selected ? .semibold : .medium, design: .monospaced))
            .foregroundColor(selected ? .black : .white)
            .offset(y: 3.5)
            .opacity(0.5)
    }

    func bigText(_ text: String, _ selected: Bool) -> some View {
        Text(text)
            .font(.system(size: 28.0, weight: selected ? .semibold : .medium, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundColor(selected ? .black : .white)
            .animation(.none, value: model.selectedGraphMetric)
    }

    func glyphRotation(for percent: Float) -> CGFloat {
        switch percent {
        case 0.0:
            return 0.0
        case 0.0...0.25:
            return -0.125 * .pi
        case -0.25...0.0:
            return 0.125 * .pi
        default:
            return percent > 0.0 ? -0.25 * .pi : 0.25 * .pi
        }
    }

    func string(for percent: Float) -> String {
        switch abs(percent) {
        case 10.0:
            return "∞% "
        default:
            return String(Int((abs(percent) * 100).rounded())) + "% "
        }
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8.0) {
            let fields: [PartialKeyPath<Activity>] = model.graphRenderData.metrics.keys.map({ $0 }).sorted(by: \.sortOrder)
            ForEach(fields, id: \.self) { key in
                let percent = model.graphRenderData.metrics[key]!.defaultPercentDifference
                let selected = key == model.selectedGraphMetric
                let color = ActivityProgressGraphModel.color(for: percent,
                                                             selected: selected,
                                                             field: key)

                Button {
                    model.selectedGraphMetric = key
                    feedbackGenerator.impactOccurred()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3.0) {
                            HStack(alignment: .top, spacing: 3.0) {
                                if key == \.movingTime {
                                    let metric = model.graphRenderData.metrics[key]!.defaultDisplayMetric
                                    let hours = String(Int(metric))
                                    let minutes = String(Int(60 * (metric.truncatingRemainder(dividingBy: 1))))

                                    if #available(iOS 17.0, *) {
                                        if Int(hours) ?? 0 > 0 {
                                            bigText(hours, selected)
                                                .contentTransition(.numericText(value: Double(hours) ?? 0.0))
                                                .transaction { t in
                                                    t.animation = .default
                                                }
                                                .modifier(BlurOpacityTransition(speed: 2.0))
                                            superscript("HR", selected)
                                                .modifier(BlurOpacityTransition(speed: 2.0))
                                                .padding(.trailing, 3.0)
                                        }
                                        bigText(minutes, selected)
                                            .contentTransition(.numericText(value: Double(minutes) ?? 0.0))
                                            .transaction { t in
                                                t.animation = .default
                                            }
                                        superscript("MIN", selected)
                                    } else {
                                        if Int(hours) ?? 0 > 0 {
                                            bigText(hours, selected)
                                                .modifier(BlurOpacityTransition(speed: 2.0))
                                            superscript("HR", selected)
                                                .modifier(BlurOpacityTransition(speed: 2.0))
                                                .padding(.trailing, 3.0)
                                        }
                                        bigText(minutes, selected)
                                        superscript("MIN", selected)
                                    }
                                } else {
                                    if #available(iOS 17.0, *) {
                                        bigText(model.graphRenderData.metrics[key]!.formattedDisplayMetric, selected)
                                            .contentTransition(.numericText(value: Double(model.graphRenderData.metrics[key]!.defaultDisplayMetric.rounded(toPlaces: 1))))
                                            .transaction { t in
                                                t.animation = .default
                                            }
                                    } else {
                                        bigText(model.graphRenderData.metrics[key]!.formattedDisplayMetric, selected)
                                    }

                                    superscript(model.graphRenderData.metrics[key]!.field.unit.uppercased(), selected)
                                }
                            }
                            .animation(.easeInOut(duration: 0.3), value: model.graphRenderData.metrics[key]!.formattedDisplayMetric)

                            Text(key.displayName)
                                .font(.system(size: 11.0, weight: selected ? .semibold : .medium, design: .monospaced))
                                .foregroundColor(selected ? .black : .white)
                                .opacity(0.5)
                                .offset(y: -2.0)

                            HStack(spacing: 0.0) {
                                let glyphRotation: CGFloat = glyphRotation(for: percent)
                                let percentString: String = string(for: percent)

                                HStack(spacing: 3.0) {
                                    Image(systemName: .arrowRightCircleFill)
                                        .font(.system(size: 16.0, weight: .medium))
                                        .rotationEffect(.radians(glyphRotation))
                                        .animation(.easeInOut(duration: 0.3), value: Double(abs(percent) * 100).rounded())
                                        .animation(.none, value: model.selectedGraphMetric)

                                    let percentText = {
                                        Text(percentString)
                                            .font(.system(size: 14, weight: selected ? .semibold : .medium))
                                            .lineLimit(1)
                                            .animation(.none, value: model.selectedGraphMetric)
                                    }()

                                    if #available(iOS 17.0, *) {
                                        percentText
                                            .contentTransition(.numericText(value: Double(abs(percent) * 100).rounded()))
                                            .transaction { t in
                                                t.animation = .default
                                            }
                                    } else {
                                        percentText
                                    }
                                }
                                .foregroundColor(color)
                                .animation(.none, value: model.selectedGraphMetric)
                            }
                        }

                        Spacer()
                    }
                    .padding()
                    .background(key == model.selectedGraphMetric ? Color.white : Color(white: 0.1))
                    .cornerRadius(18.0)
                }
                .buttonStyle(ScalingPressButtonStyle())
            }
        }
    }
}

fileprivate struct GoalCell: View {
    @ObservedObject var goal: Goal
    @Binding var goalForDetail: Goal?

    var body: some View {
        Button {
            goalForDetail = goal
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 18.0)
                    .foregroundColor(.white)
                    .opacity(0.1)
                HStack(spacing: 12.0) {
                    ZStack {
                        CircularGoalProgressView(style: .small,
                                                 progress: CGFloat(goal.distanceInSelectedUnit / goal.targetDistanceInSelectedUnit))
                        .frame(width: 50.0, height: 50.0)
                        .id(goal.distanceInSelectedUnit / goal.targetDistanceInSelectedUnit)
                        .modifier(BlurOpacityTransition(speed: 1.8))

                        Image(goal.activityType.glyphName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24.0, height: 24.0)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            String(Int(goal.distanceInSelectedUnit.rounded())) +
                            "/" +
                            String(Int(goal.targetDistanceInSelectedUnit.rounded())) +
                            goal.unit.abbreviation.lowercased()
                        )
                        .font(.presicav(size: 21))
                        .id(goal.distanceInSelectedUnit / goal.targetDistanceInSelectedUnit)
                        .modifier(BlurOpacityTransition(speed: 1.8))

                        Text("By \(goal.formattedDate)")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .opacity(0.6)
                            .id(goal.formattedDate)
                            .modifier(BlurOpacityTransition(speed: 1.8))
                    }
                    .offset(y: -2.0)

                    Spacer()
                }
                .padding()
            }
        }
        .buttonStyle(ScalingPressButtonStyle())
    }
}

fileprivate struct GoalsSection: View {
    @StateObject var user: ADUser = .current
    @Binding var goalForDetail: Goal?
    var createGoalHandler: () -> Void

    var createGoalButton: some View {
        Button {
            createGoalHandler()
        } label: {
            HStack {
                Image(systemName: .plus)
                Text("New")
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

    var body: some View {
        VStack(spacing: 8.0) {
            HStack {
                SectionHeaderText(text: "Goals")
                Spacer()
                createGoalButton
            }

            let activeGoals = user.goals.filter { Date() < $0.endDate }
            if activeGoals.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.1), lineWidth: 2)

                    VStack(spacing: 16.0) {
                        Image("glyph_goal_big")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(.white)
                            .opacity(0.3)
                            .frame(width: 45.0, height: 45.0)
                        Text("Track progress towards a distance goal")
                            .font(.system(size: 15.0))
                            .multilineTextAlignment(.center)
                            .opacity(0.6)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding([.leading, .trailing], 30.0)
                    }
                    .padding([.top, .bottom], 20)
                }
            } else {
                VStack {
                    ForEach(activeGoals, id: \.self) { goal in
                        GoalCell(goal: goal, goalForDetail: $goalForDetail)
                    }
                }
            }

            let completedGoals = user.goals.filter { Date() >= $0.endDate }
            if !completedGoals.isEmpty {
                SectionHeaderText(text: "Completed Goals")
                    .padding(.top, 16)
                VStack {
                    ForEach(completedGoals, id: \.self) { goal in
                        GoalCell(goal: goal, goalForDetail: $goalForDetail)
                    }
                }
            }
        }
        .padding([.leading, .trailing], 15)
    }
}

struct GearEmptyState: View {
    var text: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.1), lineWidth: 2)

            VStack(spacing: 16.0) {
                Image("activity_steps")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.white)
                    .opacity(0.3)
                    .frame(width: 45.0, height: 45.0)
                Text(text)
                    .font(.system(size: 15.0, weight: .regular))
                    .multilineTextAlignment(.center)
                    .opacity(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding([.leading, .trailing], 30.0)
            }
            .padding([.top, .bottom], 20)
        }
    }
}

fileprivate struct GearSection: View {
    @StateObject var user: ADUser = .current
    @Binding var gearForDetail: Gear?
    var createGearHandler: () -> Void

    var createGearButton: some View {
        Button {
            createGearHandler()
        } label: {
            HStack {
                Image(systemName: .plus)
                Text("New")
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

    var body: some View {
        VStack(spacing: 8.0) {
            HStack {
                SectionHeaderText(text: "Shoes")
                Spacer()
                createGearButton
            }

            if user.gear.isEmpty {
                GearEmptyState(text: "Track distance and time for your shoes")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(user.gear, id: \.id) { gear in
                            GearHorizontalCell(gear: gear, gearForDetail: $gearForDetail)
                        }
                    }
                    .padding([.leading, .trailing], 15)
                }
                .padding([.leading, .trailing], -15)
            }
        }
        .padding([.leading, .trailing], 15)
    }
}


fileprivate struct LifetimeActivity: View {
    var body: some View {
        VStack(spacing: 12.0) {
            ZStack {
                SectionHeaderText(text: "Lifetime Activity")
                HStack {
                    Spacer()
                    Text("Since joining Any Distance")
                        .font(.system(size: 12.0))
                        .foregroundColor(.white)
                        .opacity(0.6)
                }
            }

            VStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 18.0)
                        .foregroundColor(.white)
                        .opacity(0.1)
                    HStack(spacing: 12.0) {
                        Image(uiImage: ADUser.current.distanceUnit.filledGlyph!)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30.0, height: 30.0)
                            .padding([.leading, .trailing], 10.0)
                        VStack(alignment: .leading) {
                            HStack(alignment: .bottom, spacing: 0.0) {
                                Text(String(Int(ADUser.current.totalDistanceTracked)))
                                    .font(.system(size: 24, design: .monospaced))
                                Text(ADUser.current.distanceUnit.abbreviation.uppercased())
                                    .font(.system(size: 18, design: .monospaced))
                                    .padding(.leading, 1.0)
                                    .offset(y: -1.5)
                            }
                            .modifier(GradientEffect())

                            Text("Distance")
                                .font(.system(size: 14, design: .monospaced))
                                .opacity(0.5)
                        }

                        Spacer()
                    }
                    .padding()
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 18.0)
                        .foregroundColor(.white)
                        .opacity(0.1)
                    HStack(spacing: 12.0) {
                        Image(systemName: .stopwatchFill)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30.0, height: 30.0)
                            .padding([.leading, .trailing], 10.0)
                        VStack(alignment: .leading) {
                            HStack {
                                if ADUser.current.totalTimeTracked >= 3600.0 {
                                    HStack(alignment: .bottom, spacing: 0.0) {
                                        Text(String(Int(ADUser.current.totalTimeTracked / 3600)))
                                            .font(.system(size: 24, weight: .medium, design: .monospaced))
                                        Text("HR")
                                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                                            .padding(.leading, 1.0)
                                            .offset(y: -1.5)
                                    }
                                }

                                HStack(alignment: .bottom, spacing: 0.0) {
                                    Text(String(Int(ADUser.current.totalTimeTracked.truncatingRemainder(dividingBy: 60))))
                                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                                    Text("MIN")
                                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                                        .padding(.leading, 1.0)
                                        .offset(y: -1.5)
                                }
                            }
                            .modifier(GradientEffect())

                            Text("Active Time")
                                .font(.system(size: 14, design: .monospaced))
                                .opacity(0.5)
                        }

                        Spacer()
                    }
                    .padding()
                }
            }
        }
    }
}

struct ActivityProgressView: View {
    @StateObject var model: ActivityProgressGraphModel = ActivityProgressGraphModel()
    @StateObject var iapManager: iAPManager = .shared
    @State private var scrollViewOffset: CGFloat = 0.0
    @State private var scrollViewContentSize: CGSize = .zero
    @State private var refreshing: Bool = false
    @State private var selectedCluster: Int = 0
    @State private var showingGraphOverlay: Bool = false
    @State private var hasAppeared: Bool = false
    @State private var goalForDetail: Goal?
    @State private var gearForDetail: Gear?
    @State private var dimView: Bool = false

    let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    var safeAreaInsets: UIEdgeInsets {
        return UIApplication.shared.topViewController!.view.safeAreaInsets
    }

    func createNewGoal() {
        guard let createGoalVC = UIStoryboard(name: "Goals", bundle: nil)
            .instantiateViewController(withIdentifier: "editGoal") as? EditGoalViewController else {
            return
        }

        feedbackGenerator.impactOccurred()
        dimView = true
        createGoalVC.mode = .createGoal
        createGoalVC.doneHandler = { goal in
            goalForDetail = goal
        }
        createGoalVC.dismissHandler = {
            dimView = false
        }
        createGoalVC.modalPresentationStyle = .overFullScreen
        UIApplication.shared.topViewController?.present(createGoalVC, animated: true)
    }

    func createNewGear() {
        feedbackGenerator.impactOccurred()
        gearForDetail = Gear(type: .shoes, name: "")
    }

    var map: some View {
        ZStack {
            let noRoutes = (hasAppeared && model.hasPerformedInitialLoad) ? model.coordinateClusters.isEmpty : false
            let requiresSD = model.timePeriod.requiresSuperDistance && !iapManager.hasSuperDistanceFeatures

            MapView(model: model,
                    selectedClusterIdx: $selectedCluster)
            .saturation(0.0)
            .contrast(1.45)
            .brightness(0.08)
            .frame(height: UIScreen.main.bounds.height)
            .ignoresSafeArea()
            .offset(y: (-0.8 * scrollViewOffset) - safeAreaInsets.top)
            .blur(radius: (6 * ((scrollViewOffset + safeAreaInsets.top) / (-0.3 * UIScreen.main.bounds.height)).clamped(to: 0...30)))
            .opacity((1.0 - (scrollViewOffset / (-0.8 * UIScreen.main.bounds.height))).clamped(to: 0...1))
            .background(Color(white: 0.1))
            .overlay {
                VStack {
                    VariableBlurView()
                        .frame(height: safeAreaInsets.top)
                        .offset(y: (-1 * scrollViewOffset) - (safeAreaInsets.top / 2))
                    Spacer()
                }
            }
            .opacity(1.0 - ((scrollViewOffset + safeAreaInsets.top + (0.3 * UIScreen.main.bounds.height)) / (-0.3 * UIScreen.main.bounds.height)).clamped(to: 0...1))
            .blur(radius: noRoutes || requiresSD ? 14.0 : 0.0)
            .animation(.easeInOut(duration: 0.2), value: noRoutes)
            .animation(.easeInOut(duration: 0.2), value: requiresSD)
            .allowsHitTesting(!noRoutes && !model.loading && !requiresSD)
            .overlay {
                VStack {
                    ZStack {
                        if noRoutes {
                            VStack(spacing: 14.0) {
                                Spacer()
                                Image(model.activityType.glyphName)
                                    .resizable()
                                    .frame(width: 34.0, height: 34.0)
                                Text("No routes for this time period")
                                    .font(.system(size: 14.0, weight: .medium))
                                Spacer()
                            }
                            .opacity(0.4)
                            .modifier(BlurOpacityTransition(speed: 1.8))
                            .foregroundColor(.white)
                        } else if requiresSD {
                            VStack {
                                Spacer()
                                Button {
                                    feedbackGenerator.impactOccurred()
                                    let vc = UIHostingController(rootView: SuperDistanceView())
                                    vc.modalPresentationStyle = .overFullScreen
                                    UIApplication.shared.topViewController?.present(vc, animated: true)
                                } label: {
                                    HStack {
                                        Text("Unlock with")
                                        Image("glyph_superdistance_white")
                                            .renderingMode(.template)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .tint(Color.black)
                                            .frame(width: 85.0)
                                        Image(systemName: .chevronRight)
                                    }
                                    .font(.system(size: 13.0, weight: .medium))
                                    .foregroundColor(.black)
                                    .padding([.leading, .trailing], 15.0)
                                    .padding([.top, .bottom], 9.0)
                                    .background {
                                        RoundedRectangle(cornerRadius: 100.0, style: .continuous)
                                            .fill(Color.white)
                                    }
                                }
                                .buttonStyle(ScalingPressButtonStyle())
                                Spacer()
                            }
                            .modifier(BlurOpacityTransition(speed: 1.8))
                        }
                    }
                    .frame(height: UIScreen.main.bounds.height * 0.8)
                    .offset(y: (-0.7 * scrollViewOffset) - safeAreaInsets.top)
                    .blur(radius: (6 * ((scrollViewOffset + safeAreaInsets.top) / (-0.3 * UIScreen.main.bounds.height)).clamped(to: 0...30)))
                    .opacity((1.0 - (scrollViewOffset / (-0.8 * UIScreen.main.bounds.height))).clamped(to: 0...1))

                    Spacer()
                }
            }
        }
    }

    var graphPickerOffset: CGFloat {
        return (-0.4 * UIScreen.main.bounds.height) + (-1 * (scrollViewOffset + (UIScreen.main.bounds.height * 0.6) - 20)).clamped(to: 0...1000000)
    }

    var body: some View {
        ZStack {
            ScrollViewReader { proxy in
                ReadableScrollView(offset: $scrollViewOffset,
                                   contentSize: $scrollViewContentSize,
                                   showsIndicators: false) {
                    VStack(spacing: 16.0) {
                        map

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .center, spacing: 12.0) {
                                SmallActivityTypeSearchButton(activityType: $model.activityType)
                                    .padding([.top, .bottom], 20.0)
                                TimePeriodPicker(model: model,
                                                 fontSize: 13)
                                    .fixedSize(horizontal: true, vertical: false)

                                if model.coordinateClusters.count > 1 {
                                    ADSegmentedControl(segments: model.coordinateClusters.map { $0.geocodedName },
                                                       fontSize: 13,
                                                       selectedSegmentIdx: $selectedCluster)
                                    .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                            .padding([.leading, .trailing], 15)
                        }
                        .padding([.top, .bottom], -20.0)
                        .opacity(showingGraphOverlay ? 0.0 : 1.0)
                        .opacity(((scrollViewOffset + (UIScreen.main.bounds.height * 0.6) + 650.0) / 150.0).clamped(to: 0...1))
                        .blur(radius: 5.0 * (1.0 - ((scrollViewOffset + 1100.0) / 80.0).clamped(to: 0...1)))
                        .animation(.easeInOut(duration: 0.4), value: model.coordinateClusters.count)
                        .animation(.easeInOut(duration: 0.25), value: showingGraphOverlay)
                        .offset(y: graphPickerOffset)
                        .zIndex(1000)

                        VStack(spacing: 16.0) {
                            ProgressGraph(model: model,
                                          showingOverlay: $showingGraphOverlay)
                                .padding(.bottom, 30.0)
                                .padding(.top, 20.0)
                                .padding([.leading, .trailing], 15.0)
                                .zIndex(2000)

                            Metrics(model: model)
                                .padding(.bottom, 30.0)
                                .padding([.leading, .trailing], 15.0)

                            MedalCarousel(user: ADUser.current)
                                .padding(.bottom, 16)

                            GoalsSection(goalForDetail: $goalForDetail,
                                         createGoalHandler: createNewGoal)
                                .padding(.bottom, 16)

                            GearSection(gearForDetail: $gearForDetail,
                                        createGearHandler: createNewGear)
                                .padding(.bottom, 16)

                            LifetimeActivity()
                                .padding(.bottom, 12.0)
                                .padding([.leading, .trailing], 15.0)
                        }
                        .background {
                            VStack(spacing: 0) {
                                Image("gradient_bottom_ease_in_out")
                                    .renderingMode(.template)
                                    .resizable(resizingMode: .stretch)
                                    .frame(width: UIScreen.main.bounds.width, height: 300.0)
                                    .foregroundColor(.black)
                                    .overlay {
                                        VariableBlurView(maxBlurRadius: 3,
                                                         direction: .blurredBottomClearTop)
                                    }
                                Color.black
                                    .padding(.bottom, -800)
                            }
                            .offset(y: -90)
                        }
                        .offset(y: -0.4 * UIScreen.main.bounds.height)
                        .padding(.bottom, -0.4 * UIScreen.main.bounds.height)

                        Spacer()
                            .frame(height: 100.0)
                            .id(1)
                    }
                    .padding(.top, -34.0)
                    .overlay {
                        VStack {
                            ProgressHeader(scrollViewOffset: scrollViewOffset + UIScreen.main.safeAreaInsets.top)
                                .padding([.leading, .trailing], 15.0)
                                .padding(.top, UIScreen.main.safeAreaInsets.top)
                                .opacity(1.0 - ((scrollViewOffset + safeAreaInsets.top + (0.3 * UIScreen.main.bounds.height)) / (-0.15 * UIScreen.main.bounds.height)).clamped(to: 0...1))
                                .blur(radius: 5.0 * ((scrollViewOffset + safeAreaInsets.top + (0.2 * UIScreen.main.bounds.height)) / (-0.2 * UIScreen.main.bounds.height)).clamped(to: 0...1))
                            Spacer()
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .overlay {
                VStack(spacing: 0) {
                    Image("gradient_bottom_ease_in_out")
                        .resizable(resizingMode: .stretch)
                        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.safeAreaInsets.top)
                        .scaleEffect(y: -1)
                        .overlay {
                            VariableBlurView()
                        }
                        .opacity((scrollViewOffset / -400.0).clamped(to: 0...1))
                    Spacer()
                }
                .ignoresSafeArea()
            }
        }
        .opacity(dimView ? 0.6 : 1.0)
        .blur(radius: dimView ? 10.0 : 0.0)
        .animation(.easeInOut(duration: 0.3), value: dimView)
        .onChange(of: refreshing) { newValue in
            if newValue == true {
                Task {
                    await ActivitiesData.shared.load(updateUserAndCollectibles: true)
                    await MainActor.run {
                        refreshing = false
                    }
                }
            }
        }
        .onReceive(ReloadPublishers.setNewGoal) { _ in
            createNewGoal()
        }
        .onReceive(model.objectWillChange) { _ in
            hasAppeared = true
        }
        .onDisappear {
            model.viewVisible = false
        }
        .onAppear {
            model.viewVisible = true
        }
        .fullScreenCover(item: $goalForDetail) { goalForDetail in
            GoalProgressView(model: GoalProgressViewModel(goal: goalForDetail))
        }
        .fullScreenCover(item: $gearForDetail) { gearForDetail in
            GearDetailView(gear: gearForDetail,
                           isEditing: gearForDetail.isNew)
            .background(BackgroundClearView())
        }
    }
}

struct ActivityProgressView_Previews: PreviewProvider {
    static var previews: some View {
        ActivityProgressView()
            .previewDevice("iPhone 14 Pro")
    }
}