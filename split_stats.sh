#! /bin/bash 

FILETOPARSE=$1
LOCPATH=$2
FILEOUTNAME=$(echo $FILETOPARSE |awk -F'.' '{print $1}')


split_file(){

	if [ "X${LOCPATH}" = "X" ] 
	then
		LOCPATH=`pwd`;
	fi 

	if [ -f "$FILETOPARSE" ] 
	then 
			echo "File ${LOCPATH}/${FILETOPARSE} OK";  
		else 
			echo " File ${LOCPATH}/${FILETOPARSE} does not exists";
	fi

	OLDDATE="NEW"
	
	while read STATS
	do

		CURRENTDATE=$(echo $STATS |awk -F',' '{print $1}')

		if [ $OLDDATE = "NEW" ] 
		then
			echo "Initializing ...."
			OLDDATE=$CURRENTDATE
		fi

		FILEOUT=""
				
		if [ $CURRENTDATE = $OLDDATE ] 
		then
			FILEOUT="${FILEOUTNAME}_${OLDDATE}.csv"
			#echo "."
		else
			FILEOUT="${FILEOUTNAME}_${CURRENTDATE}.csv"
			cat $LOCPATH/${FILEOUTNAME}_date.csv > $LOCPATH/$FILEOUT
			echo "Processing file ${FILETOPARSE} Date ${CURRENTDATE}"
		fi

		echo $STATS >> $LOCPATH/$FILEOUT 
		OLDDATE=$CURRENTDATE

	done < ${LOCPATH}/${FILETOPARSE}
}

print_help(){

echo " split_stats.sh <FILE_name> <PATH>"

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
	 