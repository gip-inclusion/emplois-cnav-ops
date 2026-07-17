##@ SOPS


.PHONY: sops-edit
sops-edit: guard-SOPS_FILE  ## Edit encrypted secrets in $EDITOR (SOPS_FILE=charts/.../values-<env>.enc.yaml)
	@printf "%b[%s] Edit %s%b\n" "$(OK_COLOR)" "$(BANNER)" "$(SOPS_FILE)" "$(NO_COLOR)"
	@sops $(SOPS_FILE)

.PHONY: sops-encrypt
sops-encrypt: guard-SOPS_FILE  ## Encrypt secrets file in place (SOPS_FILE=charts/.../values-<env>.enc.yaml)
	@printf "%b[%s] Encrypt %s%b\n" "$(OK_COLOR)" "$(BANNER)" "$(SOPS_FILE)" "$(NO_COLOR)"
	@sops -e -i $(SOPS_FILE)

.PHONY: sops-decrypt
sops-decrypt: guard-SOPS_FILE  ## Decrypt secrets file to stdout (SOPS_FILE=charts/.../values-<env>.enc.yaml)
	@sops -d $(SOPS_FILE)

.PHONY: sops-rotate-keys
sops-rotate-keys:  ## Re-wrap data key on every encrypted file (run after editing .sops.yaml)
	@printf "%b[%s] Rotate keys on all *.enc.yaml%b\n" "$(OK_COLOR)" "$(BANNER)" "$(NO_COLOR)"
	@set -e; \
	find . -type f -name "*.enc.yaml" \
		| sort -u \
		| while read f; do \
			echo "Updating keys in $$f"; \
			sops updatekeys --yes "$$f"; \
		done
