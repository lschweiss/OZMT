#! /bin/bash
# ----------------------------------------------------------------------------
# @file color
# Color and format your shell script output with minimal effort.
# Inspired by Moshe Jacobson <moshe@runslinux.net>
# @author Alister Lewis-Bowen [alister@different.com]
# ----------------------------------------------------------------------------
# This software is distributed under the the MIT License.
#
# Copyright (c) 2008 Alister Lewis-Bowen
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
# ----------------------------------------------------------------------------

# 28/Dec/2012 Modified by Chip Schweiss
#
# Rebuilt function definitions to work with Bash installed on OpenIndiana 151a5
#
# Made 'color' a function instead of an executable script to be include in scripts 
# instead of being installed
#
# Changed all exits to returns

COLORS=( black red green yellow blue magenta cyan white );
NUM_COLORS=${#COLORS[@]};
EFFECTS=( nm normal bd bold ft faint it italic ul underline bk blink fb fastblink rv reverse iv invisible );
NUM_EFFECTS=${#EFFECTS[@]};

# Function: Help
# ----------------------------------------------------------------------------

color_help() {
	echo;
	echo "$(color bd)Color and format your shell script output with minimal effort.$(color)";
	echo;
	echo 'Usage:';
	echo "$(color bd)color$(color) [ $(color ul)effect$(color) ] [ [lt]$(color ul)fgcolor$(color) ] [ $(color ul)bgcolor$(color) ]";
	echo "$(color bd)color$(color) list";
	echo "$(color bd)color$(color) [ -h | --help ]";
	echo;
	echo 'where:';
	echo -n "$(color ul)fgcolor$(color) and $(color ul)bgcolor$(color) are one of ";
	for ((i=0;i<${NUM_COLORS};i++)); do
		echo -n "$(color ${COLORS[${i}]})${COLORS[${i}]}$(color) ";
	done;
	echo;
	echo -n "$(color ul)effect$(color) can be any of ";
	for ((i=0;i<${NUM_EFFECTS};i++)); do
		echo -n "$(color ${EFFECTS[${i}]})${EFFECTS[${i}]}$(color) ";
	done;
	echo;
	echo "Preceed the $(color ul)fgcolor$(color) with $(color bd)lt$(color) to use a light color."
	echo "$(color bd)color off$(color) or $(color bd)color$(color) resets to default colors and text effect.";
	echo "$(color bd)color list$(color) displays all possible color combinations.";
	echo;
	echo 'Examples:';
	echo '  echo "$(color ul)Underlined text$(color off)"';
	echo 'results in:';
	echo "  $(color ul)Underlined text$(color off)";
	echo;
	echo '  echo "Make $(color rv)this$(color nm) reverse video text$(color off)"';
	echo 'results in:';
	echo "  Make $(color rv)this$(color nm) reverse video text$(color off)";
	echo;
	echo '  echo "$(color white blue) White text on a blue background $(color)"';
	echo 'results in:';
	echo "  $(color white blue) White text on a blue background $(color)";
	echo;
	echo '  echo "$(color ltyellow green) lt prefix on the yellow text text $(color off)"';
	echo 'results in:';
	echo "  $(color ltyellow green) lt prefix on the yellow text text $(color off)";
	echo;
	echo '  echo "$(color bold blink red yellow) Blinking bold red text on a yellow background $(color)"';
	echo 'results in:';
	echo "  $(color bold blink red yellow) Blinking bold red text on a yellow background $(color)";
	echo;
	echo;
	echo -n "Note that results may vary with these standard ANSI escape sequences because of the different configurations of terminal emulators. ";
	echo;
	return 1;
}

# Function: List colors combinations
# ----------------------------------------------------------------------------

color_list() {

	echo;
	echo "$(color bd)These are the possible combinations of colors I can generate. ";
	echo "$(color nm)Since terminal color settings vary, $(color ul)the expected output may vary$(color).";
	echo;
	
	for ((bg=0;bg<${NUM_COLORS};bg++)); do
		echo "${COLORS[${bg}]}:";
			for ((fg=0;fg<${NUM_COLORS};fg++)); do
				echo -n "$(color ${COLORS[${fg}]} ${COLORS[${bg}]}) ${COLORS[${fg}]} $(color) ";
			done;
			echo;
		echo;
	done;
	
	return 1;
}

# Function: Test if color
# ----------------------------------------------------------------------------

_isColor () {
  if [ -n "$1" ]; then
  	local normalize=${1#lt};
	  for ((i=0;i<${NUM_COLORS};i++)); do
	    if [ "$normalize" = ${COLORS[${i}]} ]; then return 1; fi;
		done;
	fi;
	return 0;
}

# Function: Test if text effect
# ----------------------------------------------------------------------------

_isEffect () {
  if [ -n "$1" ]; then
	  for ((i=0;i<${NUM_EFFECTS};i++)); do
	    if [ "$1" = ${EFFECTS[${i}]} ]; then return 1; fi;
		done;
		if [ "$1" = off ]; then return 1; fi;
	fi;
	return 0;
}

# Function: Push code onto the escape sequence array
# ----------------------------------------------------------------------------

_pushcode () { 
	codes=("${codes[@]}" $1); 
}

color () {

    # Parse input arguments
    # ----------------------------------------------------------------------------
    
    if [[ "$1" = '-h' || "$1" = '--help' ]]; then color_help; return 0; fi;
    if [ "$1" = list ];                      then color_list; return 0; fi;
    if [[ "$1" = off || -z "$1" ]];          then 
    	echo -en '\033[0m';
    	return 0;
    fi;
    
    while (( "$#" )); do
    
    	_isColor $1
    	if [ $? -eq 1 ]; then
    		if [ "$FG" = '' ]; then 
    			FG=$1;
    		else
    		  if [ "$BG" = '' ]; then
    		  	BG=$1;
    		  else
    		  	error="I see more than two colors. Type color -h for more information.";
                return 1
    		  fi;
    		fi;
    	else
    		_isEffect $1
    		if [ $? -eq 1 ]; then
    			TE=("${TE[@]}" $1);
    		else
    			error="I don't recognize '$1'. Type color -h for more information.";
                return 1
    		fi;
    	fi;
    	
    	shift;
    	
    done;
    
    if [ "$error" != '' ]; then
    	echo $(color bold red)color: $error$(color); return 1;
    fi;
    
    # Insert text effects into the escape sequence
    # ----------------------------------------------------------------------------
    
    for ((i=0;i<${#TE[@]};i++)); do
    
    	case "${TE[${i}]}" in
    		nm | normal )      _pushcode 0;;
    		bd | bold )        _pushcode 1;;
    		ft | faint )       _pushcode 2;;
    		it | italic )      _pushcode 3;;
    		ul | underline)    _pushcode 4;;
    		bl | blink)        _pushcode 5;;
    		fb | fastblink)    _pushcode 6;;
    		rv | reversevideo) _pushcode 7;;
    		iv | invisible)    _pushcode 8;;
    	esac;
    
    done;
    
    # Insert foreground colors into the escape sequence
    # ----------------------------------------------------------------------------
    
    if [ `expr "$FG" : 'lt'` -eq 2 ]; then _pushcode 2; fi;
    
    case "$FG" in
    	black)   _pushcode 30;;
    	red)     _pushcode 31;;
    	green)   _pushcode 32;;
    	yellow)  _pushcode 33;;
    	blue)    _pushcode 34;;
    	magenta) _pushcode 35;;
    	cyan)    _pushcode 36;;
    	white)   _pushcode 37;;
    esac;
    
    # Insert background colors into the escape sequence
    # ----------------------------------------------------------------------------
    
    case "$BG" in
    	black)   _pushcode 40;;
    	red)     _pushcode 41;;
    	green)   _pushcode 42;;
    	yellow)  _pushcode 43;;
    	blue)    _pushcode 44;;
    	magenta) _pushcode 45;;
    	cyan)    _pushcode 46;;
    	white)   _pushcode 47;;
    esac;
    
    # Assemble and echo the ANSI escape sequence
    # ----------------------------------------------------------------------------
    
    for ((i=0;i<${#codes[@]};i++)); do
    	if [ "$seq" != '' ]; then seq=$seq';'; fi;
    	seq=$seq${codes[${i}]};
    done;
    
    echo -en '\033['${seq}m;
    
    return 0;
    
}
