#!/bin/bash
# Parse an ics file
usage()
{
  echo
  echo -e "\t*** $1 ***"
  echo -e "\tParse Google Calendar Events"
  echo -e "\tUsage:\t $(basename $0)  /path/to/file.ics  [ /another/file.ics [...] ] "
  echo -e "\t   eg:\t $(basename $0)  ~ja/etc/var/google/AE.isc"
  echo
  exit $2
}

groom_helper() 
{
  YYYYMMDD="${1:0:4}-${1:4:2}-${1:6:2}"
  HH=${1:9:2}
  MM=${1:11:2}
  SS=${1:13:2}
  echo "$YYYYMMDD, $HH:$MM:$SS"
}
groom_date_time_value_v2()
{
  case $1 in
  TZID*) groom_helper "${1#*:}";;
  ????????T??????Z) groom_helper "${1}";;
  VALUE=DATE*)    TEMP=${1#*:};echo "${TEMP:0:4}-${TEMP:4:2}-${TEMP:6:2}";;
  *);;
esac
}
spit_out_existing_record_v2()
{	# Use a For loop and mangle literals.
  for X in DTSTART DTEND CREATED DESC SUMMARY
  do
    x=$(echo $X |tr [A-Z] [a-z])		# replace upper case with lower case
    Y="$(echo $x |cut -b1 |tr [a-z] [A-Z])${x:1}"	# upper case the first letter.

    eval TMP=\${$X[@]}			# get value of each var.
    [ -n "${TMP}" ]	&& printf "%10s: %s \n" "$Y" "${TMP}"
  done
  echo
}

curtime=$(date +%s)

spit_out_existing_record_iffuture()
{	# Using printf to create a table.
  DTSTART="$(groom_date_time_value_v2 ${DTSTART})"
  unixds=$(date +%s --date="${DTSTART/,/}")
  [[ $unixds -gt $curtime ]] &&
  printf "%13s  %-30s %-70s %-22s %-22s \n" "$unixds" "$SUMMARY" "$DESC" "$DTSTART" "$(groom_date_time_value_v2 ${DTEND}) $UUID"
} 

spit_out_existing_record_v7()
{	# Using printf to create a table.
  DTSTART="$(groom_date_time_value_v2 ${DTSTART})"
  unixds=$(date +%s --date="${DTSTART/,/}")
  printf "%13s  %-30s %-70s %-22s %-22s \n" "$unixds" "$SUMMARY" "$DESC" "$DTSTART" "$(groom_date_time_value_v2 ${DTEND}) $UUID"
}
reset_vars()
{
  DTSTART=''; DTEND=''; DESC=''; SUMMARY=''; UUID=;
}

parse_ics_file()
{
  while read L
  do
    # Ignore some fields.
    # echo "$L" |egrep -q '^DTSTAMP|^UID|^ATTENDEE|^CLASS|^LAST-MODIFIED|^LOCATION|^SEQUENCE|^STATUS|^TRANSP' && continue
    # echo "$L" |egrep -q '^ ' && continue

    # Capture field values for current record.
    case $L in
    END:VEVENT) spit_out_existing_record_iffuture;; #show last event
    BEGIN:VEVENT) reset_vars;; #close record
    DTSTART*) DTSTART=${L:8};;
    DTEND*) DTEND=${L:6};;
    UID*) UUID=${L:4};;
    # echo "$L" |egrep -q '^CREATED'	&& CREATED=$(echo "$L" |cut -b9-)
    DESCRIPTION*) DESC=${L:12};;
    SUMMARY*) SUMMARY=${L:8};;
    *);;
  esac
done < ${1}
}
process_several_ics_files(){

  local 

  for FILE in $*
  do
    sed -e 's;\r;;' "${FILE}" > ${TEMPFILE}		# remove \r
  parse_ics_file ${TEMPFILE}

done #|cut -b16-			# NB, includes 2 leading spaces.
}
do_it()
{

  [ $# -lt 1  ] && usage "Kindly specify a filename." 2
  for FILE in $@ ; do [ ! -f "${FILE}" ] && usage "  Not a file: ${FILE}" 2 ; done
  Z2L=0	# Zulu to Local

  process_several_ics_files $@|sort -n
}

createmail(){
cat <<-EOF
Return-Path: <invity@ffm.freifunk.net>
To: user@wifi-frankfurt.de
Content-Type: text/plain; charset=UTF-8
From: invity@ffm.freifunk.net
Subject: Terminerinnerung: $SUBJECT

Das kommende Freifunk Event steht an:
$SUBJECT
${SUBJECT//?/=}
$DESCRIPTION

Start: $DSTART
Ende: $DEND
Ort: $LOCATION
EOF
}

printnext()
{
  # extract uuid
  uuid=$(do_it "$0" "$CALFILE"|sort -n |head -n 1|rev|awk '{print $1}'|rev)

  # extract line numbers of the event carrying this uuid
  delims=( $(grep -n -e UID:$uuid -e VEVENT ${CALFILE}|grep -A 1 -B 1 UID:$uuid |cut -d: -f1|sed 2d) )
  # print this event only
  sed -n ${delims[0]},${delims[1]}p ${CALFILE}
}

TEMPFILE=$(mktemp /tmp/ical-vevents-parse.XXXXXXXXXX) || exit 1
CALFILE=$(mktemp /tmp/ical-vevents-parse.XXXXXXXXXX) || exit 1
trap "[ -f ${TEMPFILE} ] && rm ${TEMPFILE}; [ -f ${CALFILE} ] && rm ${CALFILE}" EXIT

cp /var/lib/radicale/collections/public ${CALFILE}
[[ $1 == "--printnext" ]] && printnext
[[ $1 == "--reminder" ]] &&
{
 [[ $# -lt 2 ]] && {
 echo "SYNOPSIS: $0 --reminder DAYS"
 exit 1
 }
  while read line
  do
    case $line in
    UID:*) uuid=${line:4};;
    SUMMARY:*) SUBJECT=${line:8};;
    DTSTART*) DSTART=$(groom_date_time_value_v2 ${line:8});;
    DTEND*) DEND=$(groom_date_time_value_v2 ${line:6});;
    LOCATION:*) LOCATION=${line:9};;
    DESCRIPTION:*) DESCRIPTION=$(echo ${line:12}|par 72);;
    *);;
    esac
  done < <(printnext)

  unixtime=${DSTART/,/}
  ntime=$(date +%s --date="$unixtime")
  # determine if reminder must be sent. This is based on two criteria:
  # * a reminder for this event has not been sent
  # * the reminder is less than $2 days in the future

  mkdir -p /var/spool/invity
  [[ $((ntime - $2*24*3600)) -lt $curtime ]] &&
  {
  [[ ! -f /var/spool/invity/$uuid ]] &&
  {
    createmail|/usr/sbin/sendmail -t
    date +%s > /var/spool/invity/$uuid 
  }
}

}
exit 0

(	# Change log and Notes.
2015.04.26	speed up parser by a factor larger than 25, replace invisible first timestamp by unix-time

2009.06.24	Added a function to make date-time values more readable.
Added support for doing multiple files.

2009.06.23	Initial script, patterned after sac.lib.history.groom

)
