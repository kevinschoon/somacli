#!/bin/bash
baseurl="http://somafm.com"
xdgconfighome="${XDG_CONFIG_HOME:="$HOME/.config"}"
xdgruntimedir="${XDG_RUNTIME_DIR:="/run/user/$UID"}"
xdgdatahome="${XDG_DATA_HOME:="$HOME/.local/share"}"
stationsfile_src="https://raw.githubusercontent.com/bcicen/somacli/master/stations"
show_descriptions=0
required="mplayer curl"

datadir="${xdgdatahome}/somacli"
configbase="${xdgconfighome}/somacli"
stationsfile="${configbase}/stations.txt"
mplayerlog="${datadir}/somacli.log"
mplayerpipe="${xdgruntimedir}/somacli.fifo"

[[ ! -e $mplayerpipe ]] && mkfifo $mplayerpipe

function init_config() {
  for cmd in $required; do
    (type $cmd &> /dev/null) || {
      echo "missing required command: $cmd"
      exit 1
    }
  done
  [ ! -d "$configbase" ] && {
    mkdir -p "$configbase"
  }
  [ ! -d "$datadir" ] && {
    mkdir -p "$datadir"
  }
  [ ! -f $stationsfile ] && {
    echo "retrieving stations file..."
    curl -Lso $stationsfile $stationsfile_src
  }
}

function echo_green() { echo -e "\033[0;32m$@\033[0m"; }

function echo_bold() {
  echo_opts="-e"
  [[ $1 == "-n" ]] && {
    shift 1
    echo_opts+=" -n"
  }
  echo $echo_opts "\033[1m$@\033[0m"
}

function read_stations() {
  playlists=()
  genres=()
  stationnames=()
  descriptions=()

  while IFS="|" read name genre playlist desc; do
    stationnames+=("$name")
    genres+=("$genre")
    playlists+=("$playlist")
    descriptions+=("$desc")
  done < $1

  stationcount=$(( ${#stationnames[@]} - 1 ))
}

function select_station() {
  for i in $(seq 0 $stationcount); do
    [[ $i -le 9 ]] && echo_bold -n " $i) ${stationnames[$i]}" # left-pad single digits
    [[ $i -ge 10 ]] && echo_bold -n "$i) ${stationnames[$i]}"
    echo " ${genres[$i]}"
    ((show_descriptions % 2)) && echo "    ${descriptions[$i]}"
  done
  echo_bold "d) toggle descriptions"

  while :; do
    read -p 'Select station: ' selection
    [[ $selection == "d" ]] && {
      let show_descriptions++
      select_station
    }
    # validate input
    [[ $selection =~ ^[[:digit:]]+$ ]] && (($selection <= $stationcount)) && break
    echo "invalid selection"
  done
}

function fetch_and_play () {
  playlist=${playlists[$selection]}
  filepath="${datadir}/${playlist}"

  [[ ! -f "$filepath" ]] && {
    echo_bold "Retrieving playlist..."
    wget -q ${baseurl}/${playlist} -O $filepath
  }

  echo_bold "Playing ${stationnames[$selection]}"
  mplayer -slave \
          -quiet \
          -input file=$mplayerpipe \
          -playlist $filepath \
          &> $mplayerlog &
  mplayerpid=$!
  tail_mplayer &
}

function tail_mplayer() {
  tail -n+0 --pid=$mplayerpid -f $mplayerlog 2> /dev/null | while read line; do
    [[ "$line" == "ICY Info:"* ]] && {
      title=$(echo $line | cut -f2- -d\' | cut -f1 -d\;)
      echo "$(echo_green now playing): ${title%\'}"
    }
    [[ "$line" == "Name "* ]] && {
      name=$(echo $line | cut -f2- -d\:)
      echo "$(echo_green streaming): $name"
    }
  done
}

# stop mplayer, if running
function stop_player() {
  (kill -0 $mplayerpid 2> /dev/null) && {
    echo quit > $mplayerpipe
    wait $mplayerpid
  }
}

function shutdown() {
  stop_player
  rm $mplayerpipe
  exit 0
}

init_config
read_stations $stationsfile

while :; do
  select_station
  fetch_and_play
  isplaying=1

  echo "$(echo_bold -n C)hange station $(echo_bold -n Q)uit"
  while ((isplaying)); do
    read -sn1 activeopt
    case $activeopt in
      [cC])
        stop_player
        isplaying=0
        ;;
      [qQ])
        shutdown
        ;;
    esac
  done
done
