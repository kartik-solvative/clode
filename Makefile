BIN         := bin/cws-tui
INSTALL_DIR := $(HOME)/bin
CWS_SCRIPT  := $(HOME)/Projects/clode/clode-ws.sh

.PHONY: build install test clean smoke

build:
	mkdir -p bin
	go build -o $(BIN) ./cmd/cws-tui

install: build
	mkdir -p $(INSTALL_DIR)
	cp $(BIN) $(INSTALL_DIR)/cws-tui
	@echo "Installed: $(INSTALL_DIR)/cws-tui"
	@echo "Ensure $(INSTALL_DIR) is in PATH."

test:
	go test ./... -v

clean:
	rm -f $(BIN)

smoke: build
	@echo "==> binary help flag"
	@./$(BIN) --help
	@echo "==> shell: all three navigate functions removed"
	@zsh -c 'source $(CWS_SCRIPT); \
	    type _cws_navigate_project 2>&1 | grep -q "not found" \
	    && echo "PASS: _cws_navigate_project removed" \
	    || echo "FAIL: _cws_navigate_project still present"'
	@zsh -c 'source $(CWS_SCRIPT); \
	    type _cws_navigate_worktree 2>&1 | grep -q "not found" \
	    && echo "PASS: _cws_navigate_worktree removed" \
	    || echo "FAIL: _cws_navigate_worktree still present"'
	@zsh -c 'source $(CWS_SCRIPT); \
	    type _cws_navigate_terminal 2>&1 | grep -q "not found" \
	    && echo "PASS: _cws_navigate_terminal removed" \
	    || echo "FAIL: _cws_navigate_terminal still present"'
	@echo "==> shell: clode-ws list still works"
	@zsh -c 'source $(CWS_SCRIPT); clode-ws list 2>&1 | head -3'
	@echo "==> smoke tests complete"
