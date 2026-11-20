#!/usr/bin/env bash
# Checks what the OpenMRS Initializer may load at a clinic, so it never rewrites data the hub owns.

INITIALIZER_DOMAINS_KNOWN="addresshierarchy ampathforms ampathformstranslations appointmentservicedefinitions appointmentservicetypes appointmentspecialities attributetypes autogenerationoptions bahmniforms billableservices cashpoints cohortattributetypes cohorttypes conceptclasses conceptreferencerange concepts conceptsets conceptsources datafiltermappings dispositions drugs encounterroles encountertypes fhirconceptsources fhirpatientidentifiersystems globalproperties htmlforms idgen jsonkeyvalues liquibase locations locationtagmaps locationtags metadatasetmembers metadatasets metadatasharing metadatatermmappings ocl orderfrequencies ordertypes patientidentifiertypes paymentmodes personattributetypes privileges programs programworkflows programworkflowstates providerroles queues relationshiptypes roles visittypes"

INITIALIZER_DOMAINS_KEPT="globalproperties idgen"

INITIALIZER_DOMAINS_DEFAULT='globalproperties,idgen'

_in_words(){ case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

initializer_domains_verdict(){
  local value="$1" cfg="$2" mode=inclusion list names="" n unknown="" loaded="" d found="" loads=""
  local base="${cfg}/masterdata/configuration"
  [ -n "$value" ] || { printf 'the Initializer domain list is empty; set OPENMRS_INITIALIZER_DOMAINS or leave it unset for the default\n'; return 1; }
  case "$value" in *[[:space:]]*) printf 'OPENMRS_INITIALIZER_DOMAINS "%s" contains a space; the module reads a comma-separated list with no spaces\n' "$value"; return 1 ;; esac
  case "$value" in *[!A-Za-z0-9_.,!-]*) printf 'OPENMRS_INITIALIZER_DOMAINS "%s" contains a character no domain name has\n' "$value"; return 1 ;; esac
  list="$value"
  case "$list" in '!'*) mode=exclusion; list="${list#!}" ;; esac
  case ",${list}," in *,,*) printf 'OPENMRS_INITIALIZER_DOMAINS "%s" has an empty name (a doubled, leading or trailing comma)\n' "$value"; return 1 ;; esac

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
