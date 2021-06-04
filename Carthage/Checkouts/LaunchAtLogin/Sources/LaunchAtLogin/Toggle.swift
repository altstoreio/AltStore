import SwiftUI

@available(macOS 10.15, *)
extension LaunchAtLogin {
	/**
	This package comes with a `LaunchAtLogin.Toggle` view which is like the built-in `Toggle` but with a predefined binding and label. Clicking the view toggles “launch at login” for your app.

	```
	struct ContentView: View {
		var body: some View {
			LaunchAtLogin.Toggle()
		}
	}
	```

	The default label is `"Launch at login"`, but it can be overridden for localization and other needs:

	```
	struct ContentView: View {
		var body: some View {
			LaunchAtLogin.Toggle {
				Text("Launch at login")
			}
		}
	}
	```
	*/
	public struct Toggle<Label>: View where Label: View {
		@ObservedObject private var launchAtLogin = LaunchAtLogin.observable
		private let label: Label

		/**
		Creates a toggle that displays a custom label.

		- Parameters:
			- label: A view that describes the purpose of the toggle.
		*/
		public init(@ViewBuilder label: () -> Label) {
			self.label = label()
		}

		public var body: some View {
			SwiftUI.Toggle(isOn: $launchAtLogin.isEnabled) { label }
		}
	}
}

@available(macOS 10.15, *)
extension LaunchAtLogin.Toggle where Label == Text {
	/**
	Creates a toggle that generates its label from a localized string key.

	This initializer creates a ``Text`` view on your behalf with provided `titleKey`

	- Parameters:
		- titleKey: The key for the toggle's localized title, that describes the purpose of the toggle.
	*/
	public init(_ titleKey: LocalizedStringKey) {
		label = Text(titleKey)
	}

	/**
	Creates a toggle that generates its label from a string.

	This initializer creates a `Text` view on your behalf with the provided `title`.

	- Parameters:
		- title: A string that describes the purpose of the toggle.
	*/
	public init<S>(_ title: S) where S: StringProtocol {
		label = Text(title)
	}

	/**
	Creates a toggle with the default title of `Launch at login`.
	*/
	public init() {
		self.init("Launch at login")
	}
}
