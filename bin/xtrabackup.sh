#!/bin/bash

#set -euo pipefail
#set -o xtrace

###############################################################
# 		    !!! DO NOT CHANGE !!!		      #
###############################################################
###############################################################

DOCKERIMAGE="tw1nh3ad/xtrabackup"
DOCKERHUBURL="https://registry.hub.docker.com/v2/repositories/$DOCKERIMAGE"
BACKUPHOST="${2:-}"
BASEPATH=xtrabackup
LOGFILE=/$BASEPATH/log/mysql-backup-$BACKUPHOST-`date +%Y-%m-%d`.log
CONFDIR=$BASEPATH/conf
CONFFILE=$BACKUPHOST.cfg
DOCKBCKUPDIR=/$BASEPATH/backup
DOCKTMPDIR=/$BASEPATH/temp
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

###############################################################
###############################################################

function getinstldir {
	INSTALLDIR=$(dirname "$(readlink -f "$0")" | sed 's/\(.*\)\/xtrabackup\/bin/\1/g')
}


function getenv {
        . $INSTALLDIR/$CONFDIR/$CONFFILE
}


function checkdirs {
        mkdir -p $INSTALLDIR/$BASEPATH/{log,conf,backup,temp}
}


function checkconfig () {
	getinstldir
	if [ ! -e $INSTALLDIR/$CONFDIR/$CONFFILE ]; then
		config $1
	fi
}


function progfind() {
	getinstldir
        NAME=$1
        PROG=$(which $2)
        if [ -z $PROG ]; then
                echo -e "$2 not found\n"
                echo "Path to $2 binary:"
                read CUSTOM
                echo "$NAME=$CUSTOM" >> $INSTALLDIR/$CONFDIR/$CONFFILE
        else
                echo -e "Found $2 in $PROG"
                echo "$NAME=$PROG" >> $INSTALLDIR/$CONFDIR/$CONFFILE
        fi
}


function config {
	getinstldir
	if [ ! -f $INSTALLDIR/$CONFDIR/$CONFFILE ]; then
		echo -e "Config for $BACKUPHOST ${RED}not found!${NC}"
                echo -e "------------------\n"
		echo -e "${GREEN}>>>> HINT: Exit program with CTRL+C <<<<${NC}\n"
                echo -e "Starting wizard...\n"
		init
	else
		grep -Fxq "# Config complete" $INSTALLDIR/$CONFDIR/$CONFFILE 2>&1
	        if [ $? -eq 0 ];then
                        echo -e "Config for $BACKUPHOST ${GREEN}found!${NC}"
			echo -e "------------------\n"
			echo "Starting wizard again?"
	                while ! [[ "$recreate" =~ ^(y|n)$ ]]
		        do
               		       echo "[y]es or [n]o? [y|n]"
	                       read -r recreate
        	        done
			if [ $recreate == "n" ]; then
                        	exit 0
			else
				init
			fi
        	else
                        echo -e "Config for $BACKUPHOST ${RED}not complete!${NC}"
			echo -e "------------------\n"
                        echo "Starting wizard..."
			init $BACKUPHOST
		fi
	fi
}


function createdir () {
        DIR=
        CREATE=
        ERROR=
	DEF_DIR=$INSTALLDIR/$BASEPATH
        while [[ -z $DIR ]]; do
			echo "Where to store the $1 files on the host (outside docker) - use TAB completion: "
			READ="read -p '[ default = $DEF_DIR/$1 | ENTER for default ]: ' -e DIR"
			eval $READ
			: ${DIR:=$DEF_DIR/$1}
	done
        echo "$2=$DIR" >> $INSTALLDIR/$CONFDIR/$CONFFILE

	if [ -d $DIR ]; then
		echo -e "${GREEN}Directory $DIR already exists!${NC}\n"
	else
		echo -e "Create $DIR?"
		while ! [[ "$CREATE" =~ ^(y|n)$ ]]
		do
			echo "[y]es or [n]o? [y|n]"
			read -r CREATE
			if [ $CREATE == "y" ]; then
				mkdir -p $DIR
				if [ $? -ne 0 ]; then
					ERROR=1
				fi
				else
					break
				fi
		done

		if [[ $ERROR -eq 1 ]]; then
			echo -e "${RED}!!! Backup dir "$DIR" was not created !!!${NC}"
			echo -e "Please create ${GREEN}$DIR${NC} manually or rerun script to change!\n"
		else
			echo -e "${GREEN}Directory $DIR created!${NC}\n"
		fi
	fi
}


function createmenu() {
        OPT=
        select=0
        c=

        mapfile -t ITEM < <(printf ${LISTITEMS})
        for i in "${!ITEM[@]}"; do
                let c+=1
                echo -e "$c) ${ITEM[$i]}"
        done


        while [[ $select -eq "0" ]]; do
	        DEF=$2
	        IFS= read -p "Selection [press ENTER for $3]: " OPT
	        : ${OPT:=$DEF}
		if [ $1 == "Host" ]; then
			if [[ $OPT == "x" ]]; then
                	        exit 0
	                fi
		fi
	        if [[ $OPT =~ ^[1-9]+$ ]] && (( (OPT >=1) && (OPT <= "${#ITEM[@]}") )); then
        	        select=1
	                let OPT-=1
	                echo -e "$1 ${GREEN}${ITEM[$OPT]}${NC} selected\n"
	        else
	                echo -e "${RED}Wrong selection${NC}\n"
			if [ $1 == "Host" ]; then
				ScriptLoc=$(readlink -f "$0")
				exec $ScriptLoc list
			fi
	        fi
        done
}


function getimages {
	opt=
	select=0
	c=
	
	LISTITEMS="$(${CURL} -L -s "${DOCKERHUBURL}/tags?page_size=1024" | $JQ '."results"[]["name"]' | sed -e 's/^"//g; s/"/\\n/g' | tr -d "\n")"
	echo -e "\nThe following docker image tags were found on dockerhub; select one:"
        PS3="Use number to select an image or 'enter' to select default [default=latest] :"
}


function gethosts {
        getinstldir
        LISTITEMS=$(for i in $(cd $INSTALLDIR/$CONFDIR && ls *.cfg 2> /dev/null); do echo $i |  sed -e 's/\(.*\)\(.cfg\)/\1\\n/g' | tr -d '\n' ; done)
	if [ -z $LISTITEMS  ]; then
		echo -e "No config files found!\n"
		exit 0
	fi
        PS3="Use number to select host or 'enter' to exit: "
}


function listimages {
	getimages
        createmenu "TAG" "1" "latest"
	echo "DOCKERIMG=$DOCKERIMAGE:${ITEM[$OPT]}" >> $INSTALLDIR/$CONFDIR/$CONFFILE	
}


function removehost () {
        REMOVED=
        ERROR=
        echo -e "Remove host config file ${GREEN}"$INSTALLDIR/$CONFDIR/$1.cfg${NC}" ?\n"
        while ! [[ "$REMOVE" =~ ^(y|n)$ ]]
        do
                echo -e "[y]es or [n]o? [y|n]\n"
                read -r REMOVE
                if [ $REMOVE == "y" ]; then
                        HOSTBCKUPDIR=$(cat $INSTALLDIR/$CONFDIR/$1.cfg | grep HOSTBCKUPDIR | cut -d "=" -f2)
                        rm $INSTALLDIR/$CONFDIR/$1*
                        if [ $? -ne 0 ]; then
                                ERROR=1
                                echo -e "${RED}config file $INSTALLDIR/$CONFDIR/$1.cfg was not removed!${NC}\n"
                        else
                                REMOVED=1
                                echo -e "${GREEN}config file $INSTALLDIR/$CONFDIR/$1.cfg was removed!${NC}\n"
                        fi
                else
                        break
                fi
        done
}


function removebackups () {
        REMOVE=
        ERROR=
	for i in $1/mysql-backup-$2*; do
		if [ -f "$i" ]; then 
			EXISTS=1
			break
		fi
	done

	if [[ $EXISTS -eq 1 ]]; then
	        echo -e "Remove all backup/log files for host ${GREEN}$2${NC} in directory ${GREEN}$1${NC} ?\n"
        	ls -lsa $1/mysql-backup-$2*

	        while ! [[ "$REMOVE" =~ ^(y|n)$ ]]
	        do
	                echo -e "\n[y]es or [n]o? [y|n]\n"
	                read -r REMOVE
	                if [ $REMOVE == "y" ]; then
	                        rm $1/mysql-backup-$2*
	                        if [ $? -ne 0 ]; then
	                                echo -e "${RED}Backup files for host $2 were not removed!${NC}\n"
	                        else
	                                echo -e "${GREEN}Backup files for host $2 were removed!${NC}\n"
	                        fi
	                else
	                        break
	                fi
	        done
	fi
}


function remove {
        gethosts
        createmenu "Host" "x" "exit"
        removehost "${ITEM[$OPT]}"
        if [ ! -z $REMOVED ]; then
                removebackups "$HOSTBCKUPDIR" "${ITEM[$OPT]}"
        fi
}


function init {
	checkdirs
	trap 'echo SIGINT received && cleanup as trap handler' INT

	echo -e "Found installation in $INSTALLDIR"
	echo "BACKUPHOST=$BACKUPHOST" > $INSTALLDIR/$CONFDIR/$CONFFILE
	echo "INSTALLDIR=$INSTALLDIR" >> $INSTALLDIR/$CONFDIR/$CONFFILE
	
	progfind "NETCAT" "nc"
	progfind "JQ" "jq"
	progfind "CURL" "curl"
	
	getenv
	listimages

	DEF_MYSQL_PATH="/var/lib/mysql"
	echo "Path to mysql database directory"
	read -p "[ default = /var/lib/mysql | ENTER for default ] - use TAB completion: " -e MYSQL_PATH
	: ${MYSQL_PATH:=$DEF_MYSQL_PATH}
	echo -e "Directory set to ${GREEN}$MYSQL_PATH${NC}"
	echo "MYSQL_PATH=$MYSQL_PATH" >> $INSTALLDIR/$CONFDIR/$CONFFILE

	echo -e "\nHow to connect to the database?"

	MYSQL_AUTHTYPE=

	while ! [[ "$MYSQL_AUTHTYPE" =~ ^(c|f)$ ]] 
		do
			read -p 'using [c]redentials or [f]ile? [c|f]: ' MYSQL_AUTHTYPE
	done 

	echo "MYSQL_AUTHTYPE=$MYSQL_AUTHTYPE" >> $INSTALLDIR/$CONFDIR/$CONFFILE
	
	if [ $MYSQL_AUTHTYPE == "c" ]; then
		echo "MySQL username:"
		read MYSQL_USER
		echo "MYSQL_USER=$MYSQL_USER"  >> $INSTALLDIR/$CONFDIR/$CONFFILE
	
		echo "MySQL password:"
		read MYSQL_PASSWORD
		echo "MYSQL_PASSWORD=$MYSQL_PASSWORD" >> $INSTALLDIR/$CONFDIR/$CONFFILE

		echo -e "\nCreate mysql user with the following commands:\n"
		echo "-------------------------------------------------------------------"
		echo -e "CREATE USER ${GREEN}'$MYSQL_USER'@'172.17.0.%'${NC} IDENTIFIED BY ${GREEN}'$MYSQL_PASSWORD'${NC};"
		echo -e "GRANT ALL PRIVILEGES ON *.* TO ${GREEN}'$MYSQL_USER'@'172.17.0.%'${NC} WITH GRANT OPTION;"
		echo -e "-------------------------------------------------------------------\n"
		echo -e ">>>> Check if ${GREEN}'172.17.0.%'${NC} is the right docker network <<<<\n"
	
	else
		while [[ -z $MYSQL_CNF ]]; do
			read -p "Path to option file (+ path, e.g. /tmp/my-login.cnf - use TAB completion): " -e MYSQL_CNF
		done
		cp $MYSQL_CNF $INSTALLDIR/$CONFDIR/$BACKUPHOST-my-login.cnf
		if [ $? -ne "0" ]; then
			echo -e "${RED}File was not copied!${NC}"
			echo -e "!!! Please copy cnf file ${GREEN}'$MYSQL_CNF'${NC} to ${GREEN}$INSTALLDIR/$CONFDIR${NC} !!!\n"
			echo "MYSQL_CNF=/$CONFDIR/$BACKUPHOST-my-login.cnf" >> $INSTALLDIR/$CONFDIR/$CONFFILE
		else
			echo -e "${GREEN}$MYSQL_CNF was copied to $INSTALLDIR/$CONFDIR!${NC}\n"
			chmod 600 $INSTALLDIR/$CONFDIR/$BACKUPHOST-my-login.cnf
			echo "MYSQL_CNF=/$CONFDIR/$BACKUPHOST-my-login.cnf" >> $INSTALLDIR/$CONFDIR/$CONFFILE
		fi

	fi
	
	DEF_MYSQL_PORT="3306"
	echo "MySQL port"
	READ="read -p '[ default = $DEF_MYSQL_PORT | ENTER for default ]: ' MYSQL_PORT"
        while [[ $MYSQL_PORT == "" ]]; do
                eval $READ
		: ${MYSQL_PORT:=$DEF_MYSQL_PORT}
                if [[ ! "$MYSQL_PORT" =~ ^[-+]?[0-9]+$ ]]; then
                        echo -e "${RED}No valid input given!${NC}"
                        MYSQL_PORT=
                else
                        MYSQL_PORT=$MYSQL_PORT
                fi
        done

	echo -e "Port set to ${GREEN}$MYSQL_PORT${NC}\n"
        echo "MYSQL_PORT=$MYSQL_PORT" >> $INSTALLDIR/$CONFDIR/$CONFFILE


	createdir "backup" "HOSTBCKUPDIR"
	createdir "temp" "HOSTTMPDIR"

	DEF_RETENTION="3"
	echo "How many backups to save (retention)?"
        READ="read -p '[ default = $DEF_RETENTION | ENTER for default ]: ' RETENTION"
        while [[ $RETENTION == "" ]]; do
                eval $READ
                : ${RETENTION:=$DEF_RETENTION}
                if [[ ! "$RETENTION" =~ ^[-+]?[0-9]+$ ]]; then
                        echo -e "${RED}No valid input given!${NC}"
                        RETENTION=
                else
                        RETENTION=$RETENTION
                fi
        done

	echo -e "Retention set to ${GREEN}$RETENTION${NC}"
	echo "RETENTION=+$RETENTION" >> $INSTALLDIR/$CONFDIR/$CONFFILE
	echo -e "\n"		
	
	echo "# Config complete" >> $INSTALLDIR/$CONFDIR/$CONFFILE

	echo -e "config file ${GREEN}'$INSTALLDIR/$CONFDIR/$CONFFILE'${NC} for ${GREEN}$BACKUPHOST${NC} written:\n"
	
	cat $INSTALLDIR/$CONFDIR/$CONFFILE
	echo -e "\n"

	conntest_mysql
	conntest_docker
}


function cleanup {
	getinstldir
	echo -e "\nReally want to exit? - ${RED}config not complete!${NC}"
	while ! [[ "$abort" =~ ^(y|n)$ ]]
        do
		read -p "[y]es or [n]o? [y|n]: " -e abort
        done
	if [ $abort == "y" ]; then
		rm $INSTALLDIR/$CONFDIR/$CONFFILE
		echo -e ${GREEN}"$INSTALLDIR/$CONFDIR/$CONFFILE removed!"${NC}
		exit 1
	else
		abort=
		ScriptLoc=$(readlink -f "$0")
		exec $ScriptLoc config $BACKUPHOST
	fi
}


function core {
	getenv
	logger "$(basename $0) - started"

	if [ -f $DOCKBCKUPDIR/mysql-backup-$BACKUPHOST-`date +%Y-%m-%d`.tar.gz ] ; then
		rm $DOCKBCKUPDIR/mysql-backup-$BACKUPHOST-`date +%Y-%m-%d`.tar.gz
	fi

	echo "$(basename $0) - remove: $(find $DOCKBCKUPDIR/ -name "mysql-backup-*" -mtime $RETENTION -exec basename {} \;)" > $LOGFILE 2>&1
	echo "" >> $LOGFILE 2>&1
	logger "$(basename $0) - remove: $(find $DOCKBCKUPDIR/ -name "mysql-backup-*" -mtime $RETENTION -exec basename {} \;)"
	find $DOCKBCKUPDIR/ -name "mysql-backup-*" -mtime $RETENTION -exec rm -f {} \;  >> $LOGFILE 2>&1

	echo "" >> $LOGFILE 2>&1
	echo "$(basename $0) - backup databases" >> $LOGFILE 2>&1
	echo "" >> $LOGFILE 2>&1
	logger "$(basename $0) - backup databases"

	if [[ $MYSQL_AUTHTYPE == "f" ]]; then
		xtrabackup --defaults-extra-file=$MYSQL_CNF --backup -H $BACKUPHOST --target-dir=$DOCKTMPDIR >> $LOGFILE 2>&1
	else
		xtrabackup --user=$MYSQL_USER --password=$MYSQL_PASSWORD --backup -H $BACKUPHOST --target-dir=$DOCKTMPDIR >> $LOGFILE 2>&1
	fi

	echo "" >> $LOGFILE 2>&1
	echo "$(basename $0) - prepare backup" >> $LOGFILE 2>&1
	echo "" >> $LOGFILE 2>&1
	logger "$(basename $0) - prepare backup"
	xtrabackup --prepare --target-dir=$DOCKTMPDIR >> $LOGFILE 2>&1

	echo "" >> $LOGFILE 2>&1
	echo "$(basename $0) - compress backup" >> $LOGFILE 2>&1
	echo "" >> $LOGFILE 2>&1
	logger "$(basename $0) - compress backup"
	cd $DOCKTMPDIR
	tar -czvf $DOCKBCKUPDIR/mysql-backup-$BACKUPHOST-`date +%Y-%m-%d`.tar.gz . >> $LOGFILE 2>&1
	
	if [ $? -eq 0 ] ; then 
		echo "$(basename $0) - clean  mysql directory" >> $LOGFILE 2>&1
		logger "$(basename $0) - clean  mysql directory"
		rm -Rf $DOCKTMPDIR/*
	fi

	logger "$(basename $0) - finished"
	mv $LOGFILE $DOCKBCKUPDIR/
	echo "Backup process has finished"
}


function checktty {
	if [ -t 1 ] ; then 
		PARAM="-ti"
	else
		PARAM="-t"
	fi
}


function conntest_mysql {
	getinstldir
        getenv
        $NETCAT -z $BACKUPHOST $MYSQL_PORT
        if [ $? -ne 0 ]; then
                echo -e ${RED}"MySQL server on $BACKUPHOST with port $MYSQL_PORT is not running${NC}\n"
                exit 1
        else
                echo -e ${GREEN}"MySQL server on $BACKUPHOST with port $MYSQL_PORT is running${NC}\n"
        fi
}


function conntest_docker {
	getenv
	checktty
	docker run --rm $PARAM --name=xtrabackup-testmysql $DOCKERIMG nc -z $BACKUPHOST $MYSQL_PORT
	if [ $? -ne "0" ] ; then
		echo -e ${RED}"MySQL server on $BACKUPHOST with port $MYSQL_PORT is not accessible from docker${NC}\n"
                exit 1
        else
                echo -e ${GREEN}"MySQL server on $BACKUPHOST with port $MYSQL_PORT is accessible from docker${NC}\n"
        fi
}


function connect {
	checkconfig "$BACKUPHOST"
	getinstldir
	getenv
	checktty
	docker run --rm $PARAM --name=xtrabackup-connect -v $INSTALLDIR/$BASEPATH/:/xtrabackup -v $HOSTBCKUPDIR/:$DOCKBCKUPDIR -v $HOSTTMPDIR/:$DOCKTMPDIR -v $MYSQL_PATH/:/var/lib/mysql/ $DOCKERIMG

}


function backup {
	checkconfig "$BACKUPHOST"
	getinstldir
	conntest_docker
        getenv
	checktty
	docker run --rm $PARAM --name=xtrabackup -v $INSTALLDIR/$BASEPATH/:/xtrabackup -v $HOSTBCKUPDIR/:$DOCKBCKUPDIR -v $HOSTTMPDIR/:$DOCKTMPDIR -v $MYSQL_PATH/:/var/lib/mysql/ $DOCKERIMG /xtrabackup/bin/xtrabackup.sh core "$BACKUPHOST"
}


OPT=$1
case $OPT in
  config)
	echo "Checking config..."
        if [[ $2 == "" ]]; then
                echo "host/ip not given"
                exit 1
        fi
	config
	;;
 connect) 
  	echo "Connecting to container..."
	if [[ $2 == "" ]]; then
                echo "host/ip not given"
                exit 1
        fi
	connect
  	;;
  backup) 
  	echo "Starting backup process..." 
	if [[ $2 == "" ]]; then
		echo "host/ip not given"
		exit 1
	fi
	backup
  	;;
  remove)
        remove
        ;;

conntest)
	echo "Checking MySQL accessibility..."
        if [[ $2 == "" ]]; then
                echo "host/ip not given"
                exit 1
        fi
	conntest_mysql
	conntest_docker
	;;
    core) 
  	echo "Calling main backup function..." 
	core $BACKUPHOST
  	;;
   *) 
    echo "Bad argument!" 
    echo "Usage: $0 config <hostname|ip> | connect <hostname|ip> | backup <hostname|ip> | conntest <hostname|ip> | remove"
    echo "	config  : create config file"
    echo "	conntest: test accessibility of the mysql server"
    echo "	connect : connect to docker container with backup host settings"
    echo "	backup  : start backup"
    echo "	remove  : remove host & backup files"
    ;;
esac
