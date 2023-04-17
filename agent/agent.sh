#!/usr/bin/env bash
set -u

# Functions
HEADER="VirtualDSM Agent:"

function checkNMI {

  local nmi
  nmi=$(cat /proc/interrupts | grep NMI | sed 's/[^1-9]*//g')

  if [ "$nmi" != "" ]; then

    echo "$HEADER Received shutdown request through NMI.."

    /usr/syno/sbin/synoshutdown -s > /dev/null
    exit

  fi

}

finish() {

  echo "$HEADER Shutting down.."
  exit

}

trap finish SIGINT SIGTERM

ts=$(date +%s%N)
checkNMI

VERSION="4"
echo "$HEADER starting v$VERSION.."

# Install packages 

first_run=false

for filename in /usr/local/packages/*.spk; do
  if [ -f "$filename" ]; then
    first_run=true
  fi
done

if [ "$first_run" = true ]; then
  for filename in /usr/local/packages/*.spk; do
    if [ -f "$filename" ]; then

      BASE=$(basename "$filename" .spk)
      BASE="${BASE%%-*}"

      echo "$HEADER Installing package ${BASE}.."

      /usr/syno/bin/synopkg install "$filename" > /dev/null
      /usr/syno/bin/synopkg start "$BASE" > /dev/null &

      rm "$filename"

    fi
  done
else

  TMP="/tmp/agent.sh"
  rm -f "${TMP}"

  # Auto update the agent

  if curl -s -f -k -m 5 -o "${TMP}" https://raw.githubusercontent.com/kroese/virtual-dsm/master/agent/agent.sh; then
    if [ -f "${TMP}" ]; then
      line=$(head -1 "${TMP}")
      if [ "$line" == "#!/usr/bin/env bash" ]; then
         SCRIPT=$(readlink -f ${BASH_SOURCE[0]})
         if ! cmp --silent -- "${TMP}" "${SCRIPT}"; then
           mv -f "${TMP}" "${SCRIPT}"
           chmod +x "${SCRIPT}"
           echo "$HEADER succesfully installed update."
         else
           echo "$HEADER Update not needed."
         fi
      else
         echo "$HEADER update error, invalid header: $line"
      fi
    else
      echo "$HEADER update error, file not found.."
    fi
  else
    echo "$HEADER update error, curl error: $?"
  fi

fi

elapsed=$((($(date +%s%N) - $ts)/1000000))
difference=$(((5000-elapsed)*0.001))
      
if (( difference > 0 )); then
  echo "Elapsed time: $elapsed, difference: $difference"
  sleep $difference
fi

# Display message in docker log output

echo "-------------------------------------------"
echo " You can now login to DSM at port 5000     "
echo "-------------------------------------------"

# Wait for NMI interrupt as a shutdown signal

while true; do

  checkNMI
  sleep 2

done
