#!/bin/sh
# This script takes a list of names and displays it 
# \
exec adedit "$0" ${1+"$@"}
package require ade_lib

if { $argc == 0 } {
	puts "Command format: $argv0 name name ..."
	exit 1
}

set total $argc

puts "
The following people are in the marketing department"

while {$total > 0} {
	incr total -1
	puts "	[lindex $argv $total]"
	}

  