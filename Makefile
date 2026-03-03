SHELL := /bin/bash

TUI_BIN := ./bin/dcm2nii-resume-tui
TUI_PKG := ./cmd/dcm2nii-resume-tui
SCRIPT := ./dcm2nii-resume.sh

.PHONY: doctor deps tui tui-run bootstrap test-resume clean

doctor:
	@echo "== dcm2nii-resume doctor =="
	@echo
	@if command -v dcm2niix >/dev/null 2>&1; then \
		echo "[OK] dcm2niix: $$(command -v dcm2niix)"; \
	else \
		echo "[WARN] dcm2niix não encontrado no PATH"; \
	fi
	@if command -v go >/dev/null 2>&1; then \
		echo "[OK] go: $$(go version 2>/dev/null)"; \
	else \
		echo "[WARN] go não encontrado"; \
	fi
	@if command -v brew >/dev/null 2>&1; then \
		echo "[OK] brew: $$(command -v brew)"; \
	else \
		echo "[WARN] brew não encontrado"; \
	fi
	@if [ -x "$(TUI_BIN)" ]; then \
		echo "[OK] Bubble Tea TUI bin: $(TUI_BIN)"; \
	else \
		echo "[INFO] Bubble Tea TUI bin ausente: $(TUI_BIN) (rode 'make tui')"; \
	fi
	@echo
	@echo "Sugestão: rode 'make deps' e depois 'make tui-run' para usar a interface full-screen."

deps:
	@if ! command -v go >/dev/null 2>&1; then \
		echo "Go não encontrado."; \
		if command -v brew >/dev/null 2>&1; then \
			read -r -p "Instalar Go via Homebrew? [y/N]: " ans; \
			if [[ "$$ans" =~ ^[Yy]$$ ]]; then \
				brew install go; \
			else \
				echo "Cancelado. Instale Go manualmente e rode 'make deps' novamente."; \
				exit 1; \
			fi; \
		else \
			echo "Homebrew não encontrado. Instale Go manualmente e rode 'make deps' novamente."; \
			exit 1; \
		fi; \
	fi
	go mod tidy

tui: deps
	mkdir -p ./bin
	go build -o $(TUI_BIN) $(TUI_PKG)

tui-run: tui
	DCM2NII_RESUME_SCRIPT=$(SCRIPT) $(TUI_BIN)

bootstrap: doctor deps tui-run

test-resume:
	bash ./scripts/test_resume_smoke.sh

clean:
	rm -rf ./bin
