# Ansi task runner. Run `make help` for the list.
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
	@# firstword, not $(MAKEFILE_LIST): the `include .env.local` above makes the
	@# list two files, and grep then prefixes every hit with "Makefile:" — which
	@# the awk below prints as the target name, hiding every real one.
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(firstword $(MAKEFILE_LIST)) \
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

# One file per flow under integration_test/; each provisions its own household.
# FILE=week runs integration_test/week_test.dart alone; DEVICE=<udid> targets a
# specific booted simulator (parallel lanes run on separate sims).
test-sim: ## Integration smoke on a booted iOS sim: the directory, or FILE=<name> for one file; DEVICE=<udid> picks the sim (needs the local backend up: make db-up)
	cd $(APP) && flutter test $(if $(FILE),integration_test/$(FILE)_test.dart,integration_test) $(if $(DEVICE),-d $(DEVICE)) $(DART_DEFINES)

test-fns: ## Edge-function (Deno) tests
	cd $(FNS) && deno task test

.PHONY: coverage
coverage: ## Flutter tests with coverage
	cd $(APP) && flutter test --coverage
	@echo "lcov at $(APP)/coverage/lcov.info"

# --- backend ---
.PHONY: db-up db-down db-lint db-reset
db-up: ## Start Supabase + local PowerSync (functions need: make functions-up)
	supabase start
	docker compose --file ./docker/compose.yaml --env-file .env.local up -d
	@echo "NOTE: edge functions are NOT served by db-up — run 'make functions-up' for import"

.PHONY: functions-up
functions-up: ## Serve edge functions locally (import-recipe needs this + .env.local keys)
	supabase functions serve --env-file .env.local

db-down: ## Stop local backend
	docker compose --file ./docker/compose.yaml down
	supabase stop

db-reset: ## Reset local DB, re-run migrations + seed
	supabase db reset

db-lint: ## Sanity-check migrations (+ the rollout script ↔ pgTAP mirror)
	supabase db lint || true
	@diff <(sed -n '/^-- >>> rollout_measure_refresh/,/^-- <<< rollout_measure_refresh/p' supabase/rollout_measure_refresh.sql) \
	      <(sed -n '/^-- >>> rollout_measure_refresh/,/^-- <<< rollout_measure_refresh/p' supabase/tests/measure_rollout.sql) \
	  && echo "rollout mirror: supabase/rollout_measure_refresh.sql == tests/measure_rollout.sql" \
	  || { echo "rollout mirror DRIFTED: edit the marked block in both files"; exit 1; }

# --- evals ---
.PHONY: evals
evals: ## Run the import/matching eval harness
	cd evals && ./runner/run.sh

# --- audits (local-only; need the stack up) ---
# The density/admission review HTML page is built from the audit.json this
# target produces: scripts/export_vocab.sh dumps the TEMPLATE household's vocab
# from Postgres, then app/tool/density_audit.dart re-runs the shipped domain
# derivation (allowedUnitsFor / rankedUnitChips) over it. Deliberately NOT in
# CI — it reads the local Supabase stack, so it stays a one-command local tool.
.PHONY: vocab-audit
vocab-audit: ## Dump template vocab + derived unit admission to scratch/audit.json (needs: make db-up)
	@mkdir -p scratch
	./scripts/export_vocab.sh > scratch/vocab.json
	cd $(APP) && dart run tool/density_audit.dart ../scratch/vocab.json > ../scratch/audit.json
	@echo "scratch/vocab.json → scratch/audit.json (feeds the density/admission page)"

# --- docs (knowledge base) ---
.PHONY: docs docs-check
docs: ## Regenerate generated docs (docs/generated/*)
	./scripts/gen_docs.sh

docs-check: ## Validate the knowledge base (links + required files)
	./scripts/check_docs.sh

.PHONY: ci
ci: format analyze test docs-check ## What CI runs
