#!/bin/csh

if($#argv < 3) then
	echo "email_file.csh <recipient email address> <email subject> <email message> <text file with message to send>"
	exit 1
endif

ftouch email_report.txt

set EmailRecipient = $1
set EmailSubject = ($2)
set EmailMessage = ($3)

if($4 != "") then
	set EmailLog = $4
else
	set EmailLog = "$$"
endif

echo "Subject: $EmailSubject" >> email_report.txt
echo "$EmailMessage" >> email_report.txt
if(-e $EmailLog) then
	echo " " >> email_report.txt
	echo "*************************" >> email_report.txt
	echo " " >> email_report.txt
	cat $EmailLog >> email_report.txt
	echo " " >> email_report.txt
	echo "*************************" >> email_report.txt
	echo " " >> email_report.txt
endif

echo "Regards," >> email_report.txt
echo "	Yourself" >> email_report.txt

cat email_report.txt | sendmail -v $EmailRecipient

rm -f email_report.txt

exit 0
