#!/bin/sh

if [ "${SCRIPT_DEBUG}" = "true" ] ; then
    set -x
    echo "Script debugging is enabled, allowing bash commands and their arguments to be printed as they are executed"
fi

# For backward compatibility: CONTAINER_HEAP_PERCENT is old variable name
JAVA_MAX_MEM_RATIO=${JAVA_MAX_MEM_RATIO:-${CONTAINER_HEAP_PERCENT:+$(echo "${CONTAINER_HEAP_PERCENT}" "100" | awk '{ printf "%d", $1 * $2 }')}}

function source_java_run_scripts() {
    # load java options functions
    source "${JBOSS_CONTAINER_JAVA_JVM_MODULE}/java-default-options"
}

source_java_run_scripts

# Returns a set of options that are not supported by the current jvm.  The idea
# is that java-default-options always configures settings for the latest jvm.
# That said, it is possible that the configuration won't map to previous
# versions of the jvm.  In those cases, it might be better to have different
# implementations of java-default-options for each version of the jvm (e.g. a
# private implementation that is sourced by java-default-options based on the
# jvm version).  This would allow for the defaults to be tuned for the version
# of the jvm being used.
unsupported_options() {
    if [[ $($JAVA_HOME/bin/java -version 2>&1 | awk -F "\"" '/version/{ print $2}') == *"1.7"* ]]; then
        echo "(-XX:NativeMemoryTracking=[^ ]*|-XX:+PrintGCDateStamps|-XX:+UnlockDiagnosticVMOptions|-XX:CICompilerCount=[^ ]*|-XX:GCTimeRatio=[^ ]*|-XX:MaxMetaspaceSize=[^ ]*|-XX:AdaptiveSizePolicyWeight=[^ ]*)"
    else
        echo "(--XX:MaxPermSize=[^ ]*)"
    fi
}

# Merge default java options into the passed argument
adjust_java_options() {
    local options="$@"
    local remove_xms
    # nuke any hard-coded memory settings.  java-default-options won't add these
    # if they're already specified
    JAVA_OPTS="$(echo $JAVA_OPTS| sed -re 's/(-Xmx[^ ]*|-Xms[^ ]*)//g')"
    local java_options=$(source "${JBOSS_CONTAINER_JAVA_JVM_MODULE}/java-default-options")
    local unsupported="$(unsupported_options)"
    for option in $java_options; do
        if [[ ${option} == "-Xmx"* ]]; then
            if [[ "$options" == *"-Xmx"* ]]; then
                options=$(echo $options | sed -e "s/-Xmx[^ ]*/${option}/")
            else
                options="${options} ${option}"
            fi
            if [ "x$remove_xms" == "x" ]; then
                remove_xms=1
            fi
        elif [[ ${option} == "-Xms"* ]]; then
            if [[ "$options" == *"-Xms"* ]]; then
                options=$(echo $options | sed -e "s/-Xms[^ ]*/${option}/")
            else
                options="${options} ${option}"
            fi
            remove_xms=0
        elif $(echo "$options" | grep -Eq -- "${option%=*}(=[^ ]*)?(\s|$)") ; then
            options=$(echo $options | sed -re "s@${option%=*}(=[^ ]*)?(\s|$)@${option}\2@")
        else
            options="${options} ${option}"
        fi
    done

    if [[ "x$remove_xms" == "x1" ]]; then
        options=$(echo $options | sed -e "s/-Xms[^ ]*/ /")
    fi

    options=$(echo "${options}"| sed -re "s@${unsupported}(\s)?@@g")
    echo "${options}"
}
