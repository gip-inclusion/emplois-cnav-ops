DEBUG ?=

DIR = $(shell pwd)

BOLD = \033[1m
ITALIC = \033[3m
UNDERLINE = \033[4m

NO_COLOR = \033[0m
OK_COLOR = \033[32;01m
ERROR_COLOR = \033[31;01m
WARNING_COLOR = \033[33;01m
INFO_COLOR = \033[36m
WHITE_COLOR = \033[1m

BANNER = "GIP-Inclusion-emplois-cnav-ops"

.DEFAULT_GOAL := help


.PHONY: help
help:
	@printf "%b " "${WHITE_COLOR}${BOLD}${BANNER}${NO_COLOR}"
	@printf "%b" "\n=================================================================\n"
	@printf "%b\n" "${WHITE_COLOR}Usage${NO_COLOR}: make ${INFO_COLOR}<target>${NO_COLOR}"
	@awk 'BEGIN {FS = ":.*##"; } /^[a-zA-Z_-]+:.*?##/ { printf "  ${INFO_COLOR}%-30s${NO_COLOR} %s\n", $$1, $$2 } /^##@/ { printf "\n${WHITE_COLOR}%s${NO_COLOR}\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@echo ""

guard-%:
	@if [ "${${*}}" = "" ]; then \
		printf "%b\n" "$(ERROR_COLOR)Environment variable $* not set$(NO_COLOR)"; \
		exit 1; \
	fi
