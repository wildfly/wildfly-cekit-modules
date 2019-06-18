#!/bin/bash

if [ "${SCRIPT_DEBUG}" = "true" ] ; then
    set -x
    echo "Script debugging is enabled, allowing bash commands and their arguments to be printed as they are executed"
fi

SERVER_CONFIG=${WILDFLY_SERVER_CONFIGURATION:-standalone.xml}
CONFIG_FILE=$JBOSS_HOME/standalone/configuration/${SERVER_CONFIG}
LOGGING_FILE=$JBOSS_HOME/standalone/configuration/logging.properties

# CONFIG_ADJUSTMENT_MODE is the mode used to do the environment variable replacement.
# The values are:
# -none     - no adjustment should be done. This cam be forced if $CONFIG_IS_FINAL = true
#               is passed in when starting the container
# -xml      - adjustment will happen via the legacy xml marker replacement
# -cli      - adjustment will happen via cli commands
# -xml_cli  - adjustment will happen via xml marker replacement if the marker is found. If not,
#               it will happen via cli commands. This is the default if not set by a consumer.
#
# Handling of the meanings of this is done by the launch scripts doing the config adjustment.
# Consumers of this script are expected to set this value.
if [ -z "${CONFIG_ADJUSTMENT_MODE}" ]; then
  CONFIG_ADJUSTMENT_MODE="xml_cli"
fi
if [ "${CONFIG_IS_FINAL^^}" = "TRUE" ]; then
    CONFIG_ADJUSTMENT_MODE="none"
fi

# This is the cli file generated
CLI_SCRIPT_FILE=/tmp/cli-script.cli
# This is the file used to log errors by the CLI execution
CLI_SCRIPT_ERROR_FILE=/tmp/cli-script-error.cli
# The property file used to pass variables to jboss-cli.sh
CLI_SCRIPT_PROPERTY_FILE=/tmp/cli-script-property.cli
# The CLI file that could have been used in S2I phase to define dirvers
S2I_CLI_DRIVERS_FILE=${JBOSS_HOME}/bin/launch/drivers.cli

# Ensure we start with clean files
if [ -s "${CLI_SCRIPT_FILE}" ]; then
  echo -n "" > "${CLI_SCRIPT_FILE}"
fi
if [ -s "${CLI_SCRIPT_ERROR_FILE}" ]; then
  echo -n "" > "${CLI_SCRIPT_ERROR_FILE}"
fi
if [ -s "${CLI_SCRIPT_PROPERTY_FILE}" ]; then
  echo -n "" > "${CLI_SCRIPT_PROPERTY_FILE}"
fi
if [ -s "${S2I_CLI_DRIVERS_FILE}" ] && [ "${CONFIG_ADJUSTMENT_MODE,,}" != "cli" ]; then
# If we have content in S2I_CLI_DRIVERS_FILE and we are not in pure CLI mode, then
# the CLI operations generated in S2I will be processed at runtime
 cat "${S2I_CLI_DRIVERS_FILE}" > "${CLI_SCRIPT_FILE}"
else
  echo -n "" > "${S2I_CLI_DRIVERS_FILE}"
fi

echo "error_file=${CLI_SCRIPT_ERROR_FILE}" > "${CLI_SCRIPT_PROPERTY_FILE}"

# Takes the following parameters:
# - $1      - the xml marker to test for
# - $2      - the variable which will hold the result
# The result holding variable, $2, will be populated with one of the following
# three values:
# - ""      - no configuration should be done
# - "xml"   - configuration should happen via marker replacement
# - "cli"   - configuration should happen via cli commands
#
function getConfigurationMode() {
  local marker="${1}"
  unset -v "$2" || echo "Invalid identifier: $2" >&2

  local attemptXml="false"
  local viaCli="false"
  if [ "${CONFIG_ADJUSTMENT_MODE,,}" = "xml" ]; then
    attemptXml="true"
  elif  [ "${CONFIG_ADJUSTMENT_MODE,,}" = "cli" ]; then
    viaCli="true"
  elif  [ "${CONFIG_ADJUSTMENT_MODE,,}" = "xml_cli" ]; then
    attemptXml="true"
    viaCli="true"
  elif [ "${CONFIG_ADJUSTMENT_MODE,,}" != "none" ]; then
    echo "Bad CONFIG_ADJUSTMENT_MODE \'${CONFIG_ADJUSTMENT_MODE}\'"
    exit 1
  fi

  local configVia=""
  if [ "${attemptXml}" = "true" ]; then
    if grep -Fq "${marker}" $CONFIG_FILE; then
        configVia="xml"
    fi
  fi

  if [ -z "${configVia}" ]; then
    if [ "${viaCli}" = "true" ]; then
        configVia="cli"
    fi
  fi

  printf -v "$2" '%s' "${configVia}"
}

# Test an XpathExpression against server config file and returns
# the xmllint exit code
#
# Parameters:
# - $1      - the xpath expression to use
# - $2      - the variable which will hold the result
#
function testXpathExpression() {
  local xpath="$1"
  unset -v "$2" || echo "Invalid identifier: $2" >&2

  if [ "${SCRIPT_DEBUG}" == "true" ]; then
    eval xmllint --xpath "${xpath}" "${CONFIG_FILE}"
  else
    eval xmllint --xpath "${xpath}" "${CONFIG_FILE}" 1>/dev/null
  fi

  printf -v "$2" '%s' "$?"
}

function exec_cli_scripts() {
  local script="$1"
  local stdOut="discard"
  local redirectStdOut="1>/dev/null"

  if [ "${SCRIPT_DEBUG}" = "true" ]; then
    CLI_DEBUG="TRUE";
  fi

  if [ -s "${script}" ]; then

    # Dump the cli script file for debugging
    if [ "${CLI_DEBUG^^}" = "TRUE" ]; then
      stdOut="echo"
      redirectStdOut=""

      echo "================= CLI files debug ================="
      if [ -f "${script}" ]; then
        echo "=========== CLI Script ${script} contents:"
        cat "${script}"
      else
        echo "No CLI_SCRIPT_FILE file found ${script}"
      fi
      if [ -f "${CLI_SCRIPT_PROPERTY_FILE}" ]; then
        echo "=========== ${CLI_SCRIPT_PROPERTY_FILE} contents:"
        cat "${CLI_SCRIPT_PROPERTY_FILE}"
      else
        echo "No CLI_SCRIPT_PROPERTY_FILE file found ${CLI_SCRIPT_PROPERTY_FILE}"
      fi
    fi

    #Check we are able to use the jboss-cli.sh
    if ! [ -f "${JBOSS_HOME}/bin/jboss-cli.sh" ]; then
      echo "Cannot find ${JBOSS_HOME}/bin/jboss-cli.sh. Scripts cannot be applied"
      exit 1
    fi

    systime=$(date +%s)
    CLI_SCRIPT_FILE_FOR_EMBEDDED=/tmp/cli-configuration-script-${systime}.cli
    echo "embed-server --timeout=30 --server-config=${SERVER_CONFIG} --std-out=${stdOut}" > ${CLI_SCRIPT_FILE_FOR_EMBEDDED}
    cat ${script} >> ${CLI_SCRIPT_FILE_FOR_EMBEDDED}
    echo "" >> ${CLI_SCRIPT_FILE_FOR_EMBEDDED}
    echo "stop-embedded-server" >> ${CLI_SCRIPT_FILE_FOR_EMBEDDED}

    echo "Configuring the server using embedded server"
    start=$(date +%s%3N)
    eval ${JBOSS_HOME}/bin/jboss-cli.sh "--file=${CLI_SCRIPT_FILE_FOR_EMBEDDED}" "--properties=${CLI_SCRIPT_PROPERTY_FILE}" "${redirectStdOut}"
    cli_result=$?
    end=$(date +%s%3N)

    echo "Duration: " $((end-start)) " milliseconds"


    if [ $cli_result -ne 0 ]; then
      echo "Error applying ${CLI_SCRIPT_FILE_FOR_EMBEDDED} CLI script. Embedded server cannot start or the operations to configure the server failed."
      exit 1
    elif [ -s "${CLI_SCRIPT_ERROR_FILE}" ]; then
      echo "Error applying ${CLI_SCRIPT_FILE_FOR_EMBEDDED} CLI script. Embedded server started successful. The Operations were executed but there were unexpected values. See list of errors in ${CLI_SCRIPT_ERROR_FILE}"
      exit 1
    elif [ "${SCRIPT_DEBUG}" != "true" ] ; then
      rm ${script} 2> /dev/null
      rm ${CLI_SCRIPT_PROPERTY_FILE} 2> /dev/null
      rm ${CLI_SCRIPT_ERROR_FILE} 2> /dev/null
      rm ${CLI_SCRIPT_FILE_FOR_EMBEDDED} 2> /dev/null
    fi
  else
    if [ "${CLI_DEBUG^^}" = "TRUE" ]; then
      echo "================= CLI files debug ================="
      echo "No CLI commands were found in ${script}"
    fi
  fi

  if [ "${SCRIPT_DEBUG}" = "true" ] ; then
    echo "CLI Script used to configure the server: ${CLI_SCRIPT_FILE_FOR_EMBEDDED}"
    echo "CLI Script generated by launch: ${CLI_SCRIPT_FILE}"
    echo "CLI Script property file: ${CLI_SCRIPT_PROPERTY_FILE}"
    echo "CLI Script error file: ${CLI_SCRIPT_ERROR_FILE}"
  fi
}