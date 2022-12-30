#!/usr/bin/env bash 
set -e; set -o pipefail; set -x;

echo "Building Rust projects..."
cd em_proxy
cargo xcode --output-dir ../
cd ../
cd minimuxer
cargo xcode --output-dir ../
echo "Done!"
