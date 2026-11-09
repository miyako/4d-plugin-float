import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import yaml


ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).parent / "fixtures"
SPEC = importlib.util.spec_from_file_location(
    "lifecycle", ROOT / ".github/scripts/release_lifecycle.py"
)
life = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(life)
SHA = "a" * 40
REPO = "miyako/4d-plugin-float"


def fixture(root):
    (root / life.PROJECT).parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(FIXTURES / "project.pbxproj", root / life.PROJECT)
    shutil.copyfile(FIXTURES / "Info.plist", root / life.PLIST)


def release(tag="v0.0.1", draft=False):
    return {"id": 1, "tag_name": tag, "draft": draft, "prerelease": False}


class SourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        fixture(self.root)

    def project(self, old, new):
        path = self.root / life.PROJECT
        path.write_text(path.read_text().replace(old, new))

    def plist(self, **updates):
        path = self.root / life.PLIST
        value = plistlib.loads(path.read_bytes())
        value.update(updates)
        path.write_bytes(plistlib.dumps(value))

    def test_explicit_fixture_bumps(self):
        for mode, expected in (("patch", "2.3.5"), ("minor", "2.4.0"), ("major", "3.0.0")):
            with self.subTest(mode=mode):
                fixture(self.root)
                self.assertEqual(life.read_version(self.root), "2.3.4")
                self.assertEqual(life.bump_source(self.root, mode), expected)
                self.assertEqual(life.read_version(self.root), expected)
                text = (self.root / life.PROJECT).read_text()
                self.assertEqual(text.count(f"= {expected};"), 4)
                self.assertIn("objectVersion = 46;", text)
                self.assertIn("MACOSX_DEPLOYMENT_TARGET = 11.5;", text)
                data = plistlib.loads((self.root / life.PLIST).read_bytes())
                self.assertEqual(data["CFBundleVersion"], expected)
                self.assertEqual(data["CFBundleInfoDictionaryVersion"], "6.0")

    def test_invalid_and_drift_fields_fail_without_writes(self):
        cases = [
            ("MARKETING_VERSION = 2.3.4;", "MARKETING_VERSION = 2.3.5;"),
            ("CURRENT_PROJECT_VERSION = 2.3.4;", "CURRENT_PROJECT_VERSION = 2.3.5;"),
            ("MARKETING_VERSION = 2.3.4;", ""),
            ("CURRENT_PROJECT_VERSION = 2.3.4;", ""),
        ]
        cases += [("= 2.3.4;", f"= {bad};") for bad in
                  ("02.3.4", "v2.3.4", "2.3", "2.3.4-beta", "garbage", "$(UNKNOWN)", "")]
        for old, new in cases:
            with self.subTest(new=new):
                fixture(self.root)
                self.project(old, new)
                before = (self.root / life.PROJECT).read_bytes()
                with self.assertRaises(ValueError):
                    life.bump_source(self.root, "patch")
                self.assertEqual((self.root / life.PROJECT).read_bytes(), before)
        for key in ("CFBundleShortVersionString", "CFBundleVersion"):
            for value in ("2.3.5", "2.3", "$(UNKNOWN)", None, 234):
                with self.subTest(key=key, value=value):
                    fixture(self.root)
                    if value is None:
                        value = False
                    self.plist(**{key: value})
                    with self.assertRaises(ValueError):
                        life.read_version(self.root)

    def test_references_preserved_and_resolved(self):
        for ref in ("$(MARKETING_VERSION)", "${MARKETING_VERSION}"):
            with self.subTest(ref=ref):
                fixture(self.root)
                self.project("CURRENT_PROJECT_VERSION = 2.3.4;",
                             f'CURRENT_PROJECT_VERSION = "{ref}";')
                self.plist(CFBundleShortVersionString=ref,
                           CFBundleVersion="$(CURRENT_PROJECT_VERSION)")
                self.assertEqual(life.bump_source(self.root, "patch"), "2.3.5")
                self.assertIn(f'"{ref}"', (self.root / life.PROJECT).read_text())
                data = plistlib.loads((self.root / life.PLIST).read_bytes())
                self.assertEqual(data["CFBundleShortVersionString"], ref)
                self.assertEqual(data["CFBundleVersion"], "$(CURRENT_PROJECT_VERSION)")
        self.project("MARKETING_VERSION = 2.3.5;",
                     "MARKETING_VERSION = $(CURRENT_PROJECT_VERSION);")
        with self.assertRaisesRegex(ValueError, "cyclic"):
            life.read_version(self.root)

    def test_optional_bundle_version_not_added(self):
        data = plistlib.loads((self.root / life.PLIST).read_bytes())
        del data["CFBundleVersion"]
        (self.root / life.PLIST).write_bytes(plistlib.dumps(data))
        life.bump_source(self.root, "patch")
        self.assertNotIn("CFBundleVersion",
                         plistlib.loads((self.root / life.PLIST).read_bytes()))

    def test_missing_and_malformed_plist(self):
        data = plistlib.loads((self.root / life.PLIST).read_bytes())
        del data["CFBundleShortVersionString"]
        (self.root / life.PLIST).write_bytes(plistlib.dumps(data))
        with self.assertRaisesRegex(ValueError, "CFBundleShortVersionString"):
            life.read_version(self.root)
        (self.root / life.PLIST).write_bytes(plistlib.dumps(["not", "a", "dictionary"]))
        with self.assertRaisesRegex(ValueError, "dictionary"):
            life.read_version(self.root)
        (self.root / life.PLIST).write_text("not a plist")
        with self.assertRaises(plistlib.InvalidFileException):
            life.read_version(self.root)

    def test_live_source_derived_bump_only_touches_source_metadata(self):
        expected = life.read_version(ROOT)
        with tempfile.TemporaryDirectory() as tmp:
            copy = Path(tmp) / "repo"
            shutil.copytree(ROOT, copy, ignore=shutil.ignore_patterns(".git", "__pycache__"))
            before = {p.relative_to(copy): p.read_bytes() for p in copy.rglob("*") if p.is_file()}
            parts = list(map(int, expected.split(".")))
            parts[2] += 1
            bumped = ".".join(map(str, parts))
            self.assertEqual(life.bump_source(copy, "patch"), bumped)
            self.assertEqual(life.read_version(copy), bumped)
            changed = {path for path, data in before.items() if (copy / path).read_bytes() != data}
            self.assertEqual(changed, {life.PROJECT, life.PLIST})


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        fixture(self.root)
        self.assets = ["Float-2.3.4.zip", "Float-2.3.4.dmg"]
        for asset in self.assets:
            (self.root / asset).write_bytes(b"asset")
        self.env = patch.dict(os.environ, GITHUB_SHA=SHA, GITHUB_REPOSITORY=REPO)
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_paginated_draft_blocks_and_checks_every_schema(self):
        first = [release(f"v0.0.{i}") for i in range(100)]
        for page2 in ([release("v2.3.4", True)], {}, [None], [{"tag_name": "other"}],
                      [dict(release(), draft="false")], [dict(release(), id=True)]):
            with self.subTest(page2=page2), patch.object(life, "remote_ref", return_value=None), \
                    patch.object(life, "api", side_effect=[first, page2]) as api:
                with self.assertRaises(ValueError):
                    life.available(self.root, REPO, "v2.3.4")
                self.assertEqual(api.call_args_list[-1].args[2], "releases?per_page=100&page=2")

    def test_api_errors_including_later_pages_fail_closed(self):
        first = [release() for _ in range(100)]
        for error in (subprocess.CalledProcessError(1, ["gh"], stderr="404"),
                      subprocess.CalledProcessError(1, ["gh"], stderr="401"),
                      OSError("network"), json.JSONDecodeError("bad", "", 0)):
            for prefix in ([], [first]):
                with self.subTest(error=error, page=len(prefix) + 1), \
                        patch.object(life, "remote_ref", return_value=None), \
                        patch.object(life, "api", side_effect=prefix + [error]):
                    with self.assertRaises(type(error)):
                        life.available(self.root, REPO, "v2.3.4")

    def test_remote_tag_blocks_even_without_release(self):
        with patch.object(life, "remote_ref", return_value=SHA), patch.object(life, "api") as api:
            with self.assertRaisesRegex(ValueError, "Remote tag"):
                life.available(self.root, REPO, "v2.3.4")
            api.assert_not_called()

    def test_available_exhausts_pages(self):
        with patch.object(life, "remote_ref", return_value=None), \
                patch.object(life, "api", side_effect=[[release()] * 100, []]) as api:
            life.available(self.root, REPO, "v2.3.4")
            self.assertEqual(api.call_count, 2)

    def test_api_is_authenticated_gh_and_explicit_json(self):
        with patch.object(life, "run", return_value="[]") as run:
            life.api(REPO, "GET", "releases?per_page=100&page=1")
            self.assertEqual(run.call_args.args,
                             ("gh", "api", "--method", "GET",
                              f"repos/{REPO}/releases?per_page=100&page=1"))
        with patch.object(life, "run", return_value="{}") as run:
            life.api(REPO, "POST", "git/refs", {"sha": SHA})
            self.assertEqual(json.loads(run.call_args.kwargs["data"]), {"sha": SHA})

    def test_selected_sha_rejected_before_publication(self):
        for sha, head in (("invalid", SHA), (SHA, "b" * 40)):
            with patch.dict(os.environ, GITHUB_SHA=sha), \
                    patch.object(life, "run", return_value=head), patch.object(life, "api") as api:
                with self.assertRaisesRegex(ValueError, "immutable"):
                    life.preflight(self.root)
                api.assert_not_called()

    def simulate(self, failure=None):
        events = []
        state = {"tag": None, "release": None, "uploads": []}

        def remote(root, ref):
            events.append("remote")
            return state["tag"]

        def api(repo, method, suffix, payload=None):
            events.append((method, suffix, payload))
            if method == "GET":
                return []
            if failure == suffix:
                raise subprocess.CalledProcessError(1, ["gh", method, suffix])
            if suffix == "git/refs":
                self.assertEqual(payload, {"ref": "refs/tags/v2.3.4", "sha": SHA})
                state["tag"] = SHA
                return {"ref": payload["ref"], "object": {"sha": SHA, "type": "commit"}}
            self.assertEqual(payload, {"tag_name": "v2.3.4", "target_commitish": SHA,
                                      "name": "v2.3.4", "draft": False,
                                      "prerelease": False, "body": ""})
            state["release"] = release("v2.3.4")
            return state["release"]

        def run(*args, **kwargs):
            self.assertEqual(args, ("gh", "release", "upload", "v2.3.4",
                                    *self.assets, "--repo", REPO))
            state["uploads"].append(self.assets[0])
            events.append("upload")
            if failure == "upload":
                raise subprocess.CalledProcessError(1, args)
            state["uploads"].append(self.assets[1])

        with patch.object(life, "selected_sha", return_value=SHA), \
                patch.object(life, "remote_ref", side_effect=remote), \
                patch.object(life, "api", side_effect=api), \
                patch.object(life, "run", side_effect=run):
            if failure:
                with self.assertRaises(subprocess.CalledProcessError):
                    life.publish(self.root, self.assets)
            else:
                self.assertEqual(life.publish(self.root, self.assets), "2.3.4")
        return events, state

    def test_create_only_order_and_failure_retention(self):
        for failure in (None, "git/refs", "releases", "upload"):
            with self.subTest(failure=failure):
                events, state = self.simulate(failure)
                methods = [event[0] for event in events if isinstance(event, tuple)]
                self.assertEqual(methods, ["GET", "POST"] if failure == "git/refs"
                                 else ["GET", "POST", "POST"])
                self.assertEqual(state["tag"], None if failure == "git/refs" else SHA)
                self.assertEqual(state["release"] is not None, failure in (None, "upload"))
                if failure == "upload":
                    self.assertEqual(state["uploads"], [self.assets[0]])
                self.assertEqual(events[0:2], ["remote", ("GET", "releases?per_page=100&page=1", None)])

    def test_final_recheck_blocks_late_release(self):
        with patch.object(life, "selected_sha", return_value=SHA), \
                patch.object(life, "remote_ref", return_value=None), \
                patch.object(life, "api", return_value=[release("v2.3.4", True)]) as api:
            with self.assertRaisesRegex(ValueError, "including drafts"):
                life.publish(self.root, self.assets)
            self.assertEqual(api.call_count, 1)

    def test_wrong_remote_tag_prevents_release_post(self):
        with patch.object(life, "preflight", return_value=(SHA, "2.3.4", REPO)), \
                patch.object(life, "remote_ref", return_value="b" * 40), \
                patch.object(life, "api", return_value={
                    "ref": "refs/tags/v2.3.4", "object": {"sha": SHA, "type": "commit"}}) as api:
            with self.assertRaisesRegex(ValueError, "exactly"):
                life.publish(self.root, self.assets)
            self.assertEqual(api.call_count, 1)

    def test_malformed_post_responses_stop_without_upload(self):
        tag_response = {"ref": "refs/tags/v2.3.4",
                        "object": {"sha": SHA, "type": "commit"}}
        cases = [
            [{}],
            [dict(tag_response, object={"sha": "b" * 40, "type": "commit"})],
            [dict(tag_response, object={"sha": SHA, "type": "tag"})],
            [tag_response, {}],
            [tag_response, dict(release("v2.3.4"), draft=True)],
            [tag_response, dict(release("v2.3.4"), prerelease=True)],
            [tag_response, dict(release("v2.3.4"), id=True)],
        ]
        for responses in cases:
            with self.subTest(responses=responses), \
                    patch.object(life, "preflight", return_value=(SHA, "2.3.4", REPO)), \
                    patch.object(life, "remote_ref", return_value=SHA), \
                    patch.object(life, "api", side_effect=responses), \
                    patch.object(life, "run") as run:
                with self.assertRaises(ValueError):
                    life.publish(self.root, self.assets)
                run.assert_not_called()

    def test_missing_assets_stop_before_api_calls(self):
        (self.root / self.assets[0]).write_bytes(b"")
        with patch.object(life, "api") as api:
            with self.assertRaisesRegex(ValueError, "empty"):
                life.publish(self.root, self.assets)
            api.assert_not_called()

    def test_main_surfaces_errors_and_manual_recovery(self):
        with patch.object(sys, "argv", ["life", "publish", *self.assets]), \
                patch.object(life, "publish", side_effect=OSError("upload failed")), \
                contextlib.redirect_stderr(io.StringIO()) as errors:
            self.assertEqual(life.main(), 1)
            self.assertIn("upload failed", errors.getvalue())
            self.assertIn("retained", errors.getvalue())


class GitTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.remote = self.base / "remote.git"
        self.root = self.base / "work"
        self.root.mkdir()
        self.git("init", "--bare", str(self.remote))
        self.git("init", "-b", "selected")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.invalid")
        fixture(self.root)
        shutil.copytree(ROOT / ".github/scripts", self.root / ".github/scripts",
                        ignore=shutil.ignore_patterns("__pycache__"))
        shutil.copytree(ROOT / ".github/hooks", self.root / ".github/hooks")
        self.git("add", ".")
        self.git("commit", "-m", "fixture")
        self.old = self.git("rev-parse", "HEAD")
        (self.root / "other").write_text("unchanged")
        self.git("add", ".")
        self.git("commit", "-m", "selected")
        self.sha = self.git("rev-parse", "HEAD")
        self.git("remote", "add", "origin", str(self.remote))
        self.git("push", "origin", "HEAD:refs/heads/selected")
        self.env = patch.dict(os.environ, GITHUB_SHA=self.sha,
                              GITHUB_REF="refs/heads/selected", GITHUB_REPOSITORY=REPO)
        self.env.start()
        self.addCleanup(self.env.stop)

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, text=True, check=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.strip()

    def test_bump_nondefault_branch_no_tags_despite_followtags(self):
        self.git("config", "push.followTags", "true")
        self.git("tag", "-a", "unrelated", "-m", "must stay local")
        self.assertEqual(life.bump(self.root, "patch"), "2.3.5")
        self.assertEqual(life.remote_ref(self.root, "refs/heads/selected"),
                         self.git("rev-parse", "HEAD"))
        self.assertIsNone(life.remote_ref(self.root, "refs/tags/unrelated"))
        self.assertIsNone(life.remote_ref(self.root, "refs/tags/v2.3.5"))
        self.assertEqual(set(self.git("diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD").splitlines()),
                         {str(life.PROJECT), str(life.PLIST)})
        self.assertIn(life.TRAILER, self.git("log", "-1", "--format=%B"))

    def test_branch_races_at_precheck_and_push_negotiation(self):
        original_run = life.run
        for timing in ("precheck", "negotiation"):
            for state in ("advance", "rewind", "delete"):
                with self.subTest(timing=timing, state=state):
                    # Reset only the disposable local fixture to the selected SHA.
                    self.git("reset", "--hard", self.sha)
                    self.git("--git-dir", str(self.remote), "update-ref", "refs/heads/selected", self.sha)
                    if state == "advance":
                        tree = self.git("rev-parse", f"{self.sha}^{{tree}}")
                        target = self.git("commit-tree", tree, "-p", self.sha, "-m", "racer")
                        self.git("push", "origin", f"{target}:refs/heads/racer-{target}")
                    else:
                        target = self.old

                    def race():
                        args = ["--git-dir", str(self.remote), "update-ref"]
                        self.git(*(args + (["-d", "refs/heads/selected"] if state == "delete"
                                          else ["refs/heads/selected", target])))

                    if timing == "precheck":
                        race()

                    def run(*args, **kwargs):
                        if timing == "negotiation" and "push" in args:
                            race()
                        return original_run(*args, **kwargs)

                    with patch.object(life, "run", side_effect=run):
                        with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                            life.bump(self.root, "patch")
                    self.assertEqual(life.remote_ref(self.root, "refs/heads/selected"),
                                     None if state == "delete" else target)

    def test_real_same_sha_tag_creation_race_fails(self):
        for target in (self.sha, self.old):
            with self.subTest(target=target):
                ref = "refs/tags/v2.3.4"
                self.git("--git-dir", str(self.remote), "update-ref", "-d", ref)

                def api(repo, method, suffix, payload=None):
                    if method == "GET":
                        return []
                    self.assertEqual(suffix, "git/refs")
                    # Competitor creates the tag after the availability check.
                    self.git("--git-dir", str(self.remote), "update-ref", ref, target)
                    # Match POST git/refs create-only semantics using old zero SHA.
                    self.git("--git-dir", str(self.remote), "update-ref", ref,
                             payload["sha"], "0" * 40)

                for asset in ("a.zip", "a.dmg"):
                    (self.root / asset).write_bytes(b"asset")
                with patch.object(life, "api", side_effect=api):
                    with self.assertRaises(subprocess.CalledProcessError):
                        life.publish(self.root, ["a.zip", "a.dmg"])
                self.assertEqual(life.remote_ref(self.root, ref), target)

    def test_bump_rejects_tag_dispatch_dirty_checkout_and_wrong_sha(self):
        with patch.dict(os.environ, GITHUB_REF="refs/tags/v2.3.4"):
            with self.assertRaisesRegex(ValueError, "selected branch"):
                life.bump(self.root, "patch")
        with patch.dict(os.environ, GITHUB_SHA=self.old):
            with self.assertRaisesRegex(ValueError, "immutable"):
                life.bump(self.root, "patch")
        (self.root / "untracked").write_text("dirty")
        with self.assertRaisesRegex(ValueError, "clean"):
            life.bump(self.root, "patch")
        self.assertEqual(life.remote_ref(self.root, "refs/heads/selected"), self.sha)


class WorkflowTests(unittest.TestCase):
    def test_manual_immutable_gate_wiring_and_native_contract(self):
        # BaseLoader keeps YAML's 'on' key from YAML 1.1 boolean conversion.
        build = yaml.load((ROOT / ".github/workflows/release.yml").read_text(),
                          Loader=yaml.BaseLoader)
        bump = yaml.load((ROOT / ".github/workflows/bump-version.yml").read_text(),
                         Loader=yaml.BaseLoader)
        self.assertEqual(build["name"], "Build")
        self.assertEqual(build["on"], {"workflow_dispatch": ""})
        self.assertEqual(set(bump["on"]), {"workflow_dispatch"})
        self.assertEqual(bump["on"]["workflow_dispatch"]["inputs"]["mode"]["options"],
                         ["patch", "minor", "major"])
        self.assertEqual(build["concurrency"],
                         {"group": "release-publication", "cancel-in-progress": "false"})
        for workflow in (build, bump):
            for job in workflow["jobs"].values():
                for step in job["steps"]:
                    if step.get("uses", "").startswith("actions/checkout@"):
                        self.assertEqual(step["with"]["ref"], "${{ github.sha }}")
        self.assertEqual(set(build["jobs"]), {"version", "build-macos"})
        native = build["jobs"]["build-macos"]
        self.assertEqual(native["needs"], ["version"])
        self.assertEqual(native["runs-on"], "macos-latest")
        steps = native["steps"]
        names = [s.get("name", "") for s in steps]
        self.assertEqual(names[1:-1], [
            "check prebuilt libraries", "import Developer ID certificate",
            "store notarytool credentials", "build macOS plugin (universal)",
            "verify universal binary", "locate bundle", "codesign",
            "package, notarize & staple"])
        self.assertIn('publish "$ZIP_PATH" "$DMG_PATH"', steps[-1]["run"])
        self.assertNotIn("if", steps[-1])
        self.assertEqual(steps[-1]["env"]["GH_TOKEN"], "${{ github.token }}")
        text = (ROOT / ".github/workflows/release.yml").read_text()
        for required in ("ARCHS=\"arm64 x86_64\"", 'notarize "$ZIP_PATH"',
                         'notarize "$DMG_PATH"', 'xcrun stapler staple "$DMG_PATH"',
                         "codesign --verify --deep --strict", 'ZIP_PATH="${PRODUCT}-${VERSION}.zip"',
                         'DMG_PATH="${PRODUCT}-${VERSION}.dmg"'):
            self.assertIn(required, text)
        secrets = set(re.findall(r"secrets\.([A-Z_]+)", text))
        self.assertEqual(secrets, {"APPLE_DEVELOPER_ID_CERTIFICATE",
                                  "APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD", "KEYCHAIN_PASSWORD",
                                  "NOTARYTOOL_APPLE_ID", "NOTARYTOOL_TEAM_ID", "NOTARYTOOL_PASSWORD"})

    def test_no_destructive_or_legacy_publication_commands(self):
        helper = (ROOT / ".github/scripts/release_lifecycle.py").read_text()
        workflows = "\n".join(p.read_text() for p in (ROOT / ".github/workflows").glob("*.yml"))
        for forbidden in ("--clobber", '"DELETE"', '"PATCH"', "gh release create",
                          "softprops/action-gh-release", "inputs.tag", "git tag",
                          "--force", "--force-with-lease"):
            self.assertNotIn(forbidden, helper)
            if forbidden != "--force":  # native codesign --force is intentional
                self.assertNotIn(forbidden, workflows)
        self.assertIn('"push.followTags=false"', helper)
        self.assertIn('"--no-follow-tags"', helper)
        self.assertIn('"HEAD:{ref}"', helper)


if __name__ == "__main__":
    unittest.main()
