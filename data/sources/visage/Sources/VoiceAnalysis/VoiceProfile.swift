/// What this voice usually sounds like: the spread of its formants, its pitch and its level, learnt as it
/// speaks (spec, § 6.1). Until it has heard enough, it leans on the ranges of an adult voice.
struct VoiceProfile {
    var formant1 = Spread(range: 150...1200, prior: (260, 820))
    var formant2 = Spread(range: 500...3200, prior: (850, 2350))
    var pitch = Spread(range: 50...450, prior: (85, 260))
    var level = Spread(range: -90...0, prior: (-45, -12), low: 0.1)

    /// The level the voice speaks at: its 90th percentile.
    var speechLevel: Float { level.high }
}

/// A percentile range learnt from a histogram, blended with a prior until enough values came in.
struct Spread {
    private let lowerBound: Float
    private let binWidth: Float
    private var bins: [Int]
    private var count = 0
    private let prior: (Float, Float)
    private let lowQuantile: Float
    private let highQuantile: Float
    private var measured: (Float, Float)
    private(set) var low: Float
    private(set) var high: Float

    /// Values needed before the prior is forgotten.
    private static let confidence = 200

    init(
        range: ClosedRange<Float>, prior: (Float, Float), low lowQuantile: Float = 0.05, high highQuantile: Float = 0.95
    ) {
        lowerBound = range.lowerBound
        let binCount = 120
        binWidth = (range.upperBound - range.lowerBound) / Float(binCount)
        bins = [Int](repeating: 0, count: binCount)
        self.prior = prior
        self.lowQuantile = lowQuantile
        self.highQuantile = highQuantile
        measured = prior
        low = prior.0
        high = prior.1
    }

    mutating func add(_ value: Float) {
        let index = Int((value - lowerBound) / binWidth)
        guard index >= 0, index < bins.count else { return }
        bins[index] += 1
        count += 1
        if count % 16 == 0 { update() }
    }

    /// 0 at the low end of the range, 1 at the high end, clamped.
    func normalise(_ value: Float) -> Float {
        guard high > low else { return 0.5 }
        return min(max((value - low) / (high - low), 0), 1)
    }

    private mutating func update() {
        measured = (quantile(lowQuantile), quantile(highQuantile))
        let weight = min(Float(count) / Float(Self.confidence), 1)
        low = prior.0 + (measured.0 - prior.0) * weight
        high = prior.1 + (measured.1 - prior.1) * weight
    }

    private func quantile(_ q: Float) -> Float {
        let target = Int(Float(count) * q)
        var seen = 0
        for (index, value) in bins.enumerated() {
            seen += value
            if seen > target { return lowerBound + (Float(index) + 0.5) * binWidth }
        }
        return lowerBound + Float(bins.count) * binWidth
    }
}
