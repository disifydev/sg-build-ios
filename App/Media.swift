import SwiftUI
import Combine
import AVFoundation
import AVKit
import QuickLook
import Photos

// MARK: - запись голосового

/// Голосовое: AVAudioRecorder в m4a (AAC), уровень громкости для круга под кнопкой.
@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    @Published var recording = false
    @Published var locked = false
    @Published var level: CGFloat = 0
    @Published var elapsed: Double = 0
    @Published var blink = false

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var started = Date()
    private var url: URL?
    private var camera = false
    private var ticks = 0

    var timeText: String {
        let t = elapsed
        return "\(Int(t) / 60):" + String(format: "%02d", Int(t) % 60) + ",\(Int((t - floor(t)) * 10))"
    }

    func start(withCamera: Bool) {
        camera = withCamera
        locked = false
        elapsed = 0
        started = Date()
        recording = true
        if !withCamera {
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in
                    if granted { self.beginAudio() } else { self.cancel() }
                }
            }
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func beginAudio() {
        guard recording else { return }
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try s.setActive(true)
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
                                           AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
            let r = try AVAudioRecorder(url: u, settings: settings)
            r.isMeteringEnabled = true
            r.record()
            recorder = r
            url = u
        } catch {
            cancel()
        }
    }

    private func tick() {
        guard recording else { return }
        elapsed = Date().timeIntervalSince(started)
        ticks += 1
        if ticks % 10 == 0 { blink.toggle() }
        if let r = recorder {
            r.updateMeters()
            let db = r.averagePower(forChannel: 0)
            level = CGFloat(max(0, min(1, (db + 50) / 50)))
        } else {
            level = CGFloat.random(in: 0...0.8)
        }
        if camera && elapsed >= 60 { NotificationCenter.default.post(name: .circleLimit, object: nil) }
    }

    func stop() -> URL? {
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        recording = false
        locked = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return url
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil
        timer?.invalidate()
        recording = false
        locked = false
    }

    /// Для снимка: запись идёт и закреплена на замочке.
    func demo() {
        recording = true
        locked = true
        elapsed = 4.3
        level = 0.5
    }
}

extension Notification.Name {
    static let circleLimit = Notification.Name("sguardo.circleLimit")
}

// MARK: - запись кружка

/// Кружок: фронтальная камера и микрофон → mp4, затем обрезка в квадрат. Вспышка, смена камеры.
final class CircleRecorder: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published var active = false
    @Published var front = true
    @Published var flash = false
    @Published var running = false

    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "circle.camera")
    private var videoInput: AVCaptureDeviceInput?
    private var completion: ((URL?) -> Void)?
    private var sendOnFinish = false

    func start() {
        active = true
        flash = false
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { DispatchQueue.main.async { self.active = false }; return }
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                self.queue.async { self.configureAndRecord() }
            }
        }
    }

    private func device(front: Bool) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back)
    }

    private func configureAndRecord() {
        session.beginConfiguration()
        session.sessionPreset = .high
        for i in session.inputs { session.removeInput(i) }
        if let d = device(front: front), let i = try? AVCaptureDeviceInput(device: d), session.canAddInput(i) {
            session.addInput(i)
            videoInput = i
        }
        if let mic = AVCaptureDevice.default(for: .audio), let i = try? AVCaptureDeviceInput(device: mic), session.canAddInput(i) {
            session.addInput(i)
        }
        if !session.outputs.contains(output), session.canAddOutput(output) { session.addOutput(output) }
        output.maxRecordedDuration = CMTime(seconds: 62, preferredTimescale: 600)
        applyConnection()
        session.commitConfiguration()
        if !session.isRunning { session.startRunning() }
        DispatchQueue.main.async { self.running = self.session.isRunning }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("circle-\(UUID().uuidString).mov")
        if !output.isRecording { output.startRecording(to: u, recordingDelegate: self) }
    }

    private func applyConnection() {
        guard let c = output.connection(with: .video) else { return }
        if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
        if c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = front }
    }

    func flip() {
        front.toggle()
        let f = front
        queue.async {
            self.session.beginConfiguration()
            if let old = self.videoInput { self.session.removeInput(old) }
            if let d = self.device(front: f), let i = try? AVCaptureDeviceInput(device: d), self.session.canAddInput(i) {
                self.session.addInput(i)
                self.videoInput = i
            }
            self.applyConnection()
            self.session.commitConfiguration()
            self.setTorch()
        }
    }

    /// Вспышка: у задней камеры — фонарик, у фронтальной — белый экран.
    func toggleFlash() {
        flash.toggle()
        queue.async { self.setTorch() }
    }

    private func setTorch() {
        guard let d = videoInput?.device, d.hasTorch else { return }
        try? d.lockForConfiguration()
        d.torchMode = (flash && !front) ? .on : .off
        d.unlockForConfiguration()
    }

    func stop(send: Bool, done: ((URL?) -> Void)? = nil) {
        guard active else { return }
        sendOnFinish = send
        completion = done
        DispatchQueue.main.async { self.active = false; self.flash = false }
        queue.async {
            if self.output.isRecording { self.output.stopRecording() } else { self.finish(nil) }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        queue.async { self.session.stopRunning() }
        DispatchQueue.main.async { self.running = false }
        guard sendOnFinish else { try? FileManager.default.removeItem(at: url); finish(nil); return }
        CircleRecorder.cropSquare(url) { out in self.finish(out) }
    }

    private func finish(_ url: URL?) {
        let c = completion
        completion = nil
        DispatchQueue.main.async { c?(url) }
    }

    /// Квадрат по центру кадра (как кружок в Telegram).
    static func cropSquare(_ url: URL, done: @escaping (URL?) -> Void) {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { done(url); return }
        let t = track.preferredTransform
        let size = track.naturalSize.applying(t)
        let w = abs(size.width), h = abs(size.height), side = min(w, h)
        let comp = AVMutableVideoComposition()
        comp.renderSize = CGSize(width: side, height: side)
        comp.frameDuration = CMTime(value: 1, timescale: 30)
        let instr = AVMutableVideoCompositionInstruction()
        instr.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(t.concatenating(CGAffineTransform(translationX: -(w - side) / 2, y: -(h - side) / 2)), at: .zero)
        instr.layerInstructions = [layer]
        comp.instructions = [instr]
        guard let exp = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else { done(url); return }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("circle-\(UUID().uuidString).mp4")
        exp.videoComposition = comp
        exp.outputURL = out
        exp.outputFileType = .mp4
        exp.shouldOptimizeForNetworkUse = true
        exp.exportAsynchronously {
            done(exp.status == .completed ? out : url)
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.layer2.session = session
        v.layer2.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var layer2: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// Экран записи кружка (.cvr): размытие, круглый кадр, кольцо минуты, вспышка и смена камеры.
struct CircleOverlay: View {
    @ObservedObject var cam: CircleRecorder
    var demo = false
    @State private var progress: CGFloat = 0
    @State private var appear = false
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(cam.flash ? Color(hex: 0xFFFAF0).opacity(0.6) : Color(hex: 0x060C0C).opacity(0.5))
                .ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .opacity(0)
                    Circle().trim(from: 0, to: progress)
                        .stroke(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 300, height: 300)
                    Group {
                        if demo || !cam.running { CamPlaceholder(back: !cam.front) } else { CameraPreview(session: cam.session) }
                    }
                    .frame(width: 276, height: 276)
                    .clipShape(Circle())
                    .shadow(color: cam.flash ? .white : .clear, radius: cam.flash ? 50 : 0)
                    .overlay(Circle().stroke(Color.white.opacity(cam.flash ? 0.95 : 0), lineWidth: 16).padding(-8))
                    .scaleEffect(appear ? 1 : 0.12, anchor: .bottomTrailing)
                }
                .frame(width: 300, height: 300)
                .padding(.top, 58)
                HStack(spacing: 26) {
                    tool("bolt", on: cam.flash) { cam.toggleFlash() }
                    tool("flip", on: false) { cam.flip() }
                }
                .padding(.top, 14)
                .opacity(appear ? 1 : 0)
                Text("Смахните вверх, чтобы записывать без рук").font(Typo.body(13.5))
                    .foregroundStyle(cam.flash ? Th.ink : Color.white.opacity(0.88))
                    .multilineTextAlignment(.center).padding(.horizontal, 30).padding(.top, 18)
            }
        }
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { appear = true }; if demo { progress = 0.18 } }
        .onReceive(timer) { _ in if !demo { progress = min(1, progress + 0.1 / 60) } }
        .transition(.opacity)
    }

    private func tool(_ icon: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button { haptic(); action() } label: {
            Icon(name: icon).foregroundStyle(on ? Color(hex: 0x111111) : .white)
                .frame(width: 54, height: 54)
                .background(Circle().fill(on ? Color.white : Color.white.opacity(0.18)))
                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(icon == "bolt" ? "Вспышка" : "Перевернуть камеру")
    }
}

/// Нарисованный «кадр камеры» для демо и до запуска камеры (как .cam макета).
struct CamPlaceholder: View {
    var back = false
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                if back {
                    LinearGradient(colors: [Color(hex: 0xA7C2C8), Color(hex: 0xE6DFD0)], startPoint: .top, endPoint: .bottom)
                    Rectangle().fill(Color(hex: 0x6F5A47)).frame(height: h * 0.36).frame(maxHeight: .infinity, alignment: .bottom)
                    Ellipse().fill(Color(hex: 0xF7F1E4)).frame(width: w * 0.36, height: h * 0.52).position(x: w * 0.72, y: h * 0.34)
                } else {
                    LinearGradient(colors: [Color(hex: 0xD9CCB6), Color(hex: 0x8FA9A4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Ellipse().fill(Color(hex: 0x2E5256)).frame(width: w * 0.9, height: h * 0.6).position(x: w / 2, y: h * 1.04)
                    Ellipse().fill(Color(hex: 0x3B2A22)).frame(width: w * 0.46, height: h * 0.54).position(x: w / 2, y: h * 0.4)
                    Ellipse().fill(Color(hex: 0xE2BFA4)).frame(width: w * 0.34, height: h * 0.44).position(x: w / 2, y: h * 0.47)
                }
            }
        }
    }
}

// MARK: - голосовое в ленте

struct VoiceBubble: View {
    @Environment(Store.self) private var store
    let m: Message
    let out: Bool
    @State private var player: AVPlayer?
    @State private var playing = false
    @State private var pos: Double = 0
    @State private var observer: Any?

    var body: some View {
        let a = m.att
        let dur = a?.duration ?? 0
        let bars = wave(a)
        HStack(spacing: 10) {
            Button { toggle() } label: {
                Icon(name: playing ? "pause" : "play", size: 16)
                    .foregroundStyle(out ? Th.bubOut : Th.onTeal)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(out ? Th.bubOutFg : Th.teal))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(playing ? "Пауза" : "Слушать")
            HStack(alignment: .center, spacing: 2) {
                ForEach(bars.indices, id: \.self) { i in
                    Capsule().fill(out ? Th.bubOutFg : Th.fg)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(3, 28 * bars[i]))
                        .opacity(dur > 0 && Double(i) / Double(bars.count) < pos / dur ? 1 : 0.35)
                }
            }
            .frame(height: 28)
            Text(Fmt.dur(playing ? pos : dur)).font(Typo.body(11)).monospacedDigit().foregroundStyle((out ? Th.bubOutFg : Th.fg).opacity(0.7))
                .frame(minWidth: 28)
        }
        .padding(.vertical, 2)
        .onDisappear { player?.pause(); playing = false }
    }

    private func wave(_ a: Attachment?) -> [CGFloat] {
        if let w = a?.waveform, !w.isEmpty {
            let n = 26
            return (0..<n).map { i in
                let v = w[min(w.count - 1, i * w.count / n)]
                return CGFloat(max(0.12, min(1, v / 31)))
            }
        }
        let seed = m.id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return (0..<26).map { k in CGFloat(0.25 + abs(sin(Double(k) * 1.7 + Double(seed))) * 0.7) }
    }

    private func toggle() {
        if m.att?.url.hasPrefix("fixture:") == true { demoPlay(); return }
        guard let a = m.att, let url = API.media(a.url) else { return }
        if player == nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            let item = AVPlayerItem(asset: AVURLAsset(url: url, options: API.assetOptions(for: url)))
            let p = AVPlayer(playerItem: item)
            observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { t in
                Task { @MainActor in pos = t.seconds }
            }
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                Task { @MainActor in
                    playing = false
                    pos = 0
                    player?.seek(to: .zero)
                }
            }
            player = p
        }
        if playing { player?.pause() } else { player?.play() }
        playing.toggle()
    }

    private func demoPlay() {
        playing.toggle()
        guard playing else { return }
        Task { @MainActor in
            let d = m.att?.duration ?? 5
            while playing && pos < d {
                try? await Task.sleep(nanoseconds: 100_000_000)
                pos += 0.1
            }
            playing = false
            pos = 0
        }
    }
}

// MARK: - фото, видео, файлы

/// Бумага в линейку — заглушка фото в демо (NOTE_BG макета).
struct NotePaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xF6F0E3), Color(hex: 0xE6D9C2)], startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { g in
                Path { p in
                    var y: CGFloat = 15
                    while y < g.size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: g.size.width, y: y)); y += 16 }
                }
                .stroke(Color(red: 70 / 255, green: 100 / 255, blue: 130 / 255).opacity(0.25), lineWidth: 1)
            }
        }
    }
}

struct PhotoThumb: View {
    let a: Attachment
    var interactive = true
    @State private var preview: URL?
    @State private var busy = false

    var body: some View {
        ZStack {
            if a.url.hasPrefix("fixture:") {
                demoFill
            } else {
                AsyncImage(url: API.media(a.url)) { ph in
                    switch ph {
                    case .success(let img): img.resizable().scaledToFill()
                    case .failure: Th.fill8.overlay(Icon(name: "image").foregroundStyle(Th.muted))
                    default: Th.fill6.overlay(ProgressView())
                    }
                }
            }
            if busy { ProgressView().tint(.white) }
        }
        .contentShape(Rectangle())
        .onTapGesture { if interactive { Task { await open() } } }
        .quickLookPreview($preview)
        .accessibilityLabel("Фото")
    }

    @ViewBuilder private var demoFill: some View {
        let k = a.url.replacingOccurrences(of: "fixture:", with: "")
        if let i = Int(k), i < galleryGradients.count { galleryGradients[i] } else { NotePaper() }
    }

    private func open() async {
        guard let url = API.media(a.url) else { return }
        busy = true
        defer { busy = false }
        preview = try? await MediaSaver.download(url, name: a.name ?? "photo.jpg")
    }
}

let galleryGradients: [LinearGradient] = [
    LinearGradient(colors: [Color(hex: 0xF2C7B0), Color(hex: 0xC46F5A)], startPoint: .topLeading, endPoint: .bottomTrailing),
    LinearGradient(colors: [Color(hex: 0xC3DAE3), Color(hex: 0x4E7F8F)], startPoint: .top, endPoint: .bottom),
    LinearGradient(colors: [Color(hex: 0xF0DDA8), Color(hex: 0xB88A2E)], startPoint: .topLeading, endPoint: .bottomTrailing),
    LinearGradient(colors: [Color(hex: 0xD9D0EC), Color(hex: 0x6B5A9A)], startPoint: .topTrailing, endPoint: .bottomLeading),
    LinearGradient(colors: [Color(hex: 0xBFE0CF), Color(hex: 0x2E7A5A)], startPoint: .topLeading, endPoint: .bottomTrailing),
    LinearGradient(colors: [Color(hex: 0xEFC0BC), Color(hex: 0x8E3A3A)], startPoint: .top, endPoint: .bottom),
]

/// Первый кадр видео (с кукой сессии для своего хоста).
@MainActor
final class Thumbs {
    static var cache: [String: UIImage] = [:]
    static func frame(_ url: URL) async -> UIImage? {
        if let i = cache[url.absoluteString] { return i }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url, options: API.assetOptions(for: url)))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 600, height: 600)
        guard let cg = try? await gen.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image else { return nil }
        let img = UIImage(cgImage: cg)
        cache[url.absoluteString] = img
        return img
    }
}

struct VideoThumb: View {
    let a: Attachment
    var interactive = true
    @State private var img: UIImage?
    @State private var play: URL?

    var body: some View {
        ZStack {
            if let img { Image(uiImage: img).resizable().scaledToFill() } else { Th.fill8 }
            Icon(name: "play", size: 22).foregroundStyle(.white)
                .frame(width: 48, height: 48).background(Circle().fill(Color.black.opacity(0.35)))
        }
        .contentShape(Rectangle())
        .onTapGesture { if interactive { play = API.media(a.url) } }
        .task { if let u = API.media(a.url) { img = await Thumbs.frame(u) } }
        .fullScreenCover(item: Binding(get: { play.map { URLBox(url: $0) } }, set: { play = $0?.url })) { box in
            VideoPlayer(player: AVPlayer(playerItem: AVPlayerItem(asset: AVURLAsset(url: box.url, options: API.assetOptions(for: box.url)))))
                .ignoresSafeArea()
                .overlay(alignment: .topLeading) {
                    GlassCircle(icon: "x", label: "Закрыть") { play = nil }.padding(16)
                }
        }
        .accessibilityLabel("Видео")
    }
}

struct URLBox: Identifiable { let url: URL; var id: String { url.absoluteString } }

/// Кружок в ленте (.cvm): круг 200, при воспроизведении 244, кольцо прогресса, длительность.
struct RoundVideo: View {
    let m: Message
    var interactive = true
    @State private var img: UIImage?
    @State private var player: AVPlayer?
    @State private var playing = false
    @State private var progress: Double = 0
    @State private var observer: Any?

    var body: some View {
        let a = m.att
        let size: CGFloat = playing ? 244 : 200
        ZStack {
            Group {
                if a?.url.hasPrefix("fixture:") == true { CamPlaceholder(back: a?.url == "fixture:back") }
                else if playing, let player { PlayerLayerView(player: player) }
                else if let img { Image(uiImage: img).resizable().scaledToFill() }
                else { Th.fill8 }
            }
            Circle().trim(from: 0, to: progress).stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(2)
            if !playing {
                Icon(name: "play", size: 22).foregroundStyle(.white)
                    .frame(width: 48, height: 48).background(Circle().fill(Color.black.opacity(0.35)))
            }
            VStack {
                Spacer()
                HStack(spacing: 3) {
                    Text(Fmt.dur(a?.duration ?? 0)).monospacedDigit()
                    if m.isOut { Icon(name: m.pending == true ? "clock" : "checks", size: 13) }
                }
                .font(Typo.body(11.5)).foregroundStyle(.white)
                .padding(.horizontal, 9).frame(height: 22)
                .background(Capsule().fill(Color.black.opacity(0.4)))
                .padding(.bottom, 12)
            }
            if let r = m.reactions?.first {
                Text(r.emoji).font(.system(size: 14)).padding(.horizontal, 8).frame(height: 24)
                    .background(Capsule().fill(Color.black.opacity(0.4)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 18).padding(.bottom, 16)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.25), radius: 9, y: 6)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: playing)
        .contentShape(Circle())
        .onTapGesture { if interactive { toggle() } }
        .task { if let a, let u = API.media(a.url), !a.url.hasPrefix("fixture:") { img = await Thumbs.frame(u) } }
        .onDisappear { player?.pause(); playing = false }
        .accessibilityLabel("Видеосообщение")
    }

    private func toggle() {
        guard let a = m.att else { return }
        if a.url.hasPrefix("fixture:") {
            playing.toggle()
            withAnimation(.linear(duration: playing ? (a.duration ?? 5) : 0)) { progress = playing ? 1 : 0 }
            return
        }
        guard let url = API.media(a.url) else { return }
        if player == nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            let item = AVPlayerItem(asset: AVURLAsset(url: url, options: API.assetOptions(for: url)))
            let p = AVPlayer(playerItem: item)
            observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { t in
                Task { @MainActor in
                    let d = p.currentItem?.duration.seconds ?? 0
                    progress = d > 0 && d.isFinite ? t.seconds / d : 0
                }
            }
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                Task { @MainActor in playing = false; progress = 0; player?.seek(to: .zero) }
            }
            player = p
        }
        if playing { player?.pause() } else { player?.play() }
        playing.toggle()
    }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PV {
        let v = PV()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PV, context: Context) { uiView.playerLayer.player = player }
    final class PV: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

struct FileRow: View {
    let a: Attachment
    let out: Bool
    var interactive = true
    @State private var preview: URL?
    @State private var busy = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(out ? Th.bubOutFg : Th.teal)
                if busy { ProgressView() } else { Icon(name: "file").foregroundStyle(out ? Th.bubOut : Th.onTeal) }
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(a.name ?? "Файл").font(Typo.body(14, .semibold)).lineLimit(2)
                Text(ext).font(Typo.body(12)).opacity(0.7)
            }
            .foregroundStyle(out ? Th.bubOutFg : Th.fg)
        }
        .frame(minWidth: 210, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if interactive { Task { await open() } } }
        .quickLookPreview($preview)
    }

    private var ext: String {
        let n = a.name ?? ""
        if let dot = n.lastIndex(of: ".") { return String(n[n.index(after: dot)...]).uppercased() }
        return a.mime ?? "файл"
    }

    private func open() async {
        guard let url = API.media(a.url) else { return }
        busy = true
        defer { busy = false }
        preview = try? await MediaSaver.download(url, name: a.name ?? "file")
    }
}

// MARK: - сохранение

enum MediaSaver {
    static func download(_ url: URL, name: String) async throws -> URL {
        let data = try await API.download(url)
        let safe = name.replacingOccurrences(of: "/", with: "_")
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(String(UUID().uuidString.prefix(6)) + "-" + safe)
        try data.write(to: dest)
        return dest
    }

    /// Фото и видео — в галерею, голосовое и файлы — через «Поделиться» (можно в «Файлы»).
    @MainActor
    static func save(_ m: Message, store: Store) async {
        guard let a = m.att else { return }
        if store.fixture || a.url.hasPrefix("fixture:") {
            store.show(["image": "Фото сохранено в галерею", "video": "Видео сохранено в галерею", "round": "Видео сохранено в галерею", "audio": "Аудио сохранено в файлы"][m.kind] ?? "Файл сохранён")
            return
        }
        guard let url = API.media(a.url) else { return }
        do {
            let file = try await download(url, name: a.name ?? (a.kind == "image" ? "photo.jpg" : a.kind == "video" ? "video.mp4" : "file"))
            switch a.kind {
            case "image", "video":
                let st = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard st == .authorized || st == .limited else { store.show("Нет доступа к галерее. Разрешите в настройках iPhone", ok: false); return }
                try await PHPhotoLibrary.shared().performChanges {
                    if a.kind == "image" { _ = PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: file) }
                    else { _ = PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: file) }
                }
                store.show(a.kind == "image" ? "Фото сохранено в галерею" : "Видео сохранено в галерею")
            default:
                share([file])
            }
        } catch {
            store.show("Не получилось сохранить", ok: false)
        }
    }

    @MainActor
    static func share(_ items: [Any]) {
        guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        top.present(UIActivityViewController(activityItems: items, applicationActivities: nil), animated: true)
    }
}
