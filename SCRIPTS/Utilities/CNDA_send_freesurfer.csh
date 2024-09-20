#!/bin/sh -v
user="metcalfn" #users password
pw="N1ck65583" #users password

host="https://cnda.wustl.edu" #place we are sending the data
project="CCIR_00299" #project name? or project ID?
subject="299-APO" #subject name to upload to
sessid="test_session" #session id. The date?
fs="FS_test" #
fs_version="freesurfer-Linux-centos4_x86_64-stable-pub-v5.3.0"	#freesurfer version string
fs_date="2014-04-03" #date freesurfer was run?
localFSFiles="/scratch/SurfaceStroke/FS_test.zip" #zip containing the FS folder structure for the subject.

#command
curl -k -u ${user}:${pw} -X PUT "https://$%7bhost%7d/data/archive/projects/$%7bproject%7d/subjects/$%7bsubject%7d/experiments/$%7bsessid%7d/assessors/$%7bfs%7d?xsiType=fs:fsData&fs:fsData/fs_version=$%7bfs_version%7d&%20xnat:experimentData/date=$%7bfs_date%7d|https://${host}/data/archive/projects/${project}/subjects/${subject}/experiments/${sessid}/assessors/${fs}?xsiType=fs:fsData&fs:fsData/fs_version=${fs_version}& xnat:experimentData/date=${fs_date}"

#example
#curl -k -u userId:password -X PUT "https://cnda.wustl.edu/data/archive/projects/testProj/subjects/101/experiments/101_big_session/assessors/101_big_session_fs_20140403?xsiType=fs:fsData&fs:fsData/fs_version=freesurfer-Linux-centos4_x86_64-stable-pub-v5.1.0&xnat:experimentData/date=2014-04-03|https://cnda.wustl.edu /data/archive/projects/testProj/subjects/101/experiments/101_big_session/assessors/101_big_session_fs_20140403?xsiType=fs:fsData&fs:fsData/fs_version=freesurfer-Linux-centos4_x86_64-stable-pub-v5.1.0&xnat:experimentData/date=2014-04-03"

#command
curl -k -u ${user}:${pw} -X PUT "https://$%7bhost%7d/data/archive/projects/$%7bproject%7d/subjects/$%7bsubject%7d/experiments/$%7bsessid%7d/assessors/$%7bfs%7d/resources/DATA|https://${host}/data/archive/projects/${project}/subjects/${subject}/experiments/${sessid}/assessors/${fs}/resources/DATA"

#example
#curl -k -u userId:password -X PUT "https://cnda.wustl.edu%20/data/archive/projects/testProj/subjects/101/experiments/101_big_session/assessors/101_big_session_fs_20140403/resources/DATA|https://cnda.wustl.edu /data/archive/projects/testProj/subjects/101/experiments/101_big_session/assessors/101_big_session_fs_20140403/resources/DATA”

#command
curl -k -u ${user}:${pw} -T ${localFSFiles}.zip "https://$%7bhost%7d/data/archive/projects/$%7bproject%7d/subjects/$%7bsubject%7d/experiments/$%7bsessid%7d/assessors/$%7bfs%7d/resources/DATA/files/$%7bsession%7d.zip?inbody=true&extract=true&overwriteFiles=true|https://${host}/data/archive/projects/${project}/subjects/${subject}/experiments/${sessid}/assessors/${fs}/resources/DATA/files/${session}.zip?inbody=true&extract=true&overwriteFiles=true"

#example
#curl -k -u userId:password -T ./101_big_session_FS.zip "https://cnda.wustl.edu%20/data/archive/projects/testProj/subjects/101/experiments/101_big_session/assessors/101_big_session_fs_20140403/resources/DATA/files/101_big_session.zip?inbody=true&extract=true&overwriteFiles=true|https://cnda.wustl.edu /data/archive/projects/testProj/subjects/101/experiments/101_big_session/assessors/101_big_session_fs_20140403/resources/DATA/files/101_big_session.zip?inbody=true&extract=true&overwriteFiles=true”