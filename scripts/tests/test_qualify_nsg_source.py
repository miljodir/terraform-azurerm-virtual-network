#!/usr/bin/env python3
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from qualify_nsg_source import (
    ORIGINAL_SOURCE,
    QUALIFIED_SOURCE,
    qualify_file,
    qualify_nsg_source,
)


class QualifyNsgSourceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.valid = (
            'module "nsgs" {\n'
            f'  source = "{ORIGINAL_SOURCE}"\n'
            '  unrelated = var.source\n'
            '  version = "~> 1.4"\n'
            '}\n'
        )

    def test_rewrites_source_only_inside_target_module(self) -> None:
        content = (
            'module "other" {\n  source = "miljodir/other/azurerm"\n}\n'
            + self.valid
        )
        result = qualify_nsg_source(content)

        self.assertIn(f'source = "{QUALIFIED_SOURCE}"', result)
        self.assertIn('source = "miljodir/other/azurerm"', result)

    def test_ignores_commented_and_string_decoys(self) -> None:
        content = (
            '# module "nsgs" { source = "miljodir/nsg/azurerm" }\n'
            '/* module "nsgs" { source = "miljodir/nsg/azurerm" } */\n'
            'locals { note = "module \\"nsgs\\" { source = fake }" }\n'
            + self.valid
        )
        result = qualify_nsg_source(content)

        self.assertEqual(result.count(QUALIFIED_SOURCE), 1)
        self.assertEqual(result.count('source = "miljodir/nsg/azurerm"'), 0)
        self.assertIn('# module "nsgs" { source = "miljodir/nsg/azurerm" }', result)

    def test_rejects_changed_module_target_without_mutating_file(self) -> None:
        content = self.valid.replace('module "nsgs"', 'module "network_security"')
        self._assert_rejected_without_mutation(content)

    def test_rejects_changed_source_without_mutating_file(self) -> None:
        content = self.valid.replace(ORIGINAL_SOURCE, "miljodir/other/azurerm")
        self._assert_rejected_without_mutation(content)

    def test_rejects_duplicate_target_or_source_without_mutating_file(self) -> None:
        duplicate_block = self.valid + self.valid
        duplicate_source = self.valid.replace(
            '  version = "~> 1.4"\n',
            '  source = "miljodir/nsg/azurerm"\n  version = "~> 1.4"\n',
        )
        self._assert_rejected_without_mutation(duplicate_block)
        self._assert_rejected_without_mutation(duplicate_source)

    def _assert_rejected_without_mutation(self, content: str) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "main.tf"
            path.write_text(content, encoding="utf-8")

            with self.assertRaises(ValueError):
                qualify_file(path)

            self.assertEqual(path.read_text(encoding="utf-8"), content)


if __name__ == "__main__":
    unittest.main()
