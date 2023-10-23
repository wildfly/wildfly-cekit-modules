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
UNDERTOW_SECURITY_DOMAINS_MARKER="<!-- ##HTTP_APPLICATION_SECURITY_DOMAINS## -->"
EJB_SECURITY_DOMAINS_MARKER="<!-- ##EJB_APPLICATION_SECURITY_DOMAINS## -->"
DEPLOYMENTS="</extensions><deployments><deployment name=\"foo-webapp.war\" runtime-name=\"foo-webapp.war\"><content sha1=\"6662c9cbe0842c0b6e0b097329748f9c2e04515e\"/></deployment><deployment name=\"foo-webapp-saml.war\" runtime-name=\"foo-webapp-saml.war\"><content sha1=\"6762c9cbe0842c0b6e0b097329748f9c2e04515e\"/></deployment></deployments>"
UNDERTOW_SECURITY_DOMAINS="<application-security-domains><application-security-domain name=\"other\" security-domain=\"ApplicationDomain\"/></application-security-domains>"
EJB_SECURITY_DOMAINS="<application-security-domains><application-security-domain name=\"other\" security-domain=\"ApplicationDomain\"/></application-security-domains>"
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
if (outcome != success) of /subsystem=elytron:read-resource
echo You have set environment variables to enable sso. Fix your configuration to contain elytron subsystem for this to happen. >> \${error_file}
quit
end-if
if (outcome != success) of /subsystem=undertow:read-resource
echo You have set environment variables to enable sso. Fix your configuration to contain undertow subsystem for this to happen. >> \${error_file}
quit
end-if
if (outcome == success) of /subsystem=undertow/application-security-domain=keycloak:read-resource
echo Undertow already contains keycloak application security domain. Fix your configuration or set SSO_SECURITY_DOMAIN env variable. >> \${error_file}
quit
end-if
if (outcome != success) of /extension=org.keycloak.keycloak-saml-adapter-subsystem:read-resource
/extension=org.keycloak.keycloak-saml-adapter-subsystem:add()
end-if
if (outcome != success) of /subsystem=elytron/custom-realm=KeycloakSAMLRealm-test:read-resource
/subsystem=elytron/custom-realm=KeycloakSAMLRealm-test:add(class-name=org.keycloak.adapters.saml.elytron.KeycloakSecurityRealm, module=org.keycloak.keycloak-saml-wildfly-elytron-jakarta-adapter)
else
echo Keycloak SAML Realm already installed >> \${warning_file}
end-if
if (outcome != success) of /subsystem=elytron/security-domain=KeycloakDomain-test:read-resource
/subsystem=elytron/security-domain=KeycloakDomain-test:add(default-realm=KeycloakSAMLRealm-test,permission-mapper=default-permission-mapper,security-event-listener=local-audit,realms=[{realm=KeycloakSAMLRealm-test}])
else
echo Keycloak Security Domain already installed. Trying to install Keycloak SAML Realm. >> \${warning_file}
/subsystem=elytron/security-domain=KeycloakDomain-test:list-add(name=realms, value={realm=KeycloakSAMLRealm-test})
end-if
if (outcome != success) of /subsystem=elytron/constant-realm-mapper=keycloak-saml-realm-mapper-test:read-resource
/subsystem=elytron/constant-realm-mapper=keycloak-saml-realm-mapper-test:add(realm-name=KeycloakSAMLRealm-test)
else
echo Keycloak SAML Realm Mapper already installed >> \${warning_file}
end-if
if (outcome != success) of /subsystem=elytron/service-loader-http-server-mechanism-factory=keycloak-saml-http-server-mechanism-factory-test:read-resource
/subsystem=elytron/service-loader-http-server-mechanism-factory=keycloak-saml-http-server-mechanism-factory-test:add(module=org.keycloak.keycloak-saml-wildfly-elytron-jakarta-adapter)
else
echo Keycloak SAML HTTP Mechanism Factory already installed >> \${warning_file}
end-if
if (outcome != success) of /subsystem=elytron/aggregate-http-server-mechanism-factory=keycloak-http-server-mechanism-factory-test:read-resource
/subsystem=elytron/aggregate-http-server-mechanism-factory=keycloak-http-server-mechanism-factory-test:add(http-server-mechanism-factories=[keycloak-saml-http-server-mechanism-factory-test, global])
else
echo Keycloak HTTP Mechanism Factory already installed. Trying to install Keycloak SAML HTTP Mechanism Factory. >> \${warning_file}
/subsystem=elytron/aggregate-http-server-mechanism-factory=keycloak-http-server-mechanism-factory-test:list-add(name=http-server-mechanism-factories, value=keycloak-saml-http-server-mechanism-factory-test)
end-if
if (outcome != success) of /subsystem=elytron/http-authentication-factory=keycloak-http-authentication-test:read-resource
/subsystem=elytron/http-authentication-factory=keycloak-http-authentication-test:add(security-domain=KeycloakDomain-test,http-server-mechanism-factory=keycloak-http-server-mechanism-factory-test,mechanism-configurations=[{mechanism-name=KEYCLOAK-SAML,mechanism-realm-configurations=[{realm-name=KeycloakSAMLCRealm-test,realm-mapper=keycloak-saml-realm-mapper-test}]}])
else
echo Keycloak HTTP Authentication Factory already installed. Trying to install Keycloak SAML Mechanism Configuration >> \${warning_file}
/subsystem=elytron/http-authentication-factory=keycloak-http-authentication-test:list-add(name=mechanism-configurations, value={mechanism-name=KEYCLOAK-SAML,mechanism-realm-configurations=[{realm-name=KeycloakSAMLRealm-test,realm-mapper=keycloak-saml-realm-mapper-test}]})
end-if
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
/subsystem=elytron/security-domain=ext-KeycloakDomain-test:add(default-realm=ApplicationRealm,      permission-mapper=default-permission-mapper,security-event-listener=local-audit,      realms=[{realm=local},{realm=ApplicationRealm,role-decoder=groups-to-roles},{realm=KeycloakSAMLRealm-test}])
/subsystem=elytron/http-authentication-factory=ext-keycloak-http-authentication-test:add(      security-domain=ext-KeycloakDomain-test,http-server-mechanism-factory=keycloak-http-server-mechanism-factory-test,      mechanism-configurations=[{mechanism-name=BASIC,mechanism-realm-configurations=[{realm-name=ApplicationRealm}]},      {mechanism-name=FORM},{mechanism-name=DIGEST,mechanism-realm-configurations=[{realm-name=ApplicationRealm}]},      {mechanism-name=CLIENT_CERT},{mechanism-name=KEYCLOAK-SAML,mechanism-realm-configurations=[       {realm-name=KeycloakSAMLCRealm-test,realm-mapper=keycloak-saml-realm-mapper-test}]}])
/subsystem=undertow/application-security-domain=other:remove
/subsystem=undertow/application-security-domain=other:add(http-authentication-factory=ext-keycloak-http-authentication-test)
echo Existing other application-security-domain is extended with support for keycloak >> \${warning_file}
/subsystem=ejb3/application-security-domain=other:write-attribute(name=security-domain, value=ext-KeycloakDomain-test)
if (outcome != success) of /subsystem=ejb3/application-security-domain=keycloak:read-resource
/subsystem=ejb3/application-security-domain=keycloak:add(security-domain=KeycloakDomain-test)
else
echo ejb3 already contains keycloak application security domain. Fix your configuration or set SSO_SECURITY_DOMAIN env variable. >> \${error_file}
quit
end-if
/subsystem=undertow/application-security-domain=keycloak:add(http-authentication-factory=keycloak-http-authentication-test)
EOF
)
    SSO_URL="http://foo:9999/auth"
    TEST_FIXED_ID=test
    sed -i "s|${UNDERTOW_SECURITY_DOMAINS_MARKER}|${UNDERTOW_SECURITY_DOMAINS}|" "$JBOSS_HOME"/standalone/configuration/standalone-openshift.xml
    sed -i "s|${EJB_SECURITY_DOMAINS_MARKER}|${EJB_SECURITY_DOMAINS}|" "$JBOSS_HOME"/standalone/configuration/standalone-openshift.xml
    run configure
    echo "CONSOLE: ${output}"
    output=$(<"${CLI_SCRIPT_FILE}")
    
    normalize_spaces_new_lines
    [[ "${output}" == "${expected}" ]] 
}

@test "SSO env variables, provider enabled, generation expected, no existing security-domains" {
    expected=$(cat << EOF
if (outcome != success) of /subsystem=elytron:read-resource
echo You have set environment variables to enable sso. Fix your configuration to contain elytron subsystem for this to happen. >> \${error_file}
quit
end-if
if (outcome != success) of /subsystem=undertow:read-resource
echo You have set environment variables to enable sso. Fix your configuration to contain undertow subsystem for this to happen. >> \${error_file}
quit
end-if
if (outcome == success) of /subsystem=undertow/application-security-domain=keycloak:read-resource
echo Undertow already contains keycloak application security domain. Fix your configuration or set SSO_SECURITY_DOMAIN env variable. >> \${error_file}
quit
end-if
if (outcome != success) of /extension=org.keycloak.keycloak-saml-adapter-subsystem:read-resource
/extension=org.keycloak.keycloak-saml-adapter-subsystem:add()
end-if
if (outcome != success) of /subsystem=elytron/custom-realm=KeycloakSAMLRealm-test:read-resource
/subsystem=elytron/custom-realm=KeycloakSAMLRealm-test:add(class-name=org.keycloak.adapters.saml.elytron.KeycloakSecurityRealm, module=org.keycloak.keycloak-saml-wildfly-elytron-jakarta-adapter)
else
echo Keycloak SAML Realm already installed >> \${warning_file}
end-if
if (outcome != success) of /subsystem=elytron/security-domain=KeycloakDomain-test:read-resource
/subsystem=elytron/security-domain=KeycloakDomain-test:add(default-realm=KeycloakSAMLRealm-test,permission-mapper=default-permission-mapper,security-event-listener=local-audit,realms=[{realm=KeycloakSAMLRealm-test}])
else
echo Keycloak Security Domain already installed. Trying to install Keycloak SAML Realm. >> \${warning_file}
/subsystem=elytron/security-domain=KeycloakDomain-test:list-add(name=realms, value={realm=KeycloakSAMLRealm-test})
end-if
if (outcome != success) of /subsystem=elytron/constant-realm-mapper=keycloak-saml-realm-mapper-test:read-resource
/subsystem=elytron/constant-realm-mapper=keycloak-saml-realm-mapper-test:add(realm-name=KeycloakSAMLRealm-test)
else
echo Keycloak SAML Realm Mapper already installed >> \${warning_file}
end-if
if (outcome != success) of /subsystem=elytron/service-loader-http-server-mechanism-factory=keycloak-saml-http-server-mechanism-factory-test:read-resource
/subsystem=elytron/service-loader-http-server-mechanism-factory=keycloak-saml-http-server-mechanism-factory-test:add(module=org.keycloak.keycloak-saml-wildfly-elytron-jakarta-adapter)
else
echo Keycloak SAML HTTP Mechanism Factory already installed >> \${warning_file}
end-if
if (outcome != success) of /subsystem=elytron/aggregate-http-server-mechanism-factory=keycloak-http-server-mechanism-factory-test:read-resource
/subsystem=elytron/aggregate-http-server-mechanism-factory=keycloak-http-server-mechanism-factory-test:add(http-server-mechanism-factories=[keycloak-saml-http-server-mechanism-factory-test, global])
else
echo Keycloak HTTP Mechanism Factory already installed. Trying to install Keycloak SAML HTTP Mechanism Factory. >> \${warning_file}
/subsystem=elytron/aggregate-http-server-mechanism-factory=keycloak-http-server-mechanism-factory-test:list-add(name=http-server-mechanism-factories, value=keycloak-saml-http-server-mechanism-factory-test)
end-if
if (outcome != success) of /subsystem=elytron/http-authentication-factory=keycloak-http-authentication-test:read-resource
/subsystem=elytron/http-authentication-factory=keycloak-http-authentication-test:add(security-domain=KeycloakDomain-test,http-server-mechanism-factory=keycloak-http-server-mechanism-factory-test,mechanism-configurations=[{mechanism-name=KEYCLOAK-SAML,mechanism-realm-configurations=[{realm-name=KeycloakSAMLCRealm-test,realm-mapper=keycloak-saml-realm-mapper-test}]}])
else
echo Keycloak HTTP Authentication Factory already installed. Trying to install Keycloak SAML Mechanism Configuration >> \${warning_file}
/subsystem=elytron/http-authentication-factory=keycloak-http-authentication-test:list-add(name=mechanism-configurations, value={mechanism-name=KEYCLOAK-SAML,mechanism-realm-configurations=[{realm-name=KeycloakSAMLRealm-test,realm-mapper=keycloak-saml-realm-mapper-test}]})
end-if
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
if (outcome != success) of /subsystem=ejb3/application-security-domain=keycloak:read-resource
/subsystem=ejb3/application-security-domain=keycloak:add(security-domain=KeycloakDomain-test)
else
echo ejb3 already contains keycloak application security domain. Fix your configuration or set SSO_SECURITY_DOMAIN env variable. >> \${error_file}
quit
end-if
/subsystem=undertow/application-security-domain=keycloak:add(http-authentication-factory=keycloak-http-authentication-test)
EOF
)
    SSO_URL="http://foo:9999/auth"
    TEST_FIXED_ID=test
    run configure
    echo "CONSOLE: ${output}"
    output=$(<"${CLI_SCRIPT_FILE}")
    
    normalize_spaces_new_lines
    [[ "${output}" == "${expected}" ]] 
}

@test "SSO env variables, provider enabled, generation expected, foo security-domain" {
    expected=$(cat << EOF
if (outcome != success) of /subsystem=elytron:read-resource
echo You have set environment variables to enable sso. Fix your configuration to contain elytron subsystem for this to happen. >> \${error_file}
quit
end-if
if (outcome != success) of /subsystem=undertow:read-resource
echo You have set environment variables to enable sso. Fix your configuration to contain undertow subsystem for this to happen. >> \${error_file}
quit
end-if
if (outcome == success) of /subsystem=undertow/application-security-domain=foo:read-resource
echo Undertow already contains foo application security domain. Fix your configuration or set SSO_SECURITY_DOMAIN env variable. >> \${error_file}
quit
end-if
if (outcome != success) of /extension=org.keycloak.keycloak-saml-adapter-subsystem:read-resource
/extension=org.keycloak.keycloak-saml-adapter-subsystem:add()
end-if
if (outcome != success) of /subsystem=elytron/custom-realm=KeycloakSAMLRealm-test:read-resource
/subsystem=elytron/custom-realm=KeycloakSAMLRealm-test:add(class-name=org.keycloak.adapters.saml.elytron.KeycloakSecurityRealm, module=org.keycloak.keycloak-saml-wildfly-elytron-jakarta-adapter)
else
echo Keycloak SAML Realm already installed >> \${warning_file}
end-if
if (outcome != success) of /subsystem=elytron/security-domain=KeycloakDomain-test:read-resource
/subsystem=elytron/security-domain=KeycloakDomain-test:add(default-realm=KeycloakSAMLRealm-test,permission-mapper=default-permission-mapper,security-event-listener=local-audit,realms=[{realm=KeycloakSAMLRealm-test}])
else
echo Keycloak Security Domain already installed. Trying to install Keycloak SAML Realm. >> \${warning_file}
/subsystem=elytron/security-domain=KeycloakDomain-test:list-add(name=realms, value={realm=KeycloakSAMLRealm-test})
end-if
if (outcome != success) of /subsystem=elytron/constant-realm-mapper=keycloak-saml-realm-mapper-test:read-resource
/subsystem=elytron/constant-realm-mapper=keycloak-saml-realm-mapper-test:add(realm-name=KeycloakSAMLRealm-test)
else
echo Keycloak SAML Realm Mapper already installed >> \${warning_file}
end-if
if (outcome != success) of /subsystem=elytron/service-loader-http-server-mechanism-factory=keycloak-saml-http-server-mechanism-factory-test:read-resource
/subsystem=elytron/service-loader-http-server-mechanism-factory=keycloak-saml-http-server-mechanism-factory-test:add(module=org.keycloak.keycloak-saml-wildfly-elytron-jakarta-adapter)
else
echo Keycloak SAML HTTP Mechanism Factory already installed >> \${warning_file}
end-if
if (outcome != success) of /subsystem=elytron/aggregate-http-server-mechanism-factory=keycloak-http-server-mechanism-factory-test:read-resource
/subsystem=elytron/aggregate-http-server-mechanism-factory=keycloak-http-server-mechanism-factory-test:add(http-server-mechanism-factories=[keycloak-saml-http-server-mechanism-factory-test, global])
else
echo Keycloak HTTP Mechanism Factory already installed. Trying to install Keycloak SAML HTTP Mechanism Factory. >> \${warning_file}
/subsystem=elytron/aggregate-http-server-mechanism-factory=keycloak-http-server-mechanism-factory-test:list-add(name=http-server-mechanism-factories, value=keycloak-saml-http-server-mechanism-factory-test)
end-if
if (outcome != success) of /subsystem=elytron/http-authentication-factory=keycloak-http-authentication-test:read-resource
/subsystem=elytron/http-authentication-factory=keycloak-http-authentication-test:add(security-domain=KeycloakDomain-test,http-server-mechanism-factory=keycloak-http-server-mechanism-factory-test,mechanism-configurations=[{mechanism-name=KEYCLOAK-SAML,mechanism-realm-configurations=[{realm-name=KeycloakSAMLCRealm-test,realm-mapper=keycloak-saml-realm-mapper-test}]}])
else
echo Keycloak HTTP Authentication Factory already installed. Trying to install Keycloak SAML Mechanism Configuration >> \${warning_file}
/subsystem=elytron/http-authentication-factory=keycloak-http-authentication-test:list-add(name=mechanism-configurations, value={mechanism-name=KEYCLOAK-SAML,mechanism-realm-configurations=[{realm-name=KeycloakSAMLRealm-test,realm-mapper=keycloak-saml-realm-mapper-test}]})
end-if
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
/subsystem=elytron/security-domain=ext-KeycloakDomain-test:add(default-realm=ApplicationRealm,      permission-mapper=default-permission-mapper,security-event-listener=local-audit,      realms=[{realm=local},{realm=ApplicationRealm,role-decoder=groups-to-roles},{realm=KeycloakSAMLRealm-test}])
/subsystem=elytron/http-authentication-factory=ext-keycloak-http-authentication-test:add(      security-domain=ext-KeycloakDomain-test,http-server-mechanism-factory=keycloak-http-server-mechanism-factory-test,      mechanism-configurations=[{mechanism-name=BASIC,mechanism-realm-configurations=[{realm-name=ApplicationRealm}]},      {mechanism-name=FORM},{mechanism-name=DIGEST,mechanism-realm-configurations=[{realm-name=ApplicationRealm}]},      {mechanism-name=CLIENT_CERT},{mechanism-name=KEYCLOAK-SAML,mechanism-realm-configurations=[       {realm-name=KeycloakSAMLCRealm-test,realm-mapper=keycloak-saml-realm-mapper-test}]}])
/subsystem=undertow/application-security-domain=other:remove
/subsystem=undertow/application-security-domain=other:add(http-authentication-factory=ext-keycloak-http-authentication-test)
echo Existing other application-security-domain is extended with support for keycloak >> \${warning_file}
/subsystem=ejb3/application-security-domain=other:write-attribute(name=security-domain, value=ext-KeycloakDomain-test)
if (outcome != success) of /subsystem=ejb3/application-security-domain=foo:read-resource
/subsystem=ejb3/application-security-domain=foo:add(security-domain=KeycloakDomain-test)
else
echo ejb3 already contains foo application security domain. Fix your configuration or set SSO_SECURITY_DOMAIN env variable. >> \${error_file}
quit
end-if
/subsystem=undertow/application-security-domain=foo:add(http-authentication-factory=keycloak-http-authentication-test)
EOF
)
    SSO_URL="http://foo:9999/auth"
    SSO_SECURITY_DOMAIN=foo
    TEST_FIXED_ID=test
    sed -i "s|${UNDERTOW_SECURITY_DOMAINS_MARKER}|${UNDERTOW_SECURITY_DOMAINS}|" "$JBOSS_HOME"/standalone/configuration/standalone-openshift.xml
    sed -i "s|${EJB_SECURITY_DOMAINS_MARKER}|${EJB_SECURITY_DOMAINS}|" "$JBOSS_HOME"/standalone/configuration/standalone-openshift.xml
    run configure
    echo "CONSOLE: ${output}"
    output=$(<"${CLI_SCRIPT_FILE}")
    
    normalize_spaces_new_lines
    [[ "${output}" == "${expected}" ]] 
}
