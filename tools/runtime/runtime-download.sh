#!/usr/bin/env bash

# Download an immutable runtime input without trusting a restored cache entry.
download_verified_runtime_input() {
  local url="$1"
  local destination="$2"
  local expected_sha256="$3"
  local label="${4:-Runtime input}"
  local temporary="$destination.partial"

  if [[ -f "$destination" ]]; then
    if printf '%s  %s\n' "$expected_sha256" "$destination" | sha256sum --check --status; then
      echo "$label: using verified cached input."
      return 0
    fi
    echo "$label: discarding an invalid cached input." >&2
    rm -f "$destination"
  fi

  rm -f "$temporary"
  if ! curl --fail --location --retry 3 --retry-all-errors "$url" --output "$temporary"; then
    rm -f "$temporary"
    echo "$label: download failed." >&2
    return 2
  fi
  if ! printf '%s  %s\n' "$expected_sha256" "$temporary" | sha256sum --check --status; then
    rm -f "$temporary"
    echo "$label: downloaded input failed integrity verification." >&2
    return 3
  fi
  mv "$temporary" "$destination"
}

download_verified_oci_blob() {
  local repository="$1"
  local digest="$2"
  local destination="$3"
  local expected_sha256="$4"
  local label="${5:-OCI runtime input}"
  local temporary="$destination.partial"

  if [[ -f "$destination" ]] &&
      printf '%s  %s\n' "$expected_sha256" "$destination" | sha256sum --check --status; then
    echo "$label: using verified cached input."
    return 0
  fi
  rm -f "$destination" "$temporary"
  local token
  token="$(curl --fail --silent --show-error --location \
    "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repository}:pull" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')"
  if [[ -z "$token" ]]; then
    echo "$label: registry authentication failed." >&2
    return 2
  fi
  if ! curl --fail --location --retry 3 --retry-all-errors \
      --header "Authorization: Bearer $token" \
      "https://registry-1.docker.io/v2/${repository}/blobs/${digest}" \
      --output "$temporary"; then
    rm -f "$temporary"
    echo "$label: download failed." >&2
    return 2
  fi
  if ! printf '%s  %s\n' "$expected_sha256" "$temporary" | sha256sum --check --status; then
    rm -f "$temporary"
    echo "$label: downloaded input failed integrity verification." >&2
    return 3
  fi
  mv "$temporary" "$destination"
}
