#!/bin/sh
configure_protocol_cli_helper() {
  local params=("${@}")
  local stack=${params[0]}
  local protocol=${params[1]}
  local result
  IFS= read -rd '' result <<- EOF

    if (outcome == success) of /subsystem=jgroups/stack="${stack}"/protocol="${protocol}":read-resource
        echo Cannot configure jgroups '${protocol}' protocol under '${stack}' stack. This protocol is already configured. >> \${error_file}
        quit
    end-if

    if (outcome != success) of /subsystem=jgroups/stack="${stack}"/protocol="${protocol}":read-resource
        batch
EOF
  # removes the latest new line added by read builtin command
  result=$(echo -n "${result}")

  # starts in 2, since 0 and 1 are arguments
  for ((j=2; j<${#params[@]}; ++j)); do
    result="${result}
            ${params[j]}"
  done

  IFS= read -r -d '' result <<- EOF
        ${result}
       run-batch
    end-if
EOF


  echo "${result}"
}
