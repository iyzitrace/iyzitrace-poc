#!/bin/sh
# Pulls the manifest of every image in images.txt (no download), to find missing access before the
# install. Run it from a machine with the same egress as the cluster, e.g. a debug pod:
#   oc debug node/<node> -- chroot /host sh -c 'podman pull --quiet <image>'   # per image, if needed
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
fail=0
for img in $(grep -v '^#' "$HERE/images.txt" | grep -v '^$'); do
  if skopeo inspect --raw "docker://$img" >/dev/null 2>&1 || podman manifest inspect "$img" >/dev/null 2>&1 || docker manifest inspect "$img" >/dev/null 2>&1; then
    echo "ok    $img"
  else
    echo "FAIL  $img"; fail=1
  fi
done
exit $fail
