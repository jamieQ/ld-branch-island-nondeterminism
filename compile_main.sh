#!/bin/bash

set -euo pipefail

# Configuration
MAIN_SOURCE=${MAIN_SOURCE:-"$(pwd)/main/main.swift"}
OUTPUT_DIR=${OUTPUT_DIR:-"$(pwd)/main"}
SDK_PATH=${SDK_PATH:-$(xcrun --sdk iphoneos --show-sdk-path)}
TARGET=${TARGET:-"arm64-apple-ios15.0"}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Compile the main.swift stub into main.o for linker testing.

OPTIONS:
    -m, --main-source FILE   Path to main.swift (default: ./main/main.swift)
    -o, --output-dir DIR     Output directory for main.o (default: ./main)
    -s, --sdk PATH           Path to SDK (default: iPhone SDK)
    --target TRIPLE          Target triple (default: arm64-apple-ios15.0)
    -h, --help               Show this help message

EXAMPLES:
    # Compile with defaults
    $0

    # Specify custom paths
    $0 -m /path/to/main.swift -o /tmp/main_output
EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--main-source)
            MAIN_SOURCE="$2"
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -s|--sdk)
            SDK_PATH="$2"
            shift 2
            ;;
        --target)
            TARGET="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Main execution
main() {
    echo "=== Main Stub Compiler for Linker Testing ==="
    echo "Configuration:"
    echo "  Main source: $MAIN_SOURCE"
    echo "  Output directory: $OUTPUT_DIR"
    echo "  SDK: $SDK_PATH"
    echo "  Target: $TARGET"
    echo ""

    # Verify main.swift exists
    if [[ ! -f "$MAIN_SOURCE" ]]; then
        echo "Error: Main source file does not exist: $MAIN_SOURCE"
        exit 1
    fi

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Compile main.swift
    echo "Compiling main.swift..."
    output_file="$OUTPUT_DIR/main.o"

    if xcrun swiftc -c \
        "$MAIN_SOURCE" \
        -o "$output_file" \
        -sdk "$SDK_PATH" \
        -target "$TARGET" \
        -parse-as-library \
        -whole-module-optimization 2>&1; then
        echo "✓ Compilation succeeded"
    else
        echo "Compilation failed"
        exit 1
    fi

    echo ""
    echo "=== Summary ==="
    echo "  Output: $output_file"
    ls -lh "$output_file"
}

# Run main function
main
