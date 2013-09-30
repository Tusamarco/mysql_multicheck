#! /bin/bash 

FILETOPARSE=$1
LOCPATH=$2
LINES=$3
FILEOUTNAME=$(echo $FILETOPARSE |awk -F'.' '{print $1}')


split_file(){

	if [ "X${LOCPATH}" = "X" ] 
	then
		LOCPATH=`pwd`;
	fi 

	if [ -f "$FILETOPARSE" ] 
	then 
			echo "File ${LOCPATH}/${FILETOPARSE} OK\n";  
			echo "Number of lines for chunk ${LINES}\n"
		else 
			echo " File ${LOCPATH}/${FILETOPARSE} does not exists";
	fi

	CURRENTCHUNK=0
	CURRENTLINE=0

	while read -r CSVFILE
	do

		if [ $CURRENTCHUNK = 0 ] 
		then
			echo "Initializing ...."
			CURRENTLINE=0
			FILEOUT="${FILEOUTNAME}_${CURRENTCHUNK}.csv"
		fi

		FILEOUT=""
				
		if [ $CURRENTLINE > $LINES ] 
		then			
			CURRENTLINE=0
			CURRENTCHUNK=$(($CURRENTCHUNK + 1))
			FILEOUT="${FILEOUTNAME}_${CURRENTCHUNK}.csv"
			echo $CSVFILE >> $LOCPATH/$FILEOUT 
			
		else
			FILEOUT="${FILEOUTNAME}_${CURRENTDATE}.csv"
			echo $CSVFILE >> $LOCPATH/$FILEOUT
		fi
		CURRENTLINE=$(($CURRENTLINE + 1))
		echo "Processing file ${FILEOUT} Date ${CURRENTDATE}"
	
	done < ${LOCPATH}/${FILETOPARSE}
}

print_help(){

echo " split_stats.sh <FILE_name> <PATH> <Number of lines for chunk>"

}

case $FILETOPARSE in
    -h|--help)
      print_help
      ;;
    *)
      echo "Running Split"
      split_file
      ;;
  esac 	
	 