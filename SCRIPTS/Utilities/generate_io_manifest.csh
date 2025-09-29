#!/bin/csh 

if($#argv < 1) then
	echo "generate_io_manifest.csh <command you want to check and all options> "
	exit 0
endif

echo "monitoring: $1:t ..."

#strace -o $1:t".manifest" -f -t -y -e trace=open,openat,close,read,write,connect,accept $argv

strace -o $1:t".manifest" -f -t -y -e trace=read,write $argv

echo "Extracting reads..."
if($?PROJECTS_HOME) then
	grep "read(" $1:t".manifest" | grep $PROJECTS_HOME | cut -d"<" -f2 | cut -d">" -f1 | uniq > ! $1:t".manifest.read"
else
	grep "read(" $1:t".manifest" | cut -d"<" -f2 | cut -d">" -f1 | uniq > ! $1:t".manifest.read"
endif

echo "Exctracting writes..."
if($?PROJECTS_HOME) then
	grep "write(" $1:t".manifest" | grep $PROJECTS_HOME | cut -d"<" -f2 | cut -d">" -f1 | uniq > ! $1:t".manifest.write"
else
	grep "write(" $1:t".manifest" | cut -d"<" -f2 | cut -d">" -f1 | uniq > ! $1:t".manifest.write"
endif

exit 0
