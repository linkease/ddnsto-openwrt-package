"""Evaluate real package Makefile variables without requiring an OpenWrt SDK."""
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


def package_variables(flavor, arch):
    with tempfile.TemporaryDirectory() as directory:
        stub = pathlib.Path(directory)
        # Only SDK includes are stubbed; GNU make evaluates the real branches.
        (stub / "rules.mk").touch()
        (stub / "package.mk").touch()
        probe = "include " + str(ROOT / "ddnsto/Makefile") + "\n"
        for name in ("PKG_NAME", "PKG_SOURCE", "PKG_SOURCE_URL", "PKG_HASH",
                     "PKG_BUILD_DIR", "PKG_ARCH_DDNSTO"):
            probe += f"$(info RESULT {name}=$({name}))\n"
        probe += ".PHONY: probe\nprobe:;@:\n"
        result = subprocess.run(
            ["make", "--no-print-directory", "-f", "-", "probe",
             "TOPDIR=" + directory, "INCLUDE_DIR=" + directory,
             "BUILD_DIR=/build", "DDNSTO_TYPE=" + flavor, "ARCH=" + arch],
            input=probe, text=True, capture_output=True, check=True,
        )
        return dict(line[7:].split("=", 1) for line in result.stdout.splitlines()
                    if line.startswith("RESULT "))


class BinarySourceTests(unittest.TestCase):
    def test_micro_digest_matches_verified_download(self):
        self.assertEqual(package_variables("lite", "x86_64")["PKG_HASH"],
                         "1f02efa595df4740312eb633da1453b8ab8abc0e6b3bf33285a878430c0e7f3b")

    def test_lite_downloads_micro_without_renaming_package(self):
        for arch in ("x86_64", "aarch64", "arm", "mipsel"):
            with self.subTest(arch=arch):
                values = package_variables("lite", arch)
                self.assertEqual(values["PKG_SOURCE"], "ddnsto-micro-4.2.8.tar.gz")
                self.assertEqual(values["PKG_BUILD_DIR"], "/build/ddnsto-micro-4.2.8")
                self.assertEqual(values["PKG_NAME"], "ddnsto")
                self.assertEqual(values["PKG_ARCH_DDNSTO"], arch)
                self.assertEqual(values["PKG_SOURCE_URL"],
                                 "https://fw0.koolcenter.com/binary/ddnsto/linux-binary/")

    def test_standard_source_is_unchanged(self):
        values = package_variables("standard", "x86_64")
        self.assertEqual(values["PKG_SOURCE"], "ddnsto-standard-4.2.8.tar.gz")
        self.assertEqual(values["PKG_BUILD_DIR"], "/build/ddnsto-standard-4.2.8")
        self.assertEqual(values["PKG_HASH"],
                         "3bf7ada14448b5aa04afa171e497f85d0b8bb4adcf2209991e52ef5826d4e975")


if __name__ == "__main__":
    unittest.main()
