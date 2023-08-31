//
//  DebounceCollect.swift
//  
//
//  Created by Denys Danyliuk on 12.09.2023.
//

import Foundation

/// Collects all debounced elements and than returns it.
func debounceCollect<Output: AsyncSequence>(
    _ sequence: Output,
    for duration: TimeInterval
) -> AsyncStream<[Output.Element]> {
    AsyncStream<[Output.Element]> { continuation in
        let state = DebounceState<Output.Element>()
        Task {
            for try await item in sequence {
                await state.appendItem(item)
                await state.setOperation {
                    try await Task.sleep(seconds: duration)
                    try Task.checkCancellation()
                    await continuation.yield(state.items)
                    await state.resetItems()
                }
            }
            
            // If sequence finished
            let remainingItems = await state.items
            if !remainingItems.isEmpty {
                continuation.yield(remainingItems)
            }
            continuation.finish()
        }
    }
}

private actor DebounceState<T> {
    private(set) var items: [T] = []
    private var waitTask: Task<Void, Error>?
    
    func appendItem(_ item: T) {
        items.append(item)
    }
    
    func resetItems() {
        items.removeAll()
    }
    
    func setOperation(operation: @escaping () async throws -> Void) {
        waitTask?.cancel()
        waitTask = Task {
            try await operation()
        }
    }
}
