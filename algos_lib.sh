#!/bin/bash
# Shared reader for algorithms.conf, the single source of truth for every
# algorithm in the benchmark. Steps 2, 3, 4, 7 and 8 source this file so that an
# algorithm's name is written exactly once and cannot drift between steps.

ALGOS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALGOS_CONF="${ALGOS_CONF:-$ALGOS_LIB_DIR/algorithms.conf}"

if [ ! -f "$ALGOS_CONF" ]; then
    echo "ERROR: cannot find algorithms.conf at $ALGOS_CONF" >&2
    exit 1
fi

# algo_rows <CATEGORY>
# Prints one tab-separated "repo<TAB>id<TAB>output<TAB>input" line per
# algorithm of that category, honouring ONLY_ALGOS.
algo_rows() {
    awk -F'|' -v want_cat="$1" -v only=" ${ONLY_ALGOS:-} " '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        {
            for (i = 1; i <= NF; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i) }
            if ($1 != want_cat) next
            if (only != "  " && index(only, " " $3 " ") == 0) next
            print $2 "\t" $3 "\t" $4 "\t" $5
        }
    ' "$ALGOS_CONF"
}

# algo_ids
# Prints every algorithm id, ignoring ONLY_ALGOS.
algo_ids() {
    awk -F'|' '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        { gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3 }
    ' "$ALGOS_CONF"
}

# check_only_algos
# Fails early on a misspelled name in ONLY_ALGOS, instead of silently running
# nothing. This is the drift that used to bite: "superodom" vs "superOdom".
check_only_algos() {
    [ -n "${ONLY_ALGOS:-}" ] || return 0
    local known unknown=()
    known="$(algo_ids)"
    for a in $ONLY_ALGOS; do
        grep -qx -- "$a" <<< "$known" || unknown+=("$a")
    done
    if [ ${#unknown[@]} -gt 0 ]; then
        echo "ERROR: unknown algorithm name(s) in ONLY_ALGOS: ${unknown[*]}" >&2
        echo "Known names (see $ALGOS_CONF):" >&2
        echo "$known" | sort | paste -sd' ' - >&2
        exit 1
    fi
    echo "ONLY_ALGOS set — restricting to: $ONLY_ALGOS"
}

# image_tag <id> <CATEGORY>
# Docker forbids uppercase in image names, so the id is lowercased here. This
# is the only place where the name is allowed to differ from the id.
image_tag() {
    local id_lower
    id_lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$2" in
        ROS1)    echo "${id_lower}_noetic" ;;
        ROS2)    echo "${id_lower}_humble" ;;
        NON_ROS) echo "${id_lower}_standalone" ;;
    esac
}

# run_script <id> <CATEGORY>
# Name of the run script inside the algorithm's repository.
run_script() {
    case "$2" in
        ROS1)    echo "docker_session_run-ros1-$1.sh" ;;
        ROS2)    echo "docker_session_run-ros2-$1.sh" ;;
        NON_ROS) echo "docker_session_run-$1.sh" ;;
    esac
}

# Sensors a canonical bag can come from; see sensor_overrides.conf.
KNOWN_SENSORS="qt64 mid360"
SENSOR_OVERRIDES_CONF="${SENSOR_OVERRIDES_CONF:-$ALGOS_LIB_DIR/sensor_overrides.conf}"

# canonical_sensor <data_dir>
# Prints the dataset's sensor: CANONICAL_SENSOR, else the first word of
# <data_dir>/canonical_sensor, else qt64. Fails on an unknown value.
canonical_sensor() {
    local sensor="${CANONICAL_SENSOR:-}"
    if [ -z "$sensor" ] && [ -f "$1/canonical_sensor" ]; then
        sensor="$(awk 'NF { print $1; exit }' "$1/canonical_sensor")"
    fi
    sensor="${sensor:-qt64}"
    if ! grep -qw -- "$sensor" <<< "$KNOWN_SENSORS"; then
        echo "ERROR: unknown canonical sensor '$sensor' (known: $KNOWN_SENSORS)" >&2
        return 1
    fi
    echo "$sensor"
}

# sensor_env <id> <sensor>
# Prints the VAR=value settings of sensor_overrides.conf for that algorithm and
# sensor, one per line (nothing when the algorithm needs none).
sensor_env() {
    [ -f "$SENSOR_OVERRIDES_CONF" ] || return 0
    awk -F'|' -v id="$1" -v sensor="$2" '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        {
            for (i = 1; i <= NF; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i) }
            if ($1 != sensor || $2 != id) next
            n = split($3, kv, /[ \t]+/)
            for (i = 1; i <= n; i++) if (kv[i] != "") print kv[i]
        }
    ' "$SENSOR_OVERRIDES_CONF"
}
