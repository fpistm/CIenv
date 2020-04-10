#!/bin/bash -
#===============================================================================
#
#          FILE: configure.sh
#
#         USAGE: ./configure.sh
#
#   DESCRIPTION: Install or update the CI environnement
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Frederic Pillon (), frederic.pillon@st.com
#  ORGANIZATION: MCU Embedded Software
#     COPYRIGHT: Copyright (c) 2020, Frederic Pillon
#       CREATED: 04/10/2020 10:20:09 AM
#      REVISION:  ---
#===============================================================================

set -o nounset # Treat unset variables as an error

# env
bin_path="$HOME/bin"

cli="arduino-cli"
cli_path="$bin_path/$cli"

doCli=0
doLib=0

me=$(basename "$0")

###############################################################################
## Help function
usage() {
  echo "############################################################"
  echo "##"
  echo "## $me"
  echo "## [-a] [-b <board pattern>] [-i <.ino path>| [-f <sketch file list> | [-s <sketch pattern>]] [-v] "
  echo "##"
  echo "## Launch this script at the top of Arduino IDE directory."
  echo "##"
  echo "## Mandatory options:"
  echo "##"
  echo "## None"
  echo "##"
  echo "## Optionnal:"
  echo "##"
  echo "## -a: "
  echo "## -l: update all lib"
  echo "##"
  echo "############################################################"
  exit 0
}

install_cli() {
  # Install/update arduino-cli
  if [ ! -d "$bin_path" ]; then
    mkdir "$bin_path"
  elif [ -f "$cli_path" ]; then
    rm "$cli_path"
  fi
  curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | BINDIR="$bin_path" sh
  ret="${PIPESTATUS[0]}"
  if [ "$ret" -ne 0 ]; then
    echo "[$me] Could not retrieve arduino-cli. Abort."
    exit "$ret"
  fi
  if ! command -v $cli > /dev/null 2>&1; then
    echo "[$me] $cli not found."
    echo "Please ensure that $bin_path is in your PATH environment:"
    echo "Aborting!"
    exit 1
  fi

  arduino-cli config init --additional-urls https://github.com/stm32duino/BoardManagerFiles/raw/master/STM32/package_stm_index.json
}

# parse command line arguments
# options may be followed by one colon to indicate they have a required arg
if ! options=$(getopt -o ahl -- "$@"); then
  echo "Terminating..." >&2
  exit 1
fi

eval set -- "$options"

while true; do
  case "$1" in
    -a)
      echo "Install and configure all"
      doCli=1
      doLibs=1
      shift
      ;;
    -h | -\?)
      usage
      shift
      ;;
    -l)
      echo "Update all libraries"
      doLibs=1
      shift
      ;;
      #    -s) echo "Sketch pattern to build: $2"
      #        sketch_pattern=$2
      #        shift 2;;
    --)
      shift
      break
      ;;
    *) break ;;
  esac
done
