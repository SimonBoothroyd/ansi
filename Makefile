# Mise task runner. Run `make help` for the list.
# Env for the app comes from .env.local (see .env.local.template).
SHELL := /bin/bash
APP := app
FNS := supabase/functions

# Load .env.local if present, so `make run`/`test` can pass --dart-define.
ifneq (,$(wildcard ./.env.local))
include .env.local
export
endif

DART_DEFINES := \
	--dart-define=SUPABASE_URL=$(SUPABASE_URL) \
	--dart-define=SUPABASE_ANON_KEY=$(SUPABASE_ANON_KEY) \
	--dart-define=POWERSYNC_URL=$(POWERSYNC_URL)

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n",$$1,$$2}'

# --- setup ---
.PHONY: bootstrap
bootstrap: ## Check tooling + install deps
	./scripts/bootstrap.sh

.PHONY: deps
deps: ## Fetch Flutter packages
	cd $(APP) && flutter pub get

.PHONY: gen
gen: ## Run code generation (Riverpod/Freezed/json)
	cd $(APP) && dart run build_runner build --delete-conflicting-outputs

.PHONY: watch
watch: ## Code generation in watch mode
	cd $(APP) && dart run build_runner watch --delete-conflicting-outputs

.PHONY: app-seed
app-seed: ## Sync the bundled ingredient vocab asset from the seed source
	cp supabase/seed/vocab.jsonl $(APP)/assets/seed/vocab.jsonl

# --- run ---
.PHONY: run
run: ## Run the app (uses .env.local)
	cd $(APP) && flutter run $(DART_DEFINES)

.PHONY: run-web
run-web: ## Run the app in Chrome
	cd $(APP) && flutter run -d chrome $(DART_DEFINES)

# --- quality gates ---
.PHONY: analyze
analyze: ## Static analysis (fails on any issue)
	cd $(APP) && flutter analyze
	cd $(APP) && dart run custom_lint

.PHONY: format
format: ## Format Dart + check
	cd $(APP) && dart format --set-exit-if-changed .

.PHONY: test test-app test-fns test-sim powersync-core
test: test-app test-fns ## Run all tests

test-app: powersync-core ## Flutter unit + widget tests
	cd $(APP) && flutter test

powersync-core: ## Fetch the PowerSync SQLite core extension for host tests
	@./scripts/fetch_powersync_core.sh

test-sim: ## Integration smoke on a booted iOS simulator (local gate, not CI)
	cd $(APP) && flutter test integration_test $(DART_DEFINES)

test-fns: ## Edge-function (Deno) tests
	cd $(FNS) && deno test

.PHONY: coverage
coverage: ## Flutter tests with coverage
	cd $(APP) && flutter test --coverage
	@echo "lcov at $(APP)/coverage/lcov.info"

# --- backend ---
.PHONY: db-up db-down db-lint db-reset
db-up: ## Start Supabase + local PowerSync
	supabase start
	docker compose --file ./docker/compose.yaml --env-file .env.local up -d

db-down: ## Stop local backend
	docker compose --file ./docker/compose.yaml down
	supabase stop

db-reset: ## Reset local DB, re-run migrations + seed
	supabase db reset

db-lint: ## Sanity-check migrations
	supabase db lint || true

# --- evals ---
.PHONY: evals
evals: ## Run the import/matching eval harness
	cd evals && ./runner/run.sh

# --- docs (knowledge base) ---
.PHONY: docs docs-check
docs: ## Regenerate generated docs (docs/generated/*)
	./scripts/gen_docs.sh

docs-check: ## Validate the knowledge base (links + required files)
	./scripts/check_docs.sh

.PHONY: ci
ci: format analyze test docs-check ## What CI runs
