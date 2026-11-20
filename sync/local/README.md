# sync/local — the clinic's MirrorMaker template

`mirrormaker-config/mm2.properties.template` holds the MirrorMaker 2 settings
for the copy between a clinic and the hub. `clinic/scripts/setup-mirrormaker.sh`
renders it to `mm2.properties` (git-ignored, generated: do not edit), adding the
topics from the table lists in `../tables/`.

The table lists themselves — what a clinic sends up and what clinics pull from the cloud server — are in `../tables/`, one file per database. See `../tables/README.md`.
