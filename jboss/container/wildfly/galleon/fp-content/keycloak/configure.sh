#!/bin/sh

set -e

SCRIPT_DIR=$(dirname $0)
ADDED_DIR=${SCRIPT_DIR}/added
cp -r ${ADDED_DIR}/* ${GALLEON_FP_PATH}

# Generate the set of keycloak packages.
pushd "$JBOSS_HOME/modules/system/add-ons/keycloak/" &> /dev/null
target_file=/tmp/keycloak_modules.txt
find -name module.xml -printf '%P\n' > "$target_file"
while read line; do
  parentdir="$(dirname $line)"
  parentdir="$(dirname $parentdir)"
  modulename=${parentdir//\//.}
  pkgs="$pkgs<package name=\"$modulename\"/>\n"
done < "$target_file"
rm "$target_file"
popd

sed -i "s|<!-- ##KEYCLOAK_PACKAGES## -->|$pkgs|" "${GALLEON_FP_PATH}/src/main/resources/feature_groups/keycloak.xml"
