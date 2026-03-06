.PHONY: help build dry-run-tests stage2-tests stage3-tests stage4-tests quality quality-fast \
	live-smoke live-smoke-write release-prep release-prep-fast \
	release-notes release-tag-dry-run

help:
	@echo "Available targets:"
	@echo "  make build               - Build and install app"
	@echo "  make dry-run-tests       - Run dry-run logic tests"
	@echo "  make stage2-tests        - Run Stage 2 reliability tests"
	@echo "  make stage3-tests        - Run Stage 3 workflow tests"
	@echo "  make stage4-tests        - Run Stage 4 release-tag tests"
	@echo "  make quality             - Full quality gate"
	@echo "  make quality-fast        - Quality gate without build"
	@echo "  make live-smoke          - Live Plex smoke (read-only)"
	@echo "  make live-smoke-write    - Live Plex smoke + non-destructive write checks"
	@echo "  make release-prep        - Release prep with report + release notes"
	@echo "  make release-prep-fast   - Release prep without build"
	@echo "  make release-notes       - Generate release notes draft"
	@echo "  make release-tag-dry-run - Prepare release tag assets (requires VERSION=vX.Y.Z)"

build:
	./build_swift_app.sh

dry-run-tests:
	./run_dry_run_tests.sh

stage2-tests:
	./run_stage2_tests.sh

stage3-tests:
	./run_stage3_tests.sh

stage4-tests:
	./run_stage4_tests.sh

quality:
	./run_quality_gate.sh $(QUALITY_ARGS)

quality-fast:
	./run_quality_gate.sh --skip-build $(QUALITY_ARGS)

live-smoke:
	./run_live_plex_smoke.sh $(LIVE_SMOKE_ARGS)

live-smoke-write:
	./run_live_plex_smoke.sh --include-write $(LIVE_SMOKE_ARGS)

release-prep:
	./run_release_prep.sh $(RELEASE_PREP_ARGS)

release-prep-fast:
	./run_release_prep.sh --skip-build $(RELEASE_PREP_ARGS)

release-notes:
	./generate_release_notes.sh --to-ref HEAD $(RELEASE_NOTES_ARGS)

release-tag-dry-run:
	@if [ -z "$(VERSION)" ]; then \
		echo "Usage: make release-tag-dry-run VERSION=vX.Y.Z"; \
		exit 2; \
	fi
	./create_release_tag.sh --version "$(VERSION)" $(RELEASE_TAG_ARGS)
