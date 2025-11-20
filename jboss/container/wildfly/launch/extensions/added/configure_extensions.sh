#!/bin/sh

function preConfigure() {
  preconfigure_extensions
}

# if a delayedpostconfigure.sh file exists call it, otherwise fallback on postconfigure.sh
function postConfigure() {
  if [ -f "${JBOSS_HOME}/extensions/delayedpostconfigure.sh" ]; then
    ${JBOSS_HOME}/extensions/delayedpostconfigure.sh
  else
    postconfigure_extensions
  fi
}

function preconfigure_extensions(){
  if [ -f "${JBOSS_HOME}/extensions/preconfigure.sh" ]; then
    ${JBOSS_HOME}/extensions/preconfigure.sh
  fi
}

function postconfigure_extensions(){
  if [ -f "${JBOSS_HOME}/extensions/postconfigure.sh" ]; then
    ${JBOSS_HOME}/extensions/postconfigure.sh
  fi
}
