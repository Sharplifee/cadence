import Foundation

/// Fixed-capacity FIFO. No allocation in the audio path.
public struct RingBuffer<T> {
    private var storage: [T?]
    private var head = 0
    public private(set) var count = 0
    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    public mutating func append(_ value: T) {
        storage[head] = value
        head = (head + 1) % capacity
        if count < capacity { count += 1 }
    }

    /// Oldest to newest.
    public var elements: [T] {
        guard count > 0 else { return [] }
        var out: [T] = []
        out.reserveCapacity(count)
        let start = (head - count + capacity) % capacity
        for i in 0..<count {
            if let v = storage[(start + i) % capacity] { out.append(v) }
        }
        return out
    }

    public mutating func removeAll() {
        storage = Array(repeating: nil, count: capacity)
        head = 0; count = 0
    }
}
