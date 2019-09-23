#!/bin/bash
# This script must be sourced by external projects. It prepares all the environment to work with wildfly-cekit-modules

if [ "${SCRIPT_DEBUG}" = "true" ] ; then
    set -x
    echo "Script debugging is enabled, allowing bash commands and their arguments to be printed as they are executed"
fi

source $JBOSS_HOME/bin/launch/logging.sh
# sources external project configuration file. External projects will configure the common modules using launch-config.sh file.
# Specifically, they have to add the scripts they want to run into CONFIG_SCRIPT_CANDIDATES array
if [[ -s $JBOSS_HOME/bin/launch/launch-config.sh ]]; then
  source $JBOSS_HOME/bin/launch/launch-config.sh
fi
# Common environment variables, functions and configurations
source $JBOSS_HOME/bin/launch/openshift-common.sh


# Configure scripts. It takes all the scripts added by the external projects in CONFIG_SCRIPT_CANDIDATES arrays
# and copy them to the array used by the common modules. Later it executes all the modules and finally run any
# possible cli operation added by the modules
function configure_server() {
  CONFIGURE_CONFIG_SCRIPTS=(
  )

  if [[ -n "${CONFIG_SCRIPT_CANDIDATES}" ]]; then
      for script in "${CONFIG_SCRIPT_CANDIDATES[@]}"
      do
          if [ -f "${script}" ]; then
              CONFIGURE_SCRIPTS+=(${script})
          fi
      done
  else
      echo "No CONFIG_SCRIPT_CANDIDATES were set!"
  fi

  # Sources the configure-modules, it also will invoke all the modules configured in the CONFIGURE_SCRIPTS array
  source $JBOSS_HOME/bin/launch/configure-modules.sh

  # Process any errors and warnings generated while running the launch configuration scripts
  processErrorsAndWarnings

  # The scripts will add the operations in a special file, invoke the embedded server if it is necessary
  # and run the CLI scripts
  exec_cli_scripts "${CLI_SCRIPT_FILE}"

  # run the delayed postinstall of modules
  createConfigExecutionContext
  executeModules delayedPostConfigure

  # Process any errors and warnings generated while running the launch configuration scripts
  processErrorsAndWarnings

  # re-run CLI scipts just in case a delayed postinstall updated it
  exec_cli_scripts "${CLI_SCRIPT_FILE}"
}