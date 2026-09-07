"""Complete immutable Git evidence for candidate acceptance; never review an excerpt as complete."""
from __future__ import annotations

import json
import re

from .legacy import EvolutionError


EVIDENCE_LIMIT = 131_072
SOURCE_LIMIT = 2_000_000


def collect_evidence(task, worktree, candidate_commit, context, runner):
    base = task.base_commit
    if any(not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{40}", value) for value in (base, candidate_commit)):
        raise EvolutionError("acceptance_evidence_incomplete", "Acceptance requires immutable base and candidate commit IDs")

    def git(*arguments):
        result = runner.run(("git", "--no-pager", *arguments), worktree, timeout_seconds=120)
        if result.returncode:
            raise EvolutionError("acceptance_evidence_incomplete", "Cannot read immutable candidate evidence from Git")
        return result.stdout

    names = git("diff", "--no-ext-diff", "--no-textconv", "--no-renames", "--name-only", "-z", base, candidate_commit, "--")
    paths = [path for path in names.split("\0") if path]
    if not paths or any("\n" in path or "\r" in path for path in paths):
        raise EvolutionError("acceptance_evidence_incomplete", "Candidate changed-path evidence is empty or unsupported")
    total = 0
    observed = set()
    objects = {}
    for commit in (base, candidate_commit):
        objects[commit] = {}
        listing = git("--literal-pathspecs", "ls-tree", "-r", "-l", "-z", commit, "--", *paths)
        for entry in listing.split("\0"):
            if not entry:
                continue
            header, _, path = entry.partition("\t")
            fields = header.split()
            if len(fields) != 4 or fields[1] != "blob" or not fields[3].isdigit() or path not in paths:
                raise EvolutionError("acceptance_evidence_incomplete", "Candidate contains unsupported Git objects")
            observed.add(path)
            objects[commit][path] = fields[2]
            total += int(fields[3])
            if total > SOURCE_LIMIT:
                raise EvolutionError("acceptance_evidence_incomplete", "Candidate exceeds the complete single-review source envelope; partition the work without dropping requirements")
    if observed != set(paths):
        raise EvolutionError("acceptance_evidence_incomplete", "Changed files are missing from immutable Git object evidence")
    diff = git("diff", "--no-ext-diff", "--no-textconv", "--no-renames", "--unified=8", base, candidate_commit, "--")
    if any(line.startswith("Binary files ") or line == "GIT binary patch" for line in diff.splitlines()):
        raise EvolutionError("acceptance_evidence_incomplete", "Binary changes need a separate acceptance evaluator")
    if "\ufffd" in diff or "\ufffd" in names:
        raise EvolutionError("acceptance_evidence_incomplete", "Candidate text encoding cannot be verified losslessly")
    files = {}
    for path in paths:
        texts = []
        for commit in (base, candidate_commit):
            oid = objects[commit].get(path)
            content = git("cat-file", "blob", oid) if oid else None
            if content is not None and ("\ufffd" in content or "\0" in content):
                raise EvolutionError("acceptance_evidence_incomplete", "Changed file requires a non-text acceptance evaluator")
            texts.append(content)
        before, after = texts
        files[path] = {"before": before, "after": after,
                       "before_line_count": len(before.splitlines()) if before is not None else 0,
                       "after_line_count": len(after.splitlines()) if after is not None else 0,
                       "original_text_present": before is not None and after is not None and before in after,
                       "original_text_is_prefix": before is not None and after is not None and after.startswith(before)}
    requirements = [{"id": "task", "text": task.problem}]
    requirements.extend({"id": f"criterion-{index}", "text": value} for index, value in enumerate(task.acceptance, 1))
    evidence = {"task_id": task.task_id, "base_commit": base, "candidate_commit": candidate_commit,
                "parent_context": context, "scope": list(task.scope), "requirements": requirements,
                "changed_paths": paths, "diff": diff, "files": files,
                "text_comparison": "UTF-8 text with CRLF normalized to LF; not byte-exact equivalence"}
    if len(json.dumps(evidence, ensure_ascii=False).encode("utf-8")) > EVIDENCE_LIMIT:
        raise EvolutionError("acceptance_evidence_incomplete", "Complete acceptance evidence exceeds the review envelope; partition the work or provide a larger-context review path, never silently truncate requirements or diff")
    return evidence
