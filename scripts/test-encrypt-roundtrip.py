#!/usr/bin/env python3
"""Small stdlib regression suite for the retained-host extraction boundary."""
import importlib.util
import pathlib
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location(
    "encrypt_roundtrip", pathlib.Path(__file__).with_name("encrypt-roundtrip.py"))
roundtrip = importlib.util.module_from_spec(spec)
# Importing the helper must never export attachments or run Swift.
with mock.patch("subprocess.run", side_effect=AssertionError("Unexpected command during import")):
    spec.loader.exec_module(roundtrip)

# Public ciphertext from CipherCoreTests/GoldenVectorTests.swift; not private key material.
CIPHERTEXT = (
    'ckmsg2:AgIAQH1Z7capGsSK9ApiGUXS9NQytLDMw6QJ137RPR6pkIlm7JjqV3hQY3Y0x_8FlITDvy138W5QCS_kL2StOorQentYaa_0UF'
    'SXMsuq7V5d-bMKbaMcsOV0K61a1KGnaPGme2eqcS75IZ6fLMm5PEZyTgC3FCjmHP0x_WEdVSO7gTFu3yYw69ioMxoUsDO1Y0Epv1Pn9ze'
    'GDw7_ADoblHPr8SevKRGWU1kkKrACFhkUUFD1gvNs-6SsDVpq5y0508mcO8xNFdwtdw1v70SYyuYmDTltZrHDrPeRXpUHE8uHFpYMQUJD'
    'REVGR0hJSktMOgQd23zEpyw6SJE6p1aFoj4IT0oEoagst6MOeiT6HiMdV0tgvP_59w-GHNDJAndXFjsB0rG_gDq-IqUrCSVPXZEtUY8fX'
    '3ULk6ZmLUxmSNX5Idy-DaULCkC2HSZmSd3JZFJ6sXo0LOOtiEqkAcI6c5S72E-cHUrKJiVzTjRPV2eRn9NP_BklRg7bRcwiOSvPRQ3kR7'
    'Pn-1nqDQ'
)


class HostCiphertextExtractionTests(unittest.TestCase):
    def test_real_unicode_host_framing_extracts_exact_ciphertext(self):
        host = "До " + CIPHERTEXT + "встречи!"
        self.assertEqual(len("встречи!"), 8)
        self.assertEqual(host[3:-7], CIPHERTEXT + "в")  # The confirmed historical defect.
        self.assertEqual(roundtrip.extract_host_ciphertext(host), CIPHERTEXT)

    def test_missing_changed_or_extra_host_boundaries_are_rejected(self):
        for host in (
            CIPHERTEXT + "встречи!", "До" + CIPHERTEXT + "встречи!",
            "xДо " + CIPHERTEXT + "встречи!", "до " + CIPHERTEXT + "встречи!",
            "До " + CIPHERTEXT + "стречи!", "До " + CIPHERTEXT + "встречи",
            "До " + CIPHERTEXT + "встречи!x", "До " + CIPHERTEXT + "встречи!\n",
            "До " + CIPHERTEXT + "встречи! ",
        ):
            with self.subTest(host=host):
                with self.assertRaisesRegex(ValueError, "Host prefix/suffix"):
                    roundtrip.extract_host_ciphertext(host)

    def test_host_middle_must_be_exactly_one_ascii_line(self):
        for candidate in (
            "", "ckmsg2:", " " + CIPHERTEXT, CIPHERTEXT + " ", CIPHERTEXT + "в",
            CIPHERTEXT + "…", CIPHERTEXT + "\n", CIPHERTEXT + "\r\n",
            CIPHERTEXT + "\u00a0", CIPHERTEXT + " " + CIPHERTEXT,
            CIPHERTEXT.replace("ckmsg2:", "ckmsg1:", 1),
            CIPHERTEXT.replace("ckmsg2:", "ckmsg3:", 1),
        ):
            with self.subTest(candidate=candidate):
                with self.assertRaises(ValueError):
                    roundtrip.extract_host_ciphertext("До " + candidate + "встречи!")

    def test_padding_invalid_lengths_and_noncanonical_tail_bits_are_rejected(self):
        for candidate in (CIPHERTEXT + "=", "ckmsg2:A", "ckmsg2:AB", "ckmsg2:AAB", "ckmsg2:AA+/"):
            with self.subTest(candidate=candidate):
                with self.assertRaises(ValueError):
                    roundtrip.extract_host_ciphertext("До " + candidate + "встречи!")


if __name__ == "__main__":
    unittest.main()
