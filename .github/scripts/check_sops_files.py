#!/usr/bin/env python3

"""
Check the SOPS-encrypted files of the repository, without decrypting them.

For every file matching a creation rule of .sops.yaml:
- Ensure it is encrypted: all its values are ENC[...] strings
- Ensure it is encrypted for exactly the AGE recipients of its rule

YAML is parsed by PyYAML, which handles anchors of .sops.yaml.
"""

import re
import sys
from collections.abc import Iterator
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
JSON = dict[str, "JSON"] | list["JSON"] | str | int | float | bool | None

# SOPS options changing which values are encrypted: not handled, fail explicitly if a file uses them
UNSUPPORTED_OPTIONS = (
    "encrypted_regex",
    "unencrypted_regex",
    "encrypted_suffix",
    "encrypted_comment_regex",
    "unencrypted_comment_regex",
)


def load_yaml(path: Path) -> JSON:
    with path.open() as file:
        return yaml.safe_load(file)


def _get_age_keys(value: str | list[str] | None) -> set[str]:
    if isinstance(value, str):
        value = value.split(",")
    return {key.strip() for key in value or [] if key.strip()}


def rule_recipients(rule: dict) -> set[str]:
    recipients = _get_age_keys(rule.get("age"))
    for group in rule.get("key_groups") or []:
        recipients |= _get_age_keys(group.get("age"))
    return recipients


def plaintext_values(node: JSON, unencrypted_suffix: str, location: str = "") -> Iterator[str]:
    """
    Yield the location of every value that is not an ENC[...] string
    """
    if isinstance(node, dict):
        for key, value in node.items():
            # The whole subtree of an unencrypted key is left in clear by sops
            if not str(key).endswith(unencrypted_suffix):
                yield from plaintext_values(value, unencrypted_suffix, f"{location}.{key}")
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from plaintext_values(value, unencrypted_suffix, f"{location}[{index}]")
    elif node is not None and not (isinstance(node, str) and node.startswith("ENC[")):
        yield location


def check_file(relative: str, rule: dict) -> list[str]:
    document = load_yaml(ROOT / relative)
    metadata = document.get("sops") if isinstance(document, dict) else None
    if not isinstance(metadata, dict) or not metadata.get("mac"):
        return ["not encrypted (no sops metadata): encrypt it with `make sops-encrypt SOPS_FILE=...`"]

    errors = [f"uses {option}, not handled by this check" for option in UNSUPPORTED_OPTIONS if metadata.get(option)]

    expected = rule_recipients(rule)
    current = {entry.get("recipient") for entry in metadata.get("age") or []}
    if current != expected:
        errors.append(
            "age recipients differ from .sops.yaml "
            f"(missing: {sorted(expected - current) or 'none'}, extra: {sorted(current - expected) or 'none'}): "
            "run `make sops-rotate-keys`"
        )

    content = {key: value for key, value in document.items() if key != "sops"}
    if leaks := list(plaintext_values(content, metadata.get("unencrypted_suffix") or "_unencrypted")):
        errors.append(f"plaintext values: {', '.join(leaks)}")
    return errors


def main() -> int:
    sops_config = ROOT / ".sops.yaml"

    if not sops_config.exists():
        print("No .sops.yaml: nothing to check")
        return 0

    # Only rules with a path_regex designate files meant to be encrypted (a catch-all rule matches everything)
    rules = [rule for rule in load_yaml(sops_config).get("creation_rules") or [] if rule.get("path_regex")]

    checked = failed = 0
    for path in sorted(ROOT.rglob("*")):
        relative = path.relative_to(ROOT).as_posix()
        if not path.is_file() or relative.startswith(".git/"):
            continue

        # The first matching rule applies (like sops)
        rule = next((rule for rule in rules if re.search(rule["path_regex"], relative)), None)
        if rule is None:
            continue

        checked += 1
        for error in check_file(relative, rule):
            failed += 1
            print(f"::error file={relative}::{error}")

    print(f"{checked} SOPS-encrypted file(s) checked, {failed} error(s)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
