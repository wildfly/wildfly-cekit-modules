# only processes a single environment as the placeholder is not preserved

source $JBOSS_HOME/bin/launch/logging.sh

function prepareEnv() {
  unset HTTPS_NAME
  unset HTTPS_PASSWORD
  unset HTTPS_KEYSTORE_DIR
  unset HTTPS_KEYSTORE
  unset HTTPS_KEYSTORE_TYPE
}

function configure() {
  configure_https
}

function configureEnv() {
  configure
}

function configure_https() {
  if [ "${CONFIGURE_ELYTRON_SSL}" = "true" ]; then
    echo "Using Elytron for SSL configuration."
    return
  fi

  local sslConfMode
  getConfigurationMode "<!-- ##SSL## -->" "sslConfMode"

  local httpsConfMode
  getConfigurationMode "<!-- ##HTTPS_CONNECTOR## -->" "httpsConfMode"


  if [ -n "${HTTPS_PASSWORD}" -a -n "${HTTPS_KEYSTORE_DIR}" -a -n "${HTTPS_KEYSTORE}" ]; then

    if [ "${sslConfMode}" = "xml" ]; then
      configureSslXml
    elif [ "${sslConfMode}" = "cli" ]; then
      configureSslCli
    fi

    if [ "${httpsConfMode}" = "xml" ]; then
      configureHttpsXml
    elif [ "${httpsConfMode}" = "cli" ]; then
      configureHttpsCli
    fi

  elif [ -n "${HTTPS_PASSWORD}" -o -n "${HTTPS_KEYSTORE_DIR}" -o -n "${HTTPS_KEYSTORE}" ]; then
    log_warning "Partial HTTPS configuration, the https connector WILL NOT be configured."

    if [ "${sslConfMode}" = xml ]; then
      sed -i "s|<!-- ##SSL## -->|<!-- No SSL configuration discovered -->|" $CONFIG_FILE
    fi

    if [ "${httpsConfMode}" = xml ]; then
      sed -i "s|<!-- ##HTTPS_CONNECTOR## -->|<!-- No HTTPS configuration discovered -->|" $CONFIG_FILE
    fi
  fi
}

function configureSslXml() {
  if [ -n "$HTTPS_KEYSTORE_TYPE" ]; then
    keystore_provider="provider=\"${HTTPS_KEYSTORE_TYPE}\""
  fi
  ssl="<server-identities>\n\
            <ssl>\n\
                <keystore ${keystore_provider} path=\"${HTTPS_KEYSTORE_DIR}/${HTTPS_KEYSTORE}\" keystore-password=\"${HTTPS_PASSWORD}\"/>\n\
            </ssl>\n\
        </server-identities>"

  sed -i "s|<!-- ##SSL## -->|${ssl}|" $CONFIG_FILE
}

function configureSslCli() {
  local ssl_resource="/core-service=management/security-realm=ApplicationRealm/server-identity=ssl"
  local ssl_add="$ssl_resource:add(keystore-path=\"${HTTPS_KEYSTORE_DIR}/${HTTPS_KEYSTORE}\", keystore-password=\"${HTTPS_PASSWORD}\""
  if [ -n "$HTTPS_KEYSTORE_TYPE" ]; then
    ssl_add="${ssl_add}, keystore-provider=\"${HTTPS_KEYSTORE_TYPE}\""
  fi
  ssl_add="${ssl_add})"

  cat << EOF >> ${CLI_SCRIPT_FILE}
  if (outcome == success) of ${ssl_resource}:read-resource
      batch
        ${ssl_resource}:remove
        ${ssl_add}
      run-batch
  else
      ${ssl_add}
  end-if
EOF
}

function configureHttpsXml() {
  https_connector="<https-listener name=\"https\" socket-binding=\"https\" security-realm=\"ApplicationRealm\" proxy-address-forwarding=\"true\"/>"
  sed -i "s|<!-- ##HTTPS_CONNECTOR## -->|${https_connector}|" $CONFIG_FILE
}

function configureHttpsCli() {
    local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:undertow:')]\""
    local ret
    testXpathExpression "${xpath}" "ret"

    if [ "${ret}" -eq 0 ]; then
    cat << EOF >> ${CLI_SCRIPT_FILE}
    for serverName in /subsystem=undertow:read-children-names(child-type=server)
        if (result == []) of /subsystem=undertow/server=\$serverName:read-children-names(child-type=https-listener)
          /subsystem=undertow/server=\$serverName/https-listener=https:add(security-realm=ApplicationRealm, socket-binding=https, proxy-address-forwarding=true)
        else
          echo There is already an undertow https-listener for the '\$serverName' server so we are not adding it >> \${warning_file}
        end-if
    done
EOF
    fi
}