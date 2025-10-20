.PHONY: help setup generate-protos clean build test

help:
	@echo "Ecliptix iOS - Available Commands"
	@echo "=================================="
	@echo "make setup           - Install dependencies and tools"
	@echo "make generate-protos - Generate Swift code from .proto files"
	@echo "make clean          - Clean generated files and build artifacts"
	@echo "make build          - Build the project"
	@echo "make test           - Run tests"
	@echo ""

setup:
	@echo "Installing Protocol Buffer tools..."
	@command -v protoc >/dev/null 2>&1 || echo "⚠️  Install protoc: brew install protobuf"
	@command -v protoc-gen-swift >/dev/null 2>&1 || echo "⚠️  Install swift-protobuf: brew install swift-protobuf"
	@echo "✓ Setup check complete"
	@echo ""
	@echo "For gRPC Swift, clone and build:"
	@echo "git clone https://github.com/grpc/grpc-swift.git"
	@echo "cd grpc-swift && make plugins"
	@echo ""

generate-protos:
	@echo "Generating Protocol Buffer Swift code..."
	@./scripts/generate-protos.sh

clean:
	@echo "Cleaning generated files..."
	@rm -rf Generated/
	@rm -rf Packages/*/Sources/Generated/
	@rm -rf .build/
	@echo "✓ Clean complete"

build:
	@echo "Building project..."
	@swift build

test:
	@echo "Running tests..."
	@swift test

.DEFAULT_GOAL := help
