#!/usr/bin/env python3
"""Qualify the NSG module source only inside the disposable OpenTofu copy."""

from __future__ import annotations

import os
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


ORIGINAL_SOURCE = "miljodir/nsg/azurerm"
QUALIFIED_SOURCE = "registry.terraform.io/miljodir/nsg/azurerm"


@dataclass(frozen=True)
class Token:
    kind: str
    value: str
    start: int
    end: int
    line: int


def _tokens(source: str) -> list[Token]:
    tokens: list[Token] = []
    index = 0
    line = 1

    while index < len(source):
        char = source[index]

        if char.isspace():
            if char == "\n":
                line += 1
            index += 1
            continue

        if char == "#" or source.startswith("//", index):
            newline = source.find("\n", index)
            if newline == -1:
                break
            index = newline
            continue

        if source.startswith("/*", index):
            end = source.find("*/", index + 2)
            if end == -1:
                raise ValueError("Unterminated block comment.")
            line += source.count("\n", index, end + 2)
            index = end + 2
            continue

        if source.startswith("<<", index):
            heredoc = re.match(r"<<(-?)([A-Za-z_][A-Za-z0-9_]*)", source[index:])
            if heredoc:
                marker = heredoc.group(2)
                indented = bool(heredoc.group(1))
                start = index
                start_line = line
                newline = source.find("\n", index)
                if newline == -1:
                    raise ValueError("Unterminated heredoc.")
                index = newline + 1
                line += 1
                while index <= len(source):
                    newline = source.find("\n", index)
                    end = len(source) if newline == -1 else newline
                    content = source[index:end].rstrip("\r")
                    if (content.lstrip() if indented else content) == marker:
                        index = end if newline == -1 else newline + 1
                        if newline != -1:
                            line += 1
                        break
                    if newline == -1:
                        raise ValueError("Unterminated heredoc.")
                    index = newline + 1
                    line += 1
                tokens.append(Token("heredoc", marker, start, index, start_line))
                continue

        if char == '"':
            start = index
            start_line = line
            index += 1
            value_start = index
            escaped = False
            while index < len(source):
                current = source[index]
                if current == "\n":
                    line += 1
                if escaped:
                    escaped = False
                elif current == "\\":
                    escaped = True
                elif current == '"':
                    tokens.append(
                        Token("string", source[value_start:index], start, index + 1, start_line)
                    )
                    index += 1
                    break
                index += 1
            else:
                raise ValueError("Unterminated quoted string.")
            continue

        if char in "{}=":
            tokens.append(Token(char, char, index, index + 1, line))
            index += 1
            continue

        if char.isalpha() or char in "_-":
            start = index
            while index < len(source) and (
                source[index].isalnum() or source[index] in "_-"
            ):
                index += 1
            tokens.append(Token("identifier", source[start:index], start, index, line))
            continue

        tokens.append(Token("other", char, index, index + 1, line))
        index += 1

    return tokens


def qualify_nsg_source(source: str) -> str:
    tokens = _tokens(source)
    depth = 0
    target_depth: int | None = None
    target_blocks = 0
    source_values: list[Token] = []
    index = 0

    while index < len(tokens):
        token = tokens[index]
        is_nsg_block = (
            depth == 0
            and index + 2 < len(tokens)
            and token.kind == "identifier"
            and token.value == "module"
            and tokens[index + 1].kind == "string"
            and tokens[index + 1].value == "nsgs"
            and tokens[index + 2].kind == "{"
        )
        if is_nsg_block:
            if target_depth is not None:
                raise ValueError('Nested module "nsgs" blocks are not supported.')
            target_blocks += 1
            target_depth = depth + 1

        if (
            target_depth is not None
            and depth == target_depth
            and token.kind == "identifier"
            and token.value == "source"
        ):
            if index + 1 >= len(tokens) or tokens[index + 1].kind != "=":
                index += 1
                continue
            if index + 2 >= len(tokens) or tokens[index + 2].kind != "string":
                raise ValueError('The "nsgs" source must be a quoted string literal.')
            source_token = tokens[index + 2]
            if source_token.value != ORIGINAL_SOURCE:
                raise ValueError('The "nsgs" module source differs from the expected address.')
            if index + 3 < len(tokens) and tokens[index + 3].line == source_token.line:
                raise ValueError('The "nsgs" source must be a standalone string literal.')
            source_values.append(source_token)

        if token.kind == "{":
            depth += 1
        elif token.kind == "}":
            depth -= 1
            if depth < 0:
                raise ValueError("Unexpected closing brace.")
            if target_depth is not None and depth == target_depth - 1:
                target_depth = None
        index += 1

    if depth != 0:
        raise ValueError("Unbalanced braces in configuration.")
    if target_blocks != 1:
        raise ValueError('Expected exactly one top-level module "nsgs" block.')
    if len(source_values) != 1:
        raise ValueError('Expected exactly one source attribute in module "nsgs".')

    source_token = source_values[0]
    replacement = f'"{QUALIFIED_SOURCE}"'
    return source[: source_token.start] + replacement + source[source_token.end :]


def qualify_file(path: Path) -> None:
    with path.open("r", encoding="utf-8", newline="") as file:
        original = file.read()
    qualified = qualify_nsg_source(original)

    mode = path.stat().st_mode
    temporary_path: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            "w", encoding="utf-8", newline="", dir=path.parent, delete=False
        ) as file:
            temporary_path = file.name
            file.write(qualified)
        os.chmod(temporary_path, mode)
        os.replace(temporary_path, path)
    finally:
        if temporary_path and os.path.exists(temporary_path):
            os.unlink(temporary_path)


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: qualify_nsg_source.py <main.tf>", file=sys.stderr)
        return 2
    try:
        qualify_file(Path(sys.argv[1]))
    except (OSError, ValueError) as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    print("Qualified the NSG registry source in the disposable root-module copy for OpenTofu.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
