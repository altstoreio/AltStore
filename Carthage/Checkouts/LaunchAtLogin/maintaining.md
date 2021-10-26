# Maintaining

## Rebuild helper binaries

1. If it's the non-`with-runtime` ZIP, set the target to macOS 10.14.4 first.
2. Set build configuration to “Release”.
3. Build the binary.
4. Find the binary in “Products” in the sidebar, ZIP it, and overwrite the existing ZIP file in the source directory.
5. Run `shasum -a 256 filename.zip` on the ZIP file and copy the hash into “copy-helper-swiftpm.sh”.
