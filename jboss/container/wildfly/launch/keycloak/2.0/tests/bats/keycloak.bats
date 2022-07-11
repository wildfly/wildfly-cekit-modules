#!/usr/bin/env bats

source $BATS_TEST_DIRNAME/../../../../../../../../test-common/cli_utils.sh

# fake JBOSS_HOME
export JBOSS_HOME=$BATS_TMPDIR/jboss_home
rm -rf $JBOSS_HOME 2>/dev/null
mkdir -p $JBOSS_HOME/bin/launch

# copy scripts we are going to use
cp $BATS_TEST_DIRNAME/../../../../../launch-config/config/2.0/added/launch/openshift-common.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../../../../../launch-config/os/added/launch/launch-common.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../../../../../../../../test-common/logging.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../../added/keycloak.sh $JBOSS_HOME/bin/launch

mkdir -p $JBOSS_HOME/standalone/configuration
mkdir -p $JBOSS_HOME/standalone/deployments

# Set up the environment variables and load dependencies
WILDFLY_SERVER_CONFIGURATION=standalone-openshift.xml

# source the scripts needed
source $JBOSS_HOME/bin/launch/logging.sh
source $JBOSS_HOME/bin/launch/openshift-common.sh
source $JBOSS_HOME/bin/launch/keycloak.sh

BATS_PATH_TO_EXISTING_FILE=$BATS_TEST_DIRNAME/keycloak.bats
EXTENSIONS_END_MARKER="</extensions>"
DEPLOYMENTS="</extensions><deployments><deployment name=\"foo-webapp.war\" runtime-name=\"foo-webapp.war\"><content sha1=\"6662c9cbe0842c0b6e0b097329748f9c2e04515e\"/></deployment><deployment name=\"foo-webapp-saml.war\" runtime-name=\"foo-webapp-saml.war\"><content sha1=\"6762c9cbe0842c0b6e0b097329748f9c2e04515e\"/></deployment></deployments>"
setup() {
  cp $BATS_TEST_DIRNAME/../../../../../../../../test-common/configuration/standalone-openshift.xml $JBOSS_HOME/standalone/configuration
  cp $BATS_TEST_DIRNAME/simple-webapp-saml.war $JBOSS_HOME/standalone/deployments
  mkdir -p $JBOSS_HOME/standalone/data/content/67/62c9cbe0842c0b6e0b097329748f9c2e04515e/
  cp $BATS_TEST_DIRNAME/simple-webapp-saml.war $JBOSS_HOME/standalone/data/content/67/62c9cbe0842c0b6e0b097329748f9c2e04515e/content
  sed -i "s|${EXTENSIONS_END_MARKER}|${DEPLOYMENTS}|" "$JBOSS_HOME"/standalone/configuration/standalone-openshift.xml
}

teardown() {
  if [ -n "${CONFIG_FILE}" ] && [ -f "${CONFIG_FILE}" ]; then
    rm "${CONFIG_FILE}"
  fi
}

@test "Unconfigured, nothing should be generated" {
    run configure
    echo "CONSOLE:${output}"
    [ "${output}" = "" ]
    [ "$status" -eq 0 ]
    [ ! -a "${CLI_SCRIPT_FILE}" ]
}

@test "SSO env variables, provider enabled, generation expected" {
    expected=$(cat << EOF
    if (outcome != success) of /subsystem=keycloak-saml:read-resource
      /subsystem=keycloak-saml:add()
    end-if
   /subsystem=keycloak-saml/secure-deployment=simple-webapp-saml.war:add()
   /subsystem=keycloak-saml/secure-deployment=simple-webapp-saml.war/SP=simple-webapp-saml:add(sslPolicy=EXTERNAL)
   /subsystem=keycloak-saml/secure-deployment=simple-webapp-saml.war/SP=simple-webapp-saml/Key=Key:add(signing=true,encryption=true)
   /subsystem=keycloak-saml/secure-deployment=simple-webapp-saml.war/SP=simple-webapp-saml/IDP=idp:add(signatureAlgorithm=RSA_SHA256,               signatureCanonicalizationMethod="http://www.w3.org/2001/10/xml-exc-c14n#", SingleSignOnService={signRequest=true,requestBinding=POST,              bindingUrl=http://foo:9999/auth/realms/master/protocol/saml,validateSignature=true},              SingleLogoutService={validateRequestSignature=true,validateResponseSignature=true,signRequest=true,              signResponse=true,requestBinding=POST,responseBinding=POST, postBindingUrl=http://foo:9999/auth/realms/master/protocol/saml,              redirectBindingUrl=http://foo:9999/auth/realms/master/protocol/saml})
   /subsystem=keycloak-saml/secure-deployment=simple-webapp-saml.war/SP=simple-webapp-saml:write-attribute(name=logoutPage,value=/)
   /subsystem=keycloak-saml/secure-deployment=foo-webapp-saml.war:add()
   /subsystem=keycloak-saml/secure-deployment=foo-webapp-saml.war/SP=foo-webapp-saml:add(sslPolicy=EXTERNAL)
   /subsystem=keycloak-saml/secure-deployment=foo-webapp-saml.war/SP=foo-webapp-saml/Key=Key:add(signing=true,encryption=true)
   /subsystem=keycloak-saml/secure-deployment=foo-webapp-saml.war/SP=foo-webapp-saml/IDP=idp:add(signatureAlgorithm=RSA_SHA256,               signatureCanonicalizationMethod="http://www.w3.org/2001/10/xml-exc-c14n#", SingleSignOnService={signRequest=true,requestBinding=POST,              bindingUrl=http://foo:9999/auth/realms/master/protocol/saml,validateSignature=true},              SingleLogoutService={validateRequestSignature=true,validateResponseSignature=true,signRequest=true,              signResponse=true,requestBinding=POST,responseBinding=POST, postBindingUrl=http://foo:9999/auth/realms/master/protocol/saml,              redirectBindingUrl=http://foo:9999/auth/realms/master/protocol/saml})
  /subsystem=keycloak-saml/secure-deployment=foo-webapp-saml.war/SP=foo-webapp-saml:write-attribute(name=logoutPage,value=/)
EOF
)
    SSO_URL="http://foo:9999/auth"
    run configure
    echo "CONSOLE: ${output}"
    output=$(<"${CLI_SCRIPT_FILE}")
    
    normalize_spaces_new_lines
    [[ "${output}" == *"${expected}"* ]] 
}