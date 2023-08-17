#!/bin/sh
# common subroutines used in various places of the launch scripts

# Finds the environment variable  and returns its value if found.
# Otherwise returns the default value if provided.
#
# Arguments:
# $1 env variable name to check
# $2 default value if environment variable was not set
function find_env() {
  var=${!1}
  echo "${var:-$2}"
}

# Finds the environment variable with the given prefix. If not found
# the default value will be returned. If no prefix is provided will rely on
# find_env
#
# Arguments
#  - $1 prefix. Transformed to uppercase and replace - by _
#  - $2 variable name. Prepended by "prefix_"
#  - $3 default value if the variable is not defined
function find_prefixed_env () {
  local prefix=$1

  if [[ -z $prefix ]]; then
    find_env $2 $3
  else
    prefix=${prefix^^} # uppercase
    prefix=${prefix//-/_} #replace - by _

    local var_name=$prefix"_"$2
    echo ${!var_name:-$3}
  fi
}

# Takes the following parameters:
# - $1      - the xml marker to test for
# - $2      - the variable which will hold the result
# The result holding variable, $2, will be populated with one of the following
# three values:
# - ""      - no configuration should be done
# - "xml"   - configuration should happen via marker replacement
# - "cli"   - configuration should happen via cli commands
#
function getConfigurationMode() {
  local marker="${1}"
  unset -v "$2" || echo "Invalid identifier: $2" >&2

  local attemptXml="false"
  local viaCli="false"
  if [ "${CONFIG_ADJUSTMENT_MODE,,}" = "xml" ]; then
    attemptXml="true"
  elif  [ "${CONFIG_ADJUSTMENT_MODE,,}" = "cli" ]; then
    viaCli="true"
  elif  [ "${CONFIG_ADJUSTMENT_MODE,,}" = "xml_cli" ]; then
    attemptXml="true"
    viaCli="true"
  elif [ "${CONFIG_ADJUSTMENT_MODE,,}" != "none" ]; then
    echo "Bad CONFIG_ADJUSTMENT_MODE \'${CONFIG_ADJUSTMENT_MODE}\'"
    exit 1
  fi

  local configVia=""
  if [ "${attemptXml}" = "true" ]; then
    if grep -Fq "${marker}" $CONFIG_FILE; then
        configVia="xml"
    fi
  fi

  if [ -z "${configVia}" ]; then
    if [ "${viaCli}" = "true" ]; then
        configVia="cli"
    fi
  fi

  printf -v "$2" '%s' "${configVia}"
}

# Test an XpathExpression against server config file and returns
# the xmllint exit code
#
# Parameters:
# - $1      - the xpath expression to use
# - $2      - the variable which will hold the exit code
# - $3      - an optional variable to hold the output of the xpath command
#
function testXpathExpression() {
  local xpath="$1"
  unset -v "$2" || echo "Invalid identifier: $2" >&2

  local output
  output=$(eval xmllint --xpath "${xpath}" "${CONFIG_FILE}" 2>/dev/null)

  printf -v "$2" '%s' "$?"

  if [ -n "$3" ]; then
    unset -v "$3" && printf -v "$3" '%s' "${output}"
  fi
}

# An XPath expression e.g getting all name attributes for all the servers in the undertow subsystem
# will return a variable with all the attributes with their names on one line, e.g
#     'name="server-one" name="server-two" name="server-three"'
# Call this with ($input is the string above)
#     convertAttributesToValueOnEachLine "$input" "name"
# to convert this to :
# "server-one
# server-two
# server-three"
function splitAttributesStringIntoLines() {
  local input="${1}"
  local attribute_name="${2}"

  local temp
  temp=$(echo $input | sed "s|\" ${attribute_name}=\"|\" \n${attribute_name}=\"|g" | awk -F "\"" '{print $2}')
  echo "${temp}"
}

# retrieves the first IP v6 address
function get_host_ipv6() {
  unset -v "$1" || echo "Invalid identifier: $1" >&2

  local input="/proc/net/if_inet6"

  if [ ! -f "$input" ]; then
    log_error "$input file doesn't exist. Can't discover ip v6 address."
    exit 1
  fi
  local count=0
  while IFS= read -r line
  do
    arr=($line)
    address=${arr[0]}
    # Skip loopback and link local addresses
    if [ $address != "00000000000000000000000000000001" ] && [[ $address != fe80* ]]; then
      if [ -z "$ipv6" ]; then
        local ipv6="${address:0:4}:${address:4:4}:${address:8:4}:${address:12:4}:${address:16:4}:${address:20:4}:${address:24:4}:${address:28:4}"
      fi
      count=$((count+1))
    fi
  done < "$input"

  if [[ "$count" == "0" ]]; then
    log_error "No IP v6 address found. Can't configure IPv6"
    exit 1
  fi

  if [[ "$count" != "1" ]]; then
    log_warning "get_host_ipv6() returned $count ipv6 addresses, only the first address $ipv6 will be used. To use different address please set $JBOSS_HA_IP and $JBOSS_MESSAGING_HOST."
  fi

  printf -v "$1" '%s' "${ipv6}"
}

#
# Find the first ipv4 address of the host
# The host could have 1 or more ipv4 addresses
# For this function we need to return a single ipv4 address
#
# /proc/net/fib_tree contains the Forwarding Information Base table
#
# awk is using a block-pattern to filter lines with 32 or host
#
# python or other languages can not be used and it must be /bin/sh compatible
#
# depends on the following tools:
# sh, awk, sort, uniq, grep, wc, head
function get_host_ipv4() {
  unset -v "$1" || echo "Invalid identifier: $1" >&2
  local input="/proc/net/fib_trie"

  if [ ! -f "$input" ]; then
    log_error "$input file doesn't exist. Can't discover ip v4 address."
    exit 1
  fi
  local allIPs=$(awk '/32 host/ { print f } {f=$2}' <<< "$(<$input)" | sort -n | uniq | grep -v '127.0.0.')
  local count=$(echo "$allIPs" | wc -l)

  local ipv4=$(echo "$allIPs" | head -n1)

  if [[ "$count" == "0" ]]; then
    log_error "No IP v4 address found."
    exit 1
  fi
  if [[ "$count" != "1" ]]; then
    log_warning "get_host_ipv4() returned $count ipv4 addresses, only the first address $ipv4 will be used. To use different address please set \$JBOSS_HA_IP and \$JBOSS_MESSAGING_HOST."
  fi
  printf -v "$1" '%s' "${ipv4}"
}

# Retrieves the ip v4 (the default) or ip v6 (if SERVER_USE_IPV6 env variable is set).
# The passed argument is a name of a variable that will be set by this function
# Usage:
# local ip=
# get_host_ip_address "ip"
# echo $ip
function get_host_ip_address() {
  if [ "xxx$SERVER_USE_IPV6" == "xxxtrue" ]; then
    get_host_ipv6 "$1"
  else
    get_host_ipv4 "$1"
  fi
}

function get_bind_all_address() {
  if [ "xxx$SERVER_USE_IPV6" == "xxxtrue" ]; then
    echo "::" 
  else
    echo "0.0.0.0"
  fi
}

function get_loopback_address() {
  if [ "xxx$SERVER_USE_IPV6" == "xxxtrue" ]; then
    echo "::1" 
  else
    echo "127.0.0.1"
  fi
}