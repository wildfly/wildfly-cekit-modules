#!/bin/bash

source $JBOSS_HOME/bin/launch/logging.sh
source $JBOSS_HOME/bin/launch/oidc-keycloak-env.sh

OIDC_EXTENSION="org.wildfly.extension.elytron-oidc-client"
OIDC_SUBSYSTEM="elytron-oidc-client"

function prepareEnv() {
  unset APPLICATION_NAME
  unset APPLICATION_ROUTES
  unset OIDC_PROVIDER_NAME
  unset OIDC_PROVIDER_URL
  unset OIDC_PROVIDER_SSL_REQUIRED
  unset OIDC_PROVIDER_TRUSTSTORE
  unset OIDC_PROVIDER_TRUSTSTORE_DIR
  unset OIDC_PROVIDER_TRUSTSTORE_PASSWORD
  unset OIDC_PROVIDER_TRUSTSTORE_CERTIFICATE_ALIAS
  unset OIDC_USER_NAME
  unset OIDC_USER_PASSWORD
  unset OIDC_SECURE_DEPLOYMENT_SECRET
  unset OIDC_SECURE_DEPLOYMENT_PRINCIPAL_ATTRIBUTE
  unset OIDC_SECURE_DEPLOYMENT_ENABLE_CORS
  unset OIDC_SECURE_DEPLOYMENT_BEARER_ONLY
  unset OIDC_DISABLE_SSL_CERTIFICATE_VALIDATION
  unset OIDC_HOSTNAME_HTTP
  unset OIDC_HOSTNAME_HTTPS

  oidc_keycloak_prepareEnv
}

function configureEnv() {
  configure
}

function configure() {
  oidc_configure
}

function oidc_configure {
  if [ -n "$SSO_USE_LEGACY" ] && [ "$SSO_USE_LEGACY" == "true" ]; then
    return
  fi
  if  [ -n "${SSO_URL}" ] || [ "${OIDC_PROVIDER_NAME}" == "rh-sso" ] ||  [ "${OIDC_PROVIDER_NAME}" == "keycloak" ]; then
    source $JBOSS_HOME/bin/launch/oidc-keycloak-hooks.sh
    oidc_keycloak_mapEnvVariables
  fi
  if [ -z "$OIDC_PROVIDER_NAME" ]; then
    return
  fi
  log_info "Configuring OIDC subsystem for provider ${OIDC_PROVIDER_NAME}"
  cli=
  # defined in the provider
  oidc_init_hook
  oidc_configure_subsystem
}

# Implemented by providers 
function oidc_init_hook() {
 # NO-OP
 return
}

function oidc_create_client_hook() {
  log_warning "Client will be not register, no support for client registration for $OIDC_PROVIDER_NAME provider"
}

# end implemented by providers

function oidc_add_extension() {
  cli="if (outcome != success) of /extension=${OIDC_EXTENSION}:read-resource
           /extension=${OIDC_EXTENSION}:add()
         end-if"
  echo "$cli"
}

function oidc_add_subsystem() {
  cli="if (outcome != success) of /subsystem=${OIDC_SUBSYSTEM}:read-resource
           /subsystem=${OIDC_SUBSYSTEM}:add()
         end-if"
  echo "$cli"
}

function oidc_configure_subsystem() {
  cli=
  oidc_configure_secure_deployments
  secure_deployments="$cli"
  if [ ! -z "$secure_deployments" ]; then
    add_extension="$(oidc_add_extension)"
    add_subsystem="$(oidc_add_subsystem)"
    subsystem=/subsystem=${OIDC_SUBSYSTEM}
    provider=$subsystem/provider=${OIDC_PROVIDER_NAME}
    cli="
      ${add_extension}
      ${add_subsystem}
      ${provider}:add(provider-url=${OIDC_PROVIDER_URL},register-node-at-startup=true,register-node-period=600,ssl-required=${OIDC_PROVIDER_SSL_REQUIRED:-external},allow-any-hostname=false)"
    
    if [ -n "$OIDC_PROVIDER_TRUSTSTORE" ] && [ -n "$OIDC_PROVIDER_TRUSTSTORE_DIR" ]; then
      cli="$cli
        ${provider}:write-attribute(name=truststore,value=${OIDC_PROVIDER_TRUSTSTORE_DIR}/${OIDC_PROVIDER_TRUSTSTORE})
        ${provider}:write-attribute(name=truststore-password,value=${OIDC_PROVIDER_TRUSTSTORE_PASSWORD})"
    else
      cli="$cli
        ${provider}:write-attribute(name=disable-trust-manager,value=true)"
    fi

    if [ -n "$OIDC_SECURE_DEPLOYMENT_ENABLE_CORS" ]; then
        cors=${OIDC_SECURE_DEPLOYMENT_ENABLE_CORS}
      else
        cors=false
      fi
      cli="$cli
        ${provider}:write-attribute(name=enable-cors, value=${cors})"
    
    if [ -n "$OIDC_SECURE_DEPLOYMENT_PRINCIPAL_ATTRIBUTE" ]; then
        cli="$cli
        ${provider}:write-attribute(name=principal-attribute, value=${OIDC_SECURE_DEPLOYMENT_PRINCIPAL_ATTRIBUTE})"
      fi

    echo "${cli}
       ${secure_deployments}" >> ${CLI_SCRIPT_FILE}
  fi
}

function oidc_configure_secure_deployments() {

  pushd $JBOSS_HOME/standalone/deployments &> /dev/null
  files=*.war

  get_application_routes

  cli=

  for f in $files
  do
    if [[ $f != "*.war" ]];then
      oidc_configure_secure_deployment "${f}"
    fi
  done

  popd &> /dev/null

  # discover deployments in $JBOSS_HOME/standalone/data/content
  oidc_discover_deployed_deployments

}

function oidc_discover_deployed_deployments() {
  local deployments_xpath="//*[local-name()='deployments']//*[local-name()='deployment']"
  local count=$(xmllint --xpath "count($deployments_xpath)" "${CONFIG_FILE}" 2>/dev/null)
  for ((deployment_index=1; deployment_index<=count; deployment_index++)); do
    local deployment_runtime_name=$(xmllint --xpath "string($deployments_xpath[$deployment_index]/@runtime-name)" "${CONFIG_FILE}" 2>/dev/null)
    if [[ "${deployment_runtime_name}" == *.war ]]; then
      local deployment_name=$(xmllint --xpath "string($deployments_xpath[$deployment_index]/@name)" "${CONFIG_FILE}")
      local deployment_content=$(xmllint --xpath "string($deployments_xpath[$deployment_index]//*[local-name()='content']/@sha1)" "${CONFIG_FILE}" 2>/dev/null)
      local deployment_dir1=${deployment_content:0:2}
      local deployment_dir2=${deployment_content:2}
      local deployment_file="${JBOSS_HOME}/standalone/data/content/$deployment_dir1/$deployment_dir2/content"
      if [ -f "$deployment_file" ]; then
        log_info "Checking if name=$deployment_name runtime-name=$deployment_runtime_name content=$deployment_content is secured with OIDC"
        local tmp_file="/tmp/${deployment_runtime_name}"
        cp "$deployment_file" "$tmp_file"
        pushd /tmp &> /dev/null
        oidc_configure_secure_deployment "${deployment_runtime_name}"
        rm -f "${deployment_runtime_name}"
        popd &> /dev/null
      else
        log_warning "Deployment $deployment_runtime_name not found in content dir, deployment is ignored when scanning for OIDC deployment"
      fi
    fi
  done
}

function oidc_configure_secure_deployment() {
  f=${1}
  module_name=
  context_root=
  redirect_path=
  client_id=
  oidc_json_file=$(read_file_in_war $f WEB-INF/oidc.json)
  if [ -n "$oidc_json_file" ]; then
    log_info "Deployment $f contains WEB-INF/oidc.json descriptor, ignoring it."
    return
  fi
  web_xml=$(read_file_in_war $f WEB-INF/web.xml)
  if [ -n "$web_xml" ]; then
    requested_auth_method=$(echo $web_xml | xmllint --nowarning --xpath "string(//*[local-name()='auth-method'])" - | sed ':a;N;$!ba;s/\n//g' | tr -d '[:space:]')
    if [[ $requested_auth_method == "OIDC" ]]; then
      cli="$cli
        /subsystem=${OIDC_SUBSYSTEM}/secure-deployment=${f}:add(enable-basic-auth=true, provider=${OIDC_PROVIDER_NAME})"

      if [[ $web_xml == *"<module-name>"* ]]; then
        module_name=$(echo $web_xml | xmllint --nowarning --xpath "//*[local-name()='module-name']/text()" -)
      fi

      local jboss_web_xml=$(read_file_in_war $f WEB-INF/jboss-web.xml)
      if [ -n "$jboss_web_xml" ]; then
        if [[ $jboss_web_xml == *"<context-root>"* ]]; then
          context_root=$(echo $jboss_web_xml | xmllint --nowarning --xpath "string(//*[local-name()='context-root'])" - | sed ':a;N;$!ba;s/\n//g' | tr -d '[:space:]')
        fi
        if [ -n "$context_root" ]; then
          if [[ $context_root == /* ]]; then
            context_root="${context_root:1}"
          fi
        fi
      fi

      if [ $f == "ROOT.war" ]; then
        redirect_path=""
        if [ -z "$module_name" ]; then
          module_name="root"
        fi
      else
        if [ -n "$module_name" ]; then
          if [ -n "$context_root" ]; then
            redirect_path="${context_root}/${module_name}"
          else
            redirect_path=$module_name
          fi
        else
          if [ -n "$context_root" ]; then
            redirect_path=$context_root
            module_name=$(echo $f | sed -e "s/.war//g")
          else
            redirect_path=$(echo $f | sed -e "s/.war//g")
            module_name=$redirect_path
          fi
        fi
      fi
      if [ -n "$APPLICATION_NAME" ]; then
        client_id=${APPLICATION_NAME}-${module_name}
      else
        client_id=${module_name}
      fi

      cli="$cli
         /subsystem=${OIDC_SUBSYSTEM}/secure-deployment=${f}:write-attribute(name=client-id, value=${client_id})"
      if [ -n "${OIDC_SECURE_DEPLOYMENT_SECRET}" ]; then
        cli="$cli
          /subsystem=${OIDC_SUBSYSTEM}/secure-deployment=${f}/credential=secret:add(secret=${OIDC_SECURE_DEPLOYMENT_SECRET})"
      fi

      if [ -n "$OIDC_SECURE_DEPLOYMENT_BEARER_ONLY" ]; then
        bearer=${OIDC_SECURE_DEPLOYMENT_BEARER_ONLY}
      else
        bearer=false
      fi
      cli="$cli
      /subsystem=${OIDC_SUBSYSTEM}/secure-deployment=${f}:write-attribute(name=bearer-only, value=${bearer})"

      oidc_configure_remote_client $module_name $APPLICATION_ROUTES ${client_id} ${redirect_path}
    fi
  fi
}

function read_file_in_war {
  local jarfile="${1}"
  local filename="${2}"
  local result=

  if [ -d "$jarfile" ]; then
    if [ -e "${jarfile}/${filename}" ]; then
        result=$(cat ${jarfile}/${filename})
    fi
  else
    file_exists=$(unzip -l "$jarfile" "$filename")
    if [[ $file_exists == *"$filename"* ]]; then
      if [[ "${filename}" == *.xml ]]; then
        result=$(unzip -p "$jarfile" "$filename" | xmllint --format --recover --nowarning - | sed ':a;N;$!ba;s/\n//g')
      else
        result=$(unzip -p "$jarfile" "$filename")
      fi
    fi
  fi
  echo "$result"
}

function oidc_configure_remote_client() {
  module_name=$1
  application_routes=$2
  client_id=$3
  redirect_path=$4

  IFS_save=$IFS
  IFS=";"
  redirects=""
  endpoint=""
  for route in ${application_routes}; do
    if [ -n "$redirect_path" ]; then
      redirects="$redirects,\"${route}/${redirect_path}/*\""
      endpoint="${route}/${redirect_path}/"
    else
      redirects="$redirects,\"${route}/*\""
      endpoint="${route}/"
    fi
  done
  redirects="${redirects:1}"
  IFS=$IFS_save

  oidc_create_client_hook "${client_id}" "${redirects}" "${redirect_path}" "${endpoint}" "${module_name}"
}

function get_application_routes {
  
  if [ -n "$OIDC_HOSTNAME_HTTP" ]; then
    route="http://${OIDC_HOSTNAME_HTTP}"
  fi

  if [ -n "$OIDC_HOSTNAME_HTTPS" ]; then
    secureroute="https://${OIDC_HOSTNAME_HTTPS}"
  fi

  if [ -z "$OIDC_HOSTNAME_HTTP" ] && [ -z "$OIDC_HOSTNAME_HTTPS" ]; then
    log_warning "HOSTNAME_HTTP (or OIDC_HOSTNAME_HTTP) and HOSTNAME_HTTPS (or OIDC_HOSTNAME_HTTPS) are not set, trying to discover secure route by querying internal APIs"
    APPLICATION_ROUTES=$(discover_routes)
  else
    if [ -n "$route" ] && [ -n "$secureroute" ]; then
      APPLICATION_ROUTES="${route};${secureroute}"
    elif [ -n "$route" ]; then
      APPLICATION_ROUTES="${route}"
    elif [ -n "$secureroute" ]; then
      APPLICATION_ROUTES="${secureroute}"
    fi
  fi

  APPLICATION_ROUTES=$(add_route_with_default_port ${APPLICATION_ROUTES})
}


# Adds an aditional route to the route list with the default port only if the route doesn't have a port
# {1} Route or Route list (splited by semicolon)
function add_route_with_default_port() {
  local routes=${1}
  local routesWithPort="";
  local IFS_save=$IFS
  IFS=";"

  for route in ${routes}; do
    routesWithPort="${routesWithPort}${route};"
    # this regex match URLs with port
    if ! [[ "${route}" =~ ^(https?://.*):(\d*)\/?(.*)$ ]]; then
      if [[ "${route}" =~ ^(http://.*)$ ]]; then
        routesWithPort="${routesWithPort}${route}:80;"
      elif [[ "${route}" =~ ^(https://.*)$ ]]; then
        routesWithPort="${routesWithPort}${route}:443;"
      fi
    fi
  done
  
  IFS=$IFS_save

  echo ${routesWithPort%;}
}

# Tries to discover the route using the pod's hostname
function discover_routes() {  
  local service_name=$(compute_service_name)
  echo $(query_routes_from_service $service_name)
}

function compute_service_name() {
  IFS_save=$IFS
  IFS='-' read -ra pod_name_array <<< "${HOSTNAME}"
  local bound=$((${#pod_name_array[@]}-2))
  local name=
  for ((i=0;i<bound;i++)); do
    name="$name${pod_name_array[$i]}"
    if (( i < bound-1 )); then
      name="$name-"
    fi
  done
  IFS=$IFS_save
  echo $name
}

# Verify if the container is on OpenShift. The variable K8S_ENV could be set to emulate this behavior
function is_running_on_openshift() {
  if [ -e /var/run/secrets/kubernetes.io/serviceaccount/token ] || [ "${K8S_ENV}" = true ] ; then
    return 0
  else
    return 1
  fi
}

# Queries the Routes from the Kubernetes API based on the service name
# ${1} - service name
# see: https://docs.openshift.com/container-platform/3.11/rest_api/apis-route.openshift.io/v1.Route.html#Get-apis-route.openshift.io-v1-routes
function query_routes_from_service() {
  local serviceName=${1}
  # only execute the following lines if this container is running on OpenShift
  if is_running_on_openshift; then
    local namespace=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
    local token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    local response=$(curl -s -w "%{http_code}" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
        -H "Authorization: Bearer $token" \
        -H 'Accept: application/json' \
        ${KUBERNETES_SERVICE_PROTOCOL:-https}://${KUBERNETES_SERVICE_HOST:-kubernetes.default.svc}:${KUBERNETES_SERVICE_PORT:-443}/apis/route.openshift.io/v1/namespaces/${namespace}/routes?fieldSelector=spec.to.name=${serviceName})
    if [[ "${response: -3}" = "200" && "${response::- 3},," = *"items"* ]]; then
      response=$(echo ${response::- 3})
      echo $(oidc_get_routes_from_json "$response")
    else
      log_warning "Fail to query the Route using the Kubernetes API, the Service Account might not have the necessary privileges."
      
      if [ ! -z "${response}" ]; then
        log_warning "Response message: ${response::- 3} - HTTP Status code: ${response: -3}"
      fi
    fi
  fi
}

function oidc_get_routes_from_json() {
  json_reply="${1}"
  json_routes=$(jq -r '.items[].spec|if .tls then "https" else "http" end + "://" + .host' <<< $json_reply)
  IFS_save=$IFS
  json_routes="$(readarray -t JSON_ROUTES_ARRAY <<< "${json_routes}"; IFS=';'; echo "${JSON_ROUTES_ARRAY[*]}")"
  IFS=$IFS_save
  echo "${json_routes}"
}