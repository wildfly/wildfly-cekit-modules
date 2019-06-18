#!/bin/sh
# Configure module
set -e

SCRIPT_DIR=$(dirname $0)
ARTIFACTS_DIR=${SCRIPT_DIR}/artifacts

chown -R jboss:root $SCRIPT_DIR
chmod -R ug+rwX $SCRIPT_DIR
chmod ug+x ${ARTIFACTS_DIR}/opt/jboss/container/wildfly/s2i/*

pushd ${ARTIFACTS_DIR}
cp -pr * /
popd

ln -s /opt/jboss/container/wildfly/s2i/install-common/install-common.sh /usr/local/s2i/install-common.sh
chown -h jboss:root /usr/local/s2i/install-common.sh

mkdir $WILDFLY_S2I_OUTPUT_DIR && chown -R jboss:root $WILDFLY_S2I_OUTPUT_DIR && chmod -R ug+rwX $WILDFLY_S2I_OUTPUT_DIR
