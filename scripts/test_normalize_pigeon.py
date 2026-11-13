"""Pigeon whitespace normalization is narrow, deterministic and idempotent."""
import unittest
from normalize_pigeon import normalize_text


class NormalizePigeonTest(unittest.TestCase):
    def test_removes_only_trailing_horizontal_whitespace(self):
        original = '  /// \n  value = "keep interior  space";\t \n'
        expected = '  ///\n  value = "keep interior  space";\n'
        self.assertEqual(normalize_text(original), expected)
        self.assertEqual(normalize_text(expected), expected)

    def test_removes_excess_blank_lines_at_eof(self):
        self.assertEqual(normalize_text('value\n\n\n'), 'value\n')


if __name__ == '__main__':
    unittest.main()
