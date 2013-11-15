#! /bin/bash 

# copy-snapshots.sh

# Copy one or more snapshots to a second file system/folder.   

#
# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012, 2013  Chip Schweiss

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.


cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. ../zfs-tools-init.sh

# show program usage
show_usage() {
    echo
    echo "Usage: $0 -z {zfs_folder} -l {last_snapshot} -t {target_folder} -c {copy_mode}"
    echo "  -c {copy_mode} (normal, blind, crypt, decrypt, zfs)"
    echo "  [-f {first_snapshot}] First snapshot.  Manually declare first snapshot."
    echo "  [-i] Incrementally handle all snapshots between first and last snapshots"
    echo "  [-d] Dry run.  Show what would happen."
    echo "  [-r {report_name} Overide default report name."
    echo "  [-g {logfile) Overide default log file."
    echo 
    echo "  [-l latest] Automatically find the latest snapshot in the source"
    exit 1
}

# Minimum number of arguments needed by this program
MIN_ARGS=4

if [ "$#" -lt "$MIN_ARGS" ]; then
    show_usage
    exit 1
fi

if [ "x$ec2_logfile" != "x" ]; then
    logfile="$ec2_logfile"
else
    logfile="$default_logfile"
fi

if [ "x$ec2_report" != "x" ]; then
    report_name="$ec2_report"
else
    report_name="$default_report_name"
fi


copy_count=0
copy_bytes=0
modify_count=0
modify_bytes=0
delete_count=0
delete_bytes=0
move_count=0
move_bytes=0
warning_count=0

zflag=
fflag=
lflag=
tflag=
cflag=
iflag=
rflag=
gflag=
dflag=


copymode=""

while getopts idz:f:l:t:c:r:g:l: opt; do
    case $opt in
        z)  # ZFS folder 
            zflag=1
            zval="$OPTARG";;
        f)  # Fisrt snapshot
            fflag=1
            fval="$OPTARG";;
        l)  # Last snapshot
            lflag=1
            last_snap="$OPTARG";;
        t)  # Target
            tflag=1
            tval="$OPTARG";;
        c)  # Copy Mode
            cflag=1
            copymode="$OPTARG";;
        i)  # Incremental mode
            debug "Using incremental mode"
            iflag=1;;
        d)  # Dry run
            debug "Dry run selected."
            dflag=1;;
        r)  # Overide report name
            rflag=1
            report_name="$OPTARG";;
        g)  # Overide log file
            gflag=1
            logfile="$OPTARG";;
        ?)  # Show program usage and exit
            show_usage
            exit 1;;
        :)  # Mandatory arguments not specified
            debug "Option -$OPTARG requires an argument."
            exit 1;;
    esac
done

# Check supplied options validity

if [ "$copymode" == "" ]; then
    copymode="normal"
fi

case $copymode in
    "normal")
        debug "No encryption selected" ;;
    "blind")
        debug "Blind mode selected" 
        if [ -z "$fflag" ] || [ -z "$lflag" ]; then
            error "First and last snapshot '-f {first_snapshot}' and '-l {last_snapshot}' must be specified for blind mode."
            exit 1
        fi
        ;;
    "zfs")
        debug "ZFS Send/Receive mode selected" ;;
    "crypt")
        debug "File level encryption selected" ;;
    "decrypt")
        echo -n "Enter key/passphrase for gpg private key: "
        read -s $key
        ;;
    *)
        error "No valid copy mode.   Must specify (normal,blind,crypt,decrypt)" >&2
        ;;
esac


if [ "$sflag" == "1" ] && [ "$copymode" != "normal" ]; then
    error "ZFS Send/Receive mode specified, but copy mode not set to normal!" >&2
    exit 1
fi

zfs list -H -o name $zval 1>/dev/null 2>/dev/null; result=$?
if [ $result -ne 0 ]; then
    error "Source ZFS folder: $zval does not exist!" >&2
    exit 1
else
    zfs_source="$zval"
fi

if [ "$copymode" != "blind" ]; then
    # Target folder must be ZFS for all modes execept blind
    zfs list -H -o name $tval 1>/dev/null 2>/dev/null; result=$?
    if [ "$tval" == "" ] || [ $result -ne 0 ]; then
        error "Target ZFS folder $zval does not exist!" >&2
        exit 1
    else
        zfs_target="$tval"
    fi
else
    zfs_target="$tval"
fi



if [ "$copymode" != "blind" ]; then
    # Confirm we are using the correct snapshot for the target
    
    last_target_snapname=`zfs list -t snapshot -H -o name,creation -s creation | \
                            $grep -v "aws-backup_" | \
                            $grep "^${zfs_target}@" | \
                            $cut -f 1 | \
                            tail -n 1 | $cut -d "@" -f 2`
    
    debug "Last snapshot of ${zfs_target} is: $last_target_snapname"
    
    if [ "$last_target_snapname" == "" ]; then
        debug "Working from the root snapshot."
        first_snap="root"
    else
        debug "Working from the last target snapshot: $last_target_snapname"
        first_snap="$last_target_snapname"
    fi
    
    if [ "$last_snap" == "latest" ]; then
        debug "Finding latest snapshot of $zfs_source"
           last_snap=`zfs list -t snapshot -H -o name,creation -s creation | \
                            $grep "^${zfs_source}@" | \
                            $cut -f 1 | \
                            tail -n 1 | $cut -d "@" -f 2`
        debug "Found ${zfs_source}@${last_snap} as the latest snapshot."
    fi
    
    zfs list -t snapshot -H -o name | $grep -q "^${zfs_source}@${last_snap}"; result=$?
    if [ $result -ne 0 ]; then
        error "Last snapshot ${zfs_source}@${last_snap} does not exist!" >&2
        exit 1
    fi
    
    
    if [ "$last_snap" == "$last_target_snapname" ]; then
        notice "Nothing to do all snaps are copied!" 
        exit 0
    fi
else
    first_snap="$fval"
fi
    
debug "Processing job..."

# Prepare incremental set of snapshots if '-i' specified

if [ -n "$iflag" ]; then
    # We are processing an incremental set
    # Collect all intermediate snapshots in order of snapshot creation
    debug "Collecting intermediate snapshots..."
    gross_snap_list=`zfs list -t snapshot -H -o name,creation -s creation | \
                        $grep "^${zfs_source}@" | \
                        $cut -f 1 | \
                        $cut -d "@" -f 2`
    debug "Done."
    # Trim the list from first to last snapshots
    net_snap_list=""
    if [ "$first_snap" == "root" ]; then
        snap_list_state="between_snaps"
        base_snap_complete="false"
    else
        snap_list_state="before_first"
        base_snap_complete="true"
    fi
    for snap in $gross_snap_list; do
        case $snap_list_state in
            "before_first")
                if [ "${snap}" == "${first_snap}" ]; then
                    snap_list_state="between_snaps"
                fi
                ;;
            "between_snaps")
                net_snap_list="${net_snap_list} ${snap}"
                if [ "${snap}" == "${last_snap}" ]; then
                    snap_list_state="after_snaps"
                fi
                ;;
            "after_snaps")
                break
                ;;
        esac
    done

    
    if [ "$net_snap_list" == "" ]; then
        # There are no intermediate snaps
        debug "No intermediate snaps found."
        debug "First snap: ${first_snap}"
        debug "Last snap: ${last_snap}"
        iflag=0
    else 
        debug "Intermediate snaps are: "
        for snap in $net_snap_list; do
            debug "  $snap"
        done
    fi
else
    net_snap_list="$last_snap"
fi



copy_file () {

    # 'zfs diff' will escape many chacters as octal representations.  Passing through
    # echo will process these escapes to characters.
    local file=`echo -n "/${zfs_source}/.zfs/snapshot/${snap}/${1}"`

    if [ ! -e "$file" ]; then
        warning "File listed as new or modified does not exist. \"${file}\""
        return 2
    fi
                   
    local filedest=`echo -n "/${zfs_target}/${1}"`
    local filehash=`echo -n "/${zfs_target}/${1}.sha256"`
    local filetype=`stat --printf="%F" "$file"`
    local fileuid=`stat --printf="%u" "$file"`
    local filegid=`stat --printf="%g" "$file"`
    local filemode=`stat --printf="%a" "$file"`
    local target_fix_dir=
    local source_fix_dir=
    local error_val=0
    

    if [ "$filetype" == "regular empty file" ]; then
        filetype="regular file"
    fi

    case $filetype in 
        "regular file")
            # Update the hash
            if [ "$filesign" == "true" ]; then
                if [ -z "$dflag" ]; then
                    debug "sha256sum \"$file\" > \"$filehash\""
                    sha256sum "$file" > "$filehash"
                else
                    debug "Would: sha256sum \"$file\" > \"$filehash\""
                fi
            fi
            case $copymode in
                "normal"|"blind")
                    if [ -z "$dflag" ]; then
                        debug "copy \"$file\" to \"$filedest\""
                        basedir=`dirname "$filedest"`
                        if [ ! -d "$basedir" ]; then
                            mkdir -p "$basedir"
                            target_fix_dir="$basedir"
                            source_fix_dir=`dirname "${file}"`
                        else
                            target_fix_dir=
                            source_fix_dir=
                        fi
                        rsync -a --sparse "$file" "$filedest" &> $TMP/blind_inc_error_$$
                        error_val=$?
                    else
                        debug "Would: copy \"$file\" to \"$filedest\""
                    fi
                    ;;
                "crypt")
                    if [ -z "$dflag" ]; then
                        debug "crypt file \"$file\" to \"$cryptdest\""
                        cryptdest="${filedest}.gpg"
                        # If the file was modified gpg will ask to overwrite.  We will
                        # make sure a previous copy is not there first.
                        if [ -e "$cryptdest" ]; then
                            rm -f "$cryptdest"
                        fi
                        gpg -r "$gpg_user" --compress-algo bzip2 --output "$cryptdest" --encrypt "$file" &> $TMP/blind_inc_error_$$
                        error_val=$?
                        sha256sum "$file" > "${filedest}.sha256"
                        filedest="$cryptdest"
                    else
                        debug "Would: crypt file \"$file\" to \"$cryptdest\""
                    fi
                    ;;
                "decrypt")
                    if [ -z "$dflag" ]; then
                        debug "decrypt file \"$file\" to \"$filedest\""
                        # Remove .gpg on destination
                        # Check sha256 sum
                        namelen=$(( ${#filedest} - 4 ))
                        filedest="${filedest:0:$namelen}"
                        namelen=$(( ${#file} - 4 ))
                        sigfile="${file:0:$namelen}.sha256"
                        gpg -r "$gpg_user" --output "$filedest" --decrypt "$file" &> $TMP/blind_inc_error_$$
                        error_val=$?
                        sourcesha256=`cat ${sigfile}.sha256|$cut -f 1`
                        destsha256=`sha256sum "$filedest"|$cut -f 1`
                        if [ "$sourcesha256" != "$destsha256" ]; then
                            error "SHA256 sum of decrypted file $filedest does not match saved sum in file $sigfile."
                        fi
                    else
                        debug "Would: decrypt file \"$file\" to \"$filedest\""
                    fi
                    ;;
            esac
            ;;
        "symbolic link")
            if [ -z "$dflag" ]; then
                debug "copy \"$file\" to \"$filedest\""
                cp -a "$file" "$filedest" &> $TMP/blind_inc_error_$$
                error_val=$?
            else
                debug "Would: copy \"$file\" to \"$filedest\""
            fi
            ;;
        "directory")
            if [ -z "$dflag" ]; then
                debug "mkdir -p \"$filedest\""
                basedir=`dirname "$filedest"`
                if [ ! -d "$basedir" ]; then
                    mkdir -p "$basedir"
                    target_fix_dir="$basedir"
                    source_fix_dir=`dirname "${file}"`
                else
                    target_fix_dir=
                    source_fix_dir=
                fi
                mkdir -p "$filedest" &> $TMP/blind_inc_error_$$
                error_val=$?
            else
                debug "Would: mkdir -p \"$filedest\""
            fi
            ;;
        "character special file")
            debug "Character special file encountered: $file"     
            if [ -z "$dflag" ]; then
                debug "copy \"$file\" to \"$filedest\""
                cp -a "$file" "$filedest" &> $TMP/blind_inc_error_$$
                error_val=$?
            else
                debug "Would: copy \"$file\" to \"$filedest\""
            fi
            ;;
        "block special file")
            debug "Block special file encountered: $file"
            if [ -z "$dflag" ]; then
                debug "copy \"$file\" to \"$filedest\""
                cp -a "$file" "$filedest" &> $TMP/blind_inc_error_$$
                error_val=$?
            else
                debug "Would: copy \"$file\" to \"$filedest\""
            fi
            ;;
    esac

    # If ACLs are used this will need to be upgraded
    if [ "$filetype" == "regular file" ] && [ "$copymode" == "crypt" ] || [ "$filetype" == "directory" ]; then
        if [ -z "$dflag" ]; then
            debug "Set ownership, permissions and mtime for $filedest"
            chown ${fileuid}:${filegid} "$filedest" &>> $TMP/blind_inc_error_$$
            error_val=$(( error_val + $? ))
            chmod ${filemode} "$filedest" &>> $TMP/blind_inc_error_$$
            error_val=$(( error_val + $? ))
            touch --reference "${file}" "$filedest" &>> $TMP/blind_inc_error_$$
            error_val=$(( error_val + $? ))
        else
            debug "Would set ownership, permissions and mtime for $filedest"
        fi
    fi

    # If we had to create directories for a file copy, fix permissions on new directorie(s)
    if [ "x$target_fix_dir" != "x" ]; then
        while [ "$target_fix_dir" != "/$zfs_target" ]; do
            if [ -z "$dflag" ]; then
                fileuid=`stat --printf="%u" "$source_fix_dir"`
                filegid=`stat --printf="%g" "$source_fix_dir"`
                filemode=`stat --printf="%a" "$source_fix_dir"`
                debug "Set ownership, permissions and mtime for $target_fix_dir"
                chown ${fileuid}:${filegid} "$target_fix_dir" &>> $TMP/blind_inc_error_$$
                error_val=$(( error_val + $? ))
                chmod ${filemode} "$target_fix_dir" &>> $TMP/blind_inc_error_$$
                error_val=$(( error_val + $? ))
                touch --reference "${source_fix_dir}" "$target_fix_dir" &>> $TMP/blind_inc_error_$$
                error_val=$(( error_val + $? ))
            else
                debug "Would set ownership, permissions and mtime for $filedest"
            fi   
            # Strip one directory off end
            target_fix_dir=`dirname "$target_fix_dir"`
            source_fix_dir=`dirname "$source_fix_dir"`
        done
    fi

    return $error_val
        

}

rename_file () {

    # 'zfs diff' will escape many chacters as octal representations.  Passing through
    # echo will process these escapes to characters.
    local file=`echo -n "$1"`
    local newname=`echo -n "$2"`
    local filetype="$3"
    local error_val=0

    case $copymode in
        "normal"|"blind")
            if [ -z "$dflag" ]; then
                debug "move \"/${zfs_target}/$file\" to \"/${zfs_target}/$newname\""
                mv "/${zfs_target}/$file" "/${zfs_target}/$newname" &> $TMP/blind_inc_error_$$
                error_val=$?
            else
                debug "Would: move \"/${zfs_target}/$file\" to \"/${zfs_target}/$newname\""
            fi
            ;;
        "crypt")
            if [ "$filetype" == "F" ]; then 
                if [ -z "$dflag" ]; then
                    debug "move \"/${zfs_target}/${file}.gpg\" to \"/${zfs_target}/${newname}.gpg\""
                    mv "/${zfs_target}/${file}.gpg" "/${zfs_target}/${newname}.gpg" &> $TMP/blind_inc_error_$$
                    error_val=$?
                    debug "move \"/${zfs_target}/${file}.sha256\" to \"/${zfs_target}/${newname}.sha256\""
                    mv "/${zfs_target}/${file}.sha256" "/${zfs_target}/${newname}.sha256" &>> $TMP/blind_inc_error_$$
                    error_val=$(( error_val + $? ))
                else
                    debug "Would: move \"/${zfs_target}/${file}.gpg\" to \"/${zfs_target}/${newname}.gpg\""
                    debug "Would: move \"/${zfs_target}/${file}.sha256\" to \"/${zfs_target}/${newname}.sha256\""
                fi
            fi
            ;;
        "decrypt")
            if [ "$filetype" == "F" ]; then
                if [ -z "$dflag" ]; then
                    debug "move \"/${zfs_target}/$file\" to \"/${zfs_target}/$newname\""
                    local filelen=$(( ${#file} - 4 ))
                    file="${file:0:$filelen}" 
                    local newlen=$(( ${#newname} - 4 ))
                    newname="${newname:0:$newlen}"
                    mv "/${zfs_target}/$file" "/${zfs_target}/$newname" &> $TMP/blind_inc_error_$$
                    error_val=$?
                else
                    debug "Would: move \"/${zfs_target}/$file\" to \"/${zfs_target}/$newname\""
                fi
            fi
            ;;
    esac

    return $error_val

}

delete_file () {

    local file="$1"
    local filetype="$2"
    local error_val=0
    
    if [ "$filetype" == "/" ]; then
        rm -rf /${zfs_target}/${file}
        error_val=$?
    else
        case $copymode in
            "normal"|"blind")
                if [ -z "$dflag" ]; then
                    debug "delete \"/${zfs_target}/${file}\""
                    # If the directory was also deleted it would be 
                    # executed first and our files will not be found
                    # We will dump error output.
                    rm "/${zfs_target}/${file}" &> /dev/null
                    # error_val=$?
                    rm "/${zfs_target}/${file}.sha256" 2> /dev/null
                else
                    debug "Would: delete \"/${zfs_target}/${file}\""
                fi
                ;;
            "crypt")
                if [ -z "$dflag" ]; then
                    debug "delete \"/${zfs_target}/${file}.gpg\""
                    rm "/${zfs_target}/${file}.gpg" &> $TMP/blind_inc_error_$$
                    error_val=$?
                    debug "delete \"/${zfs_target}/${file}.sha256\""
                    rm "/${zfs_target}/${file}.sha256" 2> /dev/null
                else
                    debug "Would: delete \"/${zfs_target}/${file}.gpg\""
                    debug "Would: delete \"/${zfs_target}/${file}.sha256\""
                fi
                ;;
            "decrypt")
                if [ -z "$dflag" ]; then
                    debug "delete \"/${zfs_target}/${file}\""
                    local filelen=$(( ${#file} - 4 ))
                    file="${file:0:$filelen}"
                    rm "/${zfs_target}/${file}" &> $TMP/blind_inc_error_$$
                    error_val=$?
                else
                    debug "Would: delete \"/${zfs_target}/${file}\""
                fi
                ;;
        esac
    fi

    return $error_val
    
}

long_delete_files () {
    # This function is only used on system where the zfs diff is broken and does not
    # list deleted files.

    # It has not been tested, as the bug was fixed before this script was finished.
    # It is being left here for reference.  It was broken in OpenIndiana 151a4.

    local workdir="$1"
    local snap="$2"
    local prev_snap="$3"
    local file=""

    # List the files in the current and previous snapshots
    ls -1 -a "/${zfs_source}/.zfs/snapshot/${snap}/${workdir}" | $grep -v "." | $grep -v ".." > /tmp/copy_snap_delete_files_current_$$
    ls -1 -a "/${zfs_source}/.zfs/snapshot/${previous}/${workdir}" | $grep -v "." | $grep -v ".." > /tmp/copy_snap_delete_files_previous_$$

    # Check each file if has been removed but not renamed which is handled individually.
    while read file; do
        cat /tmp/copy_snap_delete_files_current_$$|$grep -q -x "$file";result=$?
        if [ "$result" -ne "0" ]; then
            # The file is no longer in the directory
            # Has this file been renamed?
            cat /tmp/copy_snaplist_$$|$grep -q "R\s+F\s+/${zfs_source}/${workdir}${file}\s/.+";result=$?
            if [ "$result" -ne "0" ]; then
                # File has been deleted
                delete_file "${workdir}${file}"
            fi
        fi
    done < "/tmp/copy_snap_delete_files_previous_$$"

}

#######################################################################################################
# Main processing loop
#######################################################################################################

prev_snap="$first_snap"

for snap in $net_snap_list; do
    debug "Processing $snap"

    if [ "$first_snap" == "root" ] && [ "$base_snap_complete" != "true" ]; then
        if [ "$copymode" == "zfs" ]; then
            if [ -z "$dflag" ]; then
                debug "zfs send -R ${zfs_source}@${last_snap} | zfs receive -F -vu ${zfs_target}"
                # Do the zfs send/receive to the target folder
                # Since zfs send/receive can handle a complete stream with all snapshots
                # We will do this in one operation to copy all snapshots.
                zfs send -R ${zfs_source}@${last_snap} | zfs receive -F -vu ${zfs_target}
            else
                debug "Would: zfs send -R ${zfs_source}@${last_snap} | zfs receive -F -vu ${zfs_target}"
            fi
            base_snap_complete="true"
            break
        else
            # Our source list is built from the snapshot itself not a 'zfs diff'.
            # In this special case we'll use 'find' to get our list.
        
            file_list=`find /${zfs_source}/.zfs/snapshot/${snap}/ \
                -printf "%P\n"`
            
            for file in $file_list; do
                copy_file "$file" "$snap"
            done
        
            prev_snap="$snap"
            if [ -z "$dflag" ]; then
                debug "Creating target snapshot: ${zfs_target}@${snap}"
                zfs snapshot ${zfs_target}@${snap} ; result=$?
                if [ "$result" -ne "0" ]; then
                    error "Failed to create snapshot ${zfs_target}@${snap}"
                fi
            else
                debug "Would: zfs snapshot ${zfs_target}@${snap}"
            fi
            base_snap_complete="true"
        fi
    else
        if [ "$copymode" == "zfs" ]; then
            if [ -z "$dflag" ]; then
                # Do the zfs send/receive to the target folder
                debug "zfs send -R -i ${zfs_source}@${first_snap} ${zfs_source}@${last_snap} | zfs receive -Fuv ${zfs_target}"
                zfs send -R -i ${zfs_source}@${first_snap} ${zfs_source}@${last_snap} | zfs receive -Fuv ${zfs_target}
            else
                debug "Would: zfs send -R -i ${zfs_source}@${first_snap} ${zfs_source}@${last_snap} | zfs receive -Fuv ${zfs_target}"
            fi
            break

        else        

            # Collect our file list from 'zfs diff'.  Escape all \ so then make it through the
            # read statement. 

            debug "Collecting diff between ${zfs_source}@${prev_snap} ${zfs_source}@${snap}"

            zfs diff -FH ${zfs_source}@${prev_snap} ${zfs_source}@${snap} | \
                sed 's,\\,\\\\,g' > /tmp/copy_snap_filelist_$$

            file_count=`cat /tmp/copy_snap_filelist_$$|wc -l`

            notice "Blind backup of $file_count files started from ${zfs_source}"

            # As off OI_153a4, zfs diff does not report deleted files.  It only reports the directory
            # as modified.   We will need to compensate for this.

            while read line; do
                debug "Processing: $line"
                file_count=$(( file_count - 1))
                debug "Files remaining: $file_count"
                changetype=${line:0:1}
                filetype=${line:2:1}
                file=`echo "$line"|$cut -f 3`
                stripfolderlen=$(( ${#zfs_source} + 2 ))
                file="${file:$stripfolderlen}"
                source_file=`echo -n "/${zfs_source}/.zfs/snapshot/${snap}/${file}"`
                target_file=`echo -n "/${zfs_target}/${file}"`
                case $changetype in
                    'M')
                        modify_count=$(( modify_count + 1 ))
                        if [ "$filetype" == "/" ] && [ "$brokendiff" == "true" ]; then
                            # TODO: Check for deleted files
                            long_delete_files "$file" "$snap" "$prev_snap"
                        else
                            copy_file "$file" "$snap" 
                            case $? in
                                0)
                                    let "modify_bytes = $modify_bytes + $(stat -c %s "$source_file")"
                                    ;;
                                1)
                                    warning "Failed to modify \"$file\" from ${snap}. ZFS diff line was:"
                                    warning "\"$line\"" $TMP/blind_inc_error_$$
                                    warning_count=$(( warning_count + 1 ))
                                    ;;
                                2)
                                    delete_file "$file" "$filetype"
                                    warning_count=$(( warning_count + 1 ))
                                    ;;
                            esac           
                        fi
                        ;;
                    '+')
                        copy_count=$(( copy_count + 1 ))
                        copy_file "$file" "$snap" 
                        if [ $? -eq 0 ]; then    
                            let "copy_bytes = $copy_bytes + $(stat -c %s "$source_file")"
                        else
                            warning "Failed to copy \"$file\" from ${snap}. ZFS diff line was:"
                            warning "\"$line\"" $TMP/blind_inc_error_$$
                            warning_count=$(( warning_count + 1 ))
                        fi
                        ;;
                    '-')
                        delete_file "$file" "$filetype" 
                        if [ $? -eq 0 ]; then
                            delete_count=$(( delete_count + 1 ))
                        else
                            warning "Failed to delete \"$file\".  ZFS diff line was:"
                            warning "\"$line\"" $TMP/blind_inc_error_$$
                            warning_count=$(( warning_count + 1 ))
                        fi
                            
                        ;;
                    'R')
                        rename_file "$file" "$newname" "$filetype"
                        if [ $? -eq 0 ]; then
                            move_count=$(( move_count + 1 ))
                            newname=`echo "$line"|$cut -f 4`
                            newname="${newname:$stripfolderlen}"
                        else
                            warning "Failed to rename \"$file\" to \"$newname\".  ZFS diff line was:"
                            warning "\"$line\"" $TMP/blind_inc_error_$$
                            warning_count=$(( warning_count + 1 ))
                        fi
                        ;;
                esac

            done < "/tmp/copy_snap_filelist_$$"

            # At this point all the directories we touched need to have their mtime fixed.
            # Process the list backwards so we work from deepest to shallowest directory 

            tac /tmp/copy_snap_filelist_$$ > /tmp/copy_snap_rev_filelist_$$

            while read line; do
                filetype=${line:2:1}

                if [ "$filetype" == "/" ]; then
                    changetype=${line:0:1}
                    case $changetype in
                        "M"|"+")
                            file=`echo "$line"|$cut -f 3`
                            stripfolderlen=$(( ${#zfs_source} + 2 ))
                            file="${file:$stripfolderlen}"
                            if [ -z "$dflag" ]; then
                                debug "touch --reference=\"/${zfs_source}/.zfs/snapshot/${snap}/${file}\" \\ "
                                debug "\"/${zfs_target}/${file}\""
                                touch --reference="/${zfs_source}/.zfs/snapshot/${snap}/${file}" \
                                    "/${zfs_target}/${file}"
                            else
                                debug "Would: touch --reference=\"/${zfs_source}/.zfs/snapshot/${snap}/${file}\" \\ "
                                debug "\"/${zfs_target}/${file}\""
                            fi
                            ;;
                        "R")
                            file=`echo "$line"|$cut -f 4`
                            stripfolderlen=$(( ${#zfs_source} + 2 ))
                            file="${file:$stripfolderlen}"
                            if [ -z "$dflag" ]; then
                                debug "touch --reference=\"/${zfs_source}/.zfs/snapshot/${snap}/${file}\" \\ "
                                debug "\"/${zfs_target}/${file}\""
                                touch --reference="/${zfs_source}/.zfs/snapshot/${snap}/${file}" \
                                    "/${zfs_target}/${file}"
                            else
                                debug "Would: touch --reference=\"/${zfs_source}/.zfs/snapshot/${snap}/${file}\" \\ "
                                debug "\"/${zfs_target}/${file}\""
                            fi
                            ;;
                    esac
                fi
                            
            done < "/tmp/copy_snap_rev_filelist_$$"


            prev_snap="$snap"
            if [ "$copymode" != "blind" ]; then
                zfs snapshot ${zfs_target}@${snap} ; result=$?
                if [ "$result" -ne "0" ]; then
                    error "Failed to create snapshot ${zfs_target}@${snap}" 
                fi
            fi 


            # Output statistics from copy job

            let "total_files = $modify_count + $copy_count + $delete_count + $move_count"
            let "total_bytes = $modify_bytes + $copy_bytes"
            
        
            notice "${zfs_source} ****************************************"
            notice "${zfs_source} ** Blind Increment Totals             **"
            notice "${zfs_source} ****************************************"
            notice "${zfs_source} Total number of files: $total_files"
            notice "${zfs_source} Total transfer size: $(bytestohuman $total_bytes)"
            notice "${zfs_source} Number of files deleted: $delete_count"
            notice "${zfs_source} Number of files copied: $copy_count"
            notice "${zfs_source} Total copied size: $(bytestohuman $copy_bytes)"
            notice "${zfs_source} Number of files modified: $modify_count"
            notice "${zfs_source} Total modified size: $(bytestohuman $modify_bytes)"
            notice "${zfs_source} Number of files moved/rename: $move_count"
            notice "${zfs_source} Warning count: $warning_count"

            # rm /tmp/copy_snap_filelist_$$
        
        fi # "$copymode" == "zfs"

    fi

done # for snap in $net_snap_list
