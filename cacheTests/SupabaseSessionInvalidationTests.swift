import Supabase
import XCTest
@testable import Capache

final class SupabaseSessionInvalidationTests: XCTestCase {
    func testAuthSessionMissingForcesLocalSignOut() {
        XCTAssertTrue(SupabaseSessionInvalidation.isSessionInvalidation(AuthError.sessionMissing))
    }

    func testDeletedUserForeignKeyFailureForcesLocalSignOut() {
        let error = PostgrestError(
            detail: "Key (user_id) is not present in table \"users\".",
            code: "23503",
            message: "insert or update on table \"notes\" violates foreign key constraint \"notes_user_id_fkey\""
        )

        XCTAssertTrue(SupabaseSessionInvalidation.isSessionInvalidation(error))
    }

    func testOrdinaryNetworkErrorDoesNotForceLocalSignOut() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: [NSLocalizedDescriptionKey: "The request timed out."]
        )

        XCTAssertFalse(SupabaseSessionInvalidation.isSessionInvalidation(error))
    }

    func testSwiftCancellationIsBenign() {
        XCTAssertTrue(SupabaseSessionInvalidation.isBenignCancellation(CancellationError()))
    }

    func testURLCancellationIsBenign() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCancelled,
            userInfo: [NSLocalizedDescriptionKey: "cancelled"]
        )

        XCTAssertTrue(SupabaseSessionInvalidation.isBenignCancellation(error))
    }

    func testTimedOutNetworkErrorIsNotBenignCancellation() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: [NSLocalizedDescriptionKey: "The request timed out."]
        )

        XCTAssertFalse(SupabaseSessionInvalidation.isBenignCancellation(error))
    }
}
