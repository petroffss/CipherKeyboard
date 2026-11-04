#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("network_guard", Path(__file__).with_name("check-network-boundaries.py"))
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class NetworkGuardTests(unittest.TestCase):
    def test_network_capabilities_are_rejected(self):
        for source in [
            "URLSession.shared", "URLRequest(url: url)", "NSURLConnection()", "NWBrowser()",
            "NWConnectionGroup()", "CFSocketCreate()", "CFHTTPMessageCreateRequest()", "SCNetworkReachabilityCreate()",
            "getaddrinfo()", "CKContainer.default()", "NSUbiquitousKeyValueStore.default", "WCSession.default",
            "ASWebAuthenticationSession()", "MCSession()", "Darwin.socket\n(AF_INET, 0, 0)",
            "connect\n(fd, addr, size)", "sendto(fd)", "recvfrom(fd)", "import\nCloudKit",
            "@preconcurrency import Network", "import WatchConnectivity", "import AuthenticationServices",
            "let launch = UIApplication.shared.open", "UIApplication\n.shared\n.open(url)",
            "NSExtensionContext().open(url)", "@Environment(\\.openURL) var open", 'Link("Go", destination: url)',
        ]:
            with self.subTest(source=source):
                self.assertTrue(guard.violations("App/Example.swift", source))

    def test_settings_destination_cannot_be_replaced(self):
        self.assertFalse(guard.violations("App/SystemSettings.swift", guard.SETTINGS_CODE))
        changed = guard.SETTINGS_CODE.replace("UIApplication.openSettingsURLString", '"https://example.com"')
        self.assertTrue(guard.violations("App/SystemSettings.swift", changed))
        self.assertTrue(guard.violations("App/Other.swift", guard.SETTINGS_CODE))

    def test_local_crypto_and_comments_are_allowed(self):
        self.assertFalse(guard.violations("App/Example.swift", "// URLSession is forbidden\nCipherMessage.open(text)"))


if __name__ == "__main__":
    unittest.main()
