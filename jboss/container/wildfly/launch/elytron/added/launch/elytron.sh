# only processes a single environment as the placeholder is not preserved
prepareEnv() {

  unset ELYTRON_SECDOMAIN_NAME
  unset ELYTRON_SECDOMAIN_USERS_PROPERTIES
  unset ELYTRON_SECDOMAIN_ROLES_PROPERTIES
  unset ELYTRON_SECDOMAIN_CORE_REALM

  unset HTTPS_PASSWORD
  unset HTTPS_KEY_PASSWORD
  unset HTTPS_KEYSTORE_DIR
  unset HTTPS_KEYSTORE
  unset HTTPS_KEYSTORE_TYPE
}

configure() {
  configure_https
  configure_security_domains
}

configureEnv() {
  configure
}

has_elytron_tls() {
    declare config_file="$1"
    if grep -q '<!-- ##ELYTRON_TLS## -->' "${config_file}"
    then
        echo "true"
    else
        echo "false"
    fi
}

has_elytron_legacy_tls() {
    declare config_file="$1"
    if grep -q '<!-- ##TLS## -->' "${config_file}"
    then
        echo "true"
    else
        echo "false"
    fi
}

has_elytron_keystore() {
    declare config_file="$1"
    if grep -q '<!-- ##ELYTRON_KEY_STORE## -->' "${config_file}"
    then
        echo "true"
    else
        echo "false"
    fi
}

insert_elytron_tls() {
 # the elytron skelton config. This will be used to replace <!-- ##ELYTRON_TLS## -->
 # if this is replaced, we'll also remove the legacy <!-- ##TLS## --> marker
 local elytron_tls="         <tls>\n\
            <key-stores>\n\
                <!-- ##ELYTRON_KEY_STORE## -->\n\
            </key-stores>\n\
            <key-managers>\n\
                <!-- ##ELYTRON_KEY_MANAGER## -->\n\
            </key-managers>\n\
            <server-ssl-contexts>\n\
                <!-- ##ELYTRON_SERVER_SSL_CONTEXT## -->\n\
            </server-ssl-contexts>\n\
         </tls>\n"
    # check for new config tag, use that if it's present, note we remove the <!-- ##ELYTRON_TLS## --> on first substitution
    if [ "true" = $(has_elytron_tls "${CONFIG_FILE}") ]; then
        sed -i "s|<!-- ##ELYTRON_TLS## -->|${elytron_tls}|" $CONFIG_FILE
        # remove the legacy tag, if it's present
        sed -i "s|<!-- ##TLS## -->||" $CONFIG_FILE
    fi
}

insert_elytron_tls_config_if_needed() {
    declare config_file="$1"
    if [ "$(has_elytron_tls "${config_file}")" = "true" ] || [ "$(has_elytron_keystore "${config_file}")" = "true" ]; then
        # insert the new config element, only if it hasn't been added already
        if [ "$(has_elytron_keystore "${config_file}")" = "false" ]; then
            insert_elytron_tls
        fi
    fi
}

elytron_legacy_config() {
    declare elytron_keystore="$1" elytron_key_manager="$2" elytron_server_ssl_context="$3"
    # this is to support the legacy <!-- ##TLS## --> insertion block.
    local legacy_elytron_tls="\
    <tls>\n\
        <key-stores>\n\
            ${elytron_key_store}\n\
        </key-stores>\n\
        <key-managers>\n\
            ${elytron_key_manager}\n\
        </key-managers>\n\
        <server-ssl-contexts>\n\
            ${elytron_server_ssl_context}\n\
        </server-ssl-contexts>\n\
    </tls>"

   echo ${legacy_elytron_tls}
}

create_elytron_keystore() {
    declare encrypt_keystore_name="$1" encrypt_keystore="$2" encrypt_password="$3" encrypt_keystore_type="$4" encrypt_keystore_dir="$5"

    local keystore_path=""
    local keystore_rel_to=""

    # if encrypt_keystore_dir is null, we assume the keystore is relative to the servers jboss.server.config.dir
    if [ -z "${encrypt_keystore_dir}" ]; then
      # Documented behavior; HTTPS_KEYSTORE is relative to the config dir
      # Use case is the user puts their keystore in their source's 'configuration' dir and s2i pulls it in
      keystore_path="path=\"${encrypt_keystore}\""
      keystore_rel_to="relative-to=\"jboss.server.config.dir\""
    elif [[ "${encrypt_keystore_dir}" =~ ^/ ]]; then
      # Assume leading '/' means the value is a FS path
      # Standard template behavior where the template sets this var to /etc/eap-secret-volume
      keystore_path="path=\"${encrypt_keystore_dir}/${encrypt_keystore}\""
      keystore_rel_to=""
    else
      # Compatibility edge case. Treat no leading '/' as meaning HTTPS_KEYSTORE_DIR is the name of a config model path
      keystore_path="path=\"${encrypt_keystore}\""
      keystore_rel_to="relative-to=\"${encrypt_keystore_dir}\""
    fi

    local key_store="<key-store name=\"${encrypt_keystore_name}\">\n\
              <credential-reference clear-text=\"${encrypt_password}\"/>\n"

    if [ ! "x${encrypt_keystore_type}" = "x" ]; then
      key_store=$key_store"<implementation type=\"${encrypt_keystore_type}\"/>\n"
    fi

    key_store=$key_store"<file ${keystore_path} ${keystore_rel_to} />\n\
            </key-store>"
    echo ${key_store}
}

create_elytron_keystore_cli() {
  declare encrypt_keystore_name="$1" encrypt_keystore="$2" encrypt_password="$3" encrypt_keystore_type="$4" encrypt_keystore_dir="$5"

  local keystore_path=""
  local keystore_rel_to=""

  # if encrypt_keystore_dir is null, we assume the keystore is relative to the servers jboss.server.config.dir
  if [ -z "${encrypt_keystore_dir}" ]; then
    # Documented behavior; HTTPS_KEYSTORE is relative to the config dir
    # Use case is the user puts their keystore in their source's 'configuration' dir and s2i pulls it in
    keystore_path="${encrypt_keystore}"
    keystore_rel_to="jboss.server.config.dir"
  elif [[ "${encrypt_keystore_dir}" =~ ^/ ]]; then
    # Assume leading '/' means the value is a FS path
    # Standard template behavior where the template sets this var to /etc/eap-secret-volume
    keystore_path="${encrypt_keystore_dir}/${encrypt_keystore}"
  else
    # Compatibility edge case. Treat no leading '/' as meaning HTTPS_KEYSTORE_DIR is the name of a config model path
    keystore_path="${encrypt_keystore}"
    keystore_rel_to="${encrypt_keystore_dir}"
  fi

  local cli_key_store_op="/subsystem=elytron/key-store=\"${encrypt_keystore_name}\":add(credential-reference={clear-text=\"${encrypt_password}\"}, path=\"${keystore_path}\""
  if [ ! "x${encrypt_keystore_type}" = "x" ]; then
    cli_key_store_op=${cli_key_store_op}", type=\"${encrypt_keystore_type}\""
  fi
  if [ ! "x${keystore_rel_to}" = "x" ]; then
    cli_key_store_op=${cli_key_store_op}", relative-to=\"${keystore_rel_to}\""
  fi
  cli_key_store_op=${cli_key_store_op}")"

  cat << EOF >> "${CLI_SCRIPT_FILE}"
    if (outcome == success) of /subsystem=elytron:read-resource
      ${cli_key_store_op}
    else
      echo "Cannot configure Elytron Key Store. The Elytron subsystem is not present in the server configuration file." >> \${error_file}
      quit
    end-if
EOF
}

create_elytron_keymanager() {
    declare key_manager="$1" key_store="$2" key_password="$3"
    # note key password here may be the same as the password to the keystore itself, or a seperate key specific password.
    # in either case it is required.
    local key_password="<credential-reference clear-text=\"${key_password}\"/>"
    local elytron_keymanager="<key-manager name=\"${key_manager}\" key-store=\"${key_store}\">$key_password</key-manager>"
    echo ${elytron_keymanager}
}

create_elytron_keymanager_cli() {
  declare key_manager="$1" key_store="$2" key_password="$3"
  # note key password here may be the same as the password to the keystore itself, or a seperate key specific password.
  # in either case it is required.
  cat << EOF >> "${CLI_SCRIPT_FILE}"
    if (outcome == success) of /subsystem=elytron:read-resource
      /subsystem=elytron/key-manager="${key_manager}":add(key-store="${key_store}", credential-reference={clear-text="${key_password}"})
    else
      echo "Cannot configure Elytron Key Manager. The Elytron subsystem is not present in the server configuration file." >> \${error_file}
    end-if
EOF
}

create_elytron_ssl_context() {
    declare ssl_context_name="$1" key_manager_name="$2"
    echo "<server-ssl-context name=\"${ssl_context_name}\" key-manager=\"${key_manager_name}\"/>"
}

create_elytron_ssl_context_cli() {
  declare ssl_context_name="$1" key_manager_name="$2"

  cat << EOF >> "${CLI_SCRIPT_FILE}"
    if (outcome == success) of /subsystem=elytron:read-resource
      /subsystem=elytron/server-ssl-context="${ssl_context_name}":add(key-manager="${key_manager_name}")
    else
      echo "Cannot configure Elytron Server SSL Context. The Elytron subsystem is not present in the server configuration file." >> \${error_file}
    end-if
EOF
}

create_elytron_https_connector() {
    declare name="$1" socket_binding="$2" ssl_context="$3" proxy_address_forwarding="$4"
    echo "<https-listener name=\"${name}\" socket-binding=\"${socket_binding}\" ssl-context=\"${ssl_context}\" proxy-address-forwarding=\"${proxy_address_forwarding:-true}\"/>"
}

create_elytron_https_connector_cli() {
    declare name="$1" socket_binding="$2" ssl_context="$3" proxy_address_forwarding="$4"

    local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:undertow:')]\""
    local ret
    testXpathExpression "${xpath}" "ret"
    
    if [ "${ret}" -eq 0 ]; then
      cat << EOF >> "${CLI_SCRIPT_FILE}"
      for serverName in /subsystem=undertow:read-children-names(child-type=server)
          if (result == []) of /subsystem=undertow/server=\$serverName:read-children-names(child-type=https-listener)
            /subsystem=undertow/server=\$serverName/https-listener="${name}":add(ssl-context="${ssl_context}", socket-binding="${socket_binding}", proxy-address-forwarding="${proxy_address_forwarding:-true}")
          else
            echo There is already an undertow https-listener for the '\$serverName' server so we are not adding it >> \${warning_file}
          end-if
      done
EOF
    else
      echo "echo \"You have set environment variables to configure Https. However, your base configuration does not contain the Undertow subsystem.\" >> \${error_file}" >> "${CLI_SCRIPT_FILE}"
    fi
}

configure_https() {

  if [ -n "${CONFIGURE_ELYTRON_SSL}" ]; then
    if [ "${CONFIGURE_ELYTRON_SSL}" = "true" ]; then
      log_warning "CONFIGURE_ELYTRON_SSL env variable is set to true, that is no more needed, SSL can only be configured using Elytron."
    else
      log_error "CONFIGURE_ELYTRON_SSL env variable is is set to false, SSL can only be configured using Elytron."
      log_error "Exiting..."
      exit
    fi
  fi

  local ssl="<!-- No SSL configuration discovered -->"
  local https_connector="<!-- No HTTPS configuration discovered -->"
  local missing_msg="Partial HTTPS configuration, the https connector WILL NOT be configured. Missing:"
  local key_password=""
  local elytron_key_store=""
  local elytron_key_manager=""
  local elytron_server_ssl_context=""
  local elytron_https_connector=""

  local elytron_tls_conf_mode
  getConfigurationMode "<!-- ##ELYTRON_TLS## -->" "elytron_tls_conf_mode"

  local elytron_legacy_tls_conf_mode
  getConfigurationMode "<!-- ##TLS## -->" "elytron_legacy_tls_conf_mode"

  local elytron_tls_conf_mode_via_key_store
  getConfigurationMode "<!-- ##ELYTRON_KEY_STORE## -->" "elytron_tls_conf_mode_via_key_store"

  local use_tls_cli=1
  if [ "${elytron_tls_conf_mode}" = "xml" ] || [ "${elytron_tls_conf_mode_via_key_store}" = "xml" ] || [ "${elytron_legacy_tls_conf_mode}" = "xml" ]; then
    use_tls_cli=0
  elif [ "${CONFIG_ADJUSTMENT_MODE,,}" = "none" ]; then
    return
  fi

  if [ -n "${HTTPS_PASSWORD}" -a -n "${HTTPS_KEYSTORE}" ]; then
    if [ -n "${HTTPS_KEY_PASSWORD}" ]; then
      key_password="${HTTPS_KEY_PASSWORD}"
    else
      log_warning "No HTTPS_KEY_PASSWORD was provided; using HTTPS_PASSWORD for Elytron LocalhostKeyManager."
      key_password="${HTTPS_PASSWORD}"
    fi

    if [ ${use_tls_cli} -eq 0 ]; then
      local elytron_key_store=$(create_elytron_keystore "LocalhostKeyStore" "${HTTPS_KEYSTORE}" "${HTTPS_PASSWORD}" "${HTTPS_KEYSTORE_TYPE}" "${HTTPS_KEYSTORE_DIR}")
      local elytron_key_manager=$(create_elytron_keymanager "LocalhostKeyManager" "LocalhostKeyStore" "${key_password}")
      local elytron_server_ssl_context=$(create_elytron_ssl_context "LocalhostSslContext" "LocalhostKeyManager")

      # check for new config tag, use that if it's present, also allow for the fact that somethign else has already replaced it
      if [ "$(has_elytron_tls "${CONFIG_FILE}")" = "true" ] || [ "$(has_elytron_keystore "${CONFIG_FILE}")" = "true" ]; then
          # insert the new config element, only if it hasn't been added already
          insert_elytron_tls_config_if_needed "${CONFIG_FILE}"
          # insert the individual config blocks we leave the replacement tags around in case something else (e.g. jgoups might need to add a keystore etc)
          sed -i "s|<!-- ##ELYTRON_KEY_STORE## -->|${elytron_key_store}<!-- ##ELYTRON_KEY_STORE## -->|" $CONFIG_FILE
          sed -i "s|<!-- ##ELYTRON_KEY_MANAGER## -->|${elytron_key_manager}<!-- ##ELYTRON_KEY_MANAGER## -->|" $CONFIG_FILE
          sed -i "s|<!-- ##ELYTRON_SERVER_SSL_CONTEXT## -->|${elytron_server_ssl_context}<!-- ##ELYTRON_SERVER_SSL_CONTEXT## -->|" $CONFIG_FILE
      else # legacy config
          legacy_elytron_tls=$(elytron_legacy_config "${elytron_key_store}" "${elytron_key_manager}" "${elytron_server_ssl_context}")
      fi
      # will be empty unless only the old marker is present.
      sed -i "s|<!-- ##TLS## -->|${legacy_elytron_tls}|" $CONFIG_FILE
    elif [ ${use_tls_cli} -eq 1 ]; then
      create_elytron_keystore_cli "LocalhostKeyStore" "${HTTPS_KEYSTORE}" "${HTTPS_PASSWORD}" "${HTTPS_KEYSTORE_TYPE}" "${HTTPS_KEYSTORE_DIR}"
      create_elytron_keymanager_cli "LocalhostKeyManager" "LocalhostKeyStore" "${key_password}"
      create_elytron_ssl_context_cli "LocalhostSslContext" "LocalhostKeyManager"
    fi

    local elytron_https_connector_conf_mode
    getConfigurationMode "<!-- ##HTTPS_CONNECTOR## -->" "elytron_https_connector_conf_mode"
    if [ "${elytron_https_connector_conf_mode}" = "xml" ]; then
      local elytron_https_connector=$(create_elytron_https_connector "https" "https" "LocalhostSslContext" "true")
      sed -i "s|<!-- ##HTTPS_CONNECTOR## -->|${elytron_https_connector}|" $CONFIG_FILE
    elif [ "${elytron_https_connector_conf_mode}" = "cli" ]; then
      create_elytron_https_connector_cli "https" "https" "LocalhostSslContext" "true"
    fi

  else

    if [ -z "${HTTPS_PASSWORD}" ]; then
      missing_msg="$missing_msg HTTPS_PASSWORD"
    fi
    if [ -z "${HTTPS_KEYSTORE}" ]; then
      missing_msg="$missing_msg HTTPS_KEYSTORE"
    fi

    log_warning "${missing_msg}"
  fi
}

configure_security_domains() {
  if [ -n "${SECDOMAIN_NAME}" ]; then
    log_error "SECDOMAIN_NAME env variable can't be set, use ELYTRON_SECDOMAIN_NAME env variable to configure authentication using Elytron."
    log_error "Exiting..."
    exit
  fi
  if [ -n "${ELYTRON_SECDOMAIN_NAME}" ]; then
    validate_elytron_security_domains_env
    if [ -z "${ELYTRON_SECDOMAIN_CORE_REALM}" ]; then
      elytron_sec_domain="${ELYTRON_SECDOMAIN_NAME}"
      configure_elytron_realm application-properties-"${ELYTRON_SECDOMAIN_NAME}"
      configure_elytron_only_security_domain "${ELYTRON_SECDOMAIN_NAME}" "application-properties-${ELYTRON_SECDOMAIN_NAME}"
    else
      elytron_sec_domain="ApplicationDomain"
    fi
    configure_undertow_security_domain "${ELYTRON_SECDOMAIN_NAME}" "$elytron_sec_domain"
    configure_ejb_security_domain "${ELYTRON_SECDOMAIN_NAME}" "$elytron_sec_domain"
  fi
}

validate_elytron_security_domains_env() {
  if [ -n "${ELYTRON_SECDOMAIN_CORE_REALM}" ]; then
    if [ -n "${ELYTRON_SECDOMAIN_USERS_PROPERTIES}" ] || [ -n "${ELYTRON_SECDOMAIN_ROLES_PROPERTIES}" ]; then
      log_error "When configuring an ELYTRON_SECDOMAIN, ELYTRON_SECDOMAIN_USERS_PROPERTIES and ELYTRON_SECDOMAIN_ROLES_PROPERTIES can't be used with ELYTRON_SECDOMAIN_CORE_REALM."
      exit 1
    fi
  else
    if [ -z "${ELYTRON_SECDOMAIN_USERS_PROPERTIES}" ] && [ -z "${ELYTRON_SECDOMAIN_ROLES_PROPERTIES}" ]; then
      log_error "When configuring an ELYTRON_SECDOMAIN, you must set ELYTRON_SECDOMAIN_CORE_REALM or ELYTRON_SECDOMAIN_USERS_PROPERTIES and ELYTRON_SECDOMAIN_ROLES_PROPERTIES."
      exit 1
    else
      if [ -z "${ELYTRON_SECDOMAIN_USERS_PROPERTIES}" ] || [ -z "${ELYTRON_SECDOMAIN_ROLES_PROPERTIES}" ]; then
        log_error "When configuring an ELYTRON_SECDOMAIN, you must set both ELYTRON_SECDOMAIN_USERS_PROPERTIES and ELYTRON_SECDOMAIN_ROLES_PROPERTIES."
        exit 1
      fi
    fi
  fi
}

configure_elytron_realm() {

  users_properties_arg="users-properties={path=${ELYTRON_SECDOMAIN_USERS_PROPERTIES}"
  if [ "${ELYTRON_SECDOMAIN_USERS_PROPERTIES:0:1}" != "/" ]; then
    users_properties_arg="$users_properties_arg, relative-to=jboss.server.config.dir"
  fi
  users_properties_arg="$users_properties_arg, plain-text=true, digest-realm-name=\"Application Security\"}"

  roles_properties_arg="groups-properties={path=${ELYTRON_SECDOMAIN_ROLES_PROPERTIES}"
  if [ "${ELYTRON_SECDOMAIN_ROLES_PROPERTIES:0:1}" != "/" ]; then
    roles_properties_arg="$roles_properties_arg, relative-to=jboss.server.config.dir"
  fi
  roles_properties_arg="$roles_properties_arg}"

  cat << EOF >> ${CLI_SCRIPT_FILE}
    if (outcome == success) of /subsystem=elytron/properties-realm=$1:read-resource
      echo ELYTRON_SEC_DOMAIN environment variable value conflicts with an existing elytron properties-realm, server can't be configured. >> \${error_file}
      exit
    else
      /subsystem=elytron/properties-realm=$1:add($users_properties_arg, $roles_properties_arg, groups-attribute=Roles)
    end-if
EOF
}

configure_elytron_only_security_domain() {
  cat << EOF >> ${CLI_SCRIPT_FILE}
    if (outcome == success) of /subsystem=elytron/security-domain=$1:read-resource
      echo ELYTRON_SEC_DOMAIN environment variable value conflicts with an existing elytron security domain, server can't be configured. >> \${error_file}
      exit
    else
      /subsystem=elytron/security-domain=$1:add(realms=[{realm=$2}], default-realm=$2, permission-mapper=default-permission-mapper)
    end-if
EOF
}

configure_undertow_security_domain() {
    cat << EOF >> ${CLI_SCRIPT_FILE}
    if (outcome != success) of /subsystem=undertow:read-resource
      echo You have set an ELYTRON_SEC_DOMAIN environment variables to configure an application-security-domain. Fix your configuration to contain undertow subsystem for this to happen. >> \${error_file}
      exit
    end-if
    if (outcome == success) of /subsystem=undertow/application-security-domain=$1:read-resource
      echo ELYTRON_SEC_DOMAIN environment variable value conflicts with an existing undertow security domain, server can't be configured. >> \${error_file}
      exit
    else
      /subsystem=undertow/application-security-domain=$1:add(security-domain=$2)
    end-if
EOF
}

configure_ejb_security_domain() {
    cat << EOF >> ${CLI_SCRIPT_FILE}
    if (outcome == success) of /subsystem=ejb3:read-resource
      /subsystem=ejb3/application-security-domain=$1:add(security-domain=$2)
    end-if
EOF
}