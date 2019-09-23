#!/bin/sh

source $JBOSS_HOME/bin/launch/launch-common.sh
source $JBOSS_HOME/bin/launch/logging.sh

prepareEnv() {
  clear_filters_env
}

configureEnv() {
  configure
}

configure() {
  inject_filters
}

clear_filters_env() {
  for filter_prefix in $(echo $FILTERS | sed "s/,/ /g"); do
    clear_filter_env $filter_prefix
  done
  unset FILTERS
}

clear_filter_env() {
  local prefix=$1
  unset ${prefix}_FILTER_REF_NAME
  unset ${prefix}_FILTER_RESPONSE_HEADER_NAME
  unset ${prefix}_FILTER_RESPONSE_HEADER_VALUE
}

# check to see if no already defined FILTER_RESPONSE_HEADERS_MARKER tag
# this is used in the case where no default filters are defined, so we don't
# have an empty <filters/> element in the config, or expect it to be there
has_filter_placeholder_tag() {
    if grep -q '<!-- ##HTTP_FILTERS_MARKER## -->' "${CONFIG_FILE}"
    then
        echo "true"
    else
       echo "false"
    fi
}

# <!-- ##HTTP_FILTERS_MARKER## -->
insert_filter_tag() {
    sed -i "s|<!-- ##HTTP_FILTERS_MARKER## -->|<filters><!-- ##FILTER_RESPONSE_HEADERS## --></filters>|" $CONFIG_FILE
}

inject_filters() {
  # Add extensions from envs
  if [ -n "$FILTERS" ]; then

    # We may have the comment as marker, but no existing filters, if thats the case insert the <filters></filters> skeleton now.
    if [ "true" = $(has_filter_placeholder_tag) ]; then
      insert_filter_tag
    fi

    # Determine the configuration modes once.
    # We have to wait doing this until after we called insert_filter_tag so that we have the 'proper tag'
    local filterResponseHeadersConfMode
    getConfigurationMode "##FILTER_RESPONSE_HEADERS##" "filterResponseHeadersConfMode"
    local filterRefConfMode
    getConfigurationMode "##FILTER_REFS##" "filterRefConfMode"

    # Do some checking of whether the base configuration is valid for what we want to do if CLI configuration is chosen
    local error_in_base_config
    if [ "${filterResponseHeadersConfMode}" = "cli" ]; then
      checkUndertowSubsystem
    fi
    if [ "${error_in_base_config}" = "true" ]; then
      return
    fi
    if [ "${filterRefConfMode}" = "cli" ]; then
      checkUndertowSubsystemWithHostsAndServers
    fi
    if [ "${error_in_base_config}" = "true" ]; then
      return
    fi

    # Everything seems ok, so let's do the replacements
    for filter_prefix in $(echo $FILTERS | sed "s/,/ /g"); do
      inject_filter $filter_prefix
    done
  fi
}

inject_filter() {
  local prefix=$1
  local refName=$(find_env "${prefix}_FILTER_REF_NAME")
  local responseHeaderName=$(find_env "${prefix}_FILTER_RESPONSE_HEADER_NAME")
  local responseHeaderValue=$(find_env "${prefix}_FILTER_RESPONSE_HEADER_VALUE")

  if [ -z "$refName" ]; then
    refName="${responseHeaderName}"
  fi

  if [ -z "$responseHeaderName" ] || [ -z "$responseHeaderValue" ]; then
    log_warning "Ooops, there is a problem with a filter!"
    log_warning "In order to configure the $prefix filter you need to provide following environment variables: ${prefix}_FILTER_RESPONSE_HEADER_NAME and ${prefix}_FILTER_RESPONSE_HEADER_VALUE"
    log_warning
    log_warning "Current values:"
    log_warning
    log_warning "${prefix}_FILTER_REF_NAME: $refName"
    log_warning "${prefix}_FILTER_RESPONSE_HEADER_NAME: $responseHeaderName"
    log_warning "${prefix}_FILTER_RESPONSE_HEADER_VALUE: $responseHeaderValue"
    log_warning
    log_warning "The $prefix filter WILL NOT be configured."
    return
  fi

  inject_response_header
  inject_filter_ref
}

inject_response_header() {
  if [ "${filterResponseHeadersConfMode}" = "xml" ]; then
    local responseHeader=$(generate_response_header "$refName" "$responseHeaderName" "$responseHeaderValue")
    sed -i "s|<!-- ##FILTER_RESPONSE_HEADERS## -->|${responseHeader}\n<!-- ##FILTER_RESPONSE_HEADERS## -->|" $CONFIG_FILE
  elif [ "${filterResponseHeadersConfMode}" = "cli" ]; then
    # We will do full checking in inject_filter_ref so if there is no undertow subsystem, we will report that there
    # TODO check that there is no existing response filter header
    local resourceAddress="/subsystem=undertow/configuration=filter/response-header=\"${refName}\""
    local cli="
      if (outcome == success && (result.header-name != \"${responseHeaderName}\" || result.header-value != \"${responseHeaderValue}\")) of ${resourceAddress}:query(select=[\"header-name\", \"header-value\"])
        echo You have set environment variables to add an undertow response-header filter called ${refName}. However there is already one which has conflicting values. Fix your configuration. >> \${error_file}
        exit
      end-if
      if (outcome != success) of  ${resourceAddress}:read-resource
        ${resourceAddress}:add(header-name=\"${responseHeaderName}\", header-value=\"${responseHeaderValue}\")
      end-if
    "
    echo "${cli}" >> "${CLI_SCRIPT_FILE}"
  fi
}

generate_response_header() {
  local refName=$1
  local responseHeaderName=$2
  local responseHeaderValue=$3
  local responseHeader="<response-header name=\"${refName}\" header-name=\"${responseHeaderName}\" header-value=\"${responseHeaderValue}\"/>"
  echo "${responseHeader}" | sed ':a;N;$!ba;s|\n|\\n|g'
}

inject_filter_ref() {
  if [ "${filterRefConfMode}" = "xml" ]; then
    local filterRef=$(generate_filter_ref_xml "$refName")
    sed -i "s|<!-- ##FILTER_REFS## -->|${filterRef}\n<!-- ##FILTER_REFS## -->|" $CONFIG_FILE
  elif [ "${filterRefConfMode}" = "cli" ]; then
    # No need to check if we have an undertow subsystem here, as we already checked this before starting
    generate_filter_ref_cli "$refName"
  fi
}


generate_filter_ref_xml() {
  local refName=$1
  local filterRef="<filter-ref name=\"${refName}\"/>"
  echo "${filterRef}" | sed ':a;N;$!ba;s|\n|\\n|g'
}

generate_filter_ref_cli() {
  local refName=$1
  local ret
  local serverNames
  local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:undertow:')]/*[local-name()='server']/@name\""
  testXpathExpression "${xpath}" "ret" "serverNames"
  if [ "${ret}" -eq 0 ]; then
    # We have already validated that there are servers, so there is no need to check for errors here
    serverNames=$(splitAttributesStringIntoLines "${serverNames}" "name")
    local cli
    while read -r serverName; do
      local resourceAddress="/subsystem=undertow/server=${serverName}"
      cli="${cli}
        for hostName in ${resourceAddress}:read-children-names(child-type=host)
          if (outcome == success) of ${resourceAddress}/host=\$hostName/filter-ref=${refName}:read-resource
            echo You have set environment variables to add an undertow filter-ref called ${refName} but one already exists. Fix your configuration so it does not contain clashing filter-refs for this to happen. >> \${error_file}
            exit
          else
            ${resourceAddress}/host=\$hostName/filter-ref=$refName:add()
          end-if
        done
      "
    done <<< "${serverNames}"
    echo "${cli}" >>  "${CLI_SCRIPT_FILE}"
  fi
}


checkUndertowSubsystem() {
    local ssRet
    local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:undertow:')]\""
    testXpathExpression "${xpath}" "ssRet"
    if [ "${ssRet}" -ne 0 ]; then
      echo "You have set environment variables to add undertow filters. Fix your configuration to contain the undertow subsystem for this to happen." >> "${CONFIG_ERROR_FILE}"
      error_in_base_config="true"
      return
    fi
}

checkUndertowSubsystemWithHostsAndServers() {
  checkUndertowSubsystem
  if [ "${error_in_base_config}" = "true" ]; then
    return
  fi

  # Not having any servers is an error
  local snRet
  local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:undertow:')]/*[local-name()='server']/@name\""
  testXpathExpression "${xpath}" "snRet"
  if [ "${snRet}" -ne 0 ]; then
    echo "You have set environment variables to add undertow filters. Fix your configuration to contain at least one server in the undertow subsystem for this to happen." >> "${CONFIG_ERROR_FILE}"
    error_in_base_config="true"
    return
  fi

  # Not having any hosts is an error
  local hRet
  local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:undertow:')]/*[local-name()='server']/*[local-name()='host']/@name\""
  testXpathExpression "${xpath}" "hRet"
  if [ "${hRet}" -ne 0 ]; then
    echo "You have set environment variables to add undertow filters. Fix your configuration to contain at least one host in the undertow subsystem for this to happen." >> "${CONFIG_ERROR_FILE}"
    error_in_base_config="true"
    return
  fi
}

