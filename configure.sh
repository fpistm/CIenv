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
script_path="$(dirname "$(realpath "$0")")"
bin_path="$HOME/bin"
lib_repo_path="$HOME/repo/libraries"
sketchbook_path="$HOME/Arduino"
arduino_lib_path="$HOME/Arduino/libraries"

excludeListFile="$script_path/excludeList.txt"
repoListFile="$script_path/listOfRepo.txt"
libListFile="$script_path/librariesList.txt"

gh_owner="stm32duino"
gh_stm32_json="https://github.com/stm32duino/BoardManagerFiles/raw/dev/package_stmicroelectronics_index.json"

gh_arduino_cli_release="https://api.github.com/repos/arduino/arduino-cli/releases/latest"
gh_arduino_cli="https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh"
arduino_cli="arduino-cli"
arduino_cli_path="$bin_path/$arduino_cli"

gh_cli="gh"

IDE_version="1.8.16"
IDE_name="arduino-$IDE_version"
IDE_path="$HOME/IDE"
IDE_version_path="$IDE_path/$IDE_name"
IDE_example_path="$IDE_version_path/examples"
IDE_archive="arduino-$IDE_version-linux64.tar.xz"
IDE_url="http://downloads.arduino.cc/$IDE_archive"

doCli=0

me=$(basename "$0")

###############################################################################
## Help function
usage() {
  echo "############################################################"
  echo "##"
  echo "## $me"
  echo "## [-a] [-u]"
  echo "##"
  echo "## Launch this script at the top of Arduino IDE directory."
  echo "##"
  echo "## Mandatory options:"
  echo "##"
  echo "## None"
  echo "##"
  echo "## Optionnal:"
  echo "##"
  echo "## -a: install all requirements and configure all environnement."
  echo "## -u: update the environnement"
  echo "##"
  echo "############################################################"
  exit 0
}

installCli() {
  echo "Install/update $arduino_cli..."
  if [ ! -d "$bin_path" ]; then
    mkdir -p "$bin_path"
  elif [ -f "$arduino_cli_path" ]; then
    # Check the installed version
    current_version=$($arduino_cli version | cut -d ' ' -f3)
    latest_version=$(curl -s "$gh_arduino_cli_release" | jq -r .tag_name)
    if [ "$latest_version" != "null" ] && [ "$current_version" == "$latest_version" ]; then
      echo "$arduino_cli already up to date"
      echo "done"
      return
    fi
    rm "$arduino_cli_path"
  fi
  curl -fsSL "$gh_arduino_cli" | BINDIR="$bin_path" sh
  ret="${PIPESTATUS[0]}"
  if [ "$ret" -ne 0 ]; then
    echo "[$me] Could not retrieve $arduino_cli. Abort."
    exit "$ret"
  fi
  if ! command -v $arduino_cli >/dev/null 2>&1; then
    echo "[$me] $arduino_cli not found."
    echo "Please ensure that $bin_path is in your PATH environment:"
    echo "Aborting!"
    exit 1
  fi
  # Reference the STM32 core
  if ! $arduino_cli config init --additional-urls "$gh_stm32_json" >/dev/null 2>&1; then
    if ! $arduino_cli config dump | grep "$gh_stm32_json" >/dev/null 2>&1; then
      $arduino_cli config add board_manager.additional_urls "$gh_stm32_json"
    fi
  fi

  $arduino_cli core update-index
  echo "done"
}

installIDE() {
  echo "Install/update Arduino IDE..."
  if [ -d "$IDE_path" ]; then
    # Check the installed version
    current_version=$(basename "$(find "$IDE_path" -maxdepth 1 ! -path "$IDE_path" -type d)" | cut -d'-' -f2)
    if [ "$current_version" != "" ] && [ "$IDE_version" == "$current_version" ]; then
      echo "Arduino IDE already up to date to version $IDE_version"
      echo "done"
      return
    else
      echo "Update from version $current_version to $IDE_version"
    fi
  else
    current_version=""
  fi
  mkdir -p "$IDE_version_path"

  if [ ! -f "$IDE_archive" ]; then
    wget "$IDE_url" >/dev/null 2>&1
    ret=$?
    if [ "$ret" -ne 0 ]; then
      echo "[$me] Could not download $IDE_name."
      echo "Aborting!"
      rm -fr "${IDE_version_path:?}"
      exit "$ret"
    fi
  fi
  tar xf "$IDE_archive" --strip-components=1 -C "$IDE_version_path"
  ret=$?
  if [ "$ret" -ne 0 ]; then
    echo "[$me] $IDE_name could not be extracted."
    echo "Aborting!"
    exit "$ret"
  fi

  # Handle link in Arduino sketchbook
  if [ ! -d "$sketchbook_path" ]; then
    mkdir -p "$sketchbook_path"
  fi
  mapfile -t examples_list < <(find "$IDE_example_path" -maxdepth 1 ! -path "$IDE_example_path" -type d | sort)

  for example_path in "${examples_list[@]}"; do
    ln_name=$(basename "$example_path")
    if [ -L "$sketchbook_path/$ln_name" ]; then
      rm "$sketchbook_path/$ln_name"
    elif [ -e "$sketchbook_path/$ln_name" ]; then
      rm -fr "${sketchbook_path:?}/${ln_name:?}"
    fi
    ln -s "$example_path" "$sketchbook_path/$ln_name"
  done

  # Clean up
  rm "$IDE_archive"
  if [ ! -z "$current_version" ]; then
    rm -fr "${IDE_path:?}/arduino-${current_version:?}"
  fi
  echo "done"
}

installLib() {
  echo "Install/update Arduino libraries..."
  if [ ! -d "$arduino_lib_path" ]; then
    mkdir -p "$arduino_lib_path"
  fi

  if [ ! -f "$libListFile" ]; then
    echo "No library to install"
    return
  fi

  readarray -t lib_list <"$libListFile"

  if [ ${#lib_list[@]} -eq 0 ]; then
    echo "No library to install"
    return
  else
    echo "Number of libraries found: ${#lib_list[@]}"
  fi
  $arduino_cli lib update-index

  for lib_name in "${lib_list[@]}"; do
    if [[ "$lib_name" == *"http"* ]]; then
      lib_url="$(cut -d' ' -f2 <<<"$lib_name")"
      lib_name="$(cut -d' ' -f1 <<<"$lib_name")"
      lib_archive=$(basename "$lib_url")

      if [ -f "$lib_archive" ]; then
        rm "$lib_archive"
      fi
      wget "$lib_url" >/dev/null 2>&1
      ret=$?
      if [ "$ret" -ne 0 ]; then
        echo "Could not download $lib_name."
        continue
      fi
      if [ -d "$arduino_lib_path/$lib_name" ]; then
        rm -fr "${arduino_lib_path:?}/${lib_name:?}"
      fi

      tmpdir=$(mktemp -d -p /tmp -t "$lib_name.XXXX")
      unzip -qq -d "$tmpdir" "$lib_archive"
      # Check number of files in the tmp dir
      if [ "$(find "$tmpdir" -maxdepth 1 ! -path "$tmpdir" -type d | wc -l)" -eq 1 ]; then
        # If there's only 1 file in the tmp
        mv "$tmpdir"/* "$arduino_lib_path/$lib_name"
        rmdir "$tmpdir"
      else
        # If more than 1 file
        mv "$tmpdir" "$arduino_lib_path/$lib_name"
      fi
      rm "$lib_archive"
    else
      echo "lib name is $lib_name"
      if [ -d "${arduino_lib_path:?}/${lib_name:?}" ]; then
        $arduino_cli lib upgrade "$lib_name"
      else
        $arduino_cli lib install "$lib_name"
      fi
    fi
  done
  echo "done"
}

updateCore() {
  echo "Install/update the STM32 core.."
  $arduino_cli core update-index
  if ! $arduino_cli core list | grep "stm32" >/dev/null 2>&1; then
    $arduino_cli core install STMicroelectronics:stm32
  else
    $arduino_cli core upgrade STMicroelectronics:stm32
  fi
  echo "done"
}

updateSTM32Lib() {
  # Get list of repo
  if [ ! -f "$excludeListFile" ]; then
    $gh_cli repo list "$gh_owner" -L 200 --no-archived --json url | jq '.[]|.url' | sed -e "s/\"//g" >"$repoListFile"
  else
    $gh_cli repo list "$gh_owner" -L 200 --no-archived --json url | jq '.[]|.url' | grep -v -f "$excludeListFile" | sed -e "s/\"//g" >"$repoListFile"
  fi
  ret="${PIPESTATUS[0]}"
  if [ "$ret" -ne 0 ]; then
    echo "[$0] Could not retrieve STM32duino repository list. Abort."
    exit "$ret"
  fi
  readarray -t git_list <"$repoListFile"

  if [ ${#git_list[@]} -eq 0 ]; then
    echo "[$0] No library found. Abort."
    exit 1
  else
    echo "Number of STM32 libraries found: ${#git_list[@]}"
  fi

  if [ ! -d "$lib_repo_path" ]; then
    mkdir -p "$lib_repo_path"
  fi

  for git_repo in "${git_list[@]}"; do
    git_name=$(basename "$git_repo")
    git_dir=$lib_repo_path/$git_name
    if [ -z "$git_dir" ]; then
      continue
    fi
    if [ -d "$git_dir" ] && [ ! -d "$git_dir/.git" ]; then
      rm -fr "${git_dir:?}"
    fi
    if [ -d "$git_dir/.git" ]; then
      # Check branch name master or main
      bname=$(git -C "$git_dir" branch -r | grep -v "\->" | awk -F"/" '{print $2}')
      if [ -z "$bname" ]; then
        echo "Could not find branch name for $git_name"
        continue
      fi
      rname=$(git -C "$git_dir" remote -v | grep stm32duino | awk '{print $1}' | sort -u)
      if [ -n "$rname" ]; then
        echo "Updating remote $rname of $git_name..."
        # Check if the repository is cleaned
        # First is there any uncommited change(s) or untracked file(s)?
        if output=$(git -C "$git_dir" status --porcelain) && [ -z "$output" ]; then
          # Is there any local commit?
          if output=$(git -C "$git_dir" log "${rname}/${bname}..${bname}") && [ -z "$output" ]; then
            # Fetch repo
            if output=$(git -C "$git_dir" fetch "$rname" 2>&1) && [ ! -z "$output" ]; then
              git -C "$git_dir" checkout -B "${bname}" "${rname}/${bname}"
              echo "done"
            else
              echo "Nothing to update"
            fi
          else
            echo "Not updated --> local commit(s) not pushed"
            echo "$output"
          fi
        else
          echo "Not updated --> uncommitted change(s) or untracked file(s)"
          echo "$output"
        fi
      else
        echo "Not updated --> no remote"
      fi
    else
      git -C "$lib_repo_path" clone "$git_repo"
    fi

    # Handle link in Arduino libraries path
    if [ -f "$git_dir/library.properties" ]; then
      ln_name=$(grep "name=" "$git_dir/library.properties" | tr -d '\r' | sed -e "s/name=//g" -e "s/ /_/g")
      if [ -L "$arduino_lib_path/$ln_name" ]; then
        rm "$arduino_lib_path/$ln_name"
      elif [ -e "$arduino_lib_path/$ln_name" ]; then
        rm -fr "${arduino_lib_path:?}/${ln_name:?}"
      fi
      ln -s "$git_dir" "$arduino_lib_path/$ln_name"
    else
      echo "$git_dir is not a library, add it to $excludeListFile"
    fi

  done
}

# parse command line arguments
# options may be followed by one colon to indicate they have a required arg
if ! options=$(getopt -o ahu -- "$@"); then
  echo "Terminating..." >&2
  exit 1
fi

eval set -- "$options"

while true; do
  case "$1" in
    -a)
      echo "Install and configure all"
      doCli=1
      shift
      ;;
    -h | -\?)
      usage
      shift
      ;;
    -u)
      echo "Update all"
      shift
      ;;
    --)
      shift
      break
      ;;
    *) break ;;
  esac
done

if [ "$doCli" -eq 1 ]; then
  installCli
  installLib
  installIDE
fi
updateCore
updateSTM32Lib
