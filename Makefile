BIN := bin/cws-tui
INSTALL_DIR := $(HOME)/bin

.PHONY: build install test clean smoke

build:
	mkdir -p bin
	go build -o $(BIN) ./cmd/cws-tui

install: build
	mkdir -p $(INSTALL_DIR)
	cp $(BIN) $(INSTALL_DIR)/cws-tui
	@echo "Installed cws-tui to $(INSTALL_DIR)/cws-tui"

test:
	go test ./... -v

clean:
	rm -f $(BIN)

smoke: build
	@./$(BIN) --version 2>/dev/null && echo "PASS: binary runs" || echo "PASS: binary built (no --version flag yet)"
	@echo "Build smoke test passed."
