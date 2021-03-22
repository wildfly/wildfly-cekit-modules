
function configure() {
  configure_json_logging
}

function configure_json_logging() {
  sed -i "s|^.*\.module=org\.jboss\.logmanager\.ext$||" $LOGGING_FILE
  local configureMode
  getConfigurationMode "##CONSOLE-FORMATTER##" "configureMode"
  if [ "${configureMode}" = "xml" ]; then
    configureByMarkers
    configurePatternFormatterByMarkers
  elif [ "${configureMode}" = "cli" ]; then
    configureByCLI
    configurePatternFormatterByCLI
  else
    sed -i 's|##CONSOLE-FORMATTER##|COLOR-PATTERN|' $LOGGING_FILE
  fi
}

function configureByMarkers() {
  if [ "${ENABLE_JSON_LOGGING^^}" == "TRUE" ]; then
    sed -i 's|##CONSOLE-FORMATTER##|OPENSHIFT|' $CONFIG_FILE
    sed -i 's|##CONSOLE-FORMATTER##|OPENSHIFT|' $LOGGING_FILE
  else
    sed -i 's|##CONSOLE-FORMATTER##|COLOR-PATTERN|' $CONFIG_FILE
    sed -i 's|##CONSOLE-FORMATTER##|COLOR-PATTERN|' $LOGGING_FILE
  fi
}

function configureByCLI() {
  if [ "${ENABLE_JSON_LOGGING^^}" == "TRUE" ]; then

    # We cannot have nested if sentences in CLI, so we use Xpath here to see if the subsystem=logging is in the file
    xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:logging:')]\""
    local ret
    testXpathExpression "${xpath}" "ret"

    if [ "${ret}" -eq 0 ]; then
      cat <<'EOF' >> ${CLI_SCRIPT_FILE}
          if (outcome != success) of /subsystem=logging/json-formatter=OPENSHIFT:read-resource
            /subsystem=logging/json-formatter=OPENSHIFT:add(exception-output-type=formatted, key-overrides=[timestamp="@timestamp"], meta-data=[@version=1])
          else
            /subsystem=logging/json-formatter=OPENSHIFT:write-attribute(name=exception-output-type, value=formatted)
            /subsystem=logging/json-formatter=OPENSHIFT:write-attribute(name=key-overrides, value=[timestamp="@timestamp"]
            /subsystem=logging/json-formatter=OPENSHIFT:write-attribute(name=meta-data, value=[@version=1])
          end-if
EOF
      consoleHandlerName "OPENSHIFT" >> ${CLI_SCRIPT_FILE}
    fi
    sed -i 's|##CONSOLE-FORMATTER##|OPENSHIFT|' $LOGGING_FILE
  else
    sed -i 's|##CONSOLE-FORMATTER##|COLOR-PATTERN|' $LOGGING_FILE
  fi
}

function consoleHandlerName() {
  declare name="$1"
  local result=""

  read -r -d '' result <<EOF
    if (outcome != success) of /subsystem=logging/console-handler=CONSOLE:read-resource
      /subsystem=logging/console-handler=CONSOLE:add(named-formatter=${name})
    else
      /subsystem=logging/console-handler=CONSOLE:write-attribute(name=named-formatter, value=${name})
    end-if
EOF

  echo "$result"
}

function configurePatternFormatterByMarkers(){
  local pattern="%K{level}%d{HH:mm:ss,SSS} %-5p [%c] (%t) %s%e%n"
  if [ "x${LOGGER_PATTERN}" != "x" ]; then
        pattern=${LOGGER_PATTERN}
  fi
  sed -i 's|##PATTERN_FORMATTER##|${PATTERN_FORMATTER}|' $CONFIG_FILE
  sed -i 's|##PATTERN_FORMATTER##|${PATTERN_FORMATTER}|' $LOGGING_FILE
}


function configurePatternFormatterByCLI() {
  local pattern="%K{level}%d{HH:mm:ss,SSS} %-5p [%c] (%t) %s%e%n"
  local result=""

  if [ "x${LOGGER_PATTERN}" != "x" ]; then
        pattern=${LOGGER_PATTERN}
  fi

  read -r -d '' result <<EOF
    if (outcome == success) of /subsystem=logging/console-handler=CONSOLE:read-resource
        /subsystem=logging/console-handler=CONSOLE:write-attribute(name="formatter", value=${pattern})
    end-if
EOF
  echo "$result"
}