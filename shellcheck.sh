#!/usr/bin/env bash
set -e

# only errors for now
SHELL_CHECK_FLAGS="--severity=error"

targets=()
while IFS=  read -r -d $'\0'; do
    targets+=("$REPLY")
done < <(
  find \
    -iregex '.*\.\(sh\|bash\|bats\)$' \
    -type f \
    -print0
  )

LC_ALL=C.UTF-8 shellcheck "${SHELL_CHECK_FLAGS}" "${targets[@]}"

exit $?
