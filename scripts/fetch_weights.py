"""Download the selected Laya checkpoints at the reviewed commit and verify them.

Runs at image build time, so the image serves offline (HF_HUB_OFFLINE=1). Every
file is checked against the Hub's record for its commit: LFS files by SHA-256,
the rest by git blob hash. The digests are written to ``$HF_HOME/laya-weights.json``.
"""

import hashlib
import json
import os
import sys

from huggingface_hub import HfApi, snapshot_download
from laya.revisions import PINNED_REVISIONS
from laya.router import BUNDLE_REPO, DEFAULT_MODELS

api = HfApi()
manifest: dict[str, dict] = {}


def fetch(repo: str, revision: str, keep) -> str:
    """Download the files of *repo*@*revision* that *keep* selects, verify them, return the snapshot."""
    tree = {
        f.path: f
        for f in api.list_repo_tree(repo, revision=revision, recursive=True)
        if getattr(f, "size", None) is not None and keep(f.path)
    }
    snapshot = snapshot_download(repo, revision=revision, allow_patterns=list(tree))
    digests = {}
    for path, info in sorted(tree.items()):
        with open(os.path.join(snapshot, path), "rb") as fh:
            data = fh.read()
        lfs = getattr(info, "lfs", None)
        if lfs is not None:
            got, want = hashlib.sha256(data).hexdigest(), lfs.sha256
        else:
            got = hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()
            want = info.blob_id
        if got != want:
            sys.exit(f"{repo}/{path}: hash {got} does not match the Hub's {want}")
        digests[path] = hashlib.sha256(data).hexdigest()
    # Loads that name no revision resolve "main" from the cache; point it at the pinned commit.
    refs = os.path.join(
        os.environ["HF_HOME"], "hub", "models--" + repo.replace("/", "--"), "refs"
    )
    os.makedirs(refs, exist_ok=True)
    with open(os.path.join(refs, "main"), "w") as fh:
        fh.write(revision)
    manifest[repo] = {"revision": revision, "files": digests}
    print(f"verified {len(digests)} files of {repo}@{revision[:12]}")
    return snapshot


models = [m.strip() for m in os.environ.get("LAYA_MODELS", "").split(",") if m.strip()]
unknown = [m for m in models if m not in DEFAULT_MODELS]
if not models or unknown:
    sys.exit(f"LAYA_MODELS must name some of {sorted(DEFAULT_MODELS)}; got {models}")

# english lives at the bundle root (with its own tokenizer/ and encoder/ folders);
# the other checkpoints are subfolders of it.
subfolders = {m: DEFAULT_MODELS[m][1] or "" for m in models}
checkpoint_folders = {sub for _, sub in DEFAULT_MODELS.values() if sub}


def bundle_file(path: str) -> bool:
    top = path.split("/", 1)[0] if "/" in path else None
    if top in checkpoint_folders:
        return top in subfolders.values()
    if top is None and not path.endswith(".safetensors"):
        return True
    return "english" in models


bundle = fetch(BUNDLE_REPO, PINNED_REVISIONS[BUNDLE_REPO], bundle_file)

for model, sub in subfolders.items():
    # Without these, Laya would fetch the base encoder from the Hub at load time.
    missing = [
        d
        for d in ("tokenizer", "encoder")
        if not os.path.isdir(os.path.join(bundle, sub, d))
    ]
    if missing:
        sys.exit(f"{model} does not bundle {missing}; it cannot load offline")

with open(os.path.join(os.environ["HF_HOME"], "laya-weights.json"), "w") as fh:
    json.dump({"models": models, "repos": manifest}, fh, indent=2)
