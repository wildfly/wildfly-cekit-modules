#!/bin/sh

set -e

source "${JBOSS_CONTAINER_UTIL_LOGGING_MODULE}/logging.sh"
source "${JBOSS_CONTAINER_MAVEN_S2I_MODULE}/maven-s2i"

# include our overrides/extensions
source "${JBOSS_CONTAINER_WILDFLY_S2I_MODULE}/s2i-core-hooks"
source "${JBOSS_CONTAINER_WILDFLY_S2I_MODULE}/maven-s2i-overrides"

# invoke the build
maven_s2i_build