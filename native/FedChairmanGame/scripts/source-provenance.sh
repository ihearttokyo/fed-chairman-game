#!/usr/bin/env bash

collect_source_provenance() {
  local repo_root="$1"
  SOURCE_GIT_HEAD="$(git -C "$repo_root" rev-parse HEAD)"
  SOURCE_GIT_STATUS_SHORT="$(git -C "$repo_root" status --short --untracked-files=all -- native/FedChairmanGame scripts package.json)"
  if [[ -n "$SOURCE_GIT_STATUS_SHORT" ]]; then
    SOURCE_DIRTY=true
  else
    SOURCE_DIRTY=false
  fi
  SOURCE_FINGERPRINT="$({
    while IFS= read -r -d '' file_path; do
      printf '%s\0' "$file_path"
      if [[ -f "$repo_root/$file_path" ]]; then
        shasum -a 256 "$repo_root/$file_path"
      else
        printf 'missing\n'
      fi
    done < <(git -C "$repo_root" ls-files --cached --others --exclude-standard -z -- native/FedChairmanGame scripts package.json | LC_ALL=C sort -z)
  } | shasum -a 256 | awk '{print $1}')"
}
