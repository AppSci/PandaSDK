//
//  Extension+Task.swift
//  
//
//  Created by Denys Danyliuk on 12.09.2023.
//

import Foundation

extension Task where Success == Never, Failure == Never {
    /// Suspends the current task for at least the given duration
    /// in seconds.
    ///
    /// If the task is canceled before the time ends,
    /// this function throws `CancellationError`.
    ///
    /// This function doesn't block the underlying thread.
    public static func sleep(seconds duration: TimeInterval) async throws {
        try await Task.sleep(
            nanoseconds: UInt64(duration * TimeInterval(NSEC_PER_SEC))
        )
    }
}
