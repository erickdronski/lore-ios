import CoreLocation
import SwiftUI

// MapLibre GL Native. This import (and every MLN* type below) only resolves
// once the MapLibre SPM package is built by Xcode on a device, this headless
// scaffold has no Xcode and cannot compile against it (docs/22 Half B). The
// whole file is therefore behind Config.useMapLibreMap (default false) and is
// device-verify-pending, see the // VERIFY: markers for the few calls whose
// exact v6 signature the founder should confirm on first compile.
import MapLibre

/// The native flagship map (docs/17 "Making Lore's Map Genuinely 3D", docs/22
/// Half B), a SwiftUI wrapper around MapLibre GL Native that matches the
/// proprietary web map. It is the native port of two web modules:
///
///   - `lore-web/lib/mapStyle.ts`  -> `applyLoreStyle(_:mode:)` below: the
///     day/night restyle of the OpenFreeMap `liberty` vector style (warm
///     parchment by day, deep Ink by night), matched by source-layer so one
///     rule covers every road/landcover/label, the transit POI layer hidden,
///     editorial uppercase-and-tracked labels on the big places.
///   - `lore-web/lib/map3d.ts`     -> `LoreTowers` below: the storied-tower
///     `fill-extrusion` layer, real-measured-height places only (min 20m),
///     Brass at the street climbing to Amber at the crown.
///
/// It preserves the MapScreen contract: it is handed the already-filtered,
/// for-you-arranged `places`, a `mode` (day/night), a `view` (2D/3D pitch), and
/// a selection callback, so a pin tap here drives the same place sheet a MapKit
/// Annotation tap does. Per docs/17 §3 native parity is deliberately partial:
/// extrusions + sky + tilt now, terrain + globe inherited later when MapLibre
/// Native ships them, no schema change needed.
///
/// MapKit stays the default map (Config.useMapLibreMap == false) until this
/// compiles on device, this file is device-verify-pending by construction.
struct LoreMapLibreView: UIViewRepresentable {
    /// Day (warm parchment) or night (deep Ink). Mirrors web `MapMode`.
    enum Mode { case day, night }
    /// Flat atlas plate (pitch 0) or laid-back storied-tower view (pitch 55).
    /// Mirrors web `MapView`.
    enum ViewMode { case flat, tilted }

    /// The pins to render, already hard-filtered and for-you-arranged by
    /// MapScreen so this view never re-implements relevance.
    let places: [Place]
    /// The current restyle mode.
    let mode: Mode
    /// The current 2D/3D camera view.
    let viewMode: ViewMode
    /// The camera target to fly to when a (new) city loads. Nil means leave the
    /// camera where the user put it.
    let cameraTarget: CLLocationCoordinate2D?
    /// Called with a place id when its pin is tapped, wired to the same
    /// selection MapScreen drives its place sheet from.
    let onSelectPlace: (String) -> Void

    // MARK: Ported web constants (docs/17 §2.4, web lib/mapStyle.ts).

    /// Storied-tower view: camera laid back over the skyline (VIEW_3D_PITCH=55).
    static let tiltedPitch: CGFloat = 55
    /// Flat, top-down atlas view (VIEW_2D_PITCH=0).
    static let flatPitch: CGFloat = 0
    /// The base map: OpenFreeMap liberty vector style (docs/17 §0).
    static let styleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectPlace: onSelectPlace)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: Self.styleURL)
        mapView.delegate = context.coordinator
        // Match the web camera affordances (docs/17 §2.4): tilt + rotate on,
        // laid back over the skyline. Web uses maxPitch 80.
        mapView.maximumPitch = 80 // VERIFY: property name on MLNMapView (v6).
        mapView.attributionButtonPosition = .bottomLeft
        mapView.logoView.isHidden = false // OSM/OpenFreeMap courtesy (docs/17 §2.5).

        // A single tap selects the nearest place pin under the finger.
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        mapView.addGestureRecognizer(tap)

        applyCamera(to: mapView, animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelectPlace = onSelectPlace

        // Restyle if the mode changed (day <-> night) and the style is ready.
        if coordinator.appliedMode != mode, let style = mapView.style {
            LoreStyle.apply(to: style, mode: mode)
            LoreTowers.applyPaint(to: style, mode: mode)
            coordinator.appliedMode = mode
        }

        // Rebuild the pins + towers if the place set changed.
        if coordinator.appliedPlaceIDs != places.map(\.id), let style = mapView.style {
            coordinator.places = places
            LoreTowers.update(on: style, places: places, mode: mode)
            LorePins.update(on: style, places: places)
            coordinator.appliedPlaceIDs = places.map(\.id)
        }

        // Fly to a new city center, and re-pitch on a 2D/3D toggle.
        if coordinator.appliedCameraTarget?.latitude != cameraTarget?.latitude
            || coordinator.appliedCameraTarget?.longitude != cameraTarget?.longitude
            || coordinator.appliedViewMode != viewMode {
            applyCamera(to: mapView, animated: true)
            coordinator.appliedCameraTarget = cameraTarget
            coordinator.appliedViewMode = viewMode
        }
    }

    /// Set the camera pitch (2D/3D) and, if given, fly to the city center. The
    /// pitch mirrors the web VIEW_2D_PITCH / VIEW_3D_PITCH split (docs/17 §2.4).
    private func applyCamera(to mapView: MLNMapView, animated: Bool) {
        let pitch = viewMode == .tilted ? Self.tiltedPitch : Self.flatPitch
        let center = cameraTarget ?? mapView.centerCoordinate
        // A settled city view: web lands ~zoom 14 for the storied-tower read.
        let camera = MLNMapCamera(
            lookingAtCenter: center,
            altitude: 3_000, // VERIFY: altitude vs. zoom, v6 camera prefers altitude.
            pitch: pitch,
            heading: mapView.direction
        )
        mapView.setCamera(camera, animated: animated)
    }

    // MARK: - Coordinator

    /// Holds the MapLibre delegate + tap handling and the small amount of
    /// applied-state bookkeeping so `updateUIView` only does work on real
    /// changes (idempotent, mirrors the web modules' guarded re-application).
    final class Coordinator: NSObject, MLNMapViewDelegate {
        var onSelectPlace: (String) -> Void
        var places: [Place] = []

        var appliedMode: Mode?
        var appliedViewMode: ViewMode?
        var appliedPlaceIDs: [String] = []
        var appliedCameraTarget: CLLocationCoordinate2D?

        init(onSelectPlace: @escaping (String) -> Void) {
            self.onSelectPlace = onSelectPlace
        }

        /// Style finished loading, apply the Lore restyle, then add the towers
        /// and pins. This is the native analogue of the web `map.on("load")`
        /// / `styledata` wiring (docs/17 §2.5 order of operations).
        func mapView(_ mapView: MLNMapView, didFinish style: MLNStyle) {
            let mode = appliedMode ?? .night
            LoreStyle.apply(to: style, mode: mode)
            LoreTowers.update(on: style, places: places, mode: mode)
            LorePins.update(on: style, places: places)
            appliedMode = mode
            appliedPlaceIDs = places.map(\.id)
        }

        /// A tap: hit-test the pin symbol layer and, if a place feature is
        /// under the finger, select it (the same selection a MapKit pin tap
        /// drives). Web uses HTML Markers with their own click; native uses one
        /// symbol layer + a features query, so the tower extrusions never
        /// swallow a tap (they sit below the symbol layer).
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: mapView)
            // VERIFY: visibleFeatures(at:styleLayerIdentifiers:) signature (v6).
            let features = mapView.visibleFeatures(
                at: point,
                styleLayerIdentifiers: [LorePins.layerID]
            )
            if let feature = features.first,
               let id = feature.attribute(forKey: LorePins.idKey) as? String {
                onSelectPlace(id)
                // UIKit delivers gesture actions on the main thread; hop to the
                // main actor so the isolated Haptics API is satisfied.
                Task { @MainActor in Haptics.play(.pinTap) }
            }
        }
    }
}

// MARK: - Palette (ported from lore-web/lib/mapStyle.ts)

/// The two Lore worlds, values 1:1 with `mapStyle.ts` DAY / NIGHT (and drawn
/// from the same brand ramps as LoreColor). Kept as a plain struct of UIColors
/// so `LoreStyle.apply` reads like the web restyle pass.
private struct LorePalette {
    let background: UIColor
    let land: UIColor
    let landAlt: UIColor
    let water: UIColor
    let park: UIColor
    let wood: UIColor
    let grass: UIColor
    let roadMajor: UIColor
    let roadMinor: UIColor
    let roadCasing: UIColor
    let rail: UIColor
    let building: UIColor
    let buildingOutline: UIColor
    let label: UIColor
    let labelMuted: UIColor
    let labelWater: UIColor
    let labelHalo: UIColor
    let boundary: UIColor

    static let day = LorePalette(
        background: .hex(0xEAE2D0), // BONE_200
        land: .hex(0xF6F1E6),       // BONE_100
        landAlt: .hex(0xFCFAF4),    // BONE_50
        water: .hex(0xAFC0C9),      // dusty slate-blue, Ink-family
        park: .hex(0xCFDDC0),
        wood: .hex(0xC6D6B4),
        grass: .hex(0xD6E0C4),
        roadMajor: .hex(0xD9B36A),  // BRASS_300
        roadMinor: .hex(0xFCFAF4),  // BONE_50
        roadCasing: .hex(0xD8CDB4), // BONE_300
        rail: .hex(0xD8CDB4),       // BONE_300 by day
        building: .hex(0xE5DCC6),
        buildingOutline: .hex(0xD8CDB4),
        label: .hex(0x0F1626),      // INK_900
        labelMuted: .hex(0x46506B), // INK_600
        labelWater: .hex(0x4E6A78),
        labelHalo: .hex(0xF6F1E6, alpha: 0.9),
        boundary: .hex(0x46506B, alpha: 0.5)
    )

    static let night = LorePalette(
        background: .hex(0x0A0F1B), // INK_950
        land: .hex(0x0F1626),       // INK_900
        landAlt: .hex(0x121A2C),
        water: .hex(0x0C1220),      // sinks below land, darker voids
        park: .hex(0x1B2A2A),
        wood: .hex(0x182726),
        grass: .hex(0x1D2C2B),
        roadMajor: .hex(0xB98A2F),  // BRASS
        roadMinor: .hex(0x26314A),  // INK_700
        roadCasing: .hex(0x0A0F1B), // INK_950
        rail: .hex(0x26314A),       // INK_700 by night
        building: .hex(0x161E30),
        buildingOutline: .hex(0x1F2A40),
        label: .hex(0xF6F1E6),      // BONE_100
        labelMuted: .hex(0x8A93AB),
        labelWater: .hex(0x7E94C0),
        labelHalo: .hex(0x0A0F1B, alpha: 0.85),
        boundary: .hex(0x788AA3, alpha: 0.45)
    )

    static func forMode(_ mode: LoreMapLibreView.Mode) -> LorePalette {
        mode == .day ? .day : .night
    }
}

// MARK: - LoreStyle (ported from lore-web/lib/mapStyle.ts applyLoreStyle)

/// The restyle pass. Walks the loaded liberty layers and overrides their
/// paint/layout to the Lore palette for `mode`, matched by source-layer + type
/// so one rule covers a whole family (every road class, all landcover, every
/// label), exactly as the web `applyLoreStyle` does. Idempotent, safe to call
/// again on a mode switch. Everything is guarded, an id or property that a
/// future liberty revision drops is simply skipped, never a hard failure
/// (docs/19 P1 posture, ported).
private enum LoreStyle {
    /// Layers OWNED by the tower code, never restyle these here (they are the
    /// Lore extrusion + glow, matched by id and skipped, ported LORE_OWNED).
    static let owned: Set<String> = [
        "building-3d",
        LoreTowers.coreLayerID,
        LoreTowers.glowLayerID,
    ]

    static func apply(to style: MLNStyle, mode: LoreMapLibreView.Mode) {
        let p = LorePalette.forMode(mode)

        for layer in style.layers {
            let id = layer.identifier
            if owned.contains(id) { continue }

            // Background, the field behind everything.
            if let bg = layer as? MLNBackgroundStyleLayer {
                bg.backgroundColor = constant(p.background)
                continue
            }

            // Fills, water / parks / landcover / landuse / buildings.
            if let fill = layer as? MLNFillStyleLayer {
                applyFill(fill, id: id, palette: p, mode: mode)
                continue
            }

            // Lines, waterways / roads / boundaries.
            if let line = layer as? MLNLineStyleLayer {
                applyLine(line, id: id, palette: p, mode: mode)
                continue
            }

            // Symbols, labels + POI icons + the transit layer to hide.
            if let symbol = layer as? MLNSymbolStyleLayer {
                applySymbol(symbol, id: id, palette: p, mode: mode)
                continue
            }
        }
    }

    // The web restyle keys off `source-layer`; on iOS that is
    // `sourceLayerIdentifier`. We match on it (falling back to the id) so the
    // same families are covered.
    private static func sourceLayer(_ layer: MLNVectorStyleLayer) -> String {
        layer.sourceLayerIdentifier ?? ""
    }

    private static func applyFill(
        _ fill: MLNFillStyleLayer,
        id: String,
        palette p: LorePalette,
        mode: LoreMapLibreView.Mode
    ) {
        let sl = sourceLayer(fill)
        switch sl {
        case "water":
            fill.fillColor = constant(p.water)
        case "park":
            fill.fillColor = constant(p.park)
            fill.fillOpacity = constant(mode == .day ? 0.72 : 0.55)
        case "landcover":
            fill.fillColor = constant(id.contains("wood") ? p.wood : p.grass)
        case "landuse":
            let alt = id.contains("cemetery") || id.contains("hospital") || id.contains("school")
            fill.fillColor = constant(alt ? p.landAlt : p.land)
            fill.fillOpacity = constant(mode == .day ? 0.6 : 0.7)
        case "aeroway":
            fill.fillColor = constant(p.landAlt)
        case "building":
            fill.fillColor = constant(p.building)
            fill.fillOutlineColor = constant(p.buildingOutline)
        default:
            break
        }
    }

    private static func applyLine(
        _ line: MLNLineStyleLayer,
        id: String,
        palette p: LorePalette,
        mode: LoreMapLibreView.Mode
    ) {
        let sl = sourceLayer(line)
        switch sl {
        case "waterway":
            line.lineColor = constant(p.water)
        case "transportation":
            // Rounded caps + joins so the network reads as an engraving.
            line.lineCap = constant(NSValue(mlnLineCap: .round))
            line.lineJoin = constant(NSValue(mlnLineJoin: .round))
            if id.contains("casing") {
                line.lineColor = constant(p.roadCasing)
            } else if id.contains("motorway") || id.contains("trunk") || id.contains("primary") {
                line.lineColor = constant(p.roadMajor)
                line.lineBlur = constant(mode == .day ? 0.2 : 0.9) // warm bloom on arterials
            } else if id.contains("rail") {
                line.lineColor = constant(p.rail)
            } else {
                line.lineColor = constant(p.roadMinor)
            }
        case "boundary":
            line.lineColor = constant(p.boundary)
        default:
            break
        }
    }

    private static func applySymbol(
        _ symbol: MLNSymbolStyleLayer,
        id: String,
        palette p: LorePalette,
        mode: LoreMapLibreView.Mode
    ) {
        // Transit stations (poi_transit) are wayfinding noise on a storytelling
        // map, hide them outright so the only points are the ones with a story.
        if id == "poi_transit" {
            symbol.isVisible = false // VERIFY: hidden layer flag name (v6, isVisible).
            return
        }

        let sl = sourceLayer(symbol)
        switch sl {
        case "water_name":
            symbol.textColor = constant(p.labelWater)
            symbol.textLetterSpacing = constant(0.08)
        case "place":
            let major = id.contains("continent") || id.contains("country") || id.contains("state")
            let strong = major || id.contains("city")
            symbol.textColor = constant(strong ? p.label : p.labelMuted)
            if strong {
                // Uppercase + generous tracking on big places = the atlas look.
                symbol.textTransform = constant(NSValue(mlnTextTransform: .uppercase))
                symbol.textLetterSpacing = constant(major ? 0.22 : 0.12)
            }
        case "transportation_name":
            symbol.textColor = constant(p.labelMuted)
            symbol.textLetterSpacing = constant(0.05)
        case "poi", "aerodrome_label":
            // Recede POI noise: quiet text, no competing pin glyphs.
            symbol.textColor = constant(p.labelMuted)
            symbol.textOpacity = constant(mode == .day ? 0.55 : 0.45)
            symbol.iconOpacity = constant(0)
        default:
            symbol.textColor = constant(p.label)
        }

        // Every label gets the mode's halo so glyphs stay legible everywhere.
        symbol.textHaloColor = constant(p.labelHalo)
        symbol.textHaloWidth = constant(1.3)
        symbol.textHaloBlur = constant(0.5)
    }

    /// A constant style value. MapLibre iOS paint/layout properties are
    /// `NSExpression`s; a plain constant wraps the value.
    private static func constant(_ value: Any) -> NSExpression {
        NSExpression(forConstantValue: value)
    }
}

// MARK: - LoreTowers (ported from lore-web/lib/map3d.ts)

/// The storied-tower `fill-extrusion` layer, a 1:1 port of `map3d.ts`. Only
/// places with a REAL measured height at least 20m earn a prism, a park or
/// plaza stays its pin, never a stub cylinder (founder feedback, 2026-07-05,
/// docs/17 §2.1). Brass at the street climbs to Amber at the crown, scaled by
/// height. Footprints are pre-buffered here into octagons (no turf), the same
/// as the web `placesToFootprints` + `bufferPoint`.
private enum LoreTowers {
    static let sourceID = "lore-places-3d"      // LORE_3D_SOURCE
    static let coreLayerID = "lore-place-extrusions" // LORE_3D_LAYER
    static let glowLayerID = "lore-place-glow"  // LORE_3D_GLOW_LAYER

    // Ported map3d.ts constants.
    static let minRealHeightM: Double = 20      // MIN_REAL_HEIGHT_M
    static let heightScale: Double = 1.15       // HEIGHT_SCALE
    static let glowRiseM: Double = 26           // GLOW_RISE_M
    static let footprintRadiusM: Double = 15    // FOOTPRINT_RADIUS_M
    static let metersPerDegLat: Double = 111_320

    // Brand tokens, Brass at the ground, Amber up top, hot Amber crown.
    static let brass = UIColor.hex(0xB98A2F)    // BRASS
    static let amber = UIColor.hex(0xFFB454)    // AMBER
    static let amberHot = UIColor.hex(0xFFCE7A) // AMBER_HOT

    /// The tower height for a place with a real measured height, 0 for a place
    /// that shouldn't extrude (ported towerHeight).
    static func towerHeight(_ raw: Double?) -> Double {
        guard let raw, raw >= minRealHeightM else { return 0 }
        return raw * heightScale
    }

    /// Buffer one place point into an octagon footprint, scaled by latitude so
    /// the prism stays roughly circular away from the equator (ported
    /// bufferPoint). Eight vertices read as a tower footprint while staying
    /// cheap; offset by half a step so a flat face points at the camera.
    static func footprint(lng: Double, lat: Double) -> [CLLocationCoordinate2D] {
        let dLat = footprintRadiusM / metersPerDegLat
        let dLng = footprintRadiusM
            / (metersPerDegLat * max(0.01, cos(lat * .pi / 180)))
        var ring: [CLLocationCoordinate2D] = []
        for i in 0..<8 {
            let a = (Double(i) + 0.5) / 8 * .pi * 2
            ring.append(CLLocationCoordinate2D(
                latitude: lat + sin(a) * dLat,
                longitude: lng + cos(a) * dLng
            ))
        }
        return ring
    }

    /// Build the extrudable polygon features for the visible places, real
    /// heights only (ported placesToFootprints). `height_m` carries the scaled
    /// tower height, `base_m` the core roof so the glow starts where it ends.
    private static func features(for places: [Place]) -> [MLNPolygonFeature] {
        var out: [MLNPolygonFeature] = []
        for place in places {
            let height = towerHeight(place.heightM)
            guard height > 0 else { continue }
            var coords = footprint(lng: place.lng, lat: place.lat)
            let polygon = MLNPolygonFeature(coordinates: &coords, count: UInt(coords.count))
            polygon.attributes = [
                "id": place.id,
                "height_m": height,
                "base_m": height,
            ]
            out.append(polygon)
        }
        return out
    }

    /// Create or refresh the tower source + the two extrusion layers for the
    /// current places. Idempotent: on a place-set change it replaces the source
    /// shape (ported: web setData on the geojson source + addLayer once).
    static func update(on style: MLNStyle, places: [Place], mode: LoreMapLibreView.Mode) {
        let collection = MLNShapeCollectionFeature(shapes: features(for: places))

        if let existing = style.source(withIdentifier: sourceID) as? MLNShapeSource {
            existing.shape = collection
        } else {
            let source = MLNShapeSource(identifier: sourceID, shape: collection, options: nil)
            style.addSource(source)
            addLayers(to: style, source: source, mode: mode)
        }
        applyPaint(to: style, mode: mode)
    }

    /// Add the core tower layer and the night-only glow halo above it. The core
    /// is opaque Brass->Amber by height; the glow is a taller translucent Amber
    /// shaft rising GLOW_RISE_M above the roof so tall famous towers beacon
    /// (ported lorePlaceExtrusionLayer + lorePlaceGlowLayer).
    private static func addLayers(to style: MLNStyle, source: MLNShapeSource, mode: LoreMapLibreView.Mode) {
        // Core tower. Height is our per-feature height_m (ported
        // fill-extrusion-height: coalesce(get height_m, 20)).
        let core = MLNFillExtrusionStyleLayer(identifier: coreLayerID, source: source)
        core.minimumZoomLevel = 13 // matches web (a touch below liberty building-3d at 14)
        core.fillExtrusionHeight = heightExpression(key: "height_m")
        core.fillExtrusionBase = NSExpression(forConstantValue: 0)
        core.fillExtrusionHasVerticalGradient = constantBool(true)
        style.addLayer(core)

        // Glow halo, above the core, translucent Amber.
        let glow = MLNFillExtrusionStyleLayer(identifier: glowLayerID, source: source)
        glow.minimumZoomLevel = 13
        glow.fillExtrusionColor = NSExpression(forConstantValue: amberHot)
        glow.fillExtrusionBase = heightExpression(key: "base_m")
        glow.fillExtrusionHeight = NSExpression(
            format: "base_m + %@", NSNumber(value: glowRiseM)
        )
        glow.fillExtrusionOpacity = NSExpression(forConstantValue: 0.3)
        glow.fillExtrusionHasVerticalGradient = constantBool(true)
        style.addLayer(glow)
    }

    /// Repaint the core towers for the mode, Brass->Amber->hot-Amber ramp by
    /// height (ported applyLoreTowerPaint + NIGHT_RAMP / DAY_RAMP). Idempotent,
    /// guarded so a style without the layer yet never throws.
    static func applyPaint(to style: MLNStyle, mode: LoreMapLibreView.Mode) {
        guard let core = style.layer(withIdentifier: coreLayerID) as? MLNFillExtrusionStyleLayer else {
            return
        }
        core.fillExtrusionColor = colorRamp(for: mode)
        core.fillExtrusionOpacity = NSExpression(forConstantValue: mode == .day ? 0.82 : 0.94)
    }

    /// The height driver, our per-feature `height_m` (falling back to the 20m
    /// floor if somehow absent), ported coalesce(get height_m, MIN).
    private static func heightExpression(key: String) -> NSExpression {
        NSExpression(
            format: "mgl_coalesce(%@, %@)",
            NSExpression(forKeyPath: key),
            NSExpression(forConstantValue: minRealHeightM)
        ) // VERIFY: mgl_coalesce function spelling in NSExpression DSL (v6).
    }

    /// The Brass->Amber(->hot-Amber) color ramp interpolated on height_m, the
    /// two mode ramps from map3d.ts. Night is the cinematic signature; day is a
    /// quieter warm brass-washed stone so towers read as carved mass.
    private static func colorRamp(for mode: LoreMapLibreView.Mode) -> NSExpression {
        let stops: [Double: UIColor]
        if mode == .day {
            stops = [
                minRealHeightM: .hex(0xC9B187), // warm stone at the street
                140: .hex(0xC6A264),            // brass-washed mid-rise
                320: .hex(0xCFA150),            // quiet gilt crown
            ]
        } else {
            stops = [
                minRealHeightM: brass,
                140: amber,
                320: amberHot,
            ]
        }
        // VERIFY: mgl_interpolate:withCurveType:parameters:stops: DSL spelling (v6).
        return NSExpression(
            format: "mgl_interpolate:withCurveType:parameters:stops:(CAST(mgl_coalesce(height_m, %@), 'NSNumber'), 'linear', nil, %@)",
            NSNumber(value: minRealHeightM),
            stops as NSDictionary
        )
    }

    private static func constantBool(_ value: Bool) -> NSExpression {
        NSExpression(forConstantValue: NSNumber(value: value))
    }
}

// MARK: - LorePins (place pins as a symbol layer over point features)

/// The place pins. Rendered as one `MLNSymbolStyleLayer` over an
/// `MLNShapeSource` of `MLNPointFeature`s (one per place), sitting ABOVE the
/// tower extrusions so a tap always hits the pin, never a prism (docs/17 §2.1
/// note: canvas layers below, points above). Each feature carries its place id
/// so a tap can select it. Web uses HTML Markers; the native equivalent is a
/// symbol layer plus the coordinator's features query, which keeps every pin on
/// the GPU and one tap path. The Amber-fill/Ink-stroke pin styling from the
/// MapKit `PlacePinBadge` is approximated here with a text label (the emoji)
/// over a circle, kept minimal until a device pass can add a real image.
private enum LorePins {
    static let sourceID = "lore-place-pins"
    static let layerID = "lore-place-pins"
    /// Feature attribute key holding the place id (read on tap).
    static let idKey = "id"
    /// Feature attribute key holding the pin's emoji glyph.
    static let emojiKey = "emoji"

    /// Create or refresh the pin source + symbol layer for the places.
    static func update(on style: MLNStyle, places: [Place]) {
        let features: [MLNPointFeature] = places.map { place in
            let feature = MLNPointFeature()
            feature.coordinate = place.coordinate
            feature.attributes = [
                idKey: place.id,
                emojiKey: place.displayEmoji,
            ]
            return feature
        }
        let collection = MLNShapeCollectionFeature(shapes: features)

        if let existing = style.source(withIdentifier: sourceID) as? MLNShapeSource {
            existing.shape = collection
        } else {
            let source = MLNShapeSource(identifier: sourceID, shape: collection, options: nil)
            style.addSource(source)

            let layer = MLNSymbolStyleLayer(identifier: layerID, source: source)
            // The emoji glyph as the pin content. A device pass can swap this
            // for the compound Amber/Ink badge image; the tap + placement are
            // what matter here (docs/17 §3 native parity is partial by design).
            layer.text = NSExpression(forKeyPath: emojiKey)
            layer.textFontSize = NSExpression(forConstantValue: 20)
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.textAllowsOverlap = NSExpression(forConstantValue: true)
            style.addLayer(layer)
        }
    }
}

// MARK: - UIColor hex helper

private extension UIColor {
    /// `UIColor.hex(0x0F1626)`, sRGB, matching LoreColor's `Color(hex:)` so the
    /// native map palette is byte-for-byte the brand tokens.
    static func hex(_ hex: UInt32, alpha: CGFloat = 1.0) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}
