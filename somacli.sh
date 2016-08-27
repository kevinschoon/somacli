#!/bin/bash
tmpdir="/tmp"
baseurl="http://somafm.com"
stationsfile="${SOMACLI_HOME:=.}/stations.txt"
show_descriptions=0

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
    [[ $i -le 9 ]] && echo_bold -n " $i) ${stationnames[$i]}"
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
  filepath="${tmpdir}/${playlist}"

  [[ ! -f "$filepath" ]] && {
    echo_bold "Retrieving playlist..."
    wget -q ${baseurl}/${playlist} -O $filepath
  }

  echo_bold "Playing ${stationnames[$selection]}"
  mplayer -really-quiet -playlist $filepath < /dev/null 2> /dev/null &
  mplayerpid=$!
}

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
        kill $mplayerpid
        isplaying=0
        ;;
      [qQ])
        kill $mplayerpid
        exit 0
        ;;
    esac
  done
done
