#!/bin/bash

function oidc_keycloak_prepareEnv() {
  unset SSO_BEARER_ONLY
  unset HOSTNAME_HTTP
  unset HOSTNAME_HTTPS
  unset SSO_DISABLE_SSL_CERTIFICATE_VALIDATION
  unset SSO_ENABLE_CORS
  unset SSO_PASSWORD
  unset SSO_PRINCIPAL_ATTRIBUTE
  unset SSO_PUBLIC_KEY
  unset SSO_REALM
  unset SSO_SECRET
  unset SSO_TRUSTSTORE
  unset SSO_TRUSTSTORE_CERTIFICATE_ALIAS
  unset SSO_TRUSTSTORE_DIR
  unset SSO_TRUSTSTORE_PASSWORD
  unset SSO_URL
  unset SSO_SERVICE_URL
  unset SSO_USERNAME
  unset SSO_OPENIDCONNECT_DEPLOYMENTS
}