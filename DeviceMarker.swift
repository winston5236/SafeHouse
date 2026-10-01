//
//  DeviceMarker.swift
//
//  RoomPlan does not detect air conditioners or fans. This lets the user mark them by tapping the
//  live camera view DURING the scan. Taps are raycast in the same ARSession RoomPlan is running
//  (RoomCaptureSession.arSession), so the marks should share the coordinate space of the exported
//  CapturedRoom. The marks are added to the saved JSON under "devices".
//
//  AC: tap two OPPOSITE CORNERS of the unit. That gives its real size, so you do not have to hit its
//      exact shape. The page snaps it flat against the nearest wall.
//  Ceiling fan: tap the ceiling under the fan's center.
//  Floor fan: tap the floor where it stands.
//
//  Marks must be placed while the scan is running. NOT TESTED on a device. The index.html importer
//  warns when a marked AC is not near a wall, which shows whether the two coordinate spaces match.
//

import UIKit
import ARKit
import RoomPlan
import simd

final class DeviceMarker: NSObject {
    enum Kind: Int, CaseIterable {
        case ac, ceilingFan, fan
        var key: String { ["ac", "ceilingFan", "fan"][rawValue] }
        var title: String { ["AC", "Ceiling fan", "Floor fan"][rawValue] }
    }

    private(set) var marks: [[String: Any]] = []

    /// Set to true when the scan starts and false when it stops.
    var scanning = false {
        didSet {
            picker?.isEnabled = scanning
            if !scanning {
                picker?.selectedSegmentIndex = UISegmentedControl.noSegment
                cancelPending()
            }
        }
    }

    private weak var captureView: RoomCaptureView?
    private var picker: UISegmentedControl?
    private var summary: UILabel?
    private var onStatus: ((String) -> Void)?

    /// First corner of an AC that is waiting for its opposite corner.
    private var pendingFirst: (pos: SIMD3<Float>, normal: SIMD3<Float>)?
    private var dot: UIView?

    // MARK: UI

    func install(in host: UIView, captureView: RoomCaptureView, bottomOffset: CGFloat = 76,
                 onStatus: @escaping (String) -> Void) {
        self.captureView = captureView
        self.onStatus = onStatus

        let picker = UISegmentedControl(items: Kind.allCases.map { "Mark " + $0.title })
        picker.selectedSegmentIndex = UISegmentedControl.noSegment
        picker.isEnabled = false
        picker.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        picker.selectedSegmentTintColor = .systemBlue
        picker.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        picker.addTarget(self, action: #selector(kindChanged), for: .valueChanged)
        self.picker = picker

        let undo = UIButton(type: .system)
        undo.setTitle("Undo", for: .normal)
        undo.setTitleColor(.white, for: .normal)
        undo.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        undo.layer.cornerRadius = 8
        undo.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        undo.addTarget(self, action: #selector(undoTapped), for: .touchUpInside)

        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.layer.cornerRadius = 6
        label.layer.masksToBounds = true
        label.textAlignment = .center
        self.summary = label
        updateSummary()

        let row = UIStackView(arrangedSubviews: [picker, undo])
        row.spacing = 8
        let stack = UIStackView(arrangedSubviews: [label, row])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -bottomOffset),
        ])

        captureView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }

    // MARK: Marking

    func reset() {
        marks.removeAll()
        cancelPending()
        updateSummary()
    }

    @objc private func kindChanged() {
        cancelPending()
        guard let idx = picker?.selectedSegmentIndex, let kind = Kind(rawValue: idx) else { return }
        switch kind {
        case .ac: onStatus?("Tap one corner of the AC, then the opposite corner.")
        case .ceilingFan: onStatus?("Point up and tap the ceiling under the fan's center.")
        case .fan: onStatus?("Tap the floor where the fan stands.")
        }
    }

    @objc private func undoTapped() {
        if pendingFirst != nil { cancelPending(); onStatus?("Cancelled."); return }
        guard !marks.isEmpty else { return }
        marks.removeLast()
        updateSummary()
    }

    private func cancelPending() {
        pendingFirst = nil
        dot?.removeFromSuperview()
        dot = nil
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        guard scanning,
              let idx = picker?.selectedSegmentIndex, idx != UISegmentedControl.noSegment,
              let kind = Kind(rawValue: idx),
              let cv = captureView else { return }

        let session = cv.captureSession.arSession
        guard let frame = session.currentFrame else {
            onStatus?("Camera not ready yet.")
            return
        }

        // Screen point -> normalized image point (ARKit raycasts in camera-image space).
        let size = cv.bounds.size
        let p = g.location(in: cv)
        let orientation = cv.window?.windowScene?.interfaceOrientation ?? .portrait
        let normalizedView = CGPoint(x: p.x / size.width, y: p.y / size.height)
        let imagePoint = normalizedView.applying(
            frame.displayTransform(for: orientation, viewportSize: size).inverted())

        // Any alignment: an AC is small and shiny, so the ray often lands on the wall behind it or
        // on a surface whose estimated direction is off. The page snaps the AC to the real wall.
        let alignment: ARRaycastQuery.TargetAlignment = (kind == .ac) ? .any : .horizontal
        let query = frame.raycastQuery(from: imagePoint, allowing: .estimatedPlane, alignment: alignment)
        guard let hit = session.raycast(query).first else {
            onStatus?("No surface found there. Move closer, add light, and tap again.")
            return
        }

        let t = hit.worldTransform
        let pos = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        var n = SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z) // surface normal
        let c = frame.camera.transform.columns.3
        let cam = SIMD3<Float>(c.x, c.y, c.z)
        if simd_dot(n, cam - pos) < 0 { n = -n } // make the normal face the camera

        switch kind {
        case .ac:
            guard let first = pendingFirst else {
                pendingFirst = (pos, n)
                let d = UIView(frame: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16))
                d.backgroundColor = .systemYellow
                d.layer.cornerRadius = 8
                d.isUserInteractionEnabled = false
                cv.addSubview(d)
                dot = d
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onStatus?("Corner 1 set. Now tap the opposite corner of the AC.")
                return
            }
            let mid = (first.pos + pos) / 2
            let d = pos - first.pos
            let width = max(0.3, hypot(d.x, d.z))   // along the wall
            let height = max(0.15, abs(d.y))
            marks.append([
                "type": kind.key,
                "position": [Double(mid.x), Double(mid.y), Double(mid.z)],
                "normal": [Double(first.normal.x), Double(first.normal.y), Double(first.normal.z)],
                "size": [Double(width), Double(height)],
            ])
            cancelPending()
        case .ceilingFan:
            guard n.y < -0.7, pos.y > cam.y else {
                onStatus?("That doesn't look like the ceiling. Point up and tap under the fan.")
                return
            }
            marks.append(["type": kind.key,
                          "position": [Double(pos.x), Double(pos.y), Double(pos.z)],
                          "normal": [Double(n.x), Double(n.y), Double(n.z)]])
        case .fan:
            guard n.y > 0.7, pos.y < cam.y - 0.3 else {
                onStatus?("That doesn't look like the floor. Tap the floor where the fan stands.")
                return
            }
            marks.append(["type": kind.key,
                          "position": [Double(pos.x), Double(pos.y), Double(pos.z)],
                          "normal": [Double(n.x), Double(n.y), Double(n.z)]])
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        updateSummary()
        onStatus?("Marked \(kind.title).")
    }

    private func updateSummary() {
        let counts = Kind.allCases.map { k in marks.filter { ($0["type"] as? String) == k.key }.count }
        summary?.text = "  AC \(counts[0]) · Ceiling fan \(counts[1]) · Floor fan \(counts[2])  "
    }

    // MARK: Saving

    /// Adds the marks to the CapturedRoom JSON as a top-level "devices" array.
    func merge(into data: Data) throws -> Data {
        guard !marks.isEmpty,
              var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return data }
        obj["devices"] = marks
        return try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    }
}
