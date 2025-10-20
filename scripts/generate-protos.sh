#!/bin/bash

# Protocol Buffer and gRPC Swift Code Generation Script
# This script generates Swift code from .proto files

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Protocol Buffer Swift code generation...${NC}\n"

# Directories
PROTO_DIR="Protos"
GENERATED_DIR="Generated"
NETWORKING_PACKAGE="Packages/EcliptixNetworking/Sources/Generated"

# Check if running from project root
if [ ! -d "$PROTO_DIR" ]; then
    echo -e "${RED}Error: Protos directory not found. Run this script from the project root.${NC}"
    exit 1
fi

# Check if protoc is installed
if ! command -v protoc &> /dev/null; then
    echo -e "${RED}Error: protoc is not installed${NC}"
    echo -e "${YELLOW}Install with: brew install protobuf${NC}"
    exit 1
fi

# Check if swift-protobuf plugin is installed
if ! command -v protoc-gen-swift &> /dev/null; then
    echo -e "${YELLOW}Warning: protoc-gen-swift not found in PATH${NC}"
    echo -e "${YELLOW}Install with: brew install swift-protobuf${NC}"
    echo -e "${YELLOW}Or build from source: https://github.com/apple/swift-protobuf${NC}"
fi

# Check if grpc-swift plugin is installed
if ! command -v protoc-gen-grpc-swift &> /dev/null; then
    echo -e "${YELLOW}Warning: protoc-gen-grpc-swift not found in PATH${NC}"
    echo -e "${YELLOW}Install grpc-swift from: https://github.com/grpc/grpc-swift${NC}"
fi

# Create output directories
mkdir -p "$GENERATED_DIR"
mkdir -p "$NETWORKING_PACKAGE"

echo -e "${GREEN}Cleaning previous generated files...${NC}"
rm -rf "$GENERATED_DIR"/*
rm -rf "$NETWORKING_PACKAGE"/*

# Find all .proto files
PROTO_FILES=$(find "$PROTO_DIR" -name "*.proto" | sort)

if [ -z "$PROTO_FILES" ]; then
    echo -e "${RED}Error: No .proto files found in $PROTO_DIR${NC}"
    exit 1
fi

echo -e "${GREEN}Found proto files:${NC}"
echo "$PROTO_FILES" | while read -r file; do
    echo -e "  - $file"
done
echo ""

# Generate Swift code
echo -e "${GREEN}Generating Swift Protocol Buffer code...${NC}"

protoc \
    --proto_path="$PROTO_DIR" \
    --swift_out="$GENERATED_DIR" \
    --swift_opt=Visibility=Public \
    --swift_opt=FileNaming=PathToUnderscores \
    $PROTO_DIR/**/*.proto

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Swift Protocol Buffer models generated${NC}"
else
    echo -e "${RED}✗ Failed to generate Swift Protocol Buffer models${NC}"
    exit 1
fi

# Generate gRPC service code
echo -e "${GREEN}Generating gRPC Swift service stubs...${NC}"

protoc \
    --proto_path="$PROTO_DIR" \
    --grpc-swift_out="$GENERATED_DIR" \
    --grpc-swift_opt=Visibility=Public \
    --grpc-swift_opt=FileNaming=PathToUnderscores \
    --grpc-swift_opt=Client=true \
    --grpc-swift_opt=Server=false \
    $PROTO_DIR/**/*.proto 2>/dev/null || true

if [ $? -eq 0 ] || [ -n "$(ls -A $GENERATED_DIR/*.grpc.swift 2>/dev/null)" ]; then
    echo -e "${GREEN}✓ gRPC service stubs generated${NC}"
else
    echo -e "${YELLOW}⚠ gRPC generation skipped (protoc-gen-grpc-swift not found)${NC}"
fi

# Copy generated files to package
echo -e "${GREEN}Copying generated files to Networking package...${NC}"
cp -r "$GENERATED_DIR"/* "$NETWORKING_PACKAGE/" 2>/dev/null || true

# Count generated files
PB_COUNT=$(find "$GENERATED_DIR" -name "*.pb.swift" | wc -l | tr -d ' ')
GRPC_COUNT=$(find "$GENERATED_DIR" -name "*.grpc.swift" | wc -l | tr -d ' ')

echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}Generation Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "  Protocol Buffer models: ${GREEN}$PB_COUNT${NC} files"
echo -e "  gRPC service stubs:     ${GREEN}$GRPC_COUNT${NC} files"
echo -e "  Output directory:       ${YELLOW}$GENERATED_DIR${NC}"
echo -e "  Package location:       ${YELLOW}$NETWORKING_PACKAGE${NC}"
echo ""
echo -e "${YELLOW}Note: Add generated files to Xcode project if not auto-detected${NC}"
echo ""
