#!/bin/bash

. /etc/profile

# paths (NO trailing slashes!!!)
source_path="/cygdrive/u/SD_VIDEO"
dropbox_path="/cygdrive/c/Dropbox/Class Video"
temp_path="/home/GLBI/.camdump/$(date --rfc-3339=ns | awk '{ print $1 "_" $2 }' | sed 's/:/-/g')"
remote_server="njbair@glbimedia.org"
remote_port="2222"
remote_path="/home/njbair/moodledata/repository"
ffmpeg_bin_path="/cygdrive/c/Program Files/WinFF/ffmpeg.exe"

purge_temp()
{
	echo "Purging temp directory..."
	if [ -d "${temp_path}" ]; then
		rm -r "${temp_path}"
	fi
}

copy_from_cam()
{
	echo "Copying camcorder files..."

	# (re)create temp directory
	mkdir -p "${temp_path}"

	# get all .MOD files from camcorder
	find "${source_path}" -name \*.MOD > "${temp_path}/camcorder_files" 2>/dev/null

	total_count=$(wc -l "${temp_path}/camcorder_files" | awk '{print $1}')
	current_count=0
	part=1
	echo "${total_count} files need copying..."

	# loop through .MOD files on camcorder
	# copy each file to temp directory and delete the original upon success
	cat "${temp_path}/camcorder_files" | while read line; do
		current_count=$((current_count+1))
		while [ -f "${temp_path}/${course_name}_${class_number}-${part}.MOD" ]; do
			part=$((part+1))
		done
		echo "Copying ${current_count} of ${total_count}"
		rsync --progress ${rsync_delete_sources} "${line}" "${temp_path}/${course_name}_${class_number}-${part}.MOD"
	done
}

make_all()
{
	echo "Beginning conversion..."
	
	files=(${temp_path}/*.MOD)
	total_count=${#files[@]}
	current_count=0

	for line in ${files[@]}; do
		current_count=$((current_count+1))
		echo "Converting ${current_count} of ${total_count}"
		infile="$(echo "${line}" | sed -s 's/\.MOD.*$/.MOD/')"
		mp4file="$(echo "${line}" | sed -s 's/\.MOD.*$/.mp4/')"
		mp3file="$(echo "${line}" | sed -s 's/\.MOD.*$/.mp3/')"
		wavfile="$(echo "${line}" | sed -s 's/\.MOD.*$/.wav/')"
		
		win_ffmpeg="$(cygpath -w "${ffmpeg_bin_path}")"
		win_infile="$(cygpath -w "${infile}")"
		win_mp4file="$(cygpath -w "${mp4file}")"
		win_mp3file="$(cygpath -w "${mp3file}")"
		win_wavfile="$(cygpath -w "${wavfile}")"

		if [[ "${make_mp4}" == [yY] ]]; then
			echo "Converting to MP4..."
	
			cmd /C "${win_ffmpeg}" -i "${win_infile}" \
				-c:v libx264 -s 512x288 -r 24 \
				-preset fast -filter:v yadif \
				-c:a libfaac -ac 1 -ar 44100 -b:a 64k \
				-threads 0 -y \
				"${win_mp4file}"
		fi
		
		if [[ "${make_wav}" == [yY] ]]; then
			echo "Converting to WAV..."
			
			cmd /C "${win_ffmpeg}" -i "${win_infile}" \
				-ac 1 -y \
				"${win_wavfile}"
		fi

		if [[ "${make_mp3}" == [yY] ]]; then
			echo "Converting to MP3..."
	
			cmd /C "${win_ffmpeg}" -i "${win_wavfile}" \
				-ar 44100 -b:a 64k -y \
				"${win_mp3file}"
		fi
	done
}

upload_all()
{
	if [[ "${upload_mp4}" == [yY] ]]; then
		echo "Uploading MP4..."
		if [ $(ssh -p ${remote_port} "${remote_server}" [ -d "${remote_path}/course_video/${course_name}/" ] && echo "Y" || echo "N") == "N" ]; then
			ssh -p ${remote_port} "${remote_server}" mkdir "${remote_path}/course_video/${course_name}/"
		fi
		for file in ${temp_path}/*.mp4; do
			scp -P ${remote_port} "${file}" "${remote_server}:${remote_path}/course_video/${course_name}/"
		done
	fi
	
	if [[ "${upload_mp3}" == [yY] ]]; then
		echo "Uploading MP3..."
		if [ $(ssh -p ${remote_port} "${remote_server}" [ -d "${remote_path}/course_audio/${course_name}/" ] && echo "Y" || echo "N") == "N" ]; then
			ssh -p ${remote_port} "${remote_server}" mkdir "${remote_path}/course_audio/${course_name}/"
		fi
		for file in ${temp_path}/*.mp3; do
			scp -P ${remote_port} "${file}" "${remote_server}:${remote_path}/course_audio/${course_name}/"
		done
	fi
	
	if [[ "${upload_wav}" == [yY] ]]; then
		echo "Uploading WAV..."
		if [ $(ssh -p ${remote_port} "${remote_server}" [ -d "${remote_path}/course_audio/${course_name}/" ] && echo "Y" || echo "N") == "N" ]; then
			ssh -p ${remote_port} "${remote_server}" mkdir "${remote_path}/course_audio/${course_name}/"
		fi
		for file in ${temp_path}/*.wav; do
			scp -P ${remote_port} "${file}" "${remote_server}:${remote_path}/course_audio/${course_name}/"
		done
	fi
}

dropbox_all()
{
	echo "Moving to DropBox..."
	if [[ "${dropbox_mp4}" == [yY] ]]; then
		for file in ${temp_path}/*.mp4; do
			mv "${file}" "${dropbox_path}"
		done
	fi
	if [[ "${dropbox_mp3}" == [yY] ]]; then
		for file in ${temp_path}/*.mp3; do
			mv "${file}" "${dropbox_path}"
		done
	fi
	if [[ "${dropbox_wav}" == [yY] ]]; then
		for file in ${temp_path}/*.wav; do
			mv "${file}" "${dropbox_path}"
		done
	fi
}

set -e

while getopts "dt:" opt; do
	case $opt in
		d)
			defaults=1
			;;
		t)
			if [[ -d "$OPTARG" ]]; then
				temp_path="$OPTARG"
			else
				echo "Error: Invalid directory specified for option -t"
				exit 1
			fi
			;;
	esac
done

echo

valid=1
while ! [[ "$course_name" =~ ^[a-zA-Z0-9]+$ ]] || [[ "$course_name" == "" ]]; do
	[[ $valid -eq 1 ]] || echo -e "Error: Course name must contain only letters and numbers.\n"
	read -p "Course Short Name [COURSE]: " course_name
	course_name=${course_name:-COURSE}
	valid=0
done

valid=1
while ! [[ "$class_number" =~ ^[0-9]+$ ]] || [[ "$class_number" == "" ]]; do
	[[ $valid -eq 1 ]] || echo -e "Error: Class Number must contain only numeric digits.\n"
	read -p "Class Number [99]: " class_number
	class_number=${class_number:-99}
	valid=0
done
echo

[[ "$defaults" == "1" ]] || read -p "Purge temp directory first? [Y/n]: " purge_temp && purge_temp=${purge_temp:-Y}

[[ "$defaults" == "1" ]] || read -p "Copy source files from camcorder? [Y/n]: " copy_from_cam
copy_from_cam=${copy_from_cam:-Y}
[[ $copy_from_cam == [yY] ]] && [[ "$defaults" != "1" ]] && read -p "  Delete source files after copy? [n/Y]: " delete_sources && delete_sources=${delete_sources:-Y}

[[ "$defaults" == "1" ]] || echo
[[ "$defaults" == "1" ]] || read -p "Create MP4? [Y/n]: " make_mp4
make_mp4=${make_mp4:-Y}

[[ "$defaults" == "1" ]] || read -p "Create MP3? [Y/n]: " make_mp3
make_mp3=${make_mp3:-Y}

[[ $make_mp3 != [yY] ]] && [[ "$defaults" != "1" ]] && read -p "Create WAV? [y/N]: " make_wav
if [[ $make_mp3 == [yY] ]]; then
	[[ "$defaults" == "1" ]] || echo "WAV automatically selected because MP3 depends on it."
	make_wav="Y"
else
	make_wav=${make_wav:-N}
fi

[[ "$defaults" == "1" ]] || echo
[[ "$defaults" == "1" ]] || read -p "Upload MP4? [Y/n]: " upload_mp4
upload_mp4=${upload_mp4:-Y}
[[ "$defaults" == "1" ]] || read -p "Upload MP3? [Y/n]: " upload_mp3
upload_mp3=${upload_mp3:-Y}
[[ "$defaults" == "1" ]] || read -p "Upload WAV? [y/N]: " upload_wav
upload_wav=${upload_wav:-N}

[[ "$defaults" == "1" ]] || echo
[[ "$defaults" == "1" ]] || read -p "Move MP4 to DropBox? [Y/n]: " dropbox_mp4
dropbox_mp4=${dropbox_mp4:-Y}
[[ "$defaults" == "1" ]] || read -p "Move MP3 to DropBox? [y/N]: " dropbox_mp3
dropbox_mp3=${dropbox_mp3:-N}
[[ "$defaults" == "1" ]] || read -p "Move WAV to DropBox? [y/N]: " dropbox_wav
dropbox_wav=${dropbox_wav:-N}

echo
echo "${course_name}_${class_number}"
read -p "Continue? [Y/n]: " continue
if [[ "$continue" == [nN] ]]; then
	echo "Operation Aborted! Exiting."
	exit 0
fi
echo
echo "Processing..."
echo

[[ $purge_temp == [yY] ]] && purge_temp
[[ $delete_sources == [yY] ]] && rsync_delete_sources="--remove-source-files"
[[ $copy_from_cam == [yY] ]] && copy_from_cam

echo
echo "*****************************************"
echo " TRANSFER COMPLETE!"
echo " You may now safely eject the camcorder."
echo "*****************************************"
echo

[[ $make_mp4 == [yY] ]] || [[ $make_mp3 == [yY] ]] || [[ $make_wav == [yY] ]] && make_all
[[ $upload_mp4 == [yY] ]] || [[ $upload_mp3 == [yY] ]] || [[ $upload_wav == [yY] ]] && upload_all
[[ $dropbox_mp4 == [yY] ]] || [[ $dropbox_mp3 == [yY] ]] || [[ $dropbox_wav == [yY] ]] && dropbox_all

echo
echo "SUCCESS!"
read -p "Press [Enter] to exit."
exit 0