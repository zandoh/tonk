# Developer entry points. `make tools` installs everything on macOS.
#
# No YAML auto-formatter on purpose: yamlfmt mangles comment-heavy workflow
# files (sentinel leakage in block scalars). yamllint + .editorconfig are the
# formatting gate instead.

.PHONY: check lint test tools adopters help

check: lint test ## everything CI runs (minus the live-runner smoke job)

lint: ## actionlint + yamllint + zizmor + shellcheck on embedded/repo scripts
	actionlint
	yamllint --strict .
	zizmor --no-progress .
	./scripts/extract-step.sh actions/discord-notify/action.yml | shellcheck -s bash -
	shellcheck scripts/*.sh

test: ## bats suite for the scripts embedded in the YAML
	bats tests

tools: ## install dev tooling (macOS/Homebrew)
	brew install actionlint yamllint shellcheck bats-core zizmor yq

adopters: ## public repos referencing tonk (GitHub code search; needs gh auth)
	@gh search code 'zandoh/tonk' --limit 100 --json repository \
	  --jq '[.[].repository.nameWithOwner] | unique | .[]' \
	  | grep -vx 'zandoh/tonk' || echo "none found (or search unavailable)"

help: ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-8s %s\n", $$1, $$2}'
