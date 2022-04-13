#!/bin/bash
set -e
SCRIPT_DIR=$(pwd -P)/$(dirname $0)
# Install launch scripts.
resources_dir="$1"
packages_dir="$resources_dir/packages"
common_package_dir="$packages_dir/wildfly.s2i.common/content"
mkdir -p $common_package_dir
export JBOSS_HOME="$common_package_dir"
fp_content_list_file="$2"
launch_list_file="$3"
launch_config_list_file="$4"

mkdir -p "$JBOSS_HOME/bin/launch"
  pushd "$SCRIPT_DIR"/../jboss/container/wildfly/launch > /dev/null
    while read dir; do
      if [ -d "$dir" ]; then
        echo Adding launch scripts from $dir
        pushd "$dir" > /dev/null
          if [ -f "./configure.sh" ]; then
            sh ./configure.sh
          else
            echo Missing configure.sh for "$dir"
            exit 1
          fi
        popd > /dev/null
      else
        echo invalid directory $dir
        exit 1
      fi
    done < $launch_list_file
  popd > /dev/null
  pushd "$SCRIPT_DIR"/../jboss/container/wildfly/launch-config > /dev/null
    while read dir; do
      if [ -d "$dir" ]; then
        echo Adding launch config scripts from $dir
        pushd "$dir" > /dev/null
          if [ -f "./configure.sh" ]; then
            sh ./configure.sh
          else
            echo Missing configure.sh for "$dir"
            exit 1
          fi
        popd > /dev/null
      else
        echo invalid directory $dir
        exit 1
      fi
    done < $launch_config_list_file
  popd > /dev/null
  pushd "$SCRIPT_DIR"/../jboss/container/wildfly/galleon/cloud-galleon-pack > /dev/null
   while read dir; do
     echo Adding feature-content from $dir
     pushd $dir/added/src/main/resources > /dev/null
      cp -r * "$resources_dir"
     popd > /dev/null
   done < $fp_content_list_file
  popd > /dev/null
unset JBOSS_HOME