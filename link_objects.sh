#!/bin/bash

set -euo pipefail

# Configuration
SWIFT_DIR=${SWIFT_DIR:-"$(pwd)/swift_outputs/objects"}
PADDING_DIR=${PADDING_DIR:-"$(pwd)/padding_outputs/objects"}
MAIN_OBJ=${MAIN_OBJ:-"$(pwd)/main/main.o"}
OUTPUT_DIR=${OUTPUT_DIR:-"$(pwd)/link_outputs"}
OUTPUT_NAME=${OUTPUT_NAME:-"test_binary"}
MAX_SWIFT_OBJECTS=${MAX_SWIFT_OBJECTS:-""}
MAX_PADDING_OBJECTS=${MAX_PADDING_OBJECTS:-""}
USE_LD_DIRECTLY=${USE_LD_DIRECTLY:-false}
SDK_PATH=${SDK_PATH:-$(xcrun --sdk iphoneos --show-sdk-path)}
TARGET=${TARGET:-"arm64-apple-ios15.0"}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Link Swift and padding object files into a final executable for linker testing.

OPTIONS:
    -s, --swift-dir DIR           Directory containing Swift .o files (default: ./swift_outputs/objects)
    -p, --padding-dir DIR         Directory containing padding .o files (default: ./padding_outputs/objects)
    -m, --main-obj FILE           Path to main.o file (default: ./main/main.o)
    -o, --output-dir DIR          Output directory for binary and map file (default: ./link_outputs)
    -n, --name NAME               Output binary name (default: test_binary)
    --max-swift-objects NUM       Maximum number of Swift objects to link (default: all)
    --max-padding-objects NUM     Maximum number of padding objects to link (default: all)
    --use-ld                      Use ld directly instead of invoking through clang
    --sdk PATH                    Path to SDK (default: iPhone SDK)
    --target TRIPLE               Target triple (default: arm64-apple-ios15.0)
    -h, --help                    Show this help message

EXAMPLES:
    # Link with default directories
    $0

    # Specify custom directories
    $0 -s /tmp/swift_outputs/objects -p /tmp/padding_outputs/objects

    # Custom output location and name
    $0 -o /tmp/link_test -n my_binary

    # Link only first 50 Swift objects to test at what threshold issues appear
    $0 --max-swift-objects 50

    # Specify target
    $0 --target arm64-apple-ios16.0
EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--swift-dir)
            SWIFT_DIR="$2"
            shift 2
            ;;
        -p|--padding-dir)
            PADDING_DIR="$2"
            shift 2
            ;;
        -m|--main-obj)
            MAIN_OBJ="$2"
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -n|--name)
            OUTPUT_NAME="$2"
            shift 2
            ;;
        --max-swift-objects)
            MAX_SWIFT_OBJECTS="$2"
            shift 2
            ;;
        --max-padding-objects)
            MAX_PADDING_OBJECTS="$2"
            shift 2
            ;;
        --use-ld)
            USE_LD_DIRECTLY=true
            shift
            ;;
        --sdk)
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

# Function to link object files via clang
link_objects_via_clang() {
    local output_binary=$1
    local map_file=$2
    local trace_file=$3
    shift 3
    local object_files=("$@")

    # Get Swift library path from toolchain
    local swift_lib_path=$(dirname $(xcrun --find swift))/../lib/swift/iphoneos

    xcrun clang \
        "${object_files[@]}" \
        -o "$output_binary" \
        -arch arm64 \
        -isysroot "$SDK_PATH" \
        -target "$TARGET" \
        -L"$swift_lib_path" \
        -Wl,-rpath,"$swift_lib_path" \
        -Wl,-map,"$map_file" \
        -Wl,-t \
        -Wl,-no_uuid \
        -Wl,-no_adhoc_codesign \
        -framework Foundation > "$trace_file" 2>&1
}

# Function to link object files directly with ld
link_objects_via_ld() {
    local output_binary=$1
    local map_file=$2
    local trace_file=$3
    shift 3
    local object_files=("$@")

    # Get Swift library path from toolchain
    local swift_lib_path=$(dirname $(xcrun --find swift))/../lib/swift/iphoneos

    xcrun ld \
        "${object_files[@]}" \
        -o "$output_binary" \
        -arch arm64 \
        -syslibroot "$SDK_PATH" \
        -platform_version ios 15.0 15.0 \
        -L"$swift_lib_path" \
        -rpath "$swift_lib_path" \
        -map "$map_file" \
        -t \
        -no_uuid \
        -no_adhoc_codesign \
        -framework Foundation \
        -lSystem > "$trace_file" 2>&1
}

# Main execution
main() {
    echo "=== Object Linker for Linker Testing ==="
    echo "Configuration:"
    echo "  Swift objects: $SWIFT_DIR"
    echo "  Padding objects: $PADDING_DIR"
    echo "  Main object: $MAIN_OBJ"
    echo "  Output directory: $OUTPUT_DIR"
    echo "  Output name: $OUTPUT_NAME"
    echo "  Use ld directly: $USE_LD_DIRECTLY"
    echo "  SDK: $SDK_PATH"
    echo "  Target: $TARGET"
    echo ""

    # Verify input directories exist
    if [[ ! -d "$SWIFT_DIR" ]]; then
        echo "Error: Swift directory does not exist: $SWIFT_DIR"
        exit 1
    fi

    if [[ ! -d "$PADDING_DIR" ]]; then
        echo "Error: Padding directory does not exist: $PADDING_DIR"
        exit 1
    fi

    # Verify main.o exists
    if [[ ! -f "$MAIN_OBJ" ]]; then
        echo "Error: Main object file does not exist: $MAIN_OBJ"
        exit 1
    fi

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Collect Swift object files
    echo "Collecting Swift object files..."
    swift_objects=()
    while IFS= read -r -d '' file; do
        swift_objects+=("$file")
    done < <(find "$SWIFT_DIR" -name "*.o" -print0 | sort -z)
    echo "  Found ${#swift_objects[@]} Swift object files"

    # Limit Swift objects if requested
    if [[ -n "$MAX_SWIFT_OBJECTS" && "$MAX_SWIFT_OBJECTS" -gt 0 ]]; then
        if [[ "$MAX_SWIFT_OBJECTS" -lt "${#swift_objects[@]}" ]]; then
            swift_objects=("${swift_objects[@]:0:$MAX_SWIFT_OBJECTS}")
            echo "  Limited to first $MAX_SWIFT_OBJECTS Swift object files"
        fi
    fi

    # Collect padding object files
    echo "Collecting padding object files..."
    padding_objects=()
    while IFS= read -r -d '' file; do
        padding_objects+=("$file")
    done < <(find "$PADDING_DIR" -name "*.o" -print0 | sort -z)
    echo "  Found ${#padding_objects[@]} padding object files"

    # Limit padding objects if requested
    if [[ -n "$MAX_PADDING_OBJECTS" && "$MAX_PADDING_OBJECTS" -gt 0 ]]; then
        if [[ "$MAX_PADDING_OBJECTS" -lt "${#padding_objects[@]}" ]]; then
            padding_objects=("${padding_objects[@]:0:$MAX_PADDING_OBJECTS}")
            echo "  Limited to first $MAX_PADDING_OBJECTS padding object files"
        fi
    fi

    # Check if we have any objects to link
    if [[ ${#swift_objects[@]} -eq 0 && ${#padding_objects[@]} -eq 0 ]]; then
        echo "Error: No object files found to link"
        exit 1
    fi

    # Combine object files: Swift first, then padding, then main.o last
    all_objects=("${swift_objects[@]}" "${padding_objects[@]}" "$MAIN_OBJ")

    # Define output paths
    output_binary="$OUTPUT_DIR/$OUTPUT_NAME"
    map_file="$OUTPUT_DIR/${OUTPUT_NAME}.map"
    trace_file="$OUTPUT_DIR/${OUTPUT_NAME}.trace"

    # Link
    echo "Linking ${#all_objects[@]} object files..."
    if [[ "$USE_LD_DIRECTLY" == true ]]; then
        echo "Using ld directly..."
        if link_objects_via_ld "$output_binary" "$map_file" "$trace_file" "${all_objects[@]}"; then
            echo "✓ Link succeeded"
        else
            echo "Link failed"
            exit 1
        fi
    else
        echo "Using clang (which invokes ld)..."
        if link_objects_via_clang "$output_binary" "$map_file" "$trace_file" "${all_objects[@]}"; then
            echo "✓ Link succeeded"
        else
            echo "Link failed"
            exit 1
        fi
    fi

    echo ""
    echo "=== Summary ==="
    echo "  Swift objects linked: ${#swift_objects[@]}"
    echo "  Padding objects linked: ${#padding_objects[@]}"
    echo "  Total objects: ${#all_objects[@]}"
    echo "  Output binary: $output_binary"
    echo "  Link map: $map_file"
    echo "  Link trace: $trace_file"

    # Show output file size
    echo ""
    echo "Output file size:"
    ls -lh "$output_binary"
}

# Run main function
main
