#!/bin/sh

# Openshift EAP launch script datasource generation routines

if [ -f $JBOSS_HOME/bin/launch/launch-common.sh ]; then
    source $JBOSS_HOME/bin/launch/launch-common.sh
fi

if [ -f ${JBOSS_HOME}/bin/launch/openshift-node-name.sh ]; then
    source ${JBOSS_HOME}/bin/launch/openshift-node-name.sh
fi

if [ -f $JBOSS_HOME/bin/launch/logging.sh ]; then
    source $JBOSS_HOME/bin/launch/logging.sh
fi


function clearTxDatasourceEnv() {
  tx_backend=${TX_DATABASE_PREFIX_MAPPING}

  if [ -n "${tx_backend}" ] ; then
    service_name=${tx_backend%=*}
    service=${service_name^^}
    service=${service//-/_}
    db=${service##*_}
    prefix=${tx_backend#*=}

    unset ${service}_SERVICE_HOST
    unset ${service}_SERVICE_PORT
    unset ${prefix}_JNDI
    unset ${prefix}_USERNAME
    unset ${prefix}_PASSWORD
    unset ${prefix}_DATABASE
    unset ${prefix}_TX_ISOLATION
    unset ${prefix}_MIN_POOL_SIZE
    unset ${prefix}_MAX_POOL_SIZE
  fi
}

# Arguments:
# $1 - service name
# $2 - datasource jndi name
# $3 - datasource username
# $4 - datasource password
# $5 - datasource host
# $6 - datasource port
# $7 - datasource databasename
# $8 - driver
function generate_tx_datasource() {
  local dsConfMode
  getDataSourceConfigureMode "dsConfMode"
  if [ "${dsConfMode}" = "xml" ]; then
    echo "$(generate_tx_datasource_xml $@)"
  elif [ "${dsConfMode}" = "cli" ]; then
    echo "$(generate_tx_datasource_cli $@)"
  fi
}

# See generate_tx_datasource() for the arguments
function generate_tx_datasource_xml() {

  ds="                  <datasource jta=\"false\" jndi-name=\"${2}ObjectStore\" pool-name=\"${1}ObjectStorePool\" enabled=\"true\">
                      <connection-url>jdbc:${8}://${5}:${6}/${7}</connection-url>
                      <driver>${8}</driver>"
      if [ -n "$tx_isolation" ]; then
        ds="$ds
                      <transaction-isolation>$tx_isolation</transaction-isolation>"
      fi
      if [ -n "$min_pool_size" ] || [ -n "$max_pool_size" ]; then
        ds="$ds
                      <pool>"
        if [ -n "$min_pool_size" ]; then
          ds="$ds
                          <min-pool-size>$min_pool_size</min-pool-size>"
        fi
        if [ -n "$max_pool_size" ]; then
          ds="$ds
                          <max-pool-size>$max_pool_size</max-pool-size>"
        fi
        ds="$ds
                      </pool>"
      fi
      ds="$ds

                      <security>
                          <user-name>${3}</user-name>
                          <password>${4}</password>
                      </security>
                  </datasource>"
  echo $ds | sed ':a;N;$!ba;s|\n|\\n|g'
}

# See generate_tx_datasource() for the arguments
function generate_tx_datasource_cli() {
  local subsystem_address="/subsystem=datasources"
  local ds_resource="${subsystem_address}/data-source=${1}ObjectStorePool"
  local xa_resource="${subsystem_address}/xa-data-source=${1}ObjectStorePool"
  local ds_tmp_add="$ds_resource:add(jta=false, jndi-name=${2}ObjectStore, enabled=true, connection-url=jdbc:${8}://${5}:${6}/${7}, driver-name=$8"
  ds_tmp_add="${ds_tmp_add}, user-name=${3}, password=${4}"
  if [ -n "$tx_isolation" ]; then
    ds_tmp_add="${ds_tmp_add}, transaction-isolation=$tx_isolation"
  fi
  if [ -n "$min_pool_size" ]; then
    ds_tmp_add="$d{ds_tmp_add}, min-pool-size=$min_pool_size"
  fi
  if [ -n "$max_pool_size" ]; then
    ds_tmp_add="$d{ds_tmp_add}, min-pool-size=$max_pool_size"
  fi
  ds_tmp_add="${ds_tmp_add})"

  ds="
    if (outcome != success) of ${subsystem_addr}:read-resource
      echo You have set environment variables to configure the transactional logstore datasource \'${1}ObjectStorePool\'. Fix your configuration to contain a datasources subsystem for this to happen. >> \${error_file}
      exit
    end-if

    if (outcome == success) of ${ds_resource}:read-resource
      echo You have set environment variables to configure the transactional logstore datasource \'${1}ObjectStorePool\'. However, your base configuration already contains a datasource with that name. >> \${error_file}
      exit
    end-if

    if (outcome == success) of ${xa_resource}:read-resource
      echo You have set environment variables to configure the transactional logstore datasource \'${1}ObjectStorePool\'. However, your base configuration already contains a datasource with that name. >> \${error_file}
      exit
    end-if

    ${ds_tmp_add}
    "

  echo "${ds}"
}

function inject_jdbc_store() {
  init_node_name

  local prefix="os${JBOSS_NODE_NAME//-/}"

  local dsConfMode
  getConfigurationMode "<!-- ##JDBC_STORE## -->" "dsConfMode"
  if [ "${dsConfMode}" = "xml" ]; then
    jdbcStore="<jdbc-store datasource-jndi-name=\"${1}\">\\
              <action table-prefix=\"${prefix}\"/>\\
              <communication table-prefix=\"${prefix}\"/>\\
              <state table-prefix=\"${prefix}\"/>\\
          </jdbc-store>"
    sed -i "s|<!-- ##JDBC_STORE## -->|${jdbcStore}|" $CONFIG_FILE
  elif [ "${dsConfMode}" = "cli" ]; then
    local subsystem_addr="/subsystem=transactions"
    # Since we have variables indicating that we should use a JDBC store in the Tx subsystem, we
    # error if the base configuration already contains different values for that.
    # If all is well we write the values
    local cli="
      if (outcome != success) of $subsystem_addr:read-resource
        echo You have set environment variables to configure a jdbc transactional logstore. Fix your configuration to contain a transactions subsystem for this to happen. >> \${error_file}
        exit
      end-if

      if (result.use-jdbc-store == true && (result.jdbc-store-datasource != \"${1}\" || result.jdbc-action-store-table-prefix != \"${prefix}\" || result.jdbc-communication-store-table-prefix != \"${prefix}\" || result.jdbc-state-store-table-prefix != \"${prefix}\")) of $subsystem_addr:query(select=[\"use-jdbc-store\", \"jdbc-store-datasource\", \"jdbc-action-store-table-prefix\", \"jdbc-communication-store-table-prefix\", \"jdbc-state-store-table-prefix\"])
        echo You have set environment variables to configure a jdbc logstore in the transactions subsystem which conflict with the values that already exist in the base configuration. Fix your configuration. >> \${error_file}
        exit
      end-if

      batch
      $subsystem_addr:write-attribute(name=use-jdbc-store, value=true)
      $subsystem_addr:write-attribute(name=jdbc-store-datasource, value=${1})
      $subsystem_addr:write-attribute(name=jdbc-action-store-table-prefix, value=${prefix})
      $subsystem_addr:write-attribute(name=jdbc-communication-store-table-prefix, value=${prefix})
      $subsystem_addr:write-attribute(name=jdbc-state-store-table-prefix, value=${prefix})
      run-batch
    "
    echo "${cli}" >> ${CLI_SCRIPT_FILE}
  fi

}


function inject_tx_datasource() {
  tx_backend=${TX_DATABASE_PREFIX_MAPPING}

  if [ -n "${tx_backend}" ] ; then
    service_name=${tx_backend%=*}
    service=${service_name^^}
    service=${service//-/_}
    db=${service##*_}
    prefix=${tx_backend#*=}

    host=$(find_env "${service}_SERVICE_HOST")
    port=$(find_env "${service}_SERVICE_PORT")

    if [ -z $host ] || [ -z $port ]; then
      log_warning "There is a problem with your service configuration!"
      log_warning "You provided following database mapping (via TX_SERVICE_PREFIX_MAPPING environment variable): $tx_backend. To configure datasources we expect ${service}_SERVICE_HOST and ${service}_SERVICE_PORT to be set."
      log_warning
      log_warning "Current values:"
      log_warning
      log_warning "${service}_SERVICE_HOST: $host"
      log_warning "${service}_SERVICE_PORT: $port"
      log_warning
      log_warning "Please make sure you provided correct service name and prefix in the mapping. Additionally please check that you do not set portalIP to None in the $service_name service. Headless services are not supported at this time."
      log_warning
      log_warning "The ${db,,} datasource for $prefix service WILL NOT be configured."
      return
    fi

    # Custom JNDI environment variable name format: [NAME]_[DATABASE_TYPE]_JNDI appended by ObjectStore
    jndi=$(find_env "${prefix}_JNDI" "java:jboss/datasources/${service,,}")

    # Database username environment variable name format: [NAME]_[DATABASE_TYPE]_USERNAME
    username=$(find_env "${prefix}_USERNAME")

    # Database password environment variable name format: [NAME]_[DATABASE_TYPE]_PASSWORD
    password=$(find_env "${prefix}_PASSWORD")

    # Database name environment variable name format: [NAME]_[DATABASE_TYPE]_DATABASE
    database=$(find_env "${prefix}_DATABASE")

    if [ -z $jndi ] || [ -z $username ] || [ -z $password ] || [ -z $database ]; then
      log_warning "Ooops, there is a problem with the ${db,,} datasource!"
      log_warning "In order to configure ${db,,} transactional datasource for $prefix service you need to provide following environment variables: ${prefix}_USERNAME, ${prefix}_PASSWORD, ${prefix}_DATABASE."
      log_warning
      log_warning "Current values:"
      log_warning
      log_warning "${prefix}_USERNAME: $username"
      log_warning "${prefix}_PASSWORD: $password"
      log_warning "${prefix}_DATABASE: $database"
      log_warning
      log_warning "The ${db,,} datasource for $prefix service WILL NOT be configured."
      db="ignore"
    fi

    # Transaction isolation level environment variable name format: [NAME]_[DATABASE_TYPE]_TX_ISOLATION
    tx_isolation=$(find_env "${prefix}_TX_ISOLATION")

    # min pool size environment variable name format: [NAME]_[DATABASE_TYPE]_MIN_POOL_SIZE
    min_pool_size=$(find_env "${prefix}_MIN_POOL_SIZE")

    # max pool size environment variable name format: [NAME]_[DATABASE_TYPE]_MAX_POOL_SIZE
    max_pool_size=$(find_env "${prefix}_MAX_POOL_SIZE")

    case "$db" in
      "MYSQL")
        driver="mysql"
        datasource="$(generate_tx_datasource ${service,,} $jndi $username $password $host $port $database $driver)"
        inject_jdbc_store "${jndi}ObjectStore"
        ;;
      "POSTGRESQL")
        driver="postgresql"
        datasource="$(generate_tx_datasource ${service,,} $jndi $username $password $host $port $database $driver)"
        inject_jdbc_store "${jndi}ObjectStore"
        ;;
      *)
        datasource=""
        ;;
    esac

    local dsConfMode
    getDataSourceConfigureMode "dsConfMode"
    if [ "${dsConfMode}" = "xml" ]; then
      # Only do this replacement if we are replacing an xml marker
      echo ${datasource} | sed ':a;N;$!ba;s|\n|\\n|g'
    elif [ "${dsConfMode}" = "cli" ]; then
      # If using cli, return the raw string, preserving line breaks
      echo "${datasource}"
    fi


  else
    if [ -n "$JDBC_STORE_JNDI_NAME" ]; then
      inject_jdbc_store "${JDBC_STORE_JNDI_NAME}"
    fi
  fi
}
