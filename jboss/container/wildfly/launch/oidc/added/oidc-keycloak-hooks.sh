#!/bin/bash
source $JBOSS_HOME/bin/launch/logging.sh

OIDC_AUTH_METHOD="OIDC"

function oidc_keycloak_mapEnvVariables {
  OIDC_PROVIDER_NAME=${OIDC_PROVIDER_NAME:-${SSO_DEFAULT_PROVIDER_NAME}}
  OIDC_PROVIDER_URL=${OIDC_PROVIDER_URL:-${SSO_URL}/realms/${SSO_REALM:-master}}
  OIDC_USER_NAME=${OIDC_USER_NAME:-${SSO_USERNAME}}
  OIDC_USER_PASSWORD=${OIDC_USER_PASSWORD:-${SSO_PASSWORD}}
  OIDC_SECURE_DEPLOYMENT_SECRET=${OIDC_SECURE_DEPLOYMENT_SECRET:-${SSO_SECRET}}
  OIDC_SECURE_DEPLOYMENT_PRINCIPAL_ATTRIBUTE=${OIDC_SECURE_DEPLOYMENT_PRINCIPAL_ATTRIBUTE:-${SSO_PRINCIPAL_ATTRIBUTE}}
  OIDC_SECURE_DEPLOYMENT_ENABLE_CORS=${OIDC_SECURE_DEPLOYMENT_ENABLE_CORS:-${SSO_ENABLE_CORS}}
  OIDC_SECURE_DEPLOYMENT_BEARER_ONLY=${OIDC_SECURE_DEPLOYMENT_BEARER_ONLY:-${SSO_BEARER_ONLY}}
  OIDC_PROVIDER_TRUSTSTORE=${OIDC_PROVIDER_TRUSTSTORE:-${SSO_TRUSTSTORE}}
  OIDC_PROVIDER_TRUSTSTORE_DIR=${OIDC_PROVIDER_TRUSTSTORE_DIR:-${SSO_TRUSTSTORE_DIR}}
  OIDC_PROVIDER_TRUSTSTORE_PASSWORD=${OIDC_PROVIDER_TRUSTSTORE_PASSWORD:-${SSO_TRUSTSTORE_PASSWORD}}
  OIDC_PROVIDER_TRUSTSTORE_CERTIFICATE_ALIAS=${OIDC_PROVIDER_TRUSTSTORE_CERTIFICATE_ALIAS:-${SSO_TRUSTSTORE_CERTIFICATE_ALIAS}}
  OIDC_DISABLE_SSL_CERTIFICATE_VALIDATION=${OIDC_DISABLE_SSL_CERTIFICATE_VALIDATION:-${SSO_DISABLE_SSL_CERTIFICATE_VALIDATION}}
  OIDC_HOSTNAME_HTTP=${OIDC_HOSTNAME_HTTP:-${HOSTNAME_HTTP}}
  OIDC_HOSTNAME_HTTPS=${OIDC_HOSTNAME_HTTPS:-${HOSTNAME_HTTPS}}

  if [ -n "${SSO_PUBLIC_KEY}" ]; then
    log_warning "The realm public key set in SSO_PUBLIC_KEY is being ignored by OIDC subsystem, public key is automatically retrieved from the authorization server."
  fi
}

function oidc_init_hook {
  enable_oidc_deployments
  set_curl
  get_token
}

function oidc_found_deployments() {
  if [ -n "${SSO_URL}" ]; then
    log_warning "The usage of SSO_* env variables for OIDC configuration is deprecated and would be removed in a future release. You must use OIDC_* env variables."
  fi 
}

function enable_oidc_deployments() {
  if [ -n "$SSO_OPENIDCONNECT_DEPLOYMENTS" ]; then
    explode_oidc_deployments $SSO_OPENIDCONNECT_DEPLOYMENTS
  fi
}

function explode_oidc_deployments() {
  local sso_deployments="${1}"

  for sso_deployment in $(echo $sso_deployments | sed "s/,/ /g"); do
    if [ ! -d "${JBOSS_HOME}/standalone/deployments/${sso_deployment}" ]; then
      mkdir ${JBOSS_HOME}/standalone/deployments/tmp
      unzip -o ${JBOSS_HOME}/standalone/deployments/${sso_deployment} -d ${JBOSS_HOME}/standalone/deployments/tmp
      rm -f ${JBOSS_HOME}/standalone/deployments/${sso_deployment}
      mv ${JBOSS_HOME}/standalone/deployments/tmp ${JBOSS_HOME}/standalone/deployments/${sso_deployment}
      if [ ! -f ${JBOSS_HOME}/standalone/deployments/${sso_deployment}.dodeploy ]; then
        touch ${JBOSS_HOME}/standalone/deployments/${sso_deployment}.dodeploy
      fi
    fi

    if [ -f "${JBOSS_HOME}/standalone/deployments/${sso_deployment}/WEB-INF/web.xml" ]; then
      requested_auth_method=$(cat ${JBOSS_HOME}/standalone/deployments/${sso_deployment}/WEB-INF/web.xml | xmllint --nowarning --xpath "string(//*[local-name()='auth-method'])" - | sed ':a;N;$!ba;s/\n//g' | tr -d '[:space:]')
      sed -i "s|${requested_auth_method}|${OIDC_AUTH_METHOD}|" "${JBOSS_HOME}/standalone/deployments/${sso_deployment}/WEB-INF/web.xml"
    fi
  done
}

function set_curl() {
  CURL="curl -s"
  if [ -n "$OIDC_DISABLE_SSL_CERTIFICATE_VALIDATION" ] && [[ $OIDC_DISABLE_SSL_CERTIFICATE_VALIDATION == "true" ]]; then
    CURL="curl --insecure -s"
  elif [ -n "$OIDC_PROVIDER_TRUSTSTORE" ] && [ -n "$OIDC_PROVIDER_TRUSTSTORE_DIR" ] && [ -n "$OIDC_PROVIDER_TRUSTSTORE_CERTIFICATE_ALIAS" ]; then
    TMP_SSO_TRUSTED_CERT_FILE=$(mktemp)
    keytool -exportcert -alias "$OIDC_PROVIDER_TRUSTSTORE_CERTIFICATE_ALIAS" -rfc -keystore ${OIDC_PROVIDER_TRUSTSTORE_DIR}/${OIDC_PROVIDER_TRUSTSTORE} -storepass ${OIDC_PROVIDER_TRUSTSTORE_PASSWORD} -file "$TMP_SSO_TRUSTED_CERT_FILE"
    CURL="curl -s --cacert $TMP_SSO_TRUSTED_CERT_FILE"
    unset TMP_SSO_TRUSTED_CERT_FILE
  fi
}

function get_token() {
  keycloak_token=""
  if [ -n "$OIDC_USER_NAME" ] && [ -n "$OIDC_USER_PASSWORD" ]; then
    keycloak_token=$($CURL --data "username=${OIDC_USER_NAME}&password=${OIDC_USER_PASSWORD}&grant_type=password&client_id=admin-cli" ${OIDC_PROVIDER_URL}/protocol/openid-connect/token)
    if [ $? -ne 0 ] || [[ $keycloak_token != *"access_token"* ]]; then
      log_warning "Unable to connect to SSO/Keycloak at $OIDC_PROVIDER_URL for user $OIDC_USER_NAME. SSO Clients *not* created"
      if [ -z "$keycloak_token" ]; then
        log_warning "Reason: Check the URL, no response from the URL above, check if it is valid or if the DNS is resolvable."
      else
        log_warning "Reason: $(echo $keycloak_token | grep -Po '((?<=\<p\>|\<body\>).*?(?=\</p\>|\</body\>)|(?<="error_description":")[^"]*)' | sed -e 's/<[^>]*>//g')"
      fi
      keycloak_token=
    else
      keycloak_token=$(echo $keycloak_token | grep -Po '(?<="access_token":")[^"]*')
      log_info "Obtained auth token from $OIDC_PROVIDER_URL"
    fi
  else
    log_warning "Missing SSO_USERNAME (or OIDC_USER_NAME) and/or SSO_PASSWORD (or OIDC_USER_PASSWORD). Unable to generate SSO Clients"
  fi

}

function oidc_create_client_hook() {
  client_config="$(keycloak_create_client_config ${1} ${2} ${3} ${4})"
  redirects="${2}"
  module_name="${5}"

  if [ -n "$keycloak_token" ]; then

    if [ -z "$OIDC_SECURE_DEPLOYMENT_SECRET" ]; then
      log_warning "ERROR: SSO_SECRET (or OIDC_SECURE_DEPLOYMENT_SECRET) not set. Make sure to generate a secret in the SSO/Keycloak client '$module_name' configuration and then set the SSO_SECRET (or OIDC_SECURE_DEPLOYMENT_SECRET)variable."
    fi

    result=$($CURL -w "%{http_code}" -H "Content-Type: application/json" -H "Authorization: Bearer ${keycloak_token}" -X POST -d "${client_config}" ${OIDC_PROVIDER_URL}/clients-registrations/default)

    httpcode="${result: -3}"
    if [[ "${httpcode}" =~ ^2.* ]]; then
      log_info "Registered OIDC client for module $module_name in $OIDC_PROVIDER_URL on $redirects"
    else
      log_warning "Response message: ${result::- 3} - HTTP Status code: ${httpcode}"
    fi
  fi
}

function keycloak_create_client_config() {
  client_id="${1}"
  redirects="${2}"
  redirect_path="${3}"
  endpoint="${4}"
  
  client_config="{\"redirectUris\":[${redirects}]"

  if [ -n "$OIDC_HOSTNAME_HTTP" ]; then
    client_config="${client_config},\"adminUrl\":\"http://\${application.session.host}:8080/${redirect_path}\""
  else
    client_config="${client_config},\"adminUrl\":\"https://\${application.session.host}:8443/${redirect_path}\""
  fi

  if [ -n "$OIDC_SECURE_DEPLOYMENT_BEARER_ONLY" ] && [ "$OIDC_SECURE_DEPLOYMENT_BEARER_ONLY" == "true" ]; then
    client_config="${client_config},\"bearerOnly\":\"true\""
  fi

  client_config="${client_config},\"clientId\":\"${client_id}\""
  client_config="${client_config},\"protocol\":\"openid-connect\""
  client_config="${client_config},\"baseUrl\":\"${endpoint}\""
  client_config="${client_config},\"rootUrl\":\"\""
  client_config="${client_config},\"publicClient\":\"false\",\"secret\":\"${OIDC_SECURE_DEPLOYMENT_SECRET}\""
  client_config="${client_config}}"
  echo "${client_config}"
}

