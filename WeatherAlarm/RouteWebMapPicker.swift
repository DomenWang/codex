import CoreLocation
import MapKit
import SwiftUI

@available(iOS 26.0, *)
struct RouteWebMapPicker: View {
    let onSave: @MainActor (_ startAddress: String, _ endAddress: String) async -> Bool

    @StateObject private var model: AppleRoutePickerModel
    @State private var isSaving = false
    @FocusState private var focusedRole: RouteLocationRole?

    init(
        startAddress: String,
        endAddress: String,
        activeRole: RouteLocationRole,
        onSave: @escaping @MainActor (_ startAddress: String, _ endAddress: String) async -> Bool
    ) {
        self.onSave = onSave
        _model = StateObject(
            wrappedValue: AppleRoutePickerModel(
                startAddress: startAddress,
                endAddress: endAddress,
                activeRole: activeRole
            )
        )
    }

    var body: some View {
        ZStack {
            SmartWakeAmbientBackdrop(style: .morning)

            ScrollView {
                VStack(spacing: 10) {
                    routeField(role: .start)
                    routeField(role: .end)

                    if !model.results.isEmpty {
                        searchResults
                            .zIndex(2)
                    }

                    AppleRouteMapView(
                        startCoordinate: model.startCoordinate,
                        endCoordinate: model.endCoordinate,
                        onMapTap: model.chooseMapCoordinate
                    )
                        .frame(maxWidth: .infinity, minHeight: 310)
                        .allowsHitTesting(model.isMapInteractionEnabled)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.90),
                                            SmartWakeTheme.teal.opacity(0.18),
                                            SmartWakeTheme.weatherMint.opacity(0.16)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }

                    Text(model.statusText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(SmartWakeTheme.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .smartWakeCrystalSurface(cornerRadius: 30, tint: SmartWakeTheme.teal, showsSheen: true)
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("设置通勤路线")
        .navigationBarTitleDisplayMode(.inline)
        .tint(SmartWakeTheme.teal)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                saveButton
            }
        }
        .onChange(of: focusedRole) { _, newRole in
            if let newRole {
                model.setActive(newRole)
            }
        }
        .onDisappear {
            model.stop()
        }
    }

    private var saveButton: some View {
        Button {
            guard model.canSave else {
                model.statusText = "请先设置完整的出发地和目的地。"
                return
            }

            focusedRole = nil
            isSaving = true
            Task {
                let didSave = await onSave(model.startText, model.endText)
                guard !Task.isCancelled else {
                    return
                }
                isSaving = false
                if !didSave {
                    model.statusText = "路线保存失败，请检查地址或网络后重试。"
                }
            }
        } label: {
            HStack(spacing: 7) {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(isSaving ? "保存中" : "保存")
            }
            .frame(minWidth: 64, minHeight: 44)
            .contentShape(Rectangle())
        }
        .font(.headline.weight(.black))
        .disabled(isSaving)
        .accessibilityLabel(isSaving ? "路线保存中" : "保存路线")
        .accessibilityIdentifier("smartwake.route.save")
    }

    private func routeField(role: RouteLocationRole) -> some View {
        let isActive = model.activeRole == role
        return HStack(spacing: 10) {
            Circle()
                .fill(role == .start ? SmartWakeTheme.weatherMint : SmartWakeTheme.sky)
                .frame(width: 16, height: 16)
                .shadow(
                    color: (role == .start ? SmartWakeTheme.weatherMint : SmartWakeTheme.sky).opacity(0.20),
                    radius: 7
                )

            Text(role.fieldTitle)
                .font(.subheadline.weight(.black))
                .foregroundStyle(SmartWakeTheme.secondaryInk)
                .frame(width: 54, alignment: .leading)

            TextField(role.placeholder, text: binding(for: role))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SmartWakeTheme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedRole, equals: role)
                .onSubmit {
                    model.searchActiveRole()
                }
                .onChange(of: textValue(for: role)) {
                    model.setActive(role)
                    model.queueSearch()
                }

            Button {
                model.setActive(role)
                model.searchActiveRole()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(isActive ? .white : SmartWakeTheme.tealDeep)
                    .frame(width: 38, height: 38)
                    .background(
                        isActive ? SmartWakeTheme.teal : SmartWakeTheme.teal.opacity(0.10),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 58)
        .smartWakeCrystalSurface(
            cornerRadius: 20,
            tint: isActive ? SmartWakeTheme.teal : SmartWakeTheme.sky,
            interactive: true
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                model.setActive(role)
                focusedRole = role
            }
        )
    }

    private var searchResults: some View {
        VStack(spacing: 7) {
            HStack {
                Text("选择搜索结果")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SmartWakeTheme.secondaryInk)

                Spacer()

                Button("改用地图选点") {
                    model.prepareForMapSelection()
                    focusedRole = nil
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 5)

            ForEach(model.results) { result in
                Button {
                    model.select(result)
                    focusedRole = nil
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.title)
                                .font(.subheadline.weight(.black))
                                .foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.13))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)

                            if !result.subtitle.isEmpty {
                                Text(result.subtitle)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Image(systemName: "checkmark.circle")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(SmartWakeTheme.tealDeep)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .padding(11)
                    .contentShape(Rectangle())
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .smartWakeCrystalSurface(
                    cornerRadius: 14,
                    tint: SmartWakeTheme.sky,
                    interactive: true
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .smartWakeCrystalSurface(cornerRadius: 18, tint: SmartWakeTheme.teal)
    }

    private func binding(for role: RouteLocationRole) -> Binding<String> {
        switch role {
        case .start:
            return $model.startText
        case .end:
            return $model.endText
        }
    }

    private func textValue(for role: RouteLocationRole) -> String {
        switch role {
        case .start:
            return model.startText
        case .end:
            return model.endText
        }
    }
}

@available(iOS 26.0, *)
private struct AppleRouteSearchResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D

    var displayAddress: String {
        subtitle.isEmpty ? title : "\(title) \(subtitle)"
    }
}

@available(iOS 26.0, *)
@MainActor
private final class AppleRoutePickerModel: ObservableObject {
    @Published var startText: String
    @Published var endText: String
    @Published var activeRole: RouteLocationRole
    @Published var startCoordinate: CLLocationCoordinate2D?
    @Published var endCoordinate: CLLocationCoordinate2D?
    @Published var results: [AppleRouteSearchResult] = []
    @Published var statusText = "搜索地点，或直接点地图设置当前选中的地点。"
    @Published private(set) var isMapInteractionEnabled = true

    private var searchTask: Task<Void, Never>?
    private var localSearch: MKLocalSearch?
    private var reverseGeocodingTask: Task<Void, Never>?
    private var mapInteractionTask: Task<Void, Never>?
    private var suppressNextQueuedSearch = false

    init(startAddress: String, endAddress: String, activeRole: RouteLocationRole) {
        self.startText = startAddress
        self.endText = endAddress
        self.activeRole = activeRole
    }

    var canSave: Bool {
        !startText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !endText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func setActive(_ role: RouteLocationRole) {
        if activeRole != role {
            cancelPendingSearch()
            results = []
            isMapInteractionEnabled = true
        }

        activeRole = role
    }

    func queueSearch() {
        if suppressNextQueuedSearch {
            suppressNextQueuedSearch = false
            cancelPendingSearch()
            return
        }

        cancelPendingSearch()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else {
                return
            }

            self?.searchActiveRole(quiet: true)
        }
    }

    func searchActiveRole(quiet: Bool = false) {
        cancelPendingSearch()
        let role = activeRole
        let query = text(for: role).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            if !quiet {
                statusText = "请先输入地点关键词。"
            }
            return
        }

        statusText = "正在查找地点..."
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        let search = MKLocalSearch(request: request)
        localSearch = search

        searchTask = Task { [weak self] in
            do {
                let response = try await search.start()
                guard !Task.isCancelled,
                      let self,
                      self.activeRole == role,
                      self.text(for: role).trimmingCharacters(in: .whitespacesAndNewlines) == query else {
                    return
                }

                let mappedResults = response.mapItems.prefix(8).map(Self.result)
                self.localSearch = nil
                self.results = mappedResults
                self.isMapInteractionEnabled = mappedResults.isEmpty
                self.statusText = mappedResults.isEmpty
                    ? "没有找到地点，试试更完整的关键词。"
                    : "单击一个地址即可选择；需要地图选点时先收起结果。"
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                self?.localSearch = nil
                self?.results = []
                self?.isMapInteractionEnabled = true
                self?.statusText = "地点搜索失败，请检查网络后再试。"
            }
        }
    }

    func select(_ result: AppleRouteSearchResult) {
        cancelPendingSearch()
        mapInteractionTask?.cancel()
        isMapInteractionEnabled = false
        applySelection(
            role: activeRole,
            address: result.displayAddress,
            coordinate: result.coordinate
        )
        results = []
        mapInteractionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else {
                return
            }
            self?.isMapInteractionEnabled = true
        }
    }

    func prepareForMapSelection() {
        cancelPendingSearch()
        mapInteractionTask?.cancel()
        results = []
        isMapInteractionEnabled = true
        statusText = "地图选点已开启，轻点地图设置\(activeRole.fieldTitle)。"
    }

    func stop() {
        cancelPendingSearch()
        reverseGeocodingTask?.cancel()
        reverseGeocodingTask = nil
        mapInteractionTask?.cancel()
        mapInteractionTask = nil
    }

    func chooseMapCoordinate(_ coordinate: CLLocationCoordinate2D) {
        reverseGeocodingTask?.cancel()
        let role = activeRole
        statusText = "正在识别地图位置..."
        reverseGeocodingTask = Task { [weak self] in
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let request = MKReverseGeocodingRequest(location: location)
            let mapItem: MKMapItem?
            if let request {
                do {
                    let items: [MKMapItem] = try await request.mapItems
                    mapItem = items.first
                } catch {
                    mapItem = nil
                }
            } else {
                mapItem = nil
            }
            let address = mapItem.flatMap(Self.address)
                ?? String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)

            guard !Task.isCancelled else {
                return
            }
            self?.applySelection(role: role, address: address, coordinate: coordinate)
        }
    }

    private func cancelPendingSearch() {
        searchTask?.cancel()
        searchTask = nil
        localSearch?.cancel()
        localSearch = nil
    }

    private func applySelection(
        role: RouteLocationRole,
        address: String,
        coordinate: CLLocationCoordinate2D
    ) {
        switch role {
        case .start:
            suppressNextQueuedSearch = startText != address
            startText = address
            startCoordinate = coordinate
        case .end:
            suppressNextQueuedSearch = endText != address
            endText = address
            endCoordinate = coordinate
        }

        statusText = "\(role.fieldTitle)已设置：\(address)"
    }

    private func text(for role: RouteLocationRole) -> String {
        switch role {
        case .start:
            return startText
        case .end:
            return endText
        }
    }

    private static func result(from item: MKMapItem) -> AppleRouteSearchResult {
        let title = item.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? item.name!
            : item.address?.shortAddress ?? "未命名地点"
        let fullAddress = item.addressRepresentations?.fullAddress(
            includingRegion: false,
            singleLine: true
        ) ?? item.address?.fullAddress ?? ""
        let subtitle = fullAddress == title ? "" : fullAddress

        return AppleRouteSearchResult(
            title: title,
            subtitle: subtitle,
            coordinate: item.location.coordinate
        )
    }

    private static func address(from mapItem: MKMapItem) -> String? {
        let address = mapItem.addressRepresentations?.fullAddress(
            includingRegion: false,
            singleLine: true
        ) ?? mapItem.address?.fullAddress
        guard let address = address?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty else {
            return nil
        }

        return address
    }
}

@available(iOS 26.0, *)
private struct AppleRouteMapView: UIViewRepresentable {
    let startCoordinate: CLLocationCoordinate2D?
    let endCoordinate: CLLocationCoordinate2D?
    let onMapTap: @MainActor (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMapTap: onMapTap)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .follow
        mapView.pointOfInterestFilter = .includingAll
        mapView.isRotateEnabled = false
        mapView.addGestureRecognizer(
            UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleMapTap(_:))
            )
        )
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onMapTap = onMapTap
        guard context.coordinator.coordinatesChanged(
            start: startCoordinate,
            end: endCoordinate
        ) else {
            return
        }

        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
        mapView.removeOverlays(mapView.overlays)

        var coordinates: [CLLocationCoordinate2D] = []
        if let startCoordinate {
            mapView.addAnnotation(annotation(title: "出发地", coordinate: startCoordinate))
            coordinates.append(startCoordinate)
        }

        if let endCoordinate {
            mapView.addAnnotation(annotation(title: "目的地", coordinate: endCoordinate))
            coordinates.append(endCoordinate)
        }

        if coordinates.count == 2 {
            mapView.setUserTrackingMode(.none, animated: false)
            mapView.addOverlay(MKPolyline(coordinates: coordinates, count: coordinates.count))
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            mapView.setVisibleMapRect(
                polyline.boundingMapRect,
                edgePadding: UIEdgeInsets(top: 58, left: 38, bottom: 58, right: 38),
                animated: false
            )
        } else if let lastCoordinate = coordinates.last {
            mapView.setUserTrackingMode(.none, animated: false)
            context.coordinator.didCenterOnUser = true
            mapView.setRegion(
                MKCoordinateRegion(
                    center: lastCoordinate,
                    span: Self.streetLevelSpan
                ),
                animated: false
            )
        } else if !context.coordinator.didCenterOnUser {
            mapView.setUserTrackingMode(.follow, animated: false)
        }
    }

    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        mapView.delegate = nil
        mapView.showsUserLocation = false
        mapView.setUserTrackingMode(.none, animated: false)
        mapView.gestureRecognizers?.forEach(mapView.removeGestureRecognizer)
        mapView.removeAnnotations(mapView.annotations)
        mapView.removeOverlays(mapView.overlays)
    }

    private static let streetLevelSpan = MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)

    private func annotation(title: String, coordinate: CLLocationCoordinate2D) -> MKPointAnnotation {
        let annotation = MKPointAnnotation()
        annotation.title = title
        annotation.coordinate = coordinate
        return annotation
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onMapTap: @MainActor (CLLocationCoordinate2D) -> Void
        var renderedStartCoordinate: CLLocationCoordinate2D?
        var renderedEndCoordinate: CLLocationCoordinate2D?
        var didCenterOnUser = false

        init(onMapTap: @escaping @MainActor (CLLocationCoordinate2D) -> Void) {
            self.onMapTap = onMapTap
        }

        @objc func handleMapTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView,
                  recognizer.state == .ended else {
                return
            }

            let point = recognizer.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            Task { @MainActor [weak self] in
                self?.onMapTap(coordinate)
            }
        }

        func coordinatesChanged(
            start: CLLocationCoordinate2D?,
            end: CLLocationCoordinate2D?
        ) -> Bool {
            guard !Self.coordinatesEqual(renderedStartCoordinate, start)
                    || !Self.coordinatesEqual(renderedEndCoordinate, end) else {
                return false
            }

            renderedStartCoordinate = start
            renderedEndCoordinate = end
            return true
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.72)
            renderer.lineWidth = 4
            renderer.lineCap = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard !didCenterOnUser,
                  renderedStartCoordinate == nil,
                  renderedEndCoordinate == nil,
                  let coordinate = userLocation.location?.coordinate,
                  CLLocationCoordinate2DIsValid(coordinate) else {
                return
            }

            didCenterOnUser = true
            mapView.setRegion(
                MKCoordinateRegion(
                    center: coordinate,
                    span: AppleRouteMapView.streetLevelSpan
                ),
                animated: false
            )
        }

        private static func coordinatesEqual(
            _ lhs: CLLocationCoordinate2D?,
            _ rhs: CLLocationCoordinate2D?
        ) -> Bool {
            switch (lhs, rhs) {
            case (nil, nil):
                return true
            case let (lhs?, rhs?):
                return abs(lhs.latitude - rhs.latitude) < 0.000_000_1
                    && abs(lhs.longitude - rhs.longitude) < 0.000_000_1
            default:
                return false
            }
        }
    }
}
