name: iOS-ipa-build

on:
  workflow_dispatch:

jobs:
  build-ios:
    name: 🎉 iOS Build
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3

      - uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
          architecture: x64
      - run: flutter pub get
      

      - run: pod repo update
        working-directory: ios

      - run: flutter build ios --release --no-codesign

      - run: mkdir Payload
        working-directory: build/ios/iphoneos

      - run: mv Runner.app/ Payload
        working-directory: build/ios/iphoneos

      - name: Zip output
        run: zip -qq -r -9 FlutterIpaExport.ipa Payload
        working-directory: build/ios/iphoneos

      - name: Upload binaries to release
        uses: svenstaro/upload-release-action@v2
        with:
          repo_token: ${{ secrets.GITHUB_TOKEN }}
          file: build/ios/iphoneos/FlutterIpaExport.ipa
          tag: v1.0
          overwrite: true
          body: "This is first release"
