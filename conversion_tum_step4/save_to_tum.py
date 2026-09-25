"""Register every algorithm session against the ground truth and export TUM.

The list of algorithms is not kept here: it is read from algorithms.conf, the
single source of truth shared by steps 2, 3 and 4. run_tum_step4.sh mounts
that file into the container at /workspace/algorithms.conf.
"""

import os
import sys

import multi_session_registration_py

CONF_PATH = os.environ.get("ALGOS_CONF", "/workspace/algorithms.conf")

# The ground truth is not an algorithm, so it is named here rather than in
# algorithms.conf, and it must stay first in the list.
GROUND_TRUTH = "/data/ground_truth/HDMappingGroundTruth/lio_result_0/session.mjs"


def read_algorithms(path):
    """Yield (id, output_folder) for each algorithm line of algorithms.conf."""
    if not os.path.isfile(path):
        sys.exit(f"ERROR: cannot find algorithms.conf at {path}")

    with open(path) as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            fields = [f.strip() for f in line.split("|")]
            if len(fields) < 4:
                continue
            _category, _repo, algo_id, output = fields[:4]
            yield algo_id, output


def build_sessions(path, only_algos):
    sessions = [GROUND_TRUTH]
    for algo_id, output in read_algorithms(path):
        # An empty output column means the algorithm has no automated result
        # (e.g. HDMapping_LIO, which is a manual procedure).
        if not output:
            continue
        if only_algos and algo_id not in only_algos:
            continue
        sessions.append(f"/data/{algo_id}/output_hdmapping-{output}/session.json")
    return sessions


only_algos = os.environ.get("ONLY_ALGOS", "").split()
sessions = build_sessions(CONF_PATH, only_algos)

if only_algos:
    print("ONLY_ALGOS set — registering:")
else:
    print(f"Registering {len(sessions) - 1} algorithm sessions:")
for session in sessions:
    print(f"  {session}")

result = multi_session_registration_py.run(sessions)

print(result)
