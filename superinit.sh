#
# MIT License
#
# (C) Copyright 2023 Hewlett Packard Enterprise Development LP
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
#!/bin/bash

trap "rm -fr ${TDIR}" EXIT

CRAY_FORMAT=json
DOMAINS="hpc.amslabs.hpecorp.net dev.cray.com"
CRAY_SRC="git@github.com:Cray-HPE/craycli.git"
CRAY_VERSION="master"
SAT_SRC="https://github.com/Cray-HPE/sat.git"
SAT_VERSION="3.19"
PRODUCT_CATALOG_SRC="https://github.com/Cray-HPE/cray-product-catalog"
PRODUCT_CATALOG_VERSION="1.6.0"
PRINT_SAN=false
SUPERINIT_DIR=~/.config/superinit
VERSION=0.0.2
PY_VERSION=3
PYTHON=python$PY_VERSION
PIP=pip$PY_VERSION

mkdir -p $SUPERINIT_DIR

function usage() {
  echo "Usage: $0 [-h] -s <system-name>]"
  echo ""
  echo "$0 will initialize an environment to interact with a HPE Cray EX Supercomputer."
  echo "A system name must be supplied to derive the API gateway."
  echo "options:"
  echo "h              Print this help"
  echo "s <system>     System Name (required)"
  echo "d <domain>     Provide a space seperated list of Domains to scan. Default is '$DOMAINS'"
  echo "u              Print Certificate Subject Alternate Names (Web UIs)"
  echo "p              Set the PS1 to indicate which system is active <not implemented>"
  echo ""
  exit 0
}

function craycli_check() {
  if ! command cray &> /dev/null; then
    echo "cray CLI not found. Install cray?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) craycli_install; break;;
            No  ) echo "The cray CLI must be installed to continue"; exit;;
        esac
    done
  fi
}

function craycli_init() {
  if [ $# -ne 1 ]; then
    echo "Must pass a system name to craycli_init"
    exit 1
  fi
  sys=$1

  API_GW=$(scan_for_gw $sys)
  cray init --configuration $sys --hostname $API_GW --no-auth
  cray config set auth.login username=$USER
}

function craycli_install() {
  mkdir -p $SUPERINIT_DIR/cmds
  CRAY_VENV_PATH="$SUPERINIT_DIR/cmds/cray_venv"
  $PYTHON -m venv $CRAY_VENV_PATH
  . $CRAY_VENV_PATH/bin/activate
  git clone --branch=$CRAY_VERSION $CRAY_SRC $SUPERINIT_DIR/cmds/cray
  $PIP install $SUPERINIT_DIR/cmds/cray
  deactivate
  craycli_installed=true
}

function craycli_ping_check() {
  API_GW_HOST=$(cray config get core.hostname | sed 's/https:\/\///')
  if ! ping -c1 -W3000 $API_GW_HOST > /dev/null; then
    echo "Could not ping $API_GW_HOST"
    exit 1
  fi
}

function craycli_auth_check() {
  # Check if Cray CLI has a valid authentication token...
  if cray ims images list 2>&1 | grep rror | egrep --silent "401|403"; then
    echo "cray command not authorized. Authorize with 'cray auth login'?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) cray_auth; break;;
            No  ) echo "The cray CLI must be authenticated to continue"; exit;;
        esac
    done
  fi
}

function cray_auth() {
    echo "Read Keychain for cray password?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) 
              CRAYCLI_A=$(security find-generic-password -a "$USER" -s "craycli" -w)
              cray auth login --username $USER --password $CRAYCLI_A
              break;;
            No  )
              echo "cray auth login --username $USER"
              cray auth login --username $USER
              break;;
        esac
    done
}

function sat_check() {
  if ! command sat status &> /dev/null; then
    echo "sat CLI not found. Install sat?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) sat_install; break;;
            No  ) echo "sat CLI must be installed to continue"; exit;;
        esac
    done
  fi
}

function sat_install() {
  mkdir -p $SUPERINIT_DIR/cmds
  SAT_VENV_PATH="$SUPERINIT_DIR/cmds/sat_venv"
  $PYTHON -m venv $SAT_VENV_PATH
  . $SAT_VENV_PATH/bin/activate
  git clone --branch=release/$SAT_VERSION $SAT_SRC $SUPERINIT_DIR/cmds/sat
  git clone --branch=v$PRODUCT_CATALOG_VERSION $PRODUCT_CATALOG_SRC $SUPERINIT_DIR/cmds/cray-product-catalog
  echo $PRODUCT_CATALOG_VERSION > $SUPERINIT_DIR/cmds/cray-product-catalog/.version
  sed -i '' 's/cray-product-catalog.*/.\/cray-product-catalog/' $SUPERINIT_DIR/cmds/sat/requirements.lock.txt
  
  pushd $SUPERINIT_DIR/cmds > /dev/null
  $PIP install -r $SUPERINIT_DIR/cmds/sat/requirements.lock.txt
  $PIP install $SUPERINIT_DIR/cmds/sat
  deactivate
  popd > /dev/null
  sat_installed=true
}

function sat_init() {
  if [ $# -ne 2 ]; then
    echo "Must pass a system name and API_GW to sat_init"
    exit 1
  fi
  system=$1
  apigw=$2

  sed -i '' -E "s/^(host[[:blank:]]*=[[:blank:]]*).*/\1'$apigw'/" ~/.config/sat/sat.toml
  sed -i '' -E "s/^(username[[:blank:]]*=[[:blank:]]*).*/\1'$USER'/" ~/.config/sat/sat.toml
}

function add_cert() {
  if [ $# -ne 2 ]; then
    echo "Must pass a system name and API_GW to add_cert"
    exit 1
  fi
  system=$1
  apigw=$2

  # this could be better...
  TDIR=$(mktemp -d)
  pushd $TDIR > /dev/null

  openssl s_client -showcerts -verify 5 -connect $apigw:443 < /dev/null 2> /dev/null | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/{ if(/BEGIN CERTIFICATE/){a++}; out="cert"a".pem"; print >out}'

  if $PRINT_SAN; then
    openssl s_client -showcerts -verify 5 -connect `echo $apigw | sed 's/auth/opa-gpm/'`:443 < /dev/null 2> /dev/null  > $system-opa-gpm.cert
    openssl x509 -text -noout -in $system-opa-gpm.cert | grep DNS | sed 's/DNS://g' | tr -d '[:space:]' | sed 's/,/\n/g'; echo
  fi

  for cert in *.pem; do
    certname=$(openssl x509 -noout -subject -in $cert | sed 's/.*CN=//')
    # If the Cert is already in the keychain, return without adding it again
    if security find-certificate -c "$certname" &> /dev/null; then
      return
    fi
    if [[ "$certname" = $system* ]]; then 
      continue
    else
      cat "${cert}" >> $system.cert
    fi
  done

  # Add platform CA to Keychain and save a copy
  security add-trusted-cert -r trustAsRoot -k ~/Library/Keychains/login.keychain-db $system.cert
  cp $system.cert $SUPERINIT_DIR/$system/platform-ca-certs.crt

  popd > /dev/null
  rm $TDIR/*
  rmdir $TDIR
}

function scan_for_gw() {

  if [ $# -ne 1 ]; then
    echo "Must pass a system name to scan_for_gw"
    exit 1
  fi
  sys=$1


  for domain in $DOMAINS; do
    if host auth.cmn.$sys.$domain &> /dev/null; then
      echo "auth.cmn.$sys.$domain"
      return
    fi
  done

  echo "Could not find the api gateway for $sys at the following URLs:" >&2
  for domain in $DOMAINS; do
    echo "auth.cmn.$sys.$domain" >&2
  done
  exit 1

}

while getopts "hs:d:u" arg; do
  case $arg in
    h)
      usage
      ;;
    s)
      SYSTEM=$OPTARG
      ;;
    d)
      DOMAINS="$OPTARG"
      ;;
    u)
      PRINT_SAN=true
      ;;
  esac
done

# Check for installed commands:
# openssl security python3 pip

craycli_check
sat_check

if [ "$craycli_installed" = "true" ] || [ "$sat_installed" = "true" ]; then
  echo "Add 'export PATH=\"${SUPERINIT_DIR}/cmds/cray_venv/bin:${SUPERINIT_DIR}/cmds/sat_venv/bin:\${PATH}\"' to your shell profile to use sat and cray commands." 
  export PATH="${SUPERINIT_DIR}/cmds/cray_venv/bin:${SUPERINIT_DIR}/cmds/sat_venv/bin:${PATH}"
fi

if [ "$SYSTEM" = "" ]; then
  echo "Must supply -s <system>"
  usage
  exit 1
fi

# Set the active cray configuration
if cray config use $SYSTEM 2>&1 | egrep --silent "Unable to find configuration file"; then
  echo "Could not find craycli $SYSTEM configuration. Would you like to create one?"
  select yn in "Yes" "No"; do
    case $yn in
      Yes) 
        craycli_init $SYSTEM; 
        break
        ;;
      No) 
        echo "Available configurations are:"
        cray config list | jq -r '.configurations[] | .name'
        exit
        ;;
    esac
  done
fi

# Check that the system responds to a simple ping
craycli_ping_check

# Set the API Gateway from the active craycli config
API_GW=$(cray config get core.hostname | sed 's/https:\/\///g')

mkdir -p $SUPERINIT_DIR/$SYSTEM

echo $SYSTEM > $SUPERINIT_DIR/active_system
echo $API_GW > $SUPERINIT_DIR/active_api_gw
add_cert $SYSTEM $API_GW

craycli_auth_check
sat_init $SYSTEM $API_GW
