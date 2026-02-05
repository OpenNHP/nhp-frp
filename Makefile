export PATH := $(PATH):`go env GOPATH`/bin
export GO111MODULE=on
LDFLAGS := -s -w
OS_NAME = $(shell uname -s | tr A-Z a-z)
# OpenNHP submodule directory
OPENNHP_DIR = third_party/opennhp

all: env fmt build

build: frps frpc

env:
	@go version

# compile assets into binary file
file:
	rm -rf ./assets/frps/static/*
	rm -rf ./assets/frpc/static/*
	cp -rf ./web/frps/dist/* ./assets/frps/static
	cp -rf ./web/frpc/dist/* ./assets/frpc/static

fmt:
	go fmt ./...

fmt-more:
	gofumpt -l -w .

gci:
	gci write -s standard -s default -s "prefix(github.com/fatedier/frp/)" ./

vet:
	go vet ./...

frps:
	env CGO_ENABLED=0 go build -trimpath -ldflags "$(LDFLAGS)" -tags frps -o bin/frps ./cmd/frps

# Build OpenNHP SDK from submodule
build-sdk:
	@echo "[Nhp-frp] Building OpenNHP SDK from submodule..."
ifeq ($(OS_NAME), linux)
	@$(MAKE) build-sdk-linux
else ifeq ($(OS_NAME), darwin)
	@$(MAKE) build-sdk-macos
else
	@echo "[Nhp-frp] Skipping SDK build on ${OS_NAME}, use build.bat for Windows"
endif

build-sdk-linux:
	@echo "[Nhp-frp] Building Linux SDK (nhp-agent.so)..."
	@cd $(OPENNHP_DIR)/nhp && go mod tidy
	@cd $(OPENNHP_DIR)/endpoints && go mod tidy
	@cd $(OPENNHP_DIR)/endpoints && \
		go build -a -trimpath -buildmode=c-shared -ldflags="-w -s" -v \
		-o ../../../sdk/nhp-agent.so ./agent/main/main.go ./agent/main/export.go
	@echo "[Nhp-frp] Linux SDK built successfully!"
	@cd $(OPENNHP_DIR)/nhp && git restore go.mod go.sum 2>/dev/null || git checkout go.mod go.sum 2>/dev/null || true
	@cd $(OPENNHP_DIR)/endpoints && git restore go.mod go.sum 2>/dev/null || git checkout go.mod go.sum 2>/dev/null || true
	@cd $(OPENNHP_DIR) && git reset --hard HEAD 2>/dev/null || true

build-sdk-macos:
	@echo "[Nhp-frp] Building macOS SDK (nhp-agent.dylib)..."
	@cd $(OPENNHP_DIR)/nhp && go mod tidy
	@cd $(OPENNHP_DIR)/endpoints && go mod tidy
	@cd $(OPENNHP_DIR)/endpoints && \
		GOOS=darwin GOARCH=arm64 CGO_ENABLED=1 \
		go build -a -trimpath -buildmode=c-shared -ldflags="-w -s" -v \
		-o ../../../sdk/nhp-agent.dylib ./agent/main/main.go ./agent/main/export.go
	@echo "[Nhp-frp] macOS SDK built successfully!"
	@cd $(OPENNHP_DIR)/nhp && git restore go.mod go.sum 2>/dev/null || git checkout go.mod go.sum 2>/dev/null || true
	@cd $(OPENNHP_DIR)/endpoints && git restore go.mod go.sum 2>/dev/null || git checkout go.mod go.sum 2>/dev/null || true
	@cd $(OPENNHP_DIR) && git reset --hard HEAD 2>/dev/null || true

# Clean SDK binaries
clean-sdk:
	@echo "[Nhp-frp] Cleaning SDK binaries..."
	rm -f sdk/nhp-agent.so sdk/nhp-agent.dylib sdk/nhp-agent.dll sdk/nhp-agent.h

frpc: build-sdk
	@mkdir -p ./bin/sdk
	cp ./sdk/nhp-agent.* ./bin/sdk/ 2>/dev/null 
	go build -trimpath -ldflags "$(LDFLAGS)" -tags frpc -o bin/frpc ./cmd/frpc
ifeq ($(OS_NAME), darwin)
	install_name_tool -change nhp-agent.dylib ./bin/sdk/nhp-agent.dylib ./bin/frpc
endif

test: gotest

gotest:
	go test -v --cover ./assets/...
	go test -v --cover ./cmd/...
	go test -v --cover ./client/...
	go test -v --cover ./server/...
	go test -v --cover ./pkg/...

e2e:
	./hack/run-e2e.sh

e2e-trace:
	DEBUG=true LOG_LEVEL=trace ./hack/run-e2e.sh

e2e-compatibility-last-frpc:
	if [ ! -d "./lastversion" ]; then \
		TARGET_DIRNAME=lastversion ./hack/download.sh; \
	fi
	FRPC_PATH="`pwd`/lastversion/frpc" ./hack/run-e2e.sh
	rm -r ./lastversion

e2e-compatibility-last-frps:
	if [ ! -d "./lastversion" ]; then \
		TARGET_DIRNAME=lastversion ./hack/download.sh; \
	fi
	FRPS_PATH="`pwd`/lastversion/frps" ./hack/run-e2e.sh
	rm -r ./lastversion

alltest: vet gotest e2e
	
clean:
	rm -f ./bin/frpc
	rm -f ./bin/frps
	rm -rf ./lastversion
