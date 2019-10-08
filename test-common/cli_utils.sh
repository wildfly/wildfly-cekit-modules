#!/bin/bash

normalize_spaces_new_lines() {
  output=$(printf '%s\n' "$output" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d')
  expected=$(printf '%s\n' "$expected" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d')

  echo "${output}" > "${TMPDIR}"/output
  echo "${expected}" > "${TMPDIR}"/expected
}