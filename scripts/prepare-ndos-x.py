#!/usr/bin/env python3
"""Verify pinned dependencies and apply the reviewed nDOS-X host patch set."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def git(repo, *args, env=None, check=True):
    result = subprocess.run(["git", "-C", str(repo), *args], env=env,
                            text=True, capture_output=True)
    if check and result.returncode:
        raise RuntimeError(result.stderr.strip() or f"git {' '.join(args)} failed")
    return result


def prepare(name, dependency, unprepare=False):
    repo = ROOT / dependency["path"]
    revision = git(repo, "rev-parse", "HEAD").stdout.strip()
    if revision != dependency["commit"]:
        raise RuntimeError(f"{name}: expected {dependency['commit']}, found {revision}; update the submodule explicitly")
    patches = sorted((ROOT / "Patches" / "ndos-x" / name).glob("*.patch"))
    # An isolated index computes the complete expected tree without altering
    # either the dependency's index or files. This also checks patch ordering.
    with tempfile.TemporaryDirectory(prefix="ndos-x-prepare-") as temporary:
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(temporary) / "index"))
        git(repo, "read-tree", revision, env=env)
        for patch in patches:
            git(repo, "apply", "--cached", str(patch), env=env)
        expected = git(repo, "write-tree", env=env).stdout.strip()
    unknown = git(repo, "ls-files", "--others", "--exclude-standard").stdout.strip()
    if unknown:
        raise RuntimeError(f"{name}: unexpected untracked files; preserve and inspect them before preparation:\n{unknown}")
    if (git(repo, "diff", "--cached", "--quiet", expected, "--", check=False).returncode == 0
            and git(repo, "diff", "--quiet", "--", check=False).returncode == 0):
        if unprepare:
            for patch in reversed(patches):
                git(repo, "apply", "--reverse", "--index", str(patch))
            git(repo, "diff", "--cached", "--exit-code", revision, "--")
            git(repo, "diff", "--exit-code", "--")
            print(f"{name}: restored reviewed patches to upstream {revision}")
        else:
            print(f"{name}: prepared at {revision}")
        return
    if (git(repo, "diff", "--cached", "--quiet", revision, "--", check=False).returncode != 0
            or git(repo, "diff", "--quiet", "--", check=False).returncode != 0):
        raise RuntimeError(f"{name}: unexpected local changes; preparation will not overwrite them")
    if unprepare:
        print(f"{name}: already pristine at {revision}")
        return
    for patch in patches:
        git(repo, "apply", "--index", str(patch))
    git(repo, "diff", "--exit-code", expected, "--")
    print(f"{name}: applied {len(patches)} patches at {revision}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--unprepare", action="store_true",
                        help="reverse only an exact reviewed patch set before an upstream update")
    args = parser.parse_args()
    dependencies = json.loads((ROOT / "Experimental" / "dependencies.json").read_text())
    for name, dependency in dependencies.items():
        prepare(name, dependency, args.unprepare)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
