import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("managed", Path(__file__).parents[2] / "lib/raildock/dokku-managed/merge.py")
managed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(managed)

class ManagedDeclarationTest(unittest.TestCase):
    def test_preserves_repo_settings_and_other_process_checks(self):
        original = {"env": {"SECRET": {"required": True}}, "formation": {"web": {"quantity": 2}},
                    "healthchecks": {"worker": [{"command": "check"}]}, "scripts": {"dokku": {"postdeploy": "warm"}}}
        merged = managed.merge(original, {"healthchecks": {"web": [{"path": "/ready"}]}, "scripts": {"predeploy": "migrate"}})
        self.assertEqual(merged["env"], original["env"])
        self.assertEqual(merged["formation"], original["formation"])
        self.assertEqual(merged["healthchecks"]["worker"], original["healthchecks"]["worker"])
        self.assertEqual(merged["scripts"]["dokku"], {"predeploy": "migrate", "postdeploy": "warm"})
        self.assertNotIn("web", original["healthchecks"])

    def test_explicit_empty_cron_clears_old_jobs(self):
        self.assertEqual(managed.merge({"cron": [{"command": "old"}]}, {"cron": []})["cron"], [])

    def test_empty_scripts_and_checks_clear_only_their_web_entries(self):
        original = {"healthchecks": {"web": [{"path": "/old"}], "worker": [{"command": "check"}]},
                    "scripts": {"dokku": {"predeploy": "old", "postdeploy": "keep"}, "postdeploy": "heroku"}}
        merged = managed.merge(original, {"healthchecks": {"web": []}, "scripts": {"predeploy": "", "postdeploy": ""}})
        self.assertEqual(merged["healthchecks"]["web"], [])
        self.assertEqual(merged["healthchecks"]["worker"], [{"command": "check"}])
        self.assertNotIn("dokku", merged["scripts"])
        self.assertEqual(merged["scripts"]["postdeploy"], "heroku")

if __name__ == "__main__":
    unittest.main()
