#!/bin/bash

normalize_spaces_new_lines() {
  output=$(printf '%s\n' "$output" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d')
  expected=$(printf '%s\n' "$expected" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d')

  if [ -w "${TMPDIR:-/tmp}" ] && [ -n "${output}" -a -n "${expected}" ] && [ ! "${output}" = "${expected}" ]; then
    echo "${output}" > "${TMPDIR:-/tmp}"/output
    echo "${expected}" > "${TMPDIR:-/tmp}"/expected
  fi
}