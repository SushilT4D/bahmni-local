#!/usr/bin/env bash
# What the Initializer module may load at a clinic. bash 3.2 compatible, and
# needs nothing from lib.sh. The verdict runs on every path that starts OpenMRS
# on a config tree or a domain list it has not run with yet: task 080 (before
# the stack starts), scripts/extract-ui-config.sh (on a new tree, before it
# replaces the current one) and scripts/recreate-openmrs.sh.
#
# At every start OpenMRS copies the config tree's masterdata/configuration into
# its configuration directory, and the Initializer loads each domain folder it
# finds there. Almost every domain writes master data the hub owns and sends
# down (forms, concepts, drugs, locations, roles, programs, the address
# hierarchy) or runs config changesets that do. Loaded at a clinic, it would
# create or renumber those rows locally, so the clinic's rows would no longer
# be the hub's. Forms make it concrete: the Initializer creates any form it does
# not know as a new version numbered by this node, while saved observations
# name their form by name and version.
#
# docker-compose.yml passes the setting to OpenMRS as a Java system property:
#   -Dinitializer.domains=${OPENMRS_INITIALIZER_DOMAINS:-<INITIALIZER_DOMAINS_DEFAULT>}
# Comma-separated, no spaces. A leading ! makes it an exclusion list (every
# other domain loads); otherwise it is an inclusion list (only those load). The
# module only warns about a name it does not know, which leaves that domain
# loading, so initializer_domains_verdict refuses unknown names here.
#
# The default excludes every domain the config tree carries a folder for
# except globalproperties and idgen, which write this node's own settings and
# identifier sources. An exclusion list leaves every unnamed domain on, so a
# config release that adds a folder for one (htmlforms, ampathforms and
# metadatasharing also write forms) would load it silently: the verdict
# therefore refuses any folder holding a file for a domain that would load,
# other than the kept two, and any folder holding a file whose name is not a
# domain known here (a newer module may have it). The inclusion list
# globalproperties,idgen closes the first by construction and passes the same
# check.

# The module's 52 domains (its Domain enum, lower case, underscores removed).
INITIALIZER_DOMAINS_KNOWN="addresshierarchy ampathforms ampathformstranslations appointmentservicedefinitions appointmentservicetypes appointmentspecialities attributetypes autogenerationoptions bahmniforms billableservices cashpoints cohortattributetypes cohorttypes conceptclasses conceptreferencerange concepts conceptsets conceptsources datafiltermappings dispositions drugs encounterroles encountertypes fhirconceptsources fhirpatientidentifiersystems globalproperties htmlforms idgen jsonkeyvalues liquibase locations locationtagmaps locationtags metadatasetmembers metadatasets metadatasharing metadatatermmappings ocl orderfrequencies ordertypes patientidentifiertypes paymentmodes personattributetypes privileges programs programworkflows programworkflowstates providerroles queues relationshiptypes roles visittypes"
# The domains a clinic may load from the config tree.
INITIALIZER_DOMAINS_KEPT="globalproperties idgen"
# docker-compose.yml's default; tests/test_initializer.sh holds the two equal.
INITIALIZER_DOMAINS_DEFAULT='!bahmniforms,roles,privileges,concepts,conceptsets,conceptclasses,conceptsources,drugs,ocl,locations,addresshierarchy,programs,programworkflows,programworkflowstates,attributetypes,visittypes,ordertypes,personattributetypes,relationshiptypes,appointmentspecialities,appointmentservicedefinitions,liquibase'

_in_words(){ case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

# initializer_domains_verdict VALUE CONFIG_DIR : VALUE is what
# -Dinitializer.domains will carry; CONFIG_DIR is the config tree OpenMRS
# mounts (BAHMNI_CONFIG_DIR). Prints "ok ..." and returns 0, or prints the
# refusal and returns 1.
initializer_domains_verdict(){
  local value="$1" cfg="$2" mode=inclusion list names="" n unknown="" loaded="" d found="" loads=""
  local base="${cfg}/masterdata/configuration"
  [ -n "$value" ] || { printf 'the Initializer domain list is empty; set OPENMRS_INITIALIZER_DOMAINS or leave it unset for the default\n'; return 1; }
  case "$value" in *[[:space:]]*) printf 'OPENMRS_INITIALIZER_DOMAINS "%s" contains a space; the module reads a comma-separated list with no spaces\n' "$value"; return 1 ;; esac
  case "$value" in *[!A-Za-z0-9_.,!-]*) printf 'OPENMRS_INITIALIZER_DOMAINS "%s" contains a character no domain name has\n' "$value"; return 1 ;; esac
  list="$value"
  case "$list" in '!'*) mode=exclusion; list="${list#!}" ;; esac
  case ",${list}," in *,,*) printf 'OPENMRS_INITIALIZER_DOMAINS "%s" has an empty name (a doubled, leading or trailing comma)\n' "$value"; return 1 ;; esac
  # split on commas only; the character check above leaves nothing to glob
  local oldifs="$IFS"; IFS=,
  for n in $list; do
    names="${names} ${n}"
    _in_words "$n" "$INITIALIZER_DOMAINS_KNOWN" || unknown="${unknown} ${n}"
  done
  IFS="$oldifs"
  [ -z "$unknown" ] || { printf 'OPENMRS_INITIALIZER_DOMAINS names domains the Initializer does not have:%s. The module would only warn and leave them loading. Known domains: %s\n' "$unknown" "$INITIALIZER_DOMAINS_KNOWN"; return 1; }
  for d in $INITIALIZER_DOMAINS_KNOWN; do
    if [ "$mode" = inclusion ]; then _in_words "$d" "$names" && loaded="${loaded} ${d}"
    else _in_words "$d" "$names" || loaded="${loaded} ${d}"; fi
  done
  [ -d "$base" ] || { printf 'no config tree at %s; task 045 extracts it from BAHMNI_CONFIG_IMAGE\n' "$base"; return 1; }
  # Every folder the tree carries is judged, not only the names known here: a
  # newer module can have a domain this list lacks, and an exclusion list would
  # leave it loading.
  local strange="" p
  for p in "${base}"/*; do
    [ -d "$p" ] || continue
    d="${p##*/}"
    [ -n "$(find "$p" -type f 2>/dev/null | head -1)" ] || continue   # an empty folder loads nothing
    if ! _in_words "$d" "$INITIALIZER_DOMAINS_KNOWN"; then strange="${strange} ${d}"; continue; fi
    _in_words "$d" "$loaded" || continue
    if _in_words "$d" "$INITIALIZER_DOMAINS_KEPT"; then loads="${loads} ${d}"; else found="${found} ${d}"; fi
  done
  [ -z "$strange" ] || { printf 'the config tree carries a folder for%s, which is not one of the Initializer domains known here. A newer Initializer may load it at this clinic, writing rows the hub owns. Remove the folder from the tree OpenMRS mounts, or add the domain to this list (and to the exclusion) once it is known\n' "$strange"; return 1; }
  [ -z "$found" ] || { printf 'the config tree carries a folder for%s, and with -Dinitializer.domains=%s the Initializer would load it at this clinic, writing rows the hub owns. Exclude it (add it after the !) or use the inclusion list globalproperties,idgen\n' "$found" "$value"; return 1; }
  printf 'ok %s list; from the config tree it loads:%s\n' "$mode" "${loads:- nothing}"
}
