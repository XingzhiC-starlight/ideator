@testable import Ideator

// Short names for the shapes that tests write out by the dozen: `B(1)` is a bullet at level 1.

func L(_ n: Int) -> Level { Level(clamping: n) }
let T = LineShape.plain
func B(_ level: Int = 0) -> LineShape { LineShape(kind: .bullet, level: L(level)) }
func N(_ level: Int = 0) -> LineShape { LineShape(kind: .numbered, level: L(level)) }
func D(_ level: Int = 0, done: Bool = false) -> LineShape { LineShape(kind: .todo(done: done), level: L(level)) }

func line(_ shape: LineShape, _ text: String) -> Line { Line(shape: shape, runs: [Run(text: text)]) }

/// Every sequence of up to `length` shapes over plain text and each list kind at each level.
func everyRun(upTo length: Int) -> [[LineShape]] {
    let alphabet = [T] + [LineKind.bullet, .numbered, .todo(done: true)].flatMap { kind in
        (0..<Level.count).map { LineShape(kind: kind, level: L($0)) }
    }
    var all: [[LineShape]] = [[]]
    var frontier: [[LineShape]] = [[]]
    for _ in 0..<length {
        frontier = frontier.flatMap { run in alphabet.map { run + [$0] } }
        all += frontier
    }
    return all
}
