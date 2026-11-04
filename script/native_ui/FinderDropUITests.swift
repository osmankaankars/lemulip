
// Real Finder file drags into the normally launched production workspace.
// XCTest's public drag call is atomic: these cases prove the drop outcomes,
// including the expanded padding, not the outline's in-flight appearance.
extension QualityUITests {
    func testOrchardFinderDropsPreserveInputsAndRejectDuplicates() throws {
        try finderDropReview(theme: "orchard")
    }

    func testPistachioFinderDropsPreserveInputsAndRejectDuplicates() throws {
        try finderDropReview(theme: "pistachio")
    }

    func testLemonadeFinderDropsPreserveInputsAndRejectDuplicates() throws {
        try finderDropReview(theme: "lemonade")
    }

    private func finderDropReview(theme: String) throws {
        let folder = ReviewConfiguration.fixtures.appendingPathComponent("FinderDrop/" + theme, isDirectory: true)
        let before = try finderDropFiles(in: folder)
        XCTAssertEqual(before.count, 4, "Require four input-only, isolated Finder fixtures")
        func fixture(_ prefix: String) throws -> URL {
            let matches = before.filter { $0.lastPathComponent.hasPrefix(prefix + "-") && $0.pathExtension == "txt" }
            XCTAssertEqual(matches.count, 1)
            return try XCTUnwrap(matches.first)
        }
        let existing = try fixture("Existing")
        let single = try fixture("Single")
        let multiA = try fixture("Multi-A")
        let multiB = try fixture("Multi-B")
        let inputs = [existing, single, multiA, multiB]
        let originals = try inputs.map { try Data(contentsOf: $0) }
        XCTAssertTrue(originals.allSatisfy { !$0.isEmpty })

        let app = launch(language: "en", theme: theme)
        XCTAssertTrue(app.buttons["workspace.choose-files"].waitForExistence(timeout: 10),
                      "The production workspace must start empty")
        // Only this initial file uses the application-open path. Every later
        // addition must come from an actual Finder drag.
        app.open(existing)
        try expectFinderDropWorkspace([existing], in: app)

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.open(folder)
        let window = finder.windows.matching(NSPredicate(format: "identifier == %@ AND title == %@",
                                                          "FinderWindow", folder.lastPathComponent)).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        defer {
            // Close only the exact fixture window opened by this case.
            if window.exists {
                finder.activate()
                let close = window.buttons["_XCUI:CloseWindow"]
                if close.exists && close.isHittable { close.click() }
            }
        }
        finder.typeKey("1", modifierFlags: .command)
        let icons = window.collectionViews["IconView"]
        XCTAssertTrue(icons.waitForExistence(timeout: 10))
        for input in inputs {
            XCTAssertTrue(finderDropImage(input, in: icons).waitForExistence(timeout: 10))
        }

        // Keep the source icons below the target on the small ARM display.
        // This is ordinary window dragging, using its observed frame. It does
        // not write AX attributes or alter Finder's file selection.
        try positionFinderBelowDropTarget(window, app: app, finder: finder)
        captureFinderDropState(app, finder: finder, name: theme + " populated workspace before Finder drops")

        let reject = app.buttons["navigation.workspace"]
        XCTAssertTrue(reject.exists)
        let rejectedPoint = CGPoint(x: reject.frame.midX, y: reject.frame.midY)
        try selectFinderDropFiles([single], in: icons, finder: finder)
        dragFinderDropFile(single, in: icons, window: window, to: rejectedPoint)
        // Releasing over the navigation area rejects this drop. This is not
        // described as Escape during an in-flight drag.
        try expectFinderDropWorkspace([existing], in: app)
        let unexpectedAddition = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.finderDropRemoval(single, in: app).firstMatch.exists
        }, object: nil)
        unexpectedAddition.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unexpectedAddition], timeout: 1), .completed,
                       "A rejected drop must not add its file asynchronously")
        captureFinderDropState(app, finder: finder, name: theme + " rejected drop outside the file area")

        try selectFinderDropFiles([single], in: icons, finder: finder)
        let selected = finderDropCount(1, in: app)
        let clear = app.buttons["Clear"]
        XCTAssertTrue(selected.exists && clear.exists)
        // The production selected-files container adds eight points around
        // this header. Four points above its text exercises that added strip,
        // rather than dropping on an existing file row.
        let paddingPoint = CGPoint(x: (selected.frame.minX + clear.frame.maxX) / 2,
                                   y: selected.frame.minY - 4)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(paddingPoint))
        XCTAssertLessThan(paddingPoint.y, selected.frame.minY)
        dragFinderDropFile(single, in: icons, window: window, to: paddingPoint)
        try expectFinderDropWorkspace([existing, single], in: app)
        captureFinderDropState(app, finder: finder, name: theme + " new file accepted in the top padding")

        try selectFinderDropFiles([single], in: icons, finder: finder)
        let firstName = finderDropName(existing, in: app)
        let duplicatePoint = CGPoint(x: firstName.frame.midX, y: firstName.frame.midY)
        dragFinderDropFile(single, in: icons, window: window, to: duplicatePoint)
        try expectFinderDropWorkspace([existing, single], in: app)
        XCTAssertEqual(finderDropRemoval(single, in: app).count, 1,
                       "Dropping the same Finder URL again must not duplicate the workspace row")

        try selectFinderDropFiles([multiA, multiB], in: icons, finder: finder)
        let multiplePoint = CGPoint(x: firstName.frame.midX, y: firstName.frame.midY)
        dragFinderDropFile(multiA, in: icons, window: window, to: multiplePoint)
        try expectFinderDropWorkspace(inputs, in: app)
        let existingRow = try XCTUnwrap(finderDropRemoval(existing, in: app).allElementsBoundByIndex.first)
        let singleRow = try XCTUnwrap(finderDropRemoval(single, in: app).allElementsBoundByIndex.first)
        XCTAssertLessThan(existingRow.frame.minY, singleRow.frame.minY,
                          "Further drops must preserve the existing selection's order")
        for file in [multiA, multiB] {
            let row = try XCTUnwrap(finderDropRemoval(file, in: app).allElementsBoundByIndex.first)
            XCTAssertLessThan(singleRow.frame.minY, row.frame.minY,
                              "Both Finder-selected files must be appended after the existing rows")
        }
        XCTAssertEqual(try finderDropFiles(in: folder), before,
                       "Adding, rejecting and repeating Finder drops must not create or move user files")
        XCTAssertEqual(try inputs.map { try Data(contentsOf: $0) }, originals,
                       "Every original file must retain its exact bytes")
        captureFinderDropState(app, finder: finder, name: theme + " duplicate and multiple Finder drop result")
        let record = XCTAttachment(string: [
            "Theme requested through the production preference: " + theme,
            "Observed Finder folder: " + window.title,
            "Expected input basenames: " + inputs.map(\.lastPathComponent).joined(separator: ", "),
            "Observed workspace count: " + (finderDropCount(4, in: app).value as? String ?? finderDropCount(4, in: app).label),
            "Drop in expanded top padding: \(paddingPoint)",
            "Rejected navigation drop: \(rejectedPoint)",
            "Original bytes unchanged: true",
            "User file set unchanged: true (Finder's .DS_Store metadata excluded)",
            "Scope: real drag outcomes; no in-flight outline or Escape-cancellation claim"
        ].joined(separator: "\n"))
        record.name = theme + " Finder drop outcome receipt"
        record.lifetime = .keepAlways
        add(record)
    }

    private func finderDropFiles(in folder: URL) throws -> Set<URL> {
        // Finder can write its own view metadata when the test chooses Icon
        // view. No user file or arbitrary hidden output is excluded.
        Set(try contents(folder).filter { $0.lastPathComponent != ".DS_Store" })
    }

    private func finderDropImage(_ file: URL, in icons: XCUIElement) -> XCUIElement {
        icons.images.matching(NSPredicate(format: "identifier == %@", file.lastPathComponent)).firstMatch
    }

    private func finderDropRemoval(_ file: URL, in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label == %@", "Remove " + file.lastPathComponent))
    }

    private func finderDropName(_ file: URL, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "value == %@", file.lastPathComponent)).firstMatch
    }

    private func finderDropCount(_ count: Int, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@",
                                             "\(count) Selected", "\(count) Selected")).firstMatch
    }

    private func expectFinderDropWorkspace(_ files: [URL], in app: XCUIApplication) throws {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.finderDropCount(files.count, in: app).exists && files.allSatisfy {
                self.finderDropRemoval($0, in: app).count == 1 && self.finderDropName($0, in: app).exists
            }
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed,
                       "The actual workspace must contain exactly the expected unique Finder files")
        XCTAssertFalse(app.buttons["editor.create-copy"].exists,
                       "A file drop must not open an editor or submit a conversion")
    }

    private func selectFinderDropFiles(_ files: [URL], in icons: XCUIElement,
                                       finder: XCUIApplication) throws {
        finder.activate()
        let first = try XCTUnwrap(files.first)
        let firstImage = finderDropImage(first, in: icons)
        XCTAssertTrue(firstImage.isHittable)
        firstImage.click()
        for file in files.dropFirst() {
            let image = finderDropImage(file, in: icons)
            XCTAssertTrue(image.isHittable)
            XCUIElement.perform(withKeyModifiers: .command) { image.click() }
        }
        let selected = icons.images.matching(NSPredicate(format: "selected == true"))
        let expected = Set(files.map(\.lastPathComponent))
        let correct = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            Set(selected.allElementsBoundByIndex.map(\.identifier)) == expected
        }, object: icons)
        XCTAssertEqual(XCTWaiter.wait(for: [correct], timeout: 5), .completed,
                       "The actual Finder selection must match exactly the files being dragged")
    }

    private func positionFinderBelowDropTarget(_ window: XCUIElement, app: XCUIApplication,
                                                finder: XCUIApplication) throws {
        let header = finderDropCount(1, in: app)
        XCTAssertTrue(header.exists)
        let screenSize = XCUIScreen.main.screenshot().image.size
        let desiredTop = header.frame.maxY + 80
        XCTAssertLessThan(desiredTop + 170, screenSize.height,
                          "The observed display must have space for Finder's first icon row")
        let frame = window.frame
        let grab = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.width / 2, dy: 8))
        let destination = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.width / 2 - frame.minX + 8, dy: desiredTop - frame.minY + 8))
        grab.click(forDuration: 0.15, thenDragTo: destination)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            window.frame.minY > header.frame.maxY + 35
        }, object: window)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed,
                       "Finder's actual window must leave the top file target exposed")
        XCTAssertLessThan(window.frame.minY + 150, screenSize.height)
    }

    private func dragFinderDropFile(_ file: URL, in icons: XCUIElement,
                                    window: XCUIElement, to target: CGPoint) {
        let image = finderDropImage(file, in: icons)
        XCTAssertTrue(image.exists && image.isHittable)
        XCTAssertFalse(window.frame.contains(target), "The Finder window must not cover the destination")
        // Anchor both coordinates to the foreground Finder window. The target
        // point came from the production workspace's actual accessibility frame;
        // resolving it must not activate the target before the drag begins.
        let destination = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: target.x - window.frame.minX, dy: target.y - window.frame.minY))
        image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: 0.4, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    private func captureFinderDropState(_ app: XCUIApplication, finder: XCUIApplication, name: String) {
        let graph = XCTAttachment(string: app.debugDescription + "\n\nFinder\n" + finder.debugDescription)
        graph.name = name + " AX"
        graph.lifetime = .keepAlways
        add(graph)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
