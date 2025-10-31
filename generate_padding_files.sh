#!/bin/bash

set -euo pipefail

# Configuration
NUM_FILES=${NUM_FILES:-2}
OUTPUT_DIR=${OUTPUT_DIR:-"$(pwd)/padding_outputs"}
PADDING_SIZE=${PADDING_SIZE:-67108864}  # 64MB = 64 * 1024 * 1024
SDK_PATH=${SDK_PATH:-$(xcrun --sdk iphoneos --show-sdk-path)}
TARGET=${TARGET:-"arm64-apple-ios15.0"}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Generate padding object files with configurable sizes for linker layout testing.

OPTIONS:
    -n, --num-files NUM      Number of padding files to generate (default: 2)
    -o, --output-dir DIR     Output directory for padding files and .o files (default: ./padding_outputs)
    -p, --padding-size SIZE  Size of padding in bytes (default: 67108864 = 64MB)
    -s, --sdk PATH           Path to SDK (default: iPhone SDK)
    --target TRIPLE          Target triple (default: arm64-apple-ios15.0)
    -h, --help               Show this help message

EXAMPLES:
    # Generate 2 padding files with default size (64MB each = 128MB total)
    # This forces branch islands due to binary size >128MB
    $0

    # Generate 4 files with 32MB padding each
    $0 -n 4 -p 33554432

    # Generate padding files in custom directory
    $0 -n 2 -p 67108864 -o /tmp/padding_test

    # Specify target
    $0 --num-files 2 --padding-size 67108864 --target arm64-apple-ios16.0
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
        -p|--padding-size)
            PADDING_SIZE="$2"
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

# Function to generate assembly source with padding
generate_padding_asm() {
    local index=$1
    local output_file=$2
    local size=$3

    # Convert size to hex for .space directive
    local size_hex=$(printf "0x%x" $size)

    cat > "$output_file" << EOF
    .section __TEXT,__text,regular,pure_instructions
    .globl _pad${index}_start
_pad${index}_start:
    .space $size_hex
    .globl _pad${index}_end
_pad${index}_end:
EOF
}

# Function to assemble .s file to .o
assemble_file() {
    local asm_file=$1
    local object_file=$2

    xcrun clang -c \
        "$asm_file" \
        -o "$object_file" \
        -arch arm64 \
        -isysroot "$SDK_PATH" \
        -target "$TARGET"
}

# Main execution
main() {
    echo "=== Padding File Generator for Linker Testing ==="
    echo "Configuration:"
    echo "  Number of files: $NUM_FILES"
    echo "  Output directory: $OUTPUT_DIR"
    echo "  Padding size: $PADDING_SIZE bytes"
    echo "  SDK: $SDK_PATH"
    echo "  Target: $TARGET"
    echo ""

    # Create output directories
    mkdir -p "$OUTPUT_DIR/sources"
    mkdir -p "$OUTPUT_DIR/objects"

    # Clean previous outputs if they exist
    echo "Cleaning previous outputs..."
    rm -f "$OUTPUT_DIR/sources"/*.s
    rm -f "$OUTPUT_DIR/objects"/*.o

    # Generate assembly files
    echo "Generating $NUM_FILES assembly files with $PADDING_SIZE byte padding..."
    for i in $(seq 0 $((NUM_FILES - 1))); do
        asm_file="$OUTPUT_DIR/sources/Padding_$(printf "%05d" $i).s"
        generate_padding_asm $i "$asm_file" "$PADDING_SIZE"

        if (( (i + 1) % 50 == 0 )); then
            echo "  Generated $((i + 1))/$NUM_FILES files..."
        fi
    done
    echo "✓ Generated $NUM_FILES assembly files"

    # Assemble files to .o files
    echo "Assembling files to object files..."
    local success_count=0
    local failed_count=0

    for i in $(seq 0 $((NUM_FILES - 1))); do
        asm_file="$OUTPUT_DIR/sources/Padding_$(printf "%05d" $i).s"
        object_file="$OUTPUT_DIR/objects/Padding_$(printf "%05d" $i).o"

        if assemble_file "$asm_file" "$object_file" 2>/dev/null; then
            ((success_count++))
        else
            ((failed_count++))
            echo "  Failed to assemble: $asm_file"
        fi

        if (( (i + 1) % 50 == 0 )); then
            echo "  Assembled $((i + 1))/$NUM_FILES files..."
        fi
    done

    echo ""
    echo "=== Summary ==="
    echo "  Assembly files generated: $NUM_FILES"
    echo "  Successfully assembled: $success_count"
    if (( failed_count > 0 )); then
        echo "  Failed assemblies: $failed_count"
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
