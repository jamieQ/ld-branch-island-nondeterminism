#!/bin/bash

set -euo pipefail

# Configuration
NUM_RUNS=${NUM_RUNS:-10}
SWIFT_DIR=${SWIFT_DIR:-"$(pwd)/swift_outputs/objects"}
PADDING_DIR=${PADDING_DIR:-"$(pwd)/padding_outputs/objects"}
MAIN_OBJ=${MAIN_OBJ:-"$(pwd)/main/main.o"}
TEST_OUTPUT_DIR=${TEST_OUTPUT_DIR:-"$(pwd)/nondet_test_outputs"}
MAX_SWIFT_OBJECTS=${MAX_SWIFT_OBJECTS:-""}
MAX_PADDING_OBJECTS=${MAX_PADDING_OBJECTS:-""}
USE_LD_DIRECTLY=${USE_LD_DIRECTLY:-false}
GENERATE_FILES=${GENERATE_FILES:-false}
SDK_PATH=${SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}
TARGET=${TARGET:-"arm64-apple-macos15.0"}
LINK_SCRIPT=${LINK_SCRIPT:-"$(pwd)/link_objects.sh"}
GENERATE_SWIFT_SCRIPT=${GENERATE_SWIFT_SCRIPT:-"$(pwd)/generate_swift_files.sh"}
GENERATE_PADDING_SCRIPT=${GENERATE_PADDING_SCRIPT:-"$(pwd)/generate_padding_files.sh"}
COMPILE_MAIN_SCRIPT=${COMPILE_MAIN_SCRIPT:-"$(pwd)/compile_main.sh"}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Run multiple link operations with the same inputs to detect linker nondeterminism.

OPTIONS:
    -r, --runs NUM                Number of link runs to perform (default: 10)
    -s, --swift-dir DIR           Directory containing Swift .o files (default: ./swift_outputs/objects)
    -p, --padding-dir DIR         Directory containing padding .o files (default: ./padding_outputs/objects)
    -m, --main-obj FILE           Path to main.o file (default: ./main/main.o)
    -t, --test-dir DIR            Output directory for test runs (default: ./nondet_test_outputs)
    --max-swift-objects NUM       Maximum number of Swift objects to link (default: all)
    --max-padding-objects NUM     Maximum number of padding objects to link (default: all)
    --use-ld                      Use ld directly instead of invoking through clang
    --generate                    Generate Swift files, padding files, and main.o before testing
    --sdk PATH                    Path to SDK (default: macOS SDK)
    --target TRIPLE               Target triple (default: arm64-apple-macos15.0)
    --link-script PATH            Path to link_objects.sh script (default: ./link_objects.sh)
    -h, --help                    Show this help message

EXAMPLES:
    # Generate all files and run 10 links
    $0 --generate

    # Run 10 links with existing files
    $0

    # Generate files and run 50 links
    $0 --generate -r 50

    # Test with only first 50 Swift objects to find threshold
    $0 --max-swift-objects 50 -r 10

    # Custom test directory
    $0 -t /tmp/nondet_test -r 20
EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--runs)
            NUM_RUNS="$2"
            shift 2
            ;;
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
        -t|--test-dir)
            TEST_OUTPUT_DIR="$2"
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
        --generate)
            GENERATE_FILES=true
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
        --link-script)
            LINK_SCRIPT="$2"
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

# Function to compute md5 hash of a file
compute_hash() {
    local file=$1
    md5 -q "$file"
}

# Function to compute md5 hash of map file, excluding the # Path comment line
compute_map_hash() {
    local file=$1
    grep -v '^# Path:' "$file" | md5 -q
}

# Function to run a single link operation
run_link() {
    local run_number=$1
    local output_dir="$TEST_OUTPUT_DIR/run_$(printf "%03d" $run_number)"

    mkdir -p "$output_dir"

    local link_cmd=("$LINK_SCRIPT" \
        -s "$SWIFT_DIR" \
        -p "$PADDING_DIR" \
        -m "$MAIN_OBJ" \
        -o "$output_dir" \
        -n "test_binary" \
        --sdk "$SDK_PATH" \
        --target "$TARGET")

    # Add max objects options if specified
    if [[ -n "$MAX_SWIFT_OBJECTS" ]]; then
        link_cmd+=(--max-swift-objects "$MAX_SWIFT_OBJECTS")
    fi
    if [[ -n "$MAX_PADDING_OBJECTS" ]]; then
        link_cmd+=(--max-padding-objects "$MAX_PADDING_OBJECTS")
    fi

    # Add use-ld option if specified
    if [[ "$USE_LD_DIRECTLY" == true ]]; then
        link_cmd+=(--use-ld)
    fi

    "${link_cmd[@]}" > "$output_dir/link.log" 2>&1

    echo "$output_dir"
}

# Main execution
main() {
    echo "=== Linker Nondeterminism Test Harness ==="
    echo "Configuration:"
    echo "  Number of runs: $NUM_RUNS"
    echo "  Swift objects: $SWIFT_DIR"
    echo "  Padding objects: $PADDING_DIR"
    echo "  Main object: $MAIN_OBJ"
    echo "  Test output directory: $TEST_OUTPUT_DIR"
    echo "  Generate files: $GENERATE_FILES"
    echo "  SDK: $SDK_PATH"
    echo "  Target: $TARGET"
    echo ""

    # Generate files if requested
    if [[ "$GENERATE_FILES" == true ]]; then
        echo "=== Generating Test Files ==="
        echo ""

        # Generate Swift files
        if [[ -f "$GENERATE_SWIFT_SCRIPT" ]]; then
            echo "Generating Swift files..."
            "$GENERATE_SWIFT_SCRIPT" --sdk "$SDK_PATH" --target "$TARGET"
            echo ""
        else
            echo "Error: Swift generation script not found: $GENERATE_SWIFT_SCRIPT"
            exit 1
        fi

        # Generate padding files
        if [[ -f "$GENERATE_PADDING_SCRIPT" ]]; then
            echo "Generating padding files..."
            "$GENERATE_PADDING_SCRIPT" --sdk "$SDK_PATH" --target "$TARGET"
            echo ""
        else
            echo "Error: Padding generation script not found: $GENERATE_PADDING_SCRIPT"
            exit 1
        fi

        # Compile main.swift
        if [[ -f "$COMPILE_MAIN_SCRIPT" ]]; then
            echo "Compiling main.swift..."
            "$COMPILE_MAIN_SCRIPT" --sdk "$SDK_PATH" --target "$TARGET"
            echo ""
        else
            echo "Error: Main compilation script not found: $COMPILE_MAIN_SCRIPT"
            exit 1
        fi

        echo "=== File Generation Complete ==="
        echo ""
    fi

    # Verify link script exists
    if [[ ! -f "$LINK_SCRIPT" ]]; then
        echo "Error: Link script does not exist: $LINK_SCRIPT"
        exit 1
    fi

    # Create test output directory
    mkdir -p "$TEST_OUTPUT_DIR"

    # Clean previous test outputs
    echo "Cleaning previous test outputs..."
    rm -rf "$TEST_OUTPUT_DIR"/run_*

    # Run multiple link operations
    echo "Running $NUM_RUNS link operations..."
    echo ""

    declare -a binary_hashes
    declare -a map_hashes
    declare -a output_dirs

    for i in $(seq 1 $NUM_RUNS); do
        echo "Run $i/$NUM_RUNS..."

        output_dir=$(run_link $i)
        output_dirs+=("$output_dir")

        # Compute hashes for binary and map file
        binary_file="$output_dir/test_binary"
        map_file="$output_dir/test_binary.map"

        if [[ -f "$binary_file" ]]; then
            binary_hash=$(compute_hash "$binary_file")
            binary_hashes+=("$binary_hash")
        else
            echo "  Warning: Binary not generated for run $i"
            binary_hashes+=("MISSING")
        fi

        if [[ -f "$map_file" ]]; then
            map_hash=$(compute_map_hash "$map_file")
            map_hashes+=("$map_hash")
        else
            echo "  Warning: Map file not generated for run $i"
            map_hashes+=("MISSING")
        fi
    done

    echo ""
    echo "=== Analysis ==="
    echo ""

    # Analyze binary hashes
    echo "Binary file analysis:"
    unique_binary_hashes=($(printf '%s\n' "${binary_hashes[@]}" | sort -u))

    if [[ ${#unique_binary_hashes[@]} -eq 1 ]]; then
        echo "  ✓ All binaries are identical (hash: ${unique_binary_hashes[0]})"
        binary_deterministic=true
    else
        echo "  ✗ NONDETERMINISM DETECTED in binaries"
        echo "  Found ${#unique_binary_hashes[@]} unique binary hashes:"
        for hash in "${unique_binary_hashes[@]}"; do
            count=$(printf '%s\n' "${binary_hashes[@]}" | grep -c "^${hash}$")
            echo "    - $hash: $count occurrence(s)"
        done
        binary_deterministic=false
    fi

    echo ""

    # Analyze map file hashes
    echo "Map file analysis:"
    unique_map_hashes=($(printf '%s\n' "${map_hashes[@]}" | sort -u))

    if [[ ${#unique_map_hashes[@]} -eq 1 ]]; then
        echo "  ✓ All map files are identical (hash: ${unique_map_hashes[0]})"
        map_deterministic=true
    else
        echo "  ✗ NONDETERMINISM DETECTED in map files"
        echo "  Found ${#unique_map_hashes[@]} unique map file hashes:"
        for hash in "${unique_map_hashes[@]}"; do
            count=$(printf '%s\n' "${map_hashes[@]}" | grep -c "^${hash}$")
            echo "    - $hash: $count occurrence(s)"
        done
        map_deterministic=false
    fi

    echo ""
    echo "=== Summary ==="
    echo "  Total runs: $NUM_RUNS"
    echo "  Binaries deterministic: $binary_deterministic"
    echo "  Map files deterministic: $map_deterministic"
    echo "  Test outputs: $TEST_OUTPUT_DIR"

    if [[ "$binary_deterministic" == false || "$map_deterministic" == false ]]; then
        echo ""
        echo "To compare differences between runs, use:"
        echo "  diff ${output_dirs[0]}/test_binary.map ${output_dirs[1]}/test_binary.map"
        echo "  hexdump -C ${output_dirs[0]}/test_binary > /tmp/run1.hex"
        echo "  hexdump -C ${output_dirs[1]}/test_binary > /tmp/run2.hex"
        echo "  diff /tmp/run1.hex /tmp/run2.hex"
        exit 1
    fi
}

# Run main function
main
