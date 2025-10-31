#!/bin/bash

set -euo pipefail

# Configuration
# 512 is overkill and slow to generate, but basically always will demonstrate the problem.
NUM_FILES=${NUM_FILES:-512}
OUTPUT_DIR=${OUTPUT_DIR:-"$(pwd)/swift_outputs"}
TEMPLATE_FILE=${TEMPLATE_FILE:-""}
SDK_PATH=${SDK_PATH:-$(xcrun --sdk iphoneos --show-sdk-path)}
TARGET=${TARGET:-"arm64-apple-ios15.0"}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Generate Swift source files and compile them into separate .o files for linker testing.

OPTIONS:
    -n, --num-files NUM      Number of Swift files to generate (default: 100)
    -o, --output-dir DIR     Output directory for Swift files and .o files (default: ./swift_outputs)
    -t, --template FILE      Path to Swift template file (optional, uses inline template if not provided)
    -s, --sdk PATH           Path to SDK (default: iPhone SDK)
    --target TRIPLE          Target triple (default: arm64-apple-ios15.0)
    -h, --help               Show this help message

EXAMPLES:
    # Generate 100 Swift files with default template
    $0

    # Generate 500 files in a custom directory
    $0 -n 500 -o /tmp/swift_test

    # Use a custom template file
    $0 -t my_template.swift -n 200

    # Generate files and specify target
    $0 --num-files 50 --target arm64-apple-ios16.0
EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--num-files)
            NUM_FILES="$2"
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -t|--template)
            TEMPLATE_FILE="$2"
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

# Default Swift template (inline)
DEFAULT_TEMPLATE='
import Foundation

public struct SwiftFile_INDEX {
    public var id: Int = INDEX
    public var name: String = "SwiftFile_INDEX"

    public init() {}

    public func compute() -> Int {
        var result = INDEX
        for i in 0..<10 {
            result = result &* 31 &+ i
        }
        return result
    }

    public func description() -> String {
        return "SwiftFile_INDEX: id=\(id), computed=\(compute())"
    }
}

@inline(never)
public func entryPoint() -> Int {
    let file = SwiftFile_INDEX()
    return file.compute()
}
'

# Function to generate Swift source from template
generate_swift_file() {
    local index=$1
    local output_file=$2
    local template_content=""

    if [[ -n "$TEMPLATE_FILE" && -f "$TEMPLATE_FILE" ]]; then
        template_content=$(cat "$TEMPLATE_FILE")
    else
        template_content="$DEFAULT_TEMPLATE"
    fi

    # Replace INDEX placeholder with the actual index
    echo "$template_content" | sed "s/INDEX/$index/g" > "$output_file"
}

# Function to compile Swift file to .o
compile_swift_file() {
    local swift_file=$1
    local object_file=$2

    xcrun swiftc -c \
        "$swift_file" \
        -o "$object_file" \
        -sdk "$SDK_PATH" \
        -target "$TARGET" \
        -parse-as-library \
        -whole-module-optimization
}

# Main execution
main() {
    echo "=== Swift File Generator for Linker Testing ==="
    echo "Configuration:"
    echo "  Number of files: $NUM_FILES"
    echo "  Output directory: $OUTPUT_DIR"
    echo "  Template: $([ -n "$TEMPLATE_FILE" ] && echo "$TEMPLATE_FILE" || echo "inline")"
    echo "  SDK: $SDK_PATH"
    echo "  Target: $TARGET"
    echo ""

    # Create output directories
    mkdir -p "$OUTPUT_DIR/sources"
    mkdir -p "$OUTPUT_DIR/objects"

    # Clean previous outputs if they exist
    echo "Cleaning previous outputs..."
    rm -f "$OUTPUT_DIR/sources"/*.swift
    rm -f "$OUTPUT_DIR/objects"/*.o

    # Generate Swift files
    echo "Generating $NUM_FILES Swift files..."
    for i in $(seq 0 $((NUM_FILES - 1))); do
        swift_file="$OUTPUT_DIR/sources/SwiftFile_$(printf "%05d" $i).swift"
        generate_swift_file $i "$swift_file"

        if (( (i + 1) % 50 == 0 )); then
            echo "  Generated $((i + 1))/$NUM_FILES files..."
        fi
    done
    echo "✓ Generated $NUM_FILES Swift files"

    # Compile Swift files to .o files
    echo "Compiling Swift files to object files..."
    local success_count=0
    local failed_count=0

    for i in $(seq 0 $((NUM_FILES - 1))); do
        swift_file="$OUTPUT_DIR/sources/SwiftFile_$(printf "%05d" $i).swift"
        object_file="$OUTPUT_DIR/objects/SwiftFile_$(printf "%05d" $i).o"

        if compile_swift_file "$swift_file" "$object_file" 2>/dev/null; then
            ((success_count++))
        else
            ((failed_count++))
            echo "  Failed to compile: $swift_file"
        fi

        if (( (i + 1) % 50 == 0 )); then
            echo "  Compiled $((i + 1))/$NUM_FILES files..."
        fi
    done

    echo ""
    echo "=== Summary ==="
    echo "  Swift files generated: $NUM_FILES"
    echo "  Successfully compiled: $success_count"
    if (( failed_count > 0 )); then
        echo "  Failed compilations: $failed_count"
    fi
    echo "  Output directory: $OUTPUT_DIR"
    echo "  Sources: $OUTPUT_DIR/sources/"
    echo "  Objects: $OUTPUT_DIR/objects/"

    # Show disk usage
    echo ""
    echo "Disk usage:"
    du -sh "$OUTPUT_DIR/sources"
    du -sh "$OUTPUT_DIR/objects"

    if (( failed_count > 0 )); then
        exit 1
    fi
}

# Run main function
main
