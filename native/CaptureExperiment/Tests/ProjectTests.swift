import XCTest
@testable import ExperimentModel

final class ProjectTests: XCTestCase {
    func fixture() -> EditProject {
        var project = EditProject()
        project.clips = [
            Clip(file: "first.mov", sourceTicks: 36000, durationTicks: 18000),
            Clip(file: "second.mov", sourceTicks: 36000, durationTicks: 18000)
        ]
        return project
    }

    func testValidSixtySecondProject() throws {
        let project = fixture()
        try project.validate(forRender: true)
        XCTAssertEqual(project.durationTicks, 36000)
    }

    func testRenderRequiresTwoClips() {
        XCTAssertThrowsError(try EditProject().validate(forRender: true))
    }

    func testRejectsTrimBeyondSourceAndOffFrameBoundary() {
        var project = fixture()
        project.clips[0].startTicks = 18020
        XCTAssertThrowsError(try project.validate())
        project.clips[0].startTicks = 1
        XCTAssertThrowsError(try project.validate())
        project.clips[0].startTicks = -20
        XCTAssertThrowsError(try project.validate())
    }

    func testRejectsOversizedTimelineAndInvalidGain() {
        var project = fixture()
        project.clips[0].durationTicks = 18020
        XCTAssertThrowsError(try project.validate())
        project = fixture()
        project.sourceGain = .nan
        XCTAssertThrowsError(try project.validate())
    }

    func testRejectsTraversalAndUnknownSchema() {
        var project = fixture()
        project.clips[0].file = "../outside.mov"
        XCTAssertThrowsError(try project.validate())
        project = fixture()
        project.music = "/outside.wav"
        XCTAssertThrowsError(try project.validate())
        project = fixture()
        project.schema = 2
        XCTAssertThrowsError(try project.validate())
    }

    func testSaveReopenAndCorruptNewestFallbackIsExplicit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(root: root)
        try await store.prepare()
        for file in ["first.mov", "second.mov"] {
            try Data([1, 2, 3]).write(to: root.appendingPathComponent("Media/\(file)"))
        }
        let first = try await store.save(fixture())
        var next = first
        next.title = "Revised"
        next.clips.swapAt(0, 1)
        let second = try await store.save(next)
        let recovered = try await ProjectStore(root: root).recover()
        XCTAssertEqual(recovered.project, second)
        XCTAssertNil(recovered.warning)
        try Data("corrupt".utf8).write(to: root.appendingPathComponent("Revisions/0000000002.json"))
        let fallback = try await store.recover()
        XCTAssertEqual(fallback.project, first)
        XCTAssertTrue(fallback.warning?.contains("RECOVERY FAILURE") == true)
        let third = try await store.save(fallback.project)
        XCTAssertEqual(third.revision, 3, "Never overwrite corrupt evidence")
    }

    func testMissingMediaIsReportedAndInvalidSaveDoesNotAdvance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(root: root)
        let first = try await store.save(fixture())
        var invalid = first
        invalid.clips[0].durationTicks = 0
        do {
            _ = try await store.save(invalid)
            XCTFail("Invalid project was saved")
        } catch {}
        let recovered = try await store.recover()
        XCTAssertEqual(recovered.project, first)
        XCTAssertTrue(recovered.warning?.contains("Missing media") == true)
    }

    func testAllCorruptDoesNotSilentlyReset() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(root: root)
        _ = try await store.save(fixture())
        try Data().write(to: root.appendingPathComponent("Revisions/0000000001.json"))
        do {
            _ = try await store.recover()
            XCTFail("Corrupt store silently reset")
        } catch {}
    }
}
