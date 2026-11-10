//
//  AdaptiveLayoutTests.swift
//  AltTests
//

import XCTest
import UIKit

@testable import AltStore

final class AdaptiveLayoutTests: XCTestCase
{
    @MainActor
    func testCompactHeightTracksViewResizing()
    {
        let view = UIView()
        for (height, expected) in [(568.0, true), (600.0, false), (844.0, false), (400.0, true), (720.0, false)]
        {
            view.bounds = CGRect(x: 0, y: 0, width: 800, height: height)
            XCTAssertEqual(view.isExtraCompactHeight, expected)
        }
    }

    @MainActor
    func testAuthenticationSpacingRestoresAfterResizing() throws
    {
        let storyboard = UIStoryboard(name: "Authentication", bundle: Bundle(for: AuthenticationViewController.self))
        let controller = try XCTUnwrap(storyboard.instantiateViewController(withIdentifier: "authenticationViewController") as? AuthenticationViewController)
        controller.loadViewIfNeeded()
        let stackView = try XCTUnwrap(controller.value(forKey: "contentStackView") as? UIStackView)
        let textField = try XCTUnwrap(controller.value(forKey: "appleIDTextField") as? UITextField)
        let defaultSpacing = stackView.spacing
        textField.text = "resize@example.com"

        for height in [568.0, 844.0, 400.0, 720.0, 600.0]
        {
            controller.view.bounds = CGRect(x: 0, y: 0, width: 800, height: height)
            controller.viewWillLayoutSubviews()
            XCTAssertEqual(stackView.spacing, height < 600 ? 20 : defaultSpacing)
            XCTAssertEqual(textField.text, "resize@example.com")
        }
    }

    @MainActor
    func testInstructionsMarginsRestoreAfterResizing() throws
    {
        let storyboard = UIStoryboard(name: "Authentication", bundle: Bundle(for: InstructionsViewController.self))
        let controller = try XCTUnwrap(storyboard.instantiateViewController(withIdentifier: "instructionsViewController") as? InstructionsViewController)
        controller.loadViewIfNeeded()
        let stackView = try XCTUnwrap(controller.value(forKey: "contentStackView") as? UIStackView)
        let defaultMargins = stackView.layoutMargins

        for height in [568.0, 844.0, 400.0, 720.0, 600.0]
        {
            controller.view.bounds = CGRect(x: 0, y: 0, width: 800, height: height)
            controller.viewWillLayoutSubviews()
            var expected = defaultMargins
            if height < 600
            {
                expected.top = 0
                expected.bottom = expected.left
            }
            XCTAssertEqual(stackView.layoutMargins, expected)
        }
    }
}

private class ResizeTestContentViewController: UIViewController, ScrollableContentViewController
{
    let scrollView = UIScrollView()
}

private class ResizeTestHeaderViewController: HeaderContentViewController<UIView, ResizeTestContentViewController>
{
    override func makeHeaderView() -> UIView
    {
        return UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
    }

    override func makeContentViewController() -> ResizeTestContentViewController
    {
        return ResizeTestContentViewController()
    }
}

extension AdaptiveLayoutTests
{
    @MainActor
    func testHeaderRemainsVisibleInWideShortWindows()
    {
        let controller = ResizeTestHeaderViewController()
        controller.loadViewIfNeeded()

        for size in [CGSize(width: 800, height: 400), CGSize(width: 400, height: 800), CGSize(width: 900, height: 500)]
        {
            controller.view.bounds = CGRect(origin: .zero, size: size)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            let headerFrame = controller.headerView.convert(controller.headerView.bounds, to: controller.view)
            XCTAssertGreaterThanOrEqual(headerFrame.minY, 0)
            XCTAssertLessThan(headerFrame.maxY, size.height)
            XCTAssertEqual(headerFrame.minX, 15, accuracy: 0.5)
            XCTAssertEqual(headerFrame.width, size.width - 30, accuracy: 0.5)
        }
    }
}
