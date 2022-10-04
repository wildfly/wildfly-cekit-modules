#!/bin/sh
# Configure module
set -e

SCRIPT_DIR=$(dirname $0)
ARTIFACTS_DIR=${SCRIPT_DIR}/artifacts

chown -R jboss:root $SCRIPT_DIR
chmod -R ug+rwX $SCRIPT_DIR
chmod ug+x ${ARTIFACTS_DIR}/opt/jboss/container/wildfly/s2i/assemble.sh
pushd ${ARTIFACTS_DIR}
cp -pr * /
popd

# Copy default settings.xml for clean build
cp "${HOME}/.m2/settings.xml" "${JBOSS_CONTAINER_WILDFLY_S2I_LEGACY_GALLEON_MODULE}"/clean-settings.xml
chown jboss:root "${JBOSS_CONTAINER_WILDFLY_S2I_LEGACY_GALLEON_MODULE}"/clean-settings.xml
# Kept for backward compatibility
ln -s /opt/jboss/container/wildfly/s2i/install-common/install-common.sh /usr/local/s2i/install-common.sh
chown -h jboss:root /usr/local/s2i/install-common.sh