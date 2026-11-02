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
    'ckmsg1:AQIAQH1Z7capGsSK9ApiGUXS9NQytLDMw6QJ137RPR6pkIlm7JjqV3hQY3Y0x_8FlITDvy138W5QCS_kL2StOorQens6pe1yQ'
    'IuORYZbz4yOVyP6FqEHARfT4YTlBh5445bhHIWkZjliw0AY0H6QkeTKxp9ewdWQACO0z5po91a5kYfk4tqSMSM0vuwduki3UhWxn-lhS'
    '0KW-vfhdGAQEowFMhH8DGebdxXIomCCr_qn31S8lLc6nri0UmxpM-GO-ymy4FhUq8Zvt3zbUa7WyG7dhZ9Yhnf4suX0erGrT5A_qkp_O'
    'KDU0VHA-xN_pS4Yx3lrwB8-A0_uY25wWyPKdEmQyCYXLUprepY4fsSRmoipXkxcg1t4qgYcjiSCavSgKEAY8-yXxavU_7YzG3t3S3q9E'
    'nGR7QNeK-06Tft0cIcGz-aipRBfTgEocVhAB_3-wDczvXDVhNXscSYI4pJRSRc3IBnO7uAUrtyhNk-mD_YCX1FCeHMWcbF7JZIgzGdum'
    'QE'
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
            "", "ckmsg1:", " " + CIPHERTEXT, CIPHERTEXT + " ", CIPHERTEXT + "в",
            CIPHERTEXT + "…", CIPHERTEXT + "\n", CIPHERTEXT + "\r\n",
            CIPHERTEXT + "\u00a0", CIPHERTEXT + " " + CIPHERTEXT,
            CIPHERTEXT.replace("ckmsg1:", "ckmsg2:", 1),
        ):
            with self.subTest(candidate=candidate):
                with self.assertRaises(ValueError):
                    roundtrip.extract_host_ciphertext("До " + candidate + "встречи!")

    def test_padding_invalid_lengths_and_noncanonical_tail_bits_are_rejected(self):
        for candidate in (CIPHERTEXT + "=", "ckmsg1:A", "ckmsg1:AB", "ckmsg1:AAB", "ckmsg1:AA+/"):
            with self.subTest(candidate=candidate):
                with self.assertRaises(ValueError):
                    roundtrip.extract_host_ciphertext("До " + candidate + "встречи!")


if __name__ == "__main__":
    unittest.main()
