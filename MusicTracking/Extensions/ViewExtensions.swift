import SwiftUI

// MARK: - Pull to Refresh

public struct PullToRefreshModifier: ViewModifier {
    let action: () async -> Void
    
    public func body(content: Content) -> some View {
        content
            .refreshable {
                await action()
            }
    }
}

extension View {
    public func pullToRefresh(action: @escaping () async -> Void) -> some View {
        modifier(PullToRefreshModifier(action: action))
    }
}

// MARK: - Loading Overlay

public struct LoadingOverlayModifier: ViewModifier {
    let isLoading: Bool
    let message: String
    
    public init(isLoading: Bool, message: String = "Loading...") {
        self.isLoading = isLoading
        self.message = message
    }
    
    public func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isLoading {
                        LoadingOverlay(message: message)
                    }
                }
            )
    }
}

private struct LoadingOverlay: View {
    let message: String
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                
                Text(message)
                    .font(.callout)
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(.regularMaterial)
            .cornerRadius(12)
        }
    }
}

extension View {
    public func loadingOverlay(isLoading: Bool, message: String = "Loading...") -> some View {
        modifier(LoadingOverlayModifier(isLoading: isLoading, message: message))
    }
}

// MARK: - Conditional View Modifier

extension View {
    @ViewBuilder
    public func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    @ViewBuilder
    public func ifLet<T, Content: View>(_ value: T?, transform: (Self, T) -> Content) -> some View {
        if let value = value {
            transform(self, value)
        } else {
            self
        }
    }
}

// MARK: - Navigation Bar Styling

public struct NavigationBarStyleModifier: ViewModifier {
    let backgroundColor: Color
    let foregroundColor: Color
    let hideBottomLine: Bool
    
    public init(
        backgroundColor: Color = .clear,
        foregroundColor: Color = .primary,
        hideBottomLine: Bool = false
    ) {
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.hideBottomLine = hideBottomLine
    }
    
    public func body(content: Content) -> some View {
        content
            .onAppear {
                let appearance = UINavigationBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = UIColor(backgroundColor)
                appearance.titleTextAttributes = [.foregroundColor: UIColor(foregroundColor)]
                appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(foregroundColor)]
                
                if hideBottomLine {
                    appearance.shadowColor = .clear
                }
                
                UINavigationBar.appearance().standardAppearance = appearance
                UINavigationBar.appearance().scrollEdgeAppearance = appearance
            }
    }
}

extension View {
    public func navigationBarStyle(
        backgroundColor: Color = .clear,
        foregroundColor: Color = .primary,
        hideBottomLine: Bool = false
    ) -> some View {
        modifier(NavigationBarStyleModifier(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            hideBottomLine: hideBottomLine
        ))
    }
}

// MARK: - Card Style

public struct CardStyleModifier: ViewModifier {
    let backgroundColor: Color
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let shadowOffset: CGSize
    
    public init(
        backgroundColor: Color = Color(.secondarySystemBackground),
        cornerRadius: CGFloat = 12,
        shadowRadius: CGFloat = 4,
        shadowOffset: CGSize = CGSize(width: 0, height: 2)
    ) {
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.shadowOffset = shadowOffset
    }
    
    public func body(content: Content) -> some View {
        content
            .background(backgroundColor)
            .cornerRadius(cornerRadius)
            .shadow(
                color: .black.opacity(0.1),
                radius: shadowRadius,
                x: shadowOffset.width,
                y: shadowOffset.height
            )
    }
}

extension View {
    public func cardStyle(
        backgroundColor: Color = Color(.secondarySystemBackground),
        cornerRadius: CGFloat = 12,
        shadowRadius: CGFloat = 4,
        shadowOffset: CGSize = CGSize(width: 0, height: 2)
    ) -> some View {
        modifier(CardStyleModifier(
            backgroundColor: backgroundColor,
            cornerRadius: cornerRadius,
            shadowRadius: shadowRadius,
            shadowOffset: shadowOffset
        ))
    }
}

// MARK: - Shimmer Effect

public struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    let isAnimating: Bool
    
    public init(isAnimating: Bool = true) {
        self.isAnimating = isAnimating
    }
    
    public func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isAnimating {
                        ShimmerView(phase: phase)
                    }
                }
            )
            .onAppear {
                if isAnimating {
                    withAnimation(
                        Animation.linear(duration: 1.5)
                            .repeatForever(autoreverses: false)
                    ) {
                        phase = 1
                    }
                }
            }
    }
}

private struct ShimmerView: View {
    let phase: CGFloat
    
    var body: some View {
        LinearGradient(
            colors: [
                .clear,
                .white.opacity(0.6),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .scaleEffect(x: 3, anchor: .leading)
        .offset(x: -200 + (phase * 400))
        .mask(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black)
        )
    }
}

extension View {
    public func shimmer(isAnimating: Bool = true) -> some View {
        modifier(ShimmerModifier(isAnimating: isAnimating))
    }
}

// MARK: - Skeleton Loading

public struct SkeletonModifier: ViewModifier {
    let isLoading: Bool
    let cornerRadius: CGFloat
    
    public init(isLoading: Bool, cornerRadius: CGFloat = 8) {
        self.isLoading = isLoading
        self.cornerRadius = cornerRadius
    }
    
    public func body(content: Content) -> some View {
        content
            .opacity(isLoading ? 0 : 1)
            .overlay(
                Group {
                    if isLoading {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color(.systemGray5))
                            .shimmer()
                    }
                }
            )
    }
}

extension View {
    public func skeleton(isLoading: Bool, cornerRadius: CGFloat = 8) -> some View {
        modifier(SkeletonModifier(isLoading: isLoading, cornerRadius: cornerRadius))
    }
}

// MARK: - Safe Area Insets

extension View {
    public func ignoreKeyboard() -> some View {
        self.ignoresSafeArea(.keyboard, edges: .bottom)
    }
    
    public func safeAreaPadding(_ edges: Edge.Set = .all) -> some View {
        self.padding(edges, 0)
            .background(GeometryReader { geometry in
                Color.clear.preference(
                    key: SafeAreaInsetsPreferenceKey.self,
                    value: geometry.safeAreaInsets
                )
            })
    }
}

private struct SafeAreaInsetsPreferenceKey: PreferenceKey {
    static var defaultValue: EdgeInsets = .init()
    static func reduce(value: inout EdgeInsets, nextValue: () -> EdgeInsets) {
        value = nextValue()
    }
}

// MARK: - Animated Number

public struct AnimatedNumberModifier: ViewModifier {
    let value: Double
    let format: String
    
    @State private var animatedValue: Double = 0
    
    public init(value: Double, format: String = "%.0f") {
        self.value = value
        self.format = format
    }
    
    public func body(content: Content) -> some View {
        Text(String(format: format, animatedValue))
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0)) {
                    animatedValue = value
                }
            }
            .onChange(of: value) { newValue in
                withAnimation(.easeInOut(duration: 0.5)) {
                    animatedValue = newValue
                }
            }
    }
}

public struct AnimatedNumber: View {
    let value: Double
    let format: String
    
    public init(value: Double, format: String = "%.0f") {
        self.value = value
        self.format = format
    }
    
    public var body: some View {
        Text("")
            .modifier(AnimatedNumberModifier(value: value, format: format))
    }
}

// MARK: - Haptic Feedback

extension View {
    public func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium, trigger: Bool) -> some View {
        self.onChange(of: trigger) { _ in
            let impactFeedback = UIImpactFeedbackGenerator(style: style)
            impactFeedback.impactOccurred()
        }
    }
    
    public func selectionHaptic(trigger: Bool) -> some View {
        self.onChange(of: trigger) { _ in
            let selectionFeedback = UISelectionFeedbackGenerator()
            selectionFeedback.selectionChanged()
        }
    }
    
    public func notificationHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType, trigger: Bool) -> some View {
        self.onChange(of: trigger) { _ in
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(type)
        }
    }
}

// MARK: - Gradient Background

public struct GradientBackgroundModifier: ViewModifier {
    let colors: [Color]
    let startPoint: UnitPoint
    let endPoint: UnitPoint
    
    public init(
        colors: [Color],
        startPoint: UnitPoint = .topLeading,
        endPoint: UnitPoint = .bottomTrailing
    ) {
        self.colors = colors
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: colors,
                    startPoint: startPoint,
                    endPoint: endPoint
                )
            )
    }
}

extension View {
    public func gradientBackground(
        colors: [Color],
        startPoint: UnitPoint = .topLeading,
        endPoint: UnitPoint = .bottomTrailing
    ) -> some View {
        modifier(GradientBackgroundModifier(
            colors: colors,
            startPoint: startPoint,
            endPoint: endPoint
        ))
    }
}

// MARK: - Rounded Corners

extension View {
    public func roundedCorners(_ radius: CGFloat, corners: UIRectCorner = .allCorners) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

private struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Device-specific Modifiers

extension View {
    public func iPhoneOnly() -> some View {
        self.if(UIDevice.current.userInterfaceIdiom == .phone) { view in
            view
        }
    }
    
    public func iPadOnly() -> some View {
        self.if(UIDevice.current.userInterfaceIdiom == .pad) { view in
            view
        }
    }
    
    public func compactWidth() -> some View {
        self.if(UIScreen.main.bounds.width < 400) { view in
            view
        }
    }
    
    public func largeScreen() -> some View {
        self.if(UIScreen.main.bounds.width > 400) { view in
            view
        }
    }
}

// MARK: - Visibility Modifier

extension View {
    public func hidden(_ shouldHide: Bool) -> some View {
        opacity(shouldHide ? 0 : 1)
    }
    
    public func invisible(_ shouldHide: Bool) -> some View {
        if shouldHide {
            return AnyView(EmptyView())
        } else {
            return AnyView(self)
        }
    }
}

// MARK: - Read Size Modifier

public struct SizePreferenceKey: PreferenceKey {
    public static var defaultValue: CGSize = .zero
    public static func reduce(value: inout CGSize, nextValue: () -> CGSize) {}
}

extension View {
    public func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometry.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}

// MARK: - Bounce Animation

extension View {
    public func bounceOnTap() -> some View {
        self.scaleEffect(1.0)
            .animation(.interpolatingSpring(stiffness: 300, damping: 10), value: UUID())
            .onTapGesture {
                withAnimation(.interpolatingSpring(stiffness: 300, damping: 10)) {
                    // Trigger bounce animation
                }
            }
    }
}