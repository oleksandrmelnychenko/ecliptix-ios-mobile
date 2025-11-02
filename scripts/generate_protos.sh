#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROTO_SRC_DIR="$PROJECT_ROOT/Protobufs/Sources"
PROTO_GEN_DIR="$PROJECT_ROOT/Protobufs/Generated"

echo "🔨 Generating Swift protobuf files..."
echo "📂 Source directory: $PROTO_SRC_DIR"
echo "📂 Output directory: $PROTO_GEN_DIR"

if [ ! -d "$PROTO_SRC_DIR" ]; then
    echo "❌ Error: Proto source directory not found: $PROTO_SRC_DIR"
    exit 1
fi

PROTOC_PATH=$(which protoc)
PROTOC_GEN_SWIFT=$(which protoc-gen-swift)
PROTOC_GEN_GRPC_SWIFT=$(which protoc-gen-grpc-swift)

if [ -z "$PROTOC_PATH" ]; then
    echo "❌ Error: protoc not found. Install with: brew install protobuf"
    exit 1
fi

if [ -z "$PROTOC_GEN_SWIFT" ]; then
    echo "❌ Error: protoc-gen-swift not found. Install with: brew install swift-protobuf"
    exit 1
fi

if [ -z "$PROTOC_GEN_GRPC_SWIFT" ]; then
    echo "❌ Error: protoc-gen-grpc-swift not found. Install with: brew install grpc-swift"
    exit 1
fi

echo "✅ Found protoc: $PROTOC_PATH"
echo "✅ Found protoc-gen-swift: $PROTOC_GEN_SWIFT"
echo "✅ Found protoc-gen-grpc-swift: $PROTOC_GEN_GRPC_SWIFT"

rm -rf "$PROTO_GEN_DIR"
mkdir -p "$PROTO_GEN_DIR"

PROTO_FILES=$(find "$PROTO_SRC_DIR" -name "*.proto" | sort)
PROTO_COUNT=$(echo "$PROTO_FILES" | wc -l | tr -d ' ')

echo ""
echo "📦 Found $PROTO_COUNT proto files to generate"
echo ""

TOTAL=0
SUCCESS=0
FAILED=0

for PROTO_FILE in $PROTO_FILES; do
    TOTAL=$((TOTAL + 1))
    RELATIVE_PATH="${PROTO_FILE#$PROTO_SRC_DIR/}"
    echo "[$TOTAL/$PROTO_COUNT] Processing: $RELATIVE_PATH"

    PROTO_DIR=$(dirname "$PROTO_FILE")

    if $PROTOC_PATH \
        --proto_path="$PROTO_SRC_DIR" \
        --swift_out="$PROTO_GEN_DIR" \
        --swift_opt=Visibility=Public \
        --grpc-swift_out="$PROTO_GEN_DIR" \
        --grpc-swift_opt=Visibility=Public \
        --plugin="$PROTOC_GEN_SWIFT" \
        --plugin="$PROTOC_GEN_GRPC_SWIFT" \
        "$PROTO_FILE" 2>&1; then
        SUCCESS=$((SUCCESS + 1))
        echo "  ✅ Generated Swift files"
    else
        FAILED=$((FAILED + 1))
        echo "  ❌ Failed to generate"
    fi
    echo ""
done

GENERATED_FILES=$(find "$PROTO_GEN_DIR" -name "*.swift" | wc -l | tr -d ' ')

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Protobuf Generation Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Summary:"
echo "  • Proto files processed: $TOTAL"
echo "  • Successfully generated: $SUCCESS"
echo "  • Failed: $FAILED"
echo "  • Swift files created: $GENERATED_FILES"
echo "  • Output directory: $PROTO_GEN_DIR"
echo ""

if [ $FAILED -gt 0 ]; then
    echo "⚠️  Warning: Some proto files failed to generate"
    exit 1
fi

echo "🎉 All protobuf files generated successfully!"
exit 0
