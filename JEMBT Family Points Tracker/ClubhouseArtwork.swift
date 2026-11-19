import SwiftUI

enum ClubhouseScene: CaseIterable, Identifiable {
    case family, store, rules, ledger, stats

    var id: Self { self }
}

enum ClubhouseArtworkIntensity {
    case quiet, standard

    var artworkOpacity: Double {
        switch self {
        case .quiet: 0.42
        case .standard: 0.68
        }
    }
}

struct ClubhouseBackdrop: View {
    let scene: ClubhouseScene
    var intensity: ClubhouseArtworkIntensity = .quiet

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isWide: Bool { horizontalSizeClass == .regular }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: palette,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                architecturalLayer(size: proxy.size)
                    .opacity(effectiveArtworkOpacity)

                sceneLayer(size: proxy.size)
                    .opacity(effectiveArtworkOpacity)

                readabilityScrim
            }
            .clipped()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var palette: [Color] {
        let dark = colorScheme == .dark
        switch scene {
        case .family:
            return dark ? [Color(red: 0.10, green: 0.13, blue: 0.18), Color(red: 0.20, green: 0.12, blue: 0.12)]
                : [Color(red: 0.94, green: 0.85, blue: 0.69), Color(red: 0.74, green: 0.84, blue: 0.78)]
        case .store:
            return dark ? [Color(red: 0.15, green: 0.10, blue: 0.22), Color(red: 0.08, green: 0.16, blue: 0.18)]
                : [Color(red: 0.93, green: 0.82, blue: 0.63), Color(red: 0.73, green: 0.64, blue: 0.88)]
        case .rules:
            return dark ? [Color(red: 0.17, green: 0.12, blue: 0.08), Color(red: 0.10, green: 0.15, blue: 0.16)]
                : [Color(red: 0.86, green: 0.70, blue: 0.47), Color(red: 0.76, green: 0.86, blue: 0.75)]
        case .ledger:
            return dark ? [Color(red: 0.08, green: 0.13, blue: 0.17), Color(red: 0.16, green: 0.12, blue: 0.09)]
                : [Color(red: 0.77, green: 0.88, blue: 0.90), Color(red: 0.90, green: 0.78, blue: 0.62)]
        case .stats:
            return dark ? [Color(red: 0.12, green: 0.11, blue: 0.21), Color(red: 0.18, green: 0.13, blue: 0.08)]
                : [Color(red: 0.83, green: 0.80, blue: 0.95), Color(red: 0.94, green: 0.83, blue: 0.58)]
        }
    }

    private var effectiveArtworkOpacity: Double {
        let contrastMultiplier = contrast == .increased ? 0.62 : 1.0
        return intensity.artworkOpacity * contrastMultiplier
    }

    @ViewBuilder
    private var readabilityScrim: some View {
        if reduceTransparency {
            Color(uiColor: .systemBackground).opacity(0.88)
        } else if contrast == .increased {
            Color(uiColor: .systemBackground).opacity(0.70)
        } else {
            Color(uiColor: .systemBackground).opacity(readabilityOpacity)
        }
    }

    private var readabilityOpacity: Double {
        switch intensity {
        case .quiet: 0.54
        case .standard: 0.38
        }
    }

    private func architecturalLayer(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let floorY = canvasSize.height * 0.72
            let line = Color.primary.opacity(0.14)
            context.fill(Path(CGRect(x: 0, y: floorY, width: canvasSize.width, height: canvasSize.height - floorY)), with: .color(Color.brown.opacity(0.16)))
            context.stroke(Path { path in
                path.move(to: CGPoint(x: 0, y: floorY))
                path.addLine(to: CGPoint(x: canvasSize.width, y: floorY))
                stride(from: 0.0, through: canvasSize.width, by: 72).forEach { x in
                    path.move(to: CGPoint(x: x, y: floorY))
                    path.addLine(to: CGPoint(x: x + 34, y: canvasSize.height))
                }
            }, with: .color(line), lineWidth: 1)

            if scene == .rules {
                let board = CGRect(x: canvasSize.width * 0.08, y: canvasSize.height * 0.10, width: canvasSize.width * 0.84, height: canvasSize.height * 0.45)
                context.fill(Path(roundedRect: board, cornerRadius: 18), with: .color(Color.brown.opacity(0.32)))
                context.stroke(Path(roundedRect: board.insetBy(dx: 7, dy: 7), cornerRadius: 12), with: .color(Color.orange.opacity(0.34)), lineWidth: 3)
            }
        }
    }

    @ViewBuilder
    private func sceneLayer(size: CGSize) -> some View {
        let gutter = isWide ? min(size.width * 0.12, 120) : 8.0
        switch scene {
        case .family:
            FramedFamilyPortrait()
                .frame(width: isWide ? 156 : 104, height: isWide ? 132 : 88)
                .position(x: gutter + (isWide ? 78 : 34), y: isWide ? 132 : 104)
            TeenageBaseballPlayerArtwork()
                .frame(width: isWide ? 170 : 112, height: isWide ? 230 : 154)
                .position(x: size.width - gutter - (isWide ? 82 : 40), y: isWide ? 220 : size.height * 0.57)
            PetCameo()
                .frame(width: 76, height: 60)
                .position(x: gutter + 38, y: size.height - 82)
        case .store:
            ShelfEasterEggs()
                .frame(width: isWide ? 220 : 142, height: 126)
                .position(x: size.width - gutter - (isWide ? 100 : 44), y: size.height - 104)
            StarTokenJar()
                .frame(width: 70, height: 94)
                .position(x: gutter + 36, y: size.height * 0.42)
        case .rules:
            BulletinNotes()
                .padding(.horizontal, gutter + 18)
                .padding(.top, isWide ? 94 : 76)
                .frame(maxHeight: .infinity, alignment: .top)
            Image(systemName: "paperplane.fill")
                .font(.system(size: isWide ? 74 : 48))
                .rotationEffect(.degrees(-14))
                .foregroundStyle(.blue.opacity(0.48))
                .position(x: size.width - gutter - 34, y: size.height - 94)
        case .ledger:
            DeskEasterEggs()
                .frame(width: isWide ? 250 : 160, height: 130)
                .position(x: size.width - gutter - (isWide ? 110 : 52), y: size.height - 96)
            StarTokenJar()
                .frame(width: 60, height: 82)
                .position(x: gutter + 32, y: size.height - 90)
        case .stats:
            TrophyNookArtwork()
                .frame(width: isWide ? 270 : 174, height: 190)
                .position(x: size.width - gutter - (isWide ? 120 : 58), y: isWide ? 174 : 148)
            TeenageBaseballPlayerArtwork()
                .frame(width: isWide ? 90 : 64, height: isWide ? 120 : 86)
                .position(x: gutter + 42, y: size.height - 92)
        }
    }
}

struct FramedFamilyPortrait: View {
    var body: some View {
        Image("FamilyPageWallpaper")
            .resizable()
            .scaledToFill()
            .clipped()
            .overlay { Rectangle().stroke(Color.white.opacity(0.72), lineWidth: 4) }
            .padding(9)
            .background(Color.brown.gradient, in: RoundedRectangle(cornerRadius: 7))
            .shadow(color: .black.opacity(0.26), radius: 5, y: 3)
            .rotationEffect(.degrees(-2))
    }
}

struct TeenageBaseballPlayerArtwork: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Capsule()
                    .fill(Color.brown.gradient)
                    .frame(width: w * 0.08, height: h * 0.76)
                    .rotationEffect(.degrees(15))
                    .offset(x: w * 0.30, y: h * 0.04)
                RoundedRectangle(cornerRadius: w * 0.12)
                    .fill(Color.indigo.gradient)
                    .frame(width: w * 0.38, height: h * 0.42)
                    .rotationEffect(.degrees(-10))
                    .offset(x: w * 0.24, y: h * 0.17)
                Capsule().fill(Color.primary.opacity(0.72)).frame(width: w * 0.13, height: h * 0.42).rotationEffect(.degrees(10)).offset(x: -w * 0.13, y: h * 0.32)
                Capsule().fill(Color.primary.opacity(0.72)).frame(width: w * 0.13, height: h * 0.42).rotationEffect(.degrees(-7)).offset(x: w * 0.12, y: h * 0.32)
                RoundedRectangle(cornerRadius: w * 0.16)
                    .fill(Color(red: 0.90, green: 0.90, blue: 0.84).gradient)
                    .frame(width: w * 0.58, height: h * 0.43)
                    .overlay(alignment: .bottomLeading) {
                        Circle().fill(Color.brown.opacity(0.25)).frame(width: w * 0.12).offset(x: w * 0.08, y: -h * 0.06)
                    }
                    .offset(y: h * 0.02)
                Circle().fill(Color(red: 0.68, green: 0.45, blue: 0.30)).frame(width: w * 0.38).offset(y: -h * 0.29)
                Capsule().fill(Color(red: 0.20, green: 0.28, blue: 0.42)).frame(width: w * 0.44, height: h * 0.11).offset(x: w * 0.04, y: -h * 0.39)
                Capsule().fill(Color(red: 0.22, green: 0.30, blue: 0.45)).frame(width: w * 0.30, height: h * 0.04).offset(x: w * 0.17, y: -h * 0.35)
                Capsule().fill(Color.indigo.opacity(0.85)).frame(width: w * 0.06, height: h * 0.58).rotationEffect(.degrees(-27)).offset(x: w * 0.10, y: -h * 0.02)
            }
        }
        .padding(4)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.brown.opacity(0.65), lineWidth: 5) }
        .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
        .rotationEffect(.degrees(2))
    }
}

private struct StarTokenJar: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(.blue.opacity(0.12)).overlay { RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.8), lineWidth: 2) }
            VStack(spacing: 4) {
                ForEach(0..<3) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<(row + 2), id: \.self) { _ in Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    }
                }
            }.padding(.top, 12)
        }
        .overlay(alignment: .top) { Capsule().fill(.gray).frame(height: 10).padding(.horizontal, 5) }
    }
}

private struct PetCameo: View {
    var body: some View {
        ZStack {
            Ellipse().fill(Color.orange.gradient).frame(width: 58, height: 38).offset(y: 9)
            Circle().fill(Color.orange.gradient).frame(width: 38).offset(x: 18, y: -8)
            Image(systemName: "pawprint.fill").foregroundStyle(.brown.opacity(0.55)).offset(x: -8, y: 10)
        }
    }
}

private struct ShelfEasterEggs: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4).fill(Color.brown.gradient).frame(height: 13)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(["book.closed.fill", "dice.fill", "baseball.fill", "puzzlepiece.fill"], id: \.self) { symbol in
                    Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(symbol == "baseball.fill" ? .red : .indigo)
                }
            }.padding(.bottom, 15)
        }
    }
}

private struct BulletinNotes: View {
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(Array([Color.yellow, .mint, .pink].enumerated()), id: \.offset) { index, color in
                RoundedRectangle(cornerRadius: 5)
                    .fill(color.opacity(0.72))
                    .frame(maxWidth: 130, minHeight: 86, maxHeight: 116)
                    .overlay { Image(systemName: "checklist").font(.title).foregroundStyle(.primary.opacity(0.32)) }
                    .rotationEffect(.degrees(index == 1 ? 2 : -2))
            }
        }
    }
}

private struct DeskEasterEggs: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 8).fill(Color.brown.gradient).frame(height: 25)
            HStack(alignment: .bottom, spacing: 14) {
                Image(systemName: "book.pages.fill").font(.system(size: 48)).foregroundStyle(.blue)
                Image(systemName: "pencil.and.ruler.fill").font(.system(size: 38)).foregroundStyle(.orange)
                Image(systemName: "paperplane.fill").font(.system(size: 34)).foregroundStyle(.white)
            }.padding(.bottom, 20)
        }
    }
}

private struct TrophyNookArtwork: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 10).fill(Color.brown.gradient).frame(height: 18)
            HStack(alignment: .bottom, spacing: 18) {
                Image(systemName: "medal.fill").font(.system(size: 44)).foregroundStyle(.orange)
                Image(systemName: "trophy.fill").font(.system(size: 72)).foregroundStyle(.yellow)
                Image(systemName: "star.circle.fill").font(.system(size: 42)).foregroundStyle(.purple)
            }.padding(.bottom, 20)
        }
    }
}

private struct ClubhouseSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background(
            reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(.regularMaterial),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

extension View {
    func clubhouseSurface() -> some View { modifier(ClubhouseSurfaceModifier()) }
}

#Preview("Five Clubhouse Scenes") {
    TabView {
        ForEach(ClubhouseScene.allCases) { scene in
            ClubhouseBackdrop(scene: scene, intensity: .standard)
                .overlay(alignment: .bottom) { Text(String(describing: scene).capitalized).padding().clubhouseSurface().padding() }
                .tabItem { Text(String(describing: scene).capitalized) }
        }
    }
}
