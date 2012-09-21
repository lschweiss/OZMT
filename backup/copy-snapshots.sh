#! /bin/bash

# copy-snapshots.sh

# Copy one or more snapshots to a second file system/folder.   

#
# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012  Chip Schweiss

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


# show program usage
show_usage() {
    echo
    echo "Usage: $0 -z {zfs_folder} -l {last_snapshot} -t {target_folder} -c {copy_mode}"
    echo "  -c {copy_mode} (normal, crypt, decrypt, zfs)"
    echo "  [-i] Incrementally handle all snapshots between first and last snapshots"
    echo "  [-t] trial mode.  Show what would happen."
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


zflag=
fflag=
lflag=
tflag=
cflag=
iflag=

copymode=""

while getopts iz:l:t:c: opt; do
    case $opt in
        z)  # ZFS folder 
            zflag=1
            zval="$OPTARG";;
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
            echo "Using incremental mode"
            iflag=1;;
        ?)  # Show program usage and exit
            show_usage
            exit 1;;
        :)  # Mandatory arguments not specified
            echo "Option -$OPTARG requires an argument."
            exit 1;;
    esac
done

# Check supplied options validity

if [ "$copymode" == "" ]; then
    copymode="normal"
fi

case $copymode in
    "normal")
        echo "No encryption selected" ;;
    "zfs")
        echo "ZFS Send/Receive mode selected" ;;
    "crypt")
        echo "File level encryption selected" ;;
    "decrypt")
        echo -n "Enter key/passphrase for gpg private key: "
        read -s $key
        ;;
    *)
        echo "ERROR: no valid copy mode.   Must specify (normal,crypt,decrypt)" >&2
        ;;
esac


if [ "$sflag" == "1" ] && [ "$copymode" != "normal" ]; then
    echo "ERROR: ZFS Send/Receive mode specified, but copy mode not set to normal!" >&2
    exit 1
fi

zfs list -H -o name $zval 1>/dev/null 2>/dev/null; result=$?
if [ $result -ne 0 ]; then
    echo "ERROR: Source ZFS folder: $zval does not exist!" >&2
    exit 1
else
    zfs_source="$zval"
fi

zfs list -H -o name $tval 1>/dev/null 2>/dev/null; result=$?
if [ "$tval" == "" ] || [ $result -ne 0 ]; then
    echo "ERROR: Target ZFS folder $zval does not exist!" >&2
    exit 1
else
    zfs_target="$tval"
fi


# Confirm we are using the correct snapshot for the target

last_target_snapname=`zfs list -t snapshot -H -o name,creation -s creation | \
                        grep -v "aws-backup_" | \
                        grep "^${zfs_target}@" | \
                        cut -f 1 | \
                        tail -n 1 | cut -d "@" -f 2`

echo "Last snapshot of ${zfs_target} is: $last_target_snapname"

if [ "$last_target_snapname" == "" ]; then
    echo "Working from the root snapshot."
    first_snap="root"
else
    echo "Working from the last target snapshot: $last_target_snapname"
    first_snap="$last_target_snapname"
fi

if [ "$last_snap" == "latest" ]; then
    echo "Finding latest snapshot of $zfs_source"
       last_snap=`zfs list -t snapshot -H -o name,creation -s creation | \
                        grep "^${zfs_source}@" | \
                        cut -f 1 | \
                        tail -n 1 | cut -d "@" -f 2`
    echo "Found ${zfs_source}@${last_snap} as the latest snapshot."
fi

zfs list -t snapshot -H -o name | grep -q "^${zfs_source}@${last_snap}"; result=$?
if [ $result -ne 0 ]; then
    echo "ERROR: Last snapshot ${zfs_source}@${last_snap} does not exist!" >&2
    exit 1
fi


if [ "$last_snap" == "$last_target_snapname" ]; then
    echo "NOTICE: Nothing to do all snaps are copied!" 
    exit 0
fi
    
echo "Processing job..."

if [ "$iflag" == "1" ]; then
    # We are processing an incremental set
    # Collect all intermediate snapshots in order of snapshot creation
    echo -n "Collecting intermediate snapshots..."
    gross_snap_list=`zfs list -t snapshot -H -o name,creation -s creation | \
                        grep "^${zfs_source}@" | \
                        cut -f 1 | \
                        cut -d "@" -f 2`
    echo "Done."
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
        echo "No intermediate snaps found."
        echo "First snap: ${first_snap}"
        echo "Last snap: ${last_snap}"
        iflag=0
    else 
        echo "Intermediate snaps are: "
        for snap in $net_snap_list; do
            echo "  $snap"
        done
        echo
    fi
else
    net_snap_list="$last_snap"
fi



copy_file () {

    # 'zfs diff' will escape many chacters as octal representations.  Passing through
    # echo will process these escapes to characters.
    local file=`echo -n "/${zfs_source}/.zfs/snapshot/${snap}/${1}"`
    local filedest=`echo -n "/${zfs_target}/${1}"`
    local filehash=`echo -n "/${zfs_target}/${1}.sha256"`
    local filetype=`stat --printf="%F" "$file"`
    local fileuid=`stat --printf="%u" "$file"`
    local filegid=`stat --printf="%g" "$file"`
    local filemode=`stat --printf="%a" "$file"`

    if [ "$filetype" == "regular empty file" ]; then
        filetype="regular file"
    fi

    case $filetype in 
        "regular file")
            # Update the hash
            if [ "$filesign" == "true" ]; then
                sha256sum "$file" > "$filehash"
            fi
            case $copymode in
                "normal")
                    rsync -a --sparse "$file" "$filedest"
                    ;;
                "crypt")
                    cryptdest="${filedest}.gpg"
                    # If the file was modified gpg will ask to overwrite.  We will
                    # make sure a previous copy is not there first.
                    if [ -e "$cryptdest" ]; then
                        rm -f "$cryptdest"
                    fi
                    gpg -r "CTS Admin" --compress-algo bzip2 --output "$cryptdest" --encrypt "$file"
                    sha256sum "$file" > "${filedest}.sha256"
                    filedest="$cryptdest"
                    ;;
                "decrypt")
                    # Remove .gpg on destination
                    # Check sha256 sum
                    namelen=$(( ${#filedest} - 4 ))
                    filedest="${filedest:0:$namelen}"
                    namelen=$(( ${#file} - 4 ))
                    sigfile="${file:0:$namelen}.sha256"
                    gpg -r "CTS Admin" --output "$filedest" --decrypt "$file"
                    sourcesha256=`cat ${sigfile}.sha256|cut -f 1`
                    destsha256=`sha256sum "$filedest"|cut -f 1`
                    if [ "$sourcesha256" != "$destsha256" ]; then
                        echo "ERROR: SHA256 sum of decrypted file $filedest does not match saved" >&2
                        echo "sum in file $sigfile." >&2
                    fi
                    ;;
            esac
            ;;
        "symbolic link")
            cp -a "$file" "$filedest"
            ;;
        "directory")
            mkdir -p "$filedest"
            ;;
        "character special file")
            echo "Character special file encountered: $file"
            cp -a "$file" "$filedest"
            ;;
        "block special file")
            echo "Block special file encountered: $file"
            cp -a "$file" "$filedest"
            ;;
    esac

    # If ACLs are used this will need to be upgraded
    if [ "$filetype" == "regular file" ] && [ "$copymode" == "crypt" ] || [ "$filetype" == "directory" ]; then
        chown ${fileuid}.${filegid} "$filedest"
        chmod ${filemode} "$filedest"
        touch --reference="${file}" "$filedest"
    fi

}

rename_file () {

    # 'zfs diff' will escape many chacters as octal representations.  Passing through
    # echo will process these escapes to characters.
    local file=`echo -n "$1"`
    local newname=`echo -n "$2"`
    local filetype="$3"

    case $copymode in
        "normal")
            mv "/${zfs_target}/$file" "/${zfs_target}/$newname"
            ;;
        "crypt")
            if [ "$filetype" == "F" ]; then
                mv "/${zfs_target}/${file}.gpg" "/${zfs_target}/${newname}.gpg"
                mv "/${zfs_target}/${file}.sha256" "/${zfs_target}/${newname}.sha256"
            fi
            ;;
        "decrypt")
            if [ "$filetype" == "F" ]; then
                local filelen=$(( ${#file} - 4 ))
                file="${file:0:$filelen}" 
                local newlen=$(( ${#newname} - 4 ))
                newname="${newname:0:$newlen}"
                mv "/${zfs_target}/$file" "/${zfs_target}/$newname"
            fi
            ;;
    esac

}

delete_file () {

    local file="$1"
    local filetype="$2"
    
    if [ "$filetype" == "/" ]; then
        rm -rf /${zfs_target}/${file}
    else
        case $copymode in
            "normal")
                # If the directory was also deleted it would be 
                # executed first and our files will not be found
                # We will dump error output.
                rm "/${zfs_target}/${file}" 2> /dev/null
                rm "/${zfs_target}/${file}.sha256" 2> /dev/null
                ;;
            "crypt")
                rm "/${zfs_target}/${file}.gpg" 2> /dev/null
                rm "/${zfs_target}/${file}.sha256" 2> /dev/null
                ;;
            "decrypt")
                local filelen=$(( ${#file} - 4 ))
                file="${file:0:$filelen}"
                rm "/${zfs_target}/${file}" 2> /dev/null
                ;;
        esac
    fi
    
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
    ls -1 -a "/${zfs_source}/.zfs/snapshot/${snap}/${workdir}" | grep -v "." | grep -v ".." > /tmp/copy_snap_delete_files_current_$$
    ls -1 -a "/${zfs_source}/.zfs/snapshot/${previous}/${workdir}" | grep -v "." | grep -v ".." > /tmp/copy_snap_delete_files_previous_$$

    # Check each file if has been removed but not renamed which is handled individually.
    while read file; do
        cat /tmp/copy_snap_delete_files_current_$$|grep -q -x "$file";result=$?
        if [ "$result" -ne "0" ]; then
            # The file is no longer in the directory
            # Has this file been renamed?
            cat /tmp/copy_snaplist_$$|grep -q "R\s+F\s+/${zfs_source}/${workdir}${file}\s/.+";result=$?
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
    echo "Processing $snap"
    echo

    if [ "$first_snap" == "root" ] && [ "$base_snap_complete" != "true" ]; then
        if [ "$copymode" == "zfs" ]; then
            # Do the zfs send/receive to the target folder
            # Since zfs send/receive can handle a complete stream with all snapshots
            # We will do this in one operation to copy all snapshots.
            zfs send -R ${zfs_source}@${last_snap} | zfs receive -F -vu ${zfs_target}
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
            echo "Creating target snapshot: ${zfs_target}@${snap}"
            zfs snapshot ${zfs_target}@${snap} ; result=$?
            if [ "$result" -ne "0" ]; then
                echo "ERROR: Failed to create snapshot ${zfs_target}@${snap}" >&2
            fi
            base_snap_complete="true"
        fi
    else
        if [ "$copymode" == "zfs" ]; then
            # Do the zfs send/receive to the target folder

            echo "zfs send -R -i ${zfs_source}@${first_snap} ${zfs_source}@${last_snap} | zfs receive -Fuv ${zfs_target}"
            zfs send -R -i ${zfs_source}@${first_snap} ${zfs_source}@${last_snap} | zfs receive -Fuv ${zfs_target}
            break

        else        

            # Collect our file list from 'zfs diff'.  Escape all \ so then make it through the
            # read statement. 

            zfs diff -FH ${zfs_source}@${prev_snap} ${zfs_source}@${snap} | \
                sed 's,\\,\\\\,g' > /tmp/copy_snap_filelist_$$

            # As off OI_153a4, zfs diff does not report deleted files.  It only reports the directory
            # as modified.   We will need to compensate for this.

            while read line; do
                changetype=${line:0:1}
                filetype=${line:2:1}
                file=`echo "$line"|cut -f 3`
                stripfolderlen=$(( ${#zfs_source} + 2 ))
                file="${file:$stripfolderlen}"
                case $changetype in
                    'M')
                        if [ "$filetype" == "/" ] && [ "$brokendiff" == "true" ]; then
                            # TODO: Check for deleted files
                            long_delete_files "$file" "$snap" "$prev_snap"
                        else
                            copy_file "$file" "$snap"
                        fi
                        ;;
                    '+')
                        copy_file "$file" "$snap"
                        ;;
                    '-')
                        delete_file "$file" "$filetype"
                        ;;
                    'R')
                        newname=`echo "$line"|cut -f 4`
                        newname="${newname:$stripfolderlen}"
                        rename_file "$file" "$newname" "$filetype"
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
                            file=`echo "$line"|cut -f 3`
                            stripfolderlen=$(( ${#zfs_source} + 2 ))
                            file="${file:$stripfolderlen}"
                            touch --reference="/${zfs_source}/.zfs/snapshot/${snap}/${file}" "/${zfs_target}/${file}"
                            ;;
                        "R")
                            file=`echo "$line"|cut -f 4`
                            stripfolderlen=$(( ${#zfs_source} + 2 ))
                            file="${file:$stripfolderlen}"
                            touch --reference="/${zfs_source}/.zfs/snapshot/${snap}/${file}" "/${zfs_target}/${file}"
                            ;;
                    esac
                fi
                            
            done < "/tmp/copy_snap_rev_filelist_$$"


            prev_snap="$snap"
            zfs snapshot ${zfs_target}@${snap} ; result=$?
            if [ "$result" -ne "0" ]; then
                echo "ERROR: Failed to create snapshot ${zfs_target}@${snap}" >&2
            fi
        
        fi # $copymode

    fi

done # for snap in $net_snap_list
