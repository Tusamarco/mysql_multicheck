#! /usr/bin/perl
#######################################
#
# Mysql Local Check Multiple v 2 (2011)
#
# Author Marco Tusa 
# Copyright (C) 2001-2003, 2013
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

#######################################
use Sys::Statistics::Linux;
use File::Spec;
use visualization;
use mysqlindicator;
use Time::Local;
use IO::Handle;
use Math::BigInt;
use commonPrintFormat;
use Chart::Graph qw(&gnuplot);
use strict;
use warnings;
use sigtrap;
use Cwd;
use commonDBFunctions;
use commonFunctions;
use ConfigIniSimple;
use Scalar::Util qw(looks_like_number);

use Term::ANSIScreen qw(cls);
#use Win32::Console::ANSI;



use DBI;
use Getopt::Long;
$Getopt::Long::ignorecase = 0;


#WIN
#my $CONSOLE = Win32::Console->new(STD_OUTPUT_HANDLE);

#
#$CONSOLE->Alloc();
#$CONSOLE->Cls();
#$CONSOLE->Display;
#$CONSOLE->Cls( $FG_WHITE | $BG_GREEN );

#Unix
my $terminal = Term::ANSIScreen->new;

#Window
#my $terminal = Win32::Console::ANSI->new;
#
#$terminal->clrscr();

my $html = 0;
my $Param = {};
my $user = "root";
my $pass = "mysql";
my $help = '';
my $host = '' ;
my $outfile;
my $genericStatus = '&green';
my $finalreport = "";
my $strMySQLVersion="";
my $historyListSize = 60;
my $InnodbVersion = "base";
my $innodb_version = undef;
my $innodb_advance = 1;
my $CurrentTime;
my $CurrentDate;
my $baseSP;
my $FILEOUT;
my $FILEOUTSTATS;
my $debug = 0 ;
my $MysqlIndicatorContainer ;
my $healtonscreen=0;
my $innodbMethod=3;
my $systatHeader="";
my $systatdata="";
my %processState;
my %processCommand;

my $AIB_Cacti= "";
#Innodb Report section
# adding string to this will NOT automatically add the variable
# the value needs to be trigged in the function get_innodb_status


$Param->{user}       = '';
$Param->{password}   = '';
$Param->{host}       = '';
$Param->{port}       = 3306;
$Param->{debug}      = 0;
$Param->{wrmethod}   = 0;
$Param->{session}    = 0;
$Param->{interval}    = 2; 
$Param->{loop}   = 0;
$Param->{healtonscreen}=0;
$Param->{historylistsize} = $historyListSize;
$Param->{headers}   =0;
$Param->{creategnuplot}=0;
$Param->{sysstats}   = 0;
$Param->{sysstatsinit}   = 0;
$Param->{doGraphs}   = 0;
$Param->{processlist} = 0;
$Param->{stattfile} = '';
$Param->{OS} = $^O;
#$Param->{outfile};

# ============================================================================
# converting to object
# Indicator values
# Indicator_History = x     The lenght of the main object containing the parameters 
# Indicator_FlushTime =     The frequency the main object containing the parameters needs to flush and reset
# Indicator_FIFOMode =      The if like that the container will flush the last object and free the first one (Indicator_FlushTime) will be ignored


# Variable section for  looping values
#Generalize object for now I have conceptualize as:
# Indicator (generic container)
# Indicator->{category}     This is the category for the value (query cache; traffic; handlers; innodb_rows; etc)
# Indicator->{parent}       If the parameter is bounded to another then is reported (you cannot have rowinsert without insert and so on)
# Indicator->{exectime}     The time of the request (system value);
# Indicator->{requestid}    The unique Id for the whole set of data collected (incremental number) 
# Indicator->{current}=0;   The current value
# Indicator->{previous}=0;  The previous value (I thin I will not use this doesn't make too much sense)
# Indicator->{average}=0;   The average calculated on the base of the EPOCH
# Indicator->{max}=0;       The max absolute value
# Indicator->{min}=0;       The min absolute value must be != 0
# ============================================================================


# ============================================================================
#+++++ INITIALIZATION
# ============================================================================

if (
    !GetOptions(
        'user|u:s'       => \$Param->{user},
        'password|p:s'   => \$Param->{password},
        'host|H:s'       => \$host,
        'port|P:i'       => \$Param->{port},
        'interval|i:i'   => \$Param->{interval},
        'loop|x:i'       => \$Param->{loop},        
        'html|l:i'       => \$Param->{html},
        'outfile|o:s'    => \$outfile,
        'debug|e:i'      => \$Param->{debug},
        'wrmethod|w:i'   => \$Param->{wrmethod},
        'getsession|s:i' => \$Param->{session},
	'healtonscreen:s'=> \$Param->{healtonscreen},
        'headers:i'    	 => \$Param->{headers},
        'creategnuplot:i'=> \$Param->{creategnuplot},
        'sysstats:i'     => \$Param->{sysstats},
        'processlist|C:i'=> \$Param->{processlist},
	'innodb:i'  	 => \$innodbMethod,
	'doGraphs:i'	 => \$Param->{doGraphs},
        'help|h:s'       => \$Param->{help}

    )
  )
{
    ShowOptions();
    exit(0);
}
else{
     $Param->{host} = URLDecode($host);
     if(defined $outfile){
          $Param->{outfile} = URLDecode($outfile);
     }
}

if ( defined $Param->{help}) {
    ShowOptions();
    exit(0);
}

if($Param->{debug}){
    debugEnv();
}

# $dsn = "DBI:mysql:database=mysql;mysql_socket=/tmp/mysql.sock";
# my $dbh = DBI->connect($dsn, 'pythian','22yr106xhsy96f4');

my $dsn  = "DBI:mysql:host=$Param->{host};port=$Param->{port}";
if(defined $Param->{user}){
	$user = "$Param->{user}";
}
if(defined $Param->{password}){
	$pass = "$Param->{password}";
}
if(defined $Param->{html}){
	$html = $Param->{html};
}

#my $user = "check";
#my $pass = "g33k!";

my $SPACER = "    ";


if( defined $Param->{outfile}
   && $Param->{headers} == 0
   ){
    my $fullname = $Param->{outfile};
    my $filename = "sysstat_";
    my $volume;
    my $directories;
    my $file;
    ($volume, $directories, $file) = File::Spec->splitpath($fullname);
    $Param->{stattfile} = $directories.$filename.$file;

    #my $basename = basename($fullname, my @suffixlist);
    #my $dirname  = dirname($fullname);    
    
       
    if( $Param->{wrmethod} == 0){

         open  $FILEOUT , '>>', $Param->{outfile};
         $FILEOUT->autoflush(1);

         if($Param->{sysstats} eq "1"){
            open  $FILEOUTSTATS , '>>', $directories.$filename.$file;
            $FILEOUTSTATS->autoflush(1);
            
         }
        #if (open $$FILEOUT, '>>', $Param->{outfile}){
        #}
    }
    else
    {
         open $FILEOUT , ">", $Param->{outfile};
         $FILEOUT->autoflush(1);

         if($Param->{sysstats} eq "1"){
            open  $FILEOUTSTATS , '>', $directories.$filename.$file;;
            $FILEOUTSTATS->autoflush(1);
            
         }

        #if (open $$FILEOUT, '>', $Param->{outfile}){
        #}
    }
}
else{
    my $volume;
    my $directories;
    my $file;
    my $filename = "sysstat_";

    ($volume, $directories, $file) = File::Spec->splitpath($Param->{outfile});
    $Param->{stattfile} = $directories.$filename.$file;

}
if($Param->{"OS"} ne "linux"){
    $Param->{sysstats} = 0;
}

if($Param->{sysstats} == 1){
    my $mysqlpid=0;

    if($Param->{"OS"} eq "linux"){
        $mysqlpid = `pidof mysqld`;
        $mysqlpid =~ s/\n//g;
    }
    elsif($Param->{"OS"} eq "MSWin32"){
        my @procs = `tasklist`;
        print "";
    }

    if( $mysqlpid > 0){
    $Param->{hwsys_stats} = Sys::Statistics::Linux->new(
	sysinfo   => 0,
        cpustats  => 1,
        procstats => 1,
        memstats  => 1,
        pgswstats => 1,
        netstats  => 1,
        sockstats => 0,
        diskstats => 1,
        diskusage => 1,
        loadavg   => 0,
        filestats => 0,
        processes =>{init => 1, pids=> [$mysqlpid]}
	);
    }
    else{
    $Param->{hwsys_stats} = Sys::Statistics::Linux->new(
	sysinfo   => 0,
        cpustats  => 1,
        procstats => 1,
        memstats  => 1,
        pgswstats => 1,
        netstats  => 1,
        sockstats => 0,
        diskstats => 1,
        diskusage => 1,
        loadavg   => 0,
        filestats => 0,
        processes =>0
	);
	
    }
    
    
}

# ============================================================================
# END Initialization
# ============================================================================



sub finalFlush(){
    if( !defined $Param->{outfile}){
               #print $finalreport ;
               #$CONSOLE->Flush;
               
               
               #WIN
               #$CONSOLE->Cls();
               #promptGenericWin($finalreport, $CONSOLE);
               
               
               promptGenericUnix($finalreport, $terminal);
     
    }
    else{
                #print $$FILEOUT $finalreport ;
                 promptGenericUnix($finalreport, $terminal);
                
    }
    return;
}

# ============================================================================
# sub initIndicators($$)
# Initizialization of the mysql_indicato needs to be done separatly
# - status
# - Innodb
# currently Innodb I am doing two different method not sure yet which is the best one
# so will keep both then will decide
#
# In the assignment I can define if active or not (Right now  I get acive by presence so always yes if the parameter name is in the list)
# while I read from list the parameter(s) in sequence (for future expansion).
# currently:
#	- 1) par name (active|inactive)
#	- 2) 0|1 value for calculated or not
# if calculate then the value is an absolute alway grwoing value and I have to calculate it against the previous
#---------------------------
# FIltering for consistency is done by reading the STATUS variables for the "Standard" status value
# but for MySQL Innod or other specific values I need to set special operation when I have to read from Innodb Status or other,
# and add the related functions as well
# ============================================================================

sub initIndicators($$){
    my $Param = shift;
    my $status = shift;
    my %KeyStatus = %{$status};
    my $arraySize = $Param->{historylistsize};
    my %MysqlIndicatorContainer ;
    my $icounter=0;
    my @innodbValues ;
    my %filterSP; 
    load_statusparameters();
    
    my @baseSPar = split('\,', $baseSP);
    my @innodbParamCacti = split('\,',$AIB_Cacti);
    
    my %KeyinnodbParamCacti ;
    #my @slaveProfileValues = ('Seconds_Behind_Master','ProfId','ProfUser','ProfHost','Profdb','ProfCommand','ProfTime','ProfState','ProfInfo');
    #active my $slaveSP=",Seconds_Behind_Master|0,ProfId|0,ProfTime|0,ProfState|0";
    
#    "Id: 5 
#   User: root
#   Host: localhost
#     db: NULL
#Command: Query
#   Time: 0
#  State: NULL
#   Info: show full processlist"

    # ============================================================================
    #Loading the FULL list of the variables I want to use (defined at the end now, but it will be a list externally defined)
    for($icounter = 0 ; $icounter <= $#baseSPar; $icounter++){
        my @parameters = split(/\|/,$baseSPar[$icounter]);
        if($#parameters > 0){
            $filterSP{$parameters[0]}->{status}="active";
            $filterSP{$parameters[0]}->{_calculated}=$parameters[1];
        }
        else{
            $filterSP{$baseSPar[$icounter]}->{status}="active";
            $filterSP{$baseSPar[$icounter]}->{_calculated}="1";
        }
        #$filterSP{$baseSPar[$icounter]}->{status}="active";    
    }
    # ============================================================================
    
    # ============================================================================
    #List for validation (instead of the STATUS list ) for Innodb Method 1
     if($InnodbVersion eq "base"){
        @innodbValues = ('innodb_history','innodb_mutexspin','innodb_mutexrounds','innodb_mutexoswait','innodb_merged');
     }
     else{
        @innodbValues = ('innodb_history','innodb_mutexspin','innodb_mutexrounds','innodb_mutexoswait',
                         'innodb_IBmergedinsert',
                         'innodb_IBmergedmarkdelete',
                         'innodb_IBmergedelete',
                         'innodb_IBdiscardinsert',
                         'innodb_IBdiscarddeletemark',
                         'innodb_IBdiscarddelete',
                         'innodb_IBsize',
                         'innodb_IBfreelistsize',
                         'innodb_IBsegsize',
                         'innodb_IBmerges',
                         'innodb_IBDatabasepages',
                         'innodb_IBDatabasepagesold',
                         'innodb_IBPagesread',
                         'innodb_IBPagesreadcreated',
                         'innodb_IBPagesreadwritten',
                         'innodb_IBPagesreadhaed',
                         'innodb_IBPagesreadhaedevicted',
			 'innodb_IBPendingwriteLRU',
			 'innodb_IBPendingwriteFlush',
			 'innodb_IBPendingwriteSinglepage',
                         'innodb_IBLogSequenceN',
                         'innodb_IBLogFlushN',
                         'innodb_IBLogLastCheckPN',
                         'innodb_IBLogPendingCheckpWN'                        
                         ); 
     }
     # ============================================================================
    
    # ============================================================================
    #initialize Innodb method 2
    for($icounter = 0 ; $icounter <= $#innodbParamCacti; $icounter++){
        my @parameters = split(/\|/,$innodbParamCacti[$icounter]);
        if($#parameters > 0){
            $filterSP{$parameters[0]}->{status}="active";
            $filterSP{$parameters[0]}->{_calculated}=$parameters[1];
        }
        else{
	    if (defined $innodbParamCacti[$icounter] && $innodbParamCacti[$icounter] ne ""){
		$filterSP{$innodbParamCacti[$icounter]}->{status}="active";
		$filterSP{$innodbParamCacti[$icounter]}->{_calculated}="1";
	    }
        }
	if (defined $innodbParamCacti[$icounter] && $innodbParamCacti[$icounter] ne ""){
	    $KeyinnodbParamCacti{$parameters[0]} = $innodbParamCacti[$icounter];
	}
        #$filterSP{$baseSPar[$icounter]}->{status}="active";    
    }
    # ============================================================================
    
     
    # ============================================================================
    #INITIALIZE all the Indicators
    
    #do it for time
    {
	my $indicator = eval { new mysqlindicator(); }  or die ($@);
	$indicator->{name} = "execution_date";
	$MysqlIndicatorContainer{execution_date}= $indicator;
    }
    
    {
	my $indicator = eval { new mysqlindicator(); }  or die ($@);
	$indicator->{name} = "execution_time";
	$MysqlIndicatorContainer{execution_time}= $indicator;
    }

    #do InnoDB then others
    #Method 1 
    foreach my $key (sort @innodbValues)
    {

        if( defined $filterSP{$key}  ){
            my $indicator = eval { new mysqlindicator(); }  or die ($@);

            $indicator->{name} = $key;
	    $indicator->{_calculated} = $filterSP{$key}->{_calculated};
            $MysqlIndicatorContainer{$key}= $indicator;

        }
        
    }


    #do InnoDB then others
    #Method 2 
    foreach my $key (sort keys %KeyinnodbParamCacti)
    {

        if( defined $filterSP{$key}  ){
            my $indicator = eval { new mysqlindicator(); }  or die ($@);

            $indicator->{name} = $key;
	    $indicator->{_calculated} = $filterSP{$key}->{_calculated};

            $MysqlIndicatorContainer{$key}= $indicator;
        }
        
        
    }
    
    #Now Load the indicators coming from the STATUS
    foreach my $key (sort keys %KeyStatus)
    {

        if( defined $filterSP{$key} ){
            my $indicator = eval { new mysqlindicator(); }  or die ($@);

            $indicator->{name} = $key;
            $indicator->{_calculated} = $filterSP{$key}->{_calculated};
            $MysqlIndicatorContainer{$key}= $indicator;
            if($debug > 0){print "Orig_key = ".$key." container = ".$indicator->{name}."|".$indicator->{_calculated}."\n";}
        }
        
    }


    if($Param->{processlist} eq 1){
        #Now Load the indicators coming from the Processlist STATE
        foreach my $key (sort keys %processState)
        {
                my $indicator = eval { new mysqlindicator(); }  or die ($@);
    
                $indicator->{name} = "Proc_State_".$key;
                $indicator->{_calculated} = 0;
                $MysqlIndicatorContainer{"Proc_State_".$key}= $indicator;
                if($debug > 0){print "Orig_key = ".$key." container = ".$indicator->{name}."|".$indicator->{_calculated}."\n";}
            
        }
    
    
        #Now Load the indicators coming from the Processlist STATE
        foreach my $key (sort keys %processCommand)
        {
                my $indicator = eval { new mysqlindicator(); }  or die ($@);
    
                $indicator->{name} = "Proc_Command_".$key;
                $indicator->{_calculated} = 0;
                $MysqlIndicatorContainer{"Proc_Command_".$key}= $indicator;
                if($debug > 0){print "Orig_key = ".$key." container = ".$indicator->{name}."|".$indicator->{_calculated}."\n";}
            
        }
    }




    # ============================================================================
    
    
    #my @slaveProfileValues 
    #Now Load the indicators coming from the SLAVE and Processlist
    #foreach my $key (sort @slaveProfileValues)
    #{
    #
    #    if( defined $filterSP{$key} ){
    #        my $indicator = eval { new mysqlindicator(); }  or die ($@);
    #
    #        $indicator->{name} = $key;
    #        $indicator->{_calculated} = $filterSP{$key}->{_calculated};
    #        $MysqlIndicatorContainer{$key}= $indicator;
    #        if($debug > 0){print "Orig_key = ".$key." container = ".$indicator->{name}."|".$indicator->{_calculated}."\n";}
    #    }
    #    
    #}
    # ============================================================================
    
    
    
    
    #Returning the full list of the Indicators EMPTY
    return \%MysqlIndicatorContainer;
}

##
# This function take the information for INNODB method 1
# filling the relevant Indicator already filled.

sub analise_innodb_Status_method1($)
{
my $status = shift;
my $history ;
my %mergeinfo ;
my %mutexinfo ; 

#$MysqlIndicatorContainer;

if ($status =~ m/History.*/im) {
	$history = $&;
        if ($history =~ m/\d+[1-9]*/im) {
            $history = $&;
        }
	
	if(defined $MysqlIndicatorContainer->{innodb_history}){
	    $MysqlIndicatorContainer->{innodb_history}->setValue($history);
	}
	else
	{
	    $MysqlIndicatorContainer->{innodb_history}->setValue(0);
	}
} else {
	$history = "0";
}

if ($status =~ m/^Mutex.*/im) {
	my $temp = $&;
        my @mutex = split(/,/,$temp);
        my $limit = $#mutex;
        for( my $inc = 0; $inc <= $limit; $inc++ ){
            $mutex[$inc] =~s/^\s//;
            my @temp2 = split(/\s(?![a-z])/,$mutex[$inc]);
            $temp2[0]=~s/\s//g;
            $temp2[1]=~s/\s//g;
            $mutexinfo{$temp2[0]}=$temp2[1];
            SWITCH: {
                if ($inc == 0) { if(defined $MysqlIndicatorContainer->{innodb_mutexspin}){$MysqlIndicatorContainer->{innodb_mutexspin}->setValue($temp2[1])}; last SWITCH; }
                if ($inc == 1) { if(defined $MysqlIndicatorContainer->{innodb_mutexrounds}){$MysqlIndicatorContainer->{innodb_mutexrounds}->setValue($temp2[1])}; last SWITCH; }
                if ($inc == 2) { if(defined $MysqlIndicatorContainer->{innodb_mutexoswait}){$MysqlIndicatorContainer->{innodb_mutexoswait}->setValue($temp2[1])}; last SWITCH; }
            }
            @temp2 = undef;
            
        }

        #'innodb_mutexspin','innodb_mutexrounds','innodb_mutexoswait',
} else {
	%mutexinfo = "";
}


if ($InnodbVersion eq "base"){
    if ($status =~ m/^[0-9].insert.*/im) {
            my $temp = $&;
            my @merged = split(/,/,$temp);
            my $limit = $#merged;
            
            for( my $inc = 0; $inc <= $limit; $inc++ ){
                
                my @temp2 = split(/(?!^)\s(?!r)/,$merged[$inc]);
                $mergeinfo{$temp2[1]}=$temp2[0]=~s/\s//;
                @temp2 = undef;
                
            } 
            
    } else {
            #%mergeinfo = "";
    }
}
else
{
    my ($mergedOp, $discardedOP, $ibufferOp);
    if ($status =~ m/^merged.*\n^\sinsert.*/im) {
	$mergedOp = $&;
    }
    
    if ($status =~ m/^discarded.*\n^\sinsert.*/im) {
	$discardedOP = $&;
    }

    if ($status =~ m/^Ibuf:.*/im) {
	$ibufferOp = $&;
    }

 #@innodbValues = ('innodb_history','innodb_mutexspin','innodb_mutexrounds','innodb_mutexoswait',\
 #                        'innodb_IBmergedinsert',\
 #                        'innodb_IBmergedmarkdelete',\
 #                        'innodb_IBmergedelete',\
 #                        'innodb_IBdiscardinsert',\
 #                        'innodb_IBdiscarddeletemark',\
 #                        'innodb_IBdiscarddelete',\
 #                        'innodb_IBsize',\
 #                        'innodb_IBfreelistsize',\
 #                        'innodb_IBsegsize'
                           #innodb_IBmerges );     
    if (defined $mergedOp) {
            my @merged;
            if ($status =~ m/^\sinsert.*/im) {
                @merged = split(/,/,$&);
            }
            my $limit = $#merged;
            
            for( my $inc = 0; $inc <= $limit; $inc++ ){
                
                my @temp2 = split(/\s(?![a-z])/,$merged[$inc]);
                $mergeinfo{"merged".$temp2[0]}=$temp2[1];
                SWITCH: {
                if ($inc == 0) {
		    $MysqlIndicatorContainer->{innodb_IBmergedinsert}->setValue($temp2[1]); last SWITCH; }
                if ($inc == 1) {
		    $MysqlIndicatorContainer->{innodb_IBmergedmarkdelete}->setValue($temp2[1]); last SWITCH; }
                if ($inc == 2) {
		    $MysqlIndicatorContainer->{innodb_IBmergedelete}->setValue($temp2[1]); last SWITCH; }
            }
                @temp2 = undef;
                
            } 
            
    } else {
            #%mergeinfo = "";
    }
    
    #Discarded
        if (defined $discardedOP) {
            my @discard;
            if ($status =~ m/^\sinsert.*/im) {
                @discard = split(/,/,$&);
            }
            my $limit = $#discard;
            
            for( my $inc = 0; $inc <= $limit; $inc++ ){
                
                my @temp2 = split(/\s(?![a-z])/,$discard[$inc]);
                $mergeinfo{"discard".$temp2[0]}=$temp2[1];
                SWITCH: {
                if ($inc == 0) { $MysqlIndicatorContainer->{innodb_IBdiscardinsert}->setValue($temp2[1]); last SWITCH; }
                if ($inc == 1) { $MysqlIndicatorContainer->{innodb_IBdiscarddeletemark}->setValue($temp2[1]); last SWITCH; }
                if ($inc == 2) { $MysqlIndicatorContainer->{innodb_IBdiscarddelete}->setValue($temp2[1]); last SWITCH; }
            }
                @temp2 = undef;
                
            } 
            
    } else {
            #%mergeinfo = "";
    }
    
    #ibuffer
        if (defined $ibufferOp) {
            my @ibuffer;
               @ibuffer = split(/,/,$&);

            my $limit = $#ibuffer;
            
            for( my $inc = 0; $inc <= $limit; $inc++ ){
                
                my @temp2 = split(/\s(?![a-z])/,$ibuffer[$inc]);
                SWITCH: {
                if ($inc == 0) { $MysqlIndicatorContainer->{innodb_IBsize}->setValue($temp2[1]);$mergeinfo{"ib".$temp2[0]}=$temp2[1]; last SWITCH; }
                if ($inc == 1) { $MysqlIndicatorContainer->{innodb_IBfreelistsize}->setValue($temp2[1]);$mergeinfo{"ib".$temp2[0]}=$temp2[1]; last SWITCH; }
                if ($inc == 2) { $MysqlIndicatorContainer->{innodb_IBsegsize}->setValue($temp2[1]);$mergeinfo{"ib".$temp2[0]}=$temp2[1]; last SWITCH; }
                if ($inc == 3) { my @temp3 = split(/\s/,$temp2[1]); $MysqlIndicatorContainer->{innodb_IBmerges}->setValue($temp3[0]);$mergeinfo{"ib".$temp3[1]}=$temp3[0]; last SWITCH; }
            }
                @temp2 = undef;
                
            } 
            
        }
        else {
            #%mergeinfo = "";
        }
    
    #Inndb buffer PAGES
    #    if (defined $discardedOP) {
    #        my @discard;
    #        if ($status =~ m/^\sinsert.*/im) {
    #            @discard = split(/,/,$&);
    #        }
    #        my $limit = $#discard;
    #        
    #        for( my $inc = 0; $inc <= $limit; $inc++ ){
    #            
    #            my @temp2 = split(/\s(?![a-z])/,$discard[$inc]);
    #            $mergeinfo{"discard".$temp2[0]}=$temp2[1];
    #            SWITCH: {
    #            if ($inc == 0) { $MysqlIndicatorContainer->{innodb_IBdiscardinsert}->setValue($temp2[1]); last SWITCH; }
    #            if ($inc == 1) { $MysqlIndicatorContainer->{innodb_IBdiscarddeletemark}->setValue($temp2[1]); last SWITCH; }
    #            if ($inc == 2) { $MysqlIndicatorContainer->{innodb_IBdiscarddelete}->setValue($temp2[1]); last SWITCH; }
    #        }
    #            @temp2 = undef;
    #            
    #        } 
    #        
    #} else {
    #        #%mergeinfo = "";
    #}
    #**********************************************************
    # get PAGES information:
    #**********************************************************
        #Database pages     19187
        #OLD Pages -> Old database pages 6692
        #Pages read 2499, created 41907, written 44229
        #Pages read ahead 0.00/s, evicted without access 0.00/s
    my ($dbPages, $dbPagesOld, $dbPagesRead,$dbPagesReadH);
   
    if ($status =~ m/^Database\spages.*/im) {
	$dbPages = $&;
        if (defined $dbPages) {
            my @Items;
            @Items = split(m/\s\W*(?![a-z])/im,$dbPages );
            my $limit = $#Items;
            for( my $inc = 1; $inc <= $limit; $inc++ ){
             if(defined $Items[$inc] && $Items[$inc] ne ""){
                $MysqlIndicatorContainer->{innodb_IBDatabasepages}->setValue($Items[$inc]);
             }
            }
            
        } else {
                $MysqlIndicatorContainer->{innodb_IBDatabasepages}->setValue(0);
        }
        
        
    }

    if ($status =~ m/^Old\sdatabase\spages.[0-9]*/im) {
	$dbPagesOld = $&;
        if (defined $dbPagesOld) {
            my @Items;
            @Items = split(/\s\W*(?![a-z])/,$dbPagesOld );
            $MysqlIndicatorContainer->{innodb_IBDatabasepagesold}->setValue($Items[1]);
            
        } else {
                $MysqlIndicatorContainer->{innodb_IBDatabasepagesold}->setValue(0);
        }

    }

    if ($status =~ m/^Pages\sread\s[0-9].*/im) {
	$dbPagesRead = $&;
        if (defined $dbPagesRead) {
            my @Items;
            @Items = split(/,(?![a-z])\s*/,$dbPagesRead);
            
            my $limit = $#Items;
            
            for( my $inc = 0; $inc <= $limit; $inc++ ){
                
                my @temp2 = split(/\s\W*(?![a-z])/,$Items[$inc]);
                SWITCH: {
                    if ($inc == 0) { $MysqlIndicatorContainer->{innodb_IBPagesread}->setValue($temp2[1]); last SWITCH; }
                    if ($inc == 1) { $MysqlIndicatorContainer->{innodb_IBPagesreadcreated}->setValue($temp2[1]); last SWITCH; }
                    if ($inc == 2) { $MysqlIndicatorContainer->{innodb_IBPagesreadwritten}->setValue($temp2[1]); last SWITCH; }
                }
                @temp2 = undef;
            }   
            
        } else {
            $MysqlIndicatorContainer->{innodb_IBPagesread}->setValue(0); 
            $MysqlIndicatorContainer->{innodb_IBPagesreadcreated}->setValue(0);
            $MysqlIndicatorContainer->{innodb_IBPagesreadwritten}->setValue(0);
        }
        
        
    }

    if ($status =~ m/^Pages\sread\sahead.*/im) {
	$dbPagesReadH = $&;
        if (defined $dbPagesRead) {
            my @Items;
            $dbPagesReadH=~ s!/s!!img;
            
            @Items = split(/,\s*/,$dbPagesReadH);
            
            my $limit = $#Items;
            
            for( my $inc = 0; $inc <= $limit; $inc++ ){
                
                my @temp2 = split(/\s\W*(?![a-z])/,$Items[$inc]);
                SWITCH: {
                    if ($inc == 0) { $MysqlIndicatorContainer->{innodb_IBPagesreadhaed}->setValue($temp2[1]); last SWITCH; }
                    if ($inc == 1) { $MysqlIndicatorContainer->{innodb_IBPagesreadhaedevicted}->setValue($temp2[1]); last SWITCH; }
                }
                @temp2 = undef;
            }   
            
        } else {
            $MysqlIndicatorContainer->{innodb_IBPagesreadhaed}->setValue(0); 
            $MysqlIndicatorContainer->{innodb_IBPagesreadhaedevicted}->setValue(0);
        }

    # Getting LRU (Pending writes: LRU 0, flush list 0, single page 0) Parameters innodb_old_blocks_pct and innodb_old_blocks_time. 
    if ($status =~ m/^Pending\swrites:\sLRU.*/im) {
	my $LRUpending = $&;
        if (defined $LRUpending) {
            my @Items;
            
            $LRUpending =~ s/^\s+|\s+$//g;
            $LRUpending =~ s/[,;:]//g;
            @Items = split(/ +/, $LRUpending);
            
                        
            #@Items = split(/,\s*/,$LRUpending);
            my $limit = $#Items;
            
            $MysqlIndicatorContainer->{innodb_IBPendingwriteLRU}->setValue($Items[3]); 
            $MysqlIndicatorContainer->{innodb_IBPendingwriteFlush}->setValue($Items[6]);
            $MysqlIndicatorContainer->{innodb_IBPendingwriteSinglepage}->setValue($Items[9]); 
        
                 
            
        } else {
                $MysqlIndicatorContainer->{innodb_IBPendingwriteLRU}->setValue(0); 
                $MysqlIndicatorContainer->{innodb_IBPendingwriteFlush}->setValue(0);
	        $MysqlIndicatorContainer->{innodb_IBPendingwriteSinglepage}->setValue(0);
        }
    }
    # Log Information about writes and status
    # Log sequence number 7398751789
    # Log flushed up to   7398751789
    # Last checkpoint at  7398751789
    # 0 pending log writes, 0 pending chkp writes

    # Variables:
    # innodb_IBLogSequenceN
    # innodb_IBLogFlushN   
    # innodb_IBLogLastCheckPN
    # innodb_IBLogPendingCheckpWN   

    if ($status =~ m/^Log\ssequence\s*number\s[0-9]*/im) {
	my $LogSequence = $&;
        if (defined $LogSequence) {
            my @Items;

            @Items = split(/\s\W*(?![a-z])/,$LogSequence);
            $MysqlIndicatorContainer->{innodb_IBLogSequenceN}->setValue($Items[1]); 
        } else {
                $MysqlIndicatorContainer->{innodb_IBLogSequenceN}->setValue(0); 
        }
    }

    if ($status =~ m/^Log\sflushed\s*up\sto\s*[0-9]*/im) {
	my $LogSflush = $&;
        if (defined $LogSflush) {
            my @Items;

            @Items = split(/\s\W*(?![a-z])/,$LogSflush);
            $MysqlIndicatorContainer->{innodb_IBLogFlushN}->setValue($Items[1]); 
        } else {
                $MysqlIndicatorContainer->{innodb_IBLogFlushN}->setValue(0); 
        }
    }

    if ($status =~ m/^Last\scheckpoint\s*at\s*[0-9]*/im) {
	my $LogSchkp = $&;
        if (defined $LogSchkp) {
            my @Items;

            @Items = split(/\s\W*(?![a-z])/,$LogSchkp);
            $MysqlIndicatorContainer->{innodb_IBLogLastCheckPN}->setValue($Items[1]); 
        } else {
                $MysqlIndicatorContainer->{innodb_IBLogLastCheckPN}->setValue(0); 
        }
    }

    if ($status =~ m/^[0-9]*\s*pending\slog\s*writes.*/im) {
	my $LogPendingChkpW = $&;
        $LogPendingChkpW =~ m/\s*[0-9]*\s*pending\s*chkp/im ;
        $LogPendingChkpW = $& ;
        
        if (defined $LogPendingChkpW) {
            my @Items;

            @Items = split(/\s\W*pe/,$LogPendingChkpW);
            
            $MysqlIndicatorContainer->{innodb_IBLogPendingCheckpWN}->setValue($Items[0]); 
        } else {
                $MysqlIndicatorContainer->{innodb_IBLogPendingCheckpWN}->setValue(0); 
        }
    }

   return 0;
  }
    
    


    #**********************************************************
    # get PAGES information: END
    #**********************************************************

    
}
  return;
  #$status;
  #my %v = %$ref;

  #return \%v;
}



sub print_report_header(){
if( defined $Param->{outfile}){
    my $header ;
    $header = "date,time";
    my $indicator;
    foreach my $key (sort keys %{$MysqlIndicatorContainer})
    {
        if($key ne "execution_date" && $key ne "execution_time" && defined $MysqlIndicatorContainer->{$key} ){
            $indicator = '';
            #print $key;
            $indicator = $MysqlIndicatorContainer->{$key};
            if (defined $indicator && $indicator ne '' && $indicator->{name} ne ''){
                if($debug > 0){print "key=".$key."  ".$indicator->{name}."\n";}
                $header = $header.','. $indicator->{name};
            }
        }
    }
    
    print $FILEOUT $header."\n";
    $FILEOUT->flush;
}
 else{   
    return;
 }
}


sub print_report_column(){
    my $header ;
    $header = "1:date\n2:time\n";
    my $indicator;
    my $Position=3;
    my $headerMap;
    foreach my $key (sort keys %{$MysqlIndicatorContainer})
    {
        if($key ne "execution_date" && $key ne "execution_time" && defined $MysqlIndicatorContainer->{$key} ){
            $indicator = '';
            #print $key;
            $indicator = $MysqlIndicatorContainer->{$key};
            if (defined $indicator && $indicator ne ''){
                if($debug > 0){print "key=".$key."  ".$indicator->{name}."\n";}
                $headerMap->{$indicator->{name}}=$Position;
                $header = $header.$Position++.":". $indicator->{name}."\n";
                            }
        }
    }
   
    print $header."\n";
    
    if ($Param->{creategnuplot} == 1)
    {
        my $dir = getcwd;
        my $gnuplotfile = $dir.'/gnuplot_graphs.ini';
        my $cfg = new ConfigIniSimple();
        $cfg->read($gnuplotfile);

        my @returnvalues = GnuPlotGenerator($Param,$headerMap,$cfg);
	if(@returnvalues > 0){
	    print $returnvalues[0];
	    print $returnvalues[1];
	}
        if ($Param->{sysstats} == 1)
        {
            PrintSystatGnufile($cfg,$Param->{hwsys_stats},$cfg);
        }
        
    }

}

sub print_report_summary($$){

    my $Param = shift;
    my $localMysqlIndicatorContainer = shift;
    my %MysqlIndicatorContainer = %{$localMysqlIndicatorContainer};


    if( defined $Param->{outfile}){
        my $header ;
        $header = "start_date,start_time";
        $header = $header.','. "end_date,end_time";           
    
    
        foreach my $key (sort keys %{$MysqlIndicatorContainer})
        {
            my $indicator;
            $indicator = $MysqlIndicatorContainer->{$key};
            if (defined $indicator->{name}){
               if($key ne "execution_date" && $key ne "execution_time" ){
                    $header = $header.','. $indicator->{name}."_min";
                    $header = $header.','. $indicator->{name}."_max";
                    $header = $header.','. $indicator->{name}."_avr";
               }
            }   
        }
        
        my $line;
	
	if(defined $MysqlIndicatorContainer->{execution_date}->{_min}){
            $line = $MysqlIndicatorContainer->{execution_date}->{_min};
        }
        if(defined $MysqlIndicatorContainer->{execution_time}->{_min}){
            $line = $line.",".$MysqlIndicatorContainer->{execution_time}->{_min};
        }

        if(defined $MysqlIndicatorContainer->{execution_date}->{_max}){
            $line = $line.",".$MysqlIndicatorContainer->{execution_time}->{_max};
        }
        if(defined $MysqlIndicatorContainer->{execution_time}->{_max}){
            $line = $line.",".$MysqlIndicatorContainer->{execution_time}->{_max};
        }
        
        foreach my $key (sort keys %{$MysqlIndicatorContainer})
        {
            my $indicator;
            $indicator = $MysqlIndicatorContainer->{$key};
            
               if($key ne "execution_time" ){
                    if (defined $indicator->{_min}){
                        $line = $line.','.$indicator->{_min} ;
                    }else{$line = $line.','.'0';}
                    
                    if (defined $indicator->{_max}){
                        $line = $line.','.$indicator->{_max} ;
                    }else{$line = $line.','.'0';}
    
                    if (defined $indicator->{_average}){
                        $line = $line.','.$indicator->{_average} ;
                    }else{$line = $line.','.'0';}

               }         
        }
    
    
        print $FILEOUT $header."\n";
        print $FILEOUT $line."\n";
        
       return;
    }
}

sub set_currentexecTime(){
    $MysqlIndicatorContainer->{execution_date}->{_current}=$CurrentDate;
    $MysqlIndicatorContainer->{execution_time}->{_current}=$CurrentTime;
    return;
}
sub set_minexecTime($$){
    $MysqlIndicatorContainer->{execution_date}->{_min}=shift;
    $MysqlIndicatorContainer->{execution_time}->{_min}=shift;
    return;
}

sub set_maxexecTime($$){
    $MysqlIndicatorContainer->{execution_date}->{_max}=shift;    
    $MysqlIndicatorContainer->{execution_time}->{_max}=shift;
    return;
}



sub print_report_line(){
if( defined $Param->{outfile}){
    my $line ;
    my $addcomma = 0;    
#    $line = "execution_time";

    {
            my $indicator;
            $indicator = $MysqlIndicatorContainer->{execution_date};
            $line = $indicator->{_current};
    }

    {
            my $indicator;
            $indicator = $MysqlIndicatorContainer->{execution_time};
            $line = $line.",".$indicator->{_current};
    }
    
    foreach my $key (sort keys %{$MysqlIndicatorContainer})
    {
        if($key ne "execution_time" && $key ne "execution_date"){
            my $indicator;
            $indicator = $MysqlIndicatorContainer->{$key};
            if (defined $indicator->{_relative} && $indicator->{_relative} ne ""){
                $line = $line.','.$indicator->{_relative};
            }
            else{
                $line = $line.',0';
            }
            
        }    
    }
    
    print $FILEOUT $line."\n";
    $FILEOUT->flush();
}
 else{   
    return;
 }
}

sub check_users($) {
  my $pl = shift;
  
  my $usercount = scalar(@$pl);
  
  #referring to http://dev.mysql.com/doc/refman/5.5/en/general-thread-states.html
  
  # walk the processlist
  my $stringToPrint = "\n" ;
  $stringToPrint = $stringToPrint . "There are $usercount users currently logged on.\n";
  my %state;

  foreach my $line (@$pl) {
    $state{$line->{'state'}}->{value}=0; 
  }
  
  
  if($html){
                $stringToPrint = $stringToPrint . "<table align='center' border='1'><tr>";
                $stringToPrint = $stringToPrint . "
                <th>Id</th>
                <th>User</th>
                <th>Host</th>
                <th>Db</th>
                <th>Command</th>
                <th>Time</th>
                <th>State</th>
                <th>Info</th>\n";

                $stringToPrint = $stringToPrint . "</tr>\n";
                foreach my $line (@$pl) {
                        $stringToPrint = $stringToPrint . "<tr><td>" . $line->{'Id'} . "</td>";
                        $stringToPrint = $stringToPrint . "<td>" . $line->{'User'}. "</td>";
                        $stringToPrint = $stringToPrint . "<td>" . $line->{'Host'}. "</td>";
                        $stringToPrint = $stringToPrint . "<td>" . $line->{'db'}. "</td>";
                        $stringToPrint = $stringToPrint . "<td>" . $line->{'Command'}. "</td>";
                        $stringToPrint = $stringToPrint . "<td>" . $line->{'Time'}. "</td>";
                        $stringToPrint = $stringToPrint . "<td>" . $line->{'State'}. "</td>";
                        $stringToPrint = $stringToPrint . "<td>" . $line->{'Info'}. "</td></tr>\n";
			
			$state{$line->{'state'}}->{value}=$state{$line->{'state'}}->{value}++;
		}
                $stringToPrint = $stringToPrint .  "</table>\n";
  }
  else
  {
                $stringToPrint = $stringToPrint .  "#********************************************\n";
                foreach my $line (@$pl) {
                        $stringToPrint = $stringToPrint .  "ID = " . $line->{'Id'} . "\n";
                        $stringToPrint = $stringToPrint .  "User = " . $line->{'User'} .  "\n";
                        $stringToPrint = $stringToPrint .  "Host = " . $line->{'Host'} .  "\n";
                        $stringToPrint = $stringToPrint .  "db = " . $line->{'db'} .  "\n";
                        $stringToPrint = $stringToPrint .  "Command = " . $line->{'Command'} .  "\n";
                        $stringToPrint = $stringToPrint .  "Time = " . $line->{'Time'} .  "\n";
                        $stringToPrint = $stringToPrint .  "State = " . $line->{'State'} .  "\n";
                        $stringToPrint = $stringToPrint .  "Info = " . $line->{'Info'} . "\n";
                        $stringToPrint = $stringToPrint .  "#********************************************\n";
			$state{$line->{'state'}}->{value}=$state{$line->{'state'}}->{value}++;

                }
                $stringToPrint = $stringToPrint .  "#********************************************\n";

  }
  $finalreport =$finalreport.doPrint($stringToPrint, 1,$finalreport,$genericStatus,$html);
  

  return %state;
  
}

##
## check_uptime -- check that the uptime is sufficiently high
##
## $status -- a status as returned from get_status()
##
sub check_uptime($) {
  my $status = shift;
  
  my $redlimit    = 120; #1800
  my $yellowlimit = 3600;
  
  my $uptime = $status->{'uptime'};
  my $huptime = sprintf("%.0f",($uptime / 60)/60);
  
  if ($uptime < $redlimit) {
    $finalreport =$finalreport.doPrint("${SPACER}&red Database restarted within the last $redlimit seconds ($huptime hrs).", 0,$finalreport,$genericStatus,$html);
    return;
  }

  if ($uptime < $yellowlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&yellow Database restarted within the last $yellowlimit seconds ($huptime hrs).",0,$finalreport,$genericStatus,$html);
    return;
  }

  $finalreport =$finalreport.doPrint("$SPACER&green Database has been running for $uptime seconds ($huptime hrs)." ,0,$finalreport,$genericStatus,$html);
  return;

}

##
## check_trxps -- check the transaction per second rating for the server.
##
## $status -- a status as returned from get_status()
##
sub check_trxps($) {
my $status = shift;
  
  my $redlimit    = 400;
  my $yellowlimit = 200;
  
  my $qps = sprintf("%.2f", $status->{'com_commit'}/$status->{'uptime'});
  
  if ($qps > $redlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&red Database had processed more than $redlimit Transactions per second ($qps).",0,$finalreport,$genericStatus,$html) ;
    return;
  }

  if ($qps > $yellowlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&yellow Database had processed more than $yellowlimit Transactions per second ($qps).", 0,$finalreport,$genericStatus,$html);
    return;
  }
  
  $finalreport =$finalreport.doPrint("$SPACER&green Database had processed $qps Transactions per second.", 0,$finalreport,$genericStatus,$html);
  return;    
}

##
## check_qps -- check the question per second rating for the server.
##
## $status -- a status as returned from get_status()
##


sub check_qps($) {
  my $status = shift;
  
  my $redlimit    = 4000;
  my $yellowlimit = 2000;
   
  my $question= $status->{'questions'};
  
  #if($Question->{previous} eq 0){
  #  $Question->{previous} = $question;
  #}
  #
  #$Question->{current} = ($question - $Question->{previous});
  #$Question->{average} = sprintf("%.2f", $status->{'questions'}/$status->{'uptime'});
  #
  #$Question->{previous} =  $status->{'questions'};
  #
  #if($Question->{current} gt $Question->{max}){
  #  $Question->{max} = $Question->{current} ;
  #}
  #
  my $qps = sprintf("%.2f", $status->{'questions'}/$status->{'uptime'});
  #
  #doPrint("$SPACER Questions    : $Question->{current}", 0);
  #doPrint("$SPACER Questions Av : $Question->{average}", 0);
  #doPrint("$SPACER Questions Max: $Question->{max}", 0);
  #
  if ($qps > $redlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&red Database had processed more than $redlimit queries per second ($qps).",0,$finalreport,$genericStatus,$html) ;
    return;
  }

  if ($qps > $yellowlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&yellow Database had processed more than $yellowlimit queries per second ($qps).", 0,$finalreport,$genericStatus,$html);
    return;
  }
  
  $finalreport =$finalreport.doPrint("$SPACER&green Database had processed $qps queries per second.", 0,$finalreport,$genericStatus,$html);
  return;
}


##
## check_query_cache_efficiency
##
## $status -- a status as returned from get_status()
##

sub check_query_cache_efficiency($) {
  my $status = shift;
  
  my $redlimit    = 20;
  my $yellowlimit = 35;
  
  
  ##Possible actions for fixing:
  ## FLUSH QUERY CACHE
  ## RESET QUERY CACHE
  
  #my $eff = ($status->{'qcache_hits'}/($status->{'qcache_hits'} + $status->{'com_select'}))*100;
  
  my $eff = 0;
  if ($status->{'qcache_hits'} > 0 && $status->{'com_select'} > 0){
  
        #$eff = ($status->{'qcache_hits'} / ($status->{'qcache_inserts'} + $status->{'qcache_hits'})) * 100;
        $eff = sprintf("%.0f",($status->{'qcache_hits'}/($status->{'qcache_hits'} + $status->{'com_select'}))*100);
  }  

  my $formula = " (qcache_hits = $status->{'qcache_hits'} com_select = $status->{'com_select'}) formula (qcache_hits/(qcache_hits + com_select)) * 100 ";
  if ($eff <= $redlimit && $eff > 0) {
    $finalreport =doPrintextended("$SPACER&red Query Cache Efficiency is below $redlimit% ($eff). $formula" ,0 , 0,$finalreport,$genericStatus,$html);
    
    #my $dbh = get_connection($dsn, $user, $pass);
    #my $result =  $dbh->do("RESET QUERY CACHE");
    #my $result = $dbh->commit;
    
    return;
  }

  if ($eff <= $yellowlimit && $eff > 0) {
    $finalreport =doPrintextended("$SPACER&yellow Query Cache Efficiency is below $yellowlimit% ($eff). $formula",0 , 0,$finalreport,$genericStatus,$html );
    return;
  }
  
  $finalreport =doPrintextended("$SPACER&green Query Cache Efficiency is $eff%. $formula", 0, 0 ,$finalreport,$genericStatus,$html);
  return;
}


##
## check_query_cache_fragmentation
##
## $status -- a status as returned from get_status()
##

sub check_query_cache_fragmentation($) {
  my $status = shift;
 
  ##Possible actions for fixing:
  ## FLUSH QUERY CACHE
  ## RESET QUERY CACHE  
  
  my $redlimit    = 10000; # Fragments smaller than 10K average
  my $yellowlimit = 50000; # Fragments smaller than 50K average
  
  my $fragsz = 0;
  if( $status->{'qcache_free_memory'} > 0 && $status->{'qcache_free_blocks'} > 0){
      $fragsz = sprintf("%.0f",$status->{'qcache_free_memory'} / $status->{'qcache_free_blocks'});
  }
 
  
  if ($fragsz < $redlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&red Query cache fragments smaller than $redlimit bytes average ($fragsz).",0,$finalreport,$genericStatus,$html);

    #my $dbh = get_connection($dsn, $user, $pass);
    #my $cmd = "FLUSH QUERY CACHE;";
    #my $result = $dbh->do($cmd);
    
    
    return;
  }

  if ($fragsz < $yellowlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&yellow Query cache fragments smaller than $yellowlimit bytes average ($fragsz).",0,$finalreport,$genericStatus,$html);
    return;
  }
  
  $finalreport =$finalreport.doPrint("$SPACER&green Query cache fragments are $fragsz bytes average.",0,$finalreport,$genericStatus,$html);
  return;
}

##
## check_myisam_cache_efficiency
##
## $status -- a status as returned from get_status()
##

sub check_myisam_cache_efficiency($) {
  my $status = shift;
  ## possible fix
  ## increase key_buffer_size
  
  my $redlimit    =  75;
  my $yellowlimit = 85;
  my $key_reads_requests = $status->{'key_read_requests'};
  
  my $eff = 0;
  
  if( ($status->{'key_reads'} > 0) && ($status->{'key_read_requests'} > 0) ) {
        $eff = sprintf("%.2f", $status->{'key_reads'} /$status->{'key_read_requests'});
      $eff = sprintf("%.2f",100-($eff * 100));
  }
  
  if ($eff < $redlimit && $key_reads_requests > 1000) {
    $finalreport =$finalreport.doPrint("$SPACER&red Key cache efficiency is less than $redlimit ($eff).",0,$finalreport,$genericStatus,$html);
    return;
  }

  if ($eff < $yellowlimit && $key_reads_requests > 1000) {
    $finalreport =$finalreport.doPrint("$SPACER&yellow Key cache efficiency is less than $yellowlimit ($eff).",0,$finalreport,$genericStatus,$html);
    return;
  }
  
  $finalreport =$finalreport.doPrint("$SPACER&green Key cache efficiency is $eff.",0,$finalreport,$genericStatus,$html);
  return;
}

##
## check_myisam_lock_contention
##
## $status -- a status as returned from get_status()
##

sub check_myisam_lock_contention($) {
  my $status = shift;
  
  my $redlimit    = 3;
  my $yellowlimit = 1;
  my $lockpct = 0;
  
  if($status->{'table_locks_waited'} > 0 && $status->{'table_locks_immediate'} > 0 ){
        
        $lockpct = sprintf("%.2f", $status->{'table_locks_waited'} / $status->{'table_locks_immediate'}) * 100;
        
  }
  if ($lockpct > $redlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&red Table_locks_waited are above $redlimit% ($lockpct).  Lock Waited = $status->{'table_locks_waited'}",0,$finalreport,$genericStatus,$html);
    return;
  }

  if ($lockpct > $yellowlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&yellow Table_locks_waited are above $yellowlimit% ($lockpct). Lock Waited = $status->{'table_locks_waited'}",0,$finalreport,$genericStatus,$html);
    return;
  }
  
  $finalreport =$finalreport.doPrint("$SPACER&green Table_locks_waited are at $lockpct%. Lock Waited = $status->{'table_locks_waited'}",0,$finalreport,$genericStatus,$html);
  return;
}

##
## check_innodb_cache_efficiency
##
## $status -- a status as returned from get_status()
##

sub check_innodb_cache_efficiency($) {
  my $status = shift;
  
  my $redlimit    =  75;
  my $yellowlimit = 85;

  my $eff = sprintf("%.2f",100 - (($status->{'innodb_buffer_pool_reads'} / $status->{'innodb_buffer_pool_read_requests'}) * 100));
  
  if ($eff <= $redlimit && $eff > 0) {
    $finalreport =$finalreport.doPrint("$SPACER&red Innodb buffer pool efficiency is less than $redlimit ($eff).",0,$finalreport,$genericStatus,$html);
    return;
  }

  if ($eff < $yellowlimit && $eff > 0) {
    $finalreport =$finalreport.doPrint("$SPACER&yellow Innodb buffer pool efficiency is less than $yellowlimit ($eff).",0,$finalreport,$genericStatus,$html);
    return;
  }
  
  $finalreport =$finalreport.doPrint("$SPACER&green Innodb buffer pool efficiency is $eff.",0,$finalreport,$genericStatus,$html);
  return;
}

##
## check_innodb_log_waits
##
## $status -- a status as returned from get_status()
##

sub check_innodb_log_waits($) {
  my $status = shift;
  
  my $redlimit    = 100;
  my $yellowlimit = 10;

  my $logchk = $status->{'innodb_log_waits'};
  
  if ($logchk > $redlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&red We have seen more than $redlimit innodb_log_waits ($logchk).",0,$finalreport,$genericStatus,$html);
    return;
  }

  if ($logchk > $yellowlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&yellow We have seen more than $yellowlimit innodb_log_waits ($logchk).",0,$finalreport,$genericStatus,$html);
    return;
  }
  
  $finalreport =$finalreport.doPrint("$SPACER&green We have seen $logchk innodb_log_waits.",0,$finalreport,$genericStatus,$html);
  return;
}

##
## check_innodb_pending_ops
##
## $status -- a status as returned from get_status()
##

sub check_innodb_pending_ops($) {
  my $status = shift;
  
  my $pend = $status->{'innodb_data_pending_fsyncs'}
           + $status->{'innodb_data_pending_reads'}
           + $status->{'innodb_data_pending_writes'}
           + $status->{'innodb_os_log_pending_fsyncs'}
           + $status->{'innodb_os_log_pending_writes'};

  my $redlimit    = 100;
  my $yellowlimit = 10;

  if ($pend > $redlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&red We have more than $redlimit pending operations in InnoDB ($pend).",0,$finalreport,$genericStatus,$html);
    return;
  }

  if ($pend > $yellowlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&yellow We have more than $yellowlimit pending operations in InnoDB ($pend).",0,$finalreport,$genericStatus,$html);
    return;
  }
  
  $finalreport =$finalreport.doPrint("$SPACER&green We see $pend pending operations in InnoDB.",0,$finalreport,$genericStatus,$html);
  return;
}

sub check_handlers($){
    my $status    = shift;
    my $Variables = "handler_commit,handler_delete,handler_prepare,handler_read_first,handler_read_key,handler_read_last,handler_read_next,handler_read_prev,handler_read_rnd,handler_read_rnd_next,handler_rollback,handler_update,handler_write";
    
     foreach my $key (sort split(',',$Variables)){
	    my $indicator;
	    my $value =0;
            $indicator = $MysqlIndicatorContainer->{$key};
            if (defined $indicator->{_relative} && $indicator->{_relative} ne ""){
                $value = $indicator->{_relative};
            }            
	$finalreport =$finalreport.doPrint("$SPACER $key = $value",0,$finalreport,$genericStatus,$html);
	
     }

}

##
## check_table_cache
##
## $status    -- a status as returned from get_status()
## $variables -- a variable list as returned from get_variables()
##

sub check_table_cache($$$) {
  my $status    = shift;
  my $variables = shift;
  my $Param = shift;
  #MySQL 5.1
  #my $tcache_used = $status->{'open_tables'} / $variables->{'table_open_cache'} * 100;
  #MySQL 5.0
  my $tcache_used = 0;
  if($Param->{mysqlversion} eq '5.0')
  {
       if ($status->{'open_tables'} > 0 && $variables->{'table_cache'} > 0)
    {
	  $tcache_used = $status->{'open_tables'} / $variables->{'table_cache'} * 100;
    }
    else
    {
      
    }
    
  }
  else
  {
    
    if ($status->{'open_tables'} > 0 && $variables->{'table_open_cache'} > 0)
    {
	  $tcache_used = $status->{'open_tables'} / $variables->{'table_open_cache'} * 100;
    }
    else
    {
      
    }
  }
  
  
    
  my $redlimit    = 99;
  my $yellowlimit = 90;

  if ($tcache_used > $redlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&red Table cache more than $redlimit% used ($tcache_used).",0,$finalreport,$genericStatus,$html);
    
    my $dbh = get_connection($dsn, $user, $pass,$SPACER);
    my $cmd = "FLUSH TABLES;";
    my $sth = $dbh->prepare($cmd);
    $sth->execute();
    #while (my $ref = $sth->fetchrow_hashref())
    #{
    #    my $n = $ref->{'Variable_name'};
    #$v{"\L$n\E"} = $ref->{'Value'};
    #}

    $dbh->disconnect;

    
    return;
  }

  if ($tcache_used > $yellowlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&yellow Table cache more than $yellowlimit% used ($tcache_used).",0,$finalreport,$genericStatus,$html);
    return;
  }
  
  $finalreport =$finalreport.doPrint("$SPACER&green Table cache $tcache_used% used.",0,$finalreport,$genericStatus,$html);
  return;
}

##
## check_thread_cache
##
## $status    -- a status as returned from get_status()
##

sub check_thread_cache($) {
  my $status    = shift;
  
  my $threads_created = sprintf("%.2f", $status->{'threads_created'} / $status->{'uptime'});

  my $redlimit    = 100;
  my $yellowlimit = 10;

  if ($threads_created > $redlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&red Creating more than $redlimit threads per second ($threads_created).",0,$finalreport,$genericStatus,$html);
    return;
  }

  if ($threads_created > $yellowlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&yellow Creating more than $yellowlimit threads per second ($threads_created).",0,$finalreport,$genericStatus,$html);
    return;
  }
  
  $finalreport =$finalreport.doPrint("$SPACER&green Creating $threads_created threads per second.",0,$finalreport,$genericStatus,$html);
  return;
}

##
## check_connection_limits
##
## $status    -- a status as returned from get_status()
## $variables -- a variable list as returned from get_variables()
##

sub check_connection_limits($$) {
  my $status    = shift;
  my $variables = shift;
  my $conn_used = 0;
  
  if( $status->{'max_used_connections'} > 0 && $variables->{'max_connections'} > 0 ){
    
        $conn_used = $status->{'max_used_connections'} / $variables->{'max_connections'} * 100;
  
  }
  my $redlimit    = 99;
  my $yellowlimit = 90;

  if ($conn_used > $redlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&red More than $redlimit% of all possible connections used ($conn_used).",0,$finalreport,$genericStatus,$html);
    return;
  }

  if ($conn_used > $yellowlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&yellow More than $yellowlimit% of all possible connections used ($conn_used).",0,$finalreport,$genericStatus,$html);
    return;
  }
  
  $finalreport =$finalreport.doPrint("$SPACER&green $conn_used% of all possible connections have been used.",0,$finalreport,$genericStatus,$html);
  return;
}

##
## check_tmp_disk_tables
##
## $status    -- a status as returned from get_status()
##

sub check_tmp_disk_tables($) {
  my $status    = shift;

  my $tmp_to_disk = sprintf("%.2f", ($status->{'created_tmp_disk_tables'} / $status->{'created_tmp_tables'}) * 100);

  my $redlimit    = 80;
  my $yellowlimit = 70;

  if ($tmp_to_disk > $redlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&red More than $redlimit% of all tmp tables go to disk ($tmp_to_disk).",0,$finalreport,$genericStatus,$html);
    return;
  }

  if ($tmp_to_disk > $yellowlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&yellow More than $yellowlimit% of all tmp tables go to disk ($tmp_to_disk).",0,$finalreport,$genericStatus,$html);
    return;
  }
  
  $finalreport =$finalreport.doPrint("$SPACER&green $tmp_to_disk% of all tmp tables go to disk.",0,$finalreport,$genericStatus,$html);
  return;
}

##
## check_slave_running
##
## $slave_status    -- a status as returned from get_slave_status()
##

sub check_slave_running($) {
  my $status    = shift;

  if ($status->{'Slave_IO_Running'} ne "Yes") {
    $finalreport =$finalreport.doPrint("$SPACER&red Slave IO Thread has stopped.",0,$finalreport,$genericStatus,$html);
  } else {
    $finalreport =$finalreport.doPrint("$SPACER&green Slave IO Thread is running.",0,$finalreport,$genericStatus,$html);
  }

  if ($status->{'Slave_SQL_Running'} ne "Yes") {
    $finalreport =$finalreport.doPrint("$SPACER&red Slave SQL Thread has stopped.",0,$finalreport,$genericStatus,$html);
  } else {
    $finalreport =$finalreport.doPrint("$SPACER&green Slave SQL Thread is running.",0,$finalreport,$genericStatus,$html);
  }
  
  return;
}






##
## check insert 
##
## $status -- a status as returned from get_status()
##

sub check_inserts($) {
  my $status = shift;
    
    my $value =0;
    my $indicator = $MysqlIndicatorContainer->{com_insert};
    my $indicator2 =$MysqlIndicatorContainer->{com_insert_select};
    
    if (defined $indicator->{_relative} && $indicator->{_relative} ne ""){
                $value = $indicator->{_relative};
    }
    if (defined $indicator2->{_relative} && $indicator2->{_relative} ne ""){
                $value = $value + $indicator2->{_relative};
    }


  my $eff = sprintf("%.2f",((($status->{'com_insert'} + $status->{'com_insert_select'}) / $status->{'queries'}) * 100));
  my $a_sum = sprintf("%.2f", $status->{'com_insert'} + $status->{'com_insert_select'} ); 
  
  $finalreport =$finalreport.doPrint("$SPACER&green Insert =($eff) of total | Insert Cur = $value  Total = $a_sum.",0,$finalreport,$genericStatus,$html);
  return;
}

##
## check update 
##
## $status -- a status as returned from get_status()
##

sub check_updates($) {
  my $status = shift;
   
    my $value =0;
    my $indicator = $MysqlIndicatorContainer->{com_update};
    my $indicator2 =$MysqlIndicatorContainer->{com_update_multi};
    
    if (defined $indicator->{_relative} && $indicator->{_relative} ne ""){
                $value = $indicator->{_relative};
    }
    if (defined $indicator2->{_relative} && $indicator2->{_relative} ne ""){
                $value = $value + $indicator2->{_relative};
    }

  my $eff = sprintf("%.2f",((($status->{'com_update'} + $status->{'com_update_multi'}) / $status->{'queries'}) * 100));

  my $a_sum = sprintf("%.2f", $status->{'com_update'} + $status->{'com_update_multi'} );
  
  $finalreport =$finalreport.doPrint("$SPACER&green Update  =($eff) of total | Updates Cur = $value  Total = $a_sum.",0,$finalreport,$genericStatus,$html);
  return;
}

##
## check replace 
##
## $status -- a status as returned from get_status()
##

sub check_replace($) {
  my $status = shift;

   my $value =0;
    my $indicator = $MysqlIndicatorContainer->{com_replace};
    
    if (defined $indicator->{_relative} && $indicator->{_relative} ne ""){
                $value = $indicator->{_relative};
    }
    
  my $eff = sprintf("%.2f", ((($status->{'com_replace'} ) / $status->{'queries'}) * 100));

  
  $finalreport =$finalreport.doPrint("$SPACER&green Replace  =($eff) of total | Replace Curr = $value Total = $status->{'com_replace'}.",0,$finalreport,$genericStatus,$html);
  return;
}

##
## check replace 
##
## $status -- a status as returned from get_status()
##

sub check_deletes($) {
  my $status = shift;

  my $value =0;
    my $indicator = $MysqlIndicatorContainer->{com_delete};
    
    if (defined $indicator->{_relative} && $indicator->{_relative} ne ""){
                $value = $indicator->{_relative};
    }
    
  my $eff = sprintf("%.2f", ((($status->{'com_delete'} ) / $status->{'queries'}) * 100));

  
  $finalreport =$finalreport.doPrint("$SPACER&green Deletes  =($eff) of total | Delete Curr = $value  Total = $status->{'com_delete'}.",0,$finalreport,$genericStatus,$html);
  return;
}

##
## check all modifier statments 
##
## $status -- a status as returned from get_status()
##

sub check_allmodifier($) {
  my $status = shift;

    my $value =0;
    my $indicator = $MysqlIndicatorContainer->{com_replace};
    my $indicator2 =$MysqlIndicatorContainer->{com_update};
    my $indicator3 =$MysqlIndicatorContainer->{com_update_multi};
    my $indicator4 =$MysqlIndicatorContainer->{com_insert};
    my $indicator5 =$MysqlIndicatorContainer->{com_insert_select};
    
    if (defined $indicator->{_relative} && $indicator->{_relative} ne ""){
                $value = $indicator->{_relative};
    }
    if (defined $indicator2->{_relative} && $indicator2->{_relative} ne ""){
                $value = $value + $indicator2->{_relative};
    }
    if (defined $indicator3->{_relative} && $indicator3->{_relative} ne ""){
                $value = $value + $indicator3->{_relative};
    }
    if (defined $indicator3->{_relative} && $indicator3->{_relative} ne ""){
                $value = $value + $indicator3->{_relative};
    }
    if (defined $indicator4->{_relative} && $indicator4->{_relative} ne ""){
                $value = $value + $indicator4->{_relative};
    }
    if (defined $indicator5->{_relative} && $indicator5->{_relative} ne ""){
                $value = $value + $indicator5->{_relative};
    }


  my $eff = sprintf("%.2f", ((($status->{'com_replace'} + $status->{'com_update'} + $status->{'com_update_multi'} + $status->{'com_insert'} + $status->{'com_insert_select'} ) / $status->{'queries'}) * 100));

  my $a_sum = sprintf("%.2f",$status->{'com_replace'} + $status->{'com_update'} + $status->{'com_delete'} + $status->{'com_update_multi'} + $status->{'com_insert'} + $status->{'com_insert_select'});
  $finalreport =$finalreport.doPrint("$SPACER&green ALL modifier statments  =($eff) of total | All modifier = $value Total = $a_sum.",0,$finalreport,$genericStatus,$html);
  return;
}

##
## check all reads
##
## $status -- a status as returned from get_status()
##

sub check_selects($) {
  my $status = shift;

    my $indicator;
    my $value =0;
    $indicator = $MysqlIndicatorContainer->{com_select};
    if (defined $indicator->{_relative} && $indicator->{_relative} ne ""){
                $value = $indicator->{_relative};
    }            
  my $eff = sprintf("%.2f",((($status->{'com_select'}) / $status->{'queries'}) * 100));

  my $a_sum = sprintf("%.2f", $status->{'com_select'} );
  
  $finalreport =$finalreport.doPrint("$SPACER&green Select  =($eff) of total | Select Cur = $value Total = $a_sum.",0,$finalreport,$genericStatus,$html);
  return;
}

##
## check if server is mainly read or write
##
## $status -- a status as returned from get_status()
##
sub check_read_or_write($) {
  my $status = shift;
  my $eff = sprintf("%.2f",($status->{'com_select'}));

  my $a_sum = sprintf("%.2f",$status->{'com_replace'} + $status->{'com_update'} + $status->{'com_update_multi'} + $status->{'com_insert'} + $status->{'com_insert_select'}); 
  
  if ($eff < $a_sum) {
    $finalreport =$finalreport.doPrint("$SPACER This server is **Mainly** executing WRITES",0,$finalreport,$genericStatus,$html);
    return;
  }
  elsif ($eff > $a_sum) {
    $finalreport =$finalreport.doPrint("$SPACER This server is **Mainly** executing READS",0,$finalreport,$genericStatus,$html);
    return;
  }
  else {
    $finalreport =$finalreport.doPrint("$SPACER This server is Doing balanced READS and WRITES ",0,$finalreport,$genericStatus,$html);
    return;
  }
  
  $finalreport =$finalreport.doPrint("$SPACER&green Server is performing Select  =($eff) of total | Select = $a_sum  Total = $status->{'queries'}.",0,$finalreport,$genericStatus,$html);
  return;
}

##
## check_slave_lag
##
## $slave_status    -- a status as returned from get_slave_status()
##

sub check_slave_lag($) {
  my $status    = shift;

  my $redlimit    = 30;
  my $yellowlimit = 10;
  my $applyDelayPos = $status->{'Read_Master_Log_Pos'} - $status->{'Exec_Master_Log_Pos'};

    if(defined $MysqlIndicatorContainer->{slave_seconds_behind_master}){
        $MysqlIndicatorContainer->{slave_seconds_behind_master}->setValue($status->{'Seconds_Behind_Master'});
    }

    if(defined $MysqlIndicatorContainer->{slave_pos_write_delay}){
        $MysqlIndicatorContainer->{slave_pos_write_delay}->setValue($applyDelayPos);
    }

  $finalreport =$finalreport.doPrint("$SPACER Slave is in delay EXECUTING Master statments of $applyDelayPos POS.",0,$finalreport,$genericStatus,$html);
  
  my $lag = $status->{'Seconds_Behind_Master'};
  if (!defined($lag)) {
    $finalreport =$finalreport.doPrint("$SPACER&red Slave is not running, no lag defined.",0,$finalreport,$genericStatus,$html);
    return;
  }

  if ($lag > $redlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&red Slave is lagging more than $redlimit seconds ($lag).",0,$finalreport,$genericStatus,$html);
    return;
  }

  if ($lag > $yellowlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&yellow Slave is lagging more than $yellowlimit seconds ($lag).",0,$finalreport,$genericStatus,$html);
    return;
  }

  $finalreport =$finalreport.doPrint("$SPACER&green Slave is lagging $lag seconds.",0,$finalreport,$genericStatus,$html);
  return;
}

##
## check_slave_errors
##
## $slave_status    -- a status as returned from get_slave_status()
##

sub check_slave_errors($) {
  my $status    = shift;

  my $errno = $status->{'Last_Errno'};
  my $error = $status->{'Last_Error'};
  
  if ($errno > 0) {
    $finalreport =$finalreport.doPrint("$SPACER&red Slave error: $errno ($error).",0,$finalreport,$genericStatus,$html);
  } else {
    $finalreport =$finalreport.doPrint("$SPACER&green No slave errors.",0,$finalreport,$genericStatus,$html);
  }

  return;
}


##
## check_databases
##
## $databases    -- array of databases returned from get_databases()
##
sub check_databases($){
    my $databases_list = shift;
    
    $finalreport =$finalreport.doPrint("<pre>\n",1,$finalreport,$genericStatus,$html);
    $finalreport =$finalreport.doPrint("Databases\n",1,$finalreport,$genericStatus,$html);

    for (my $i = 0; $i <= $#$databases_list; $i++){
     
            $finalreport =$finalreport.doPrint("$databases_list->[$i] \n",1,$finalreport,$genericStatus,$html);
    }
    $finalreport =$finalreport.doPrint("</pre>",1,$finalreport,$genericStatus,$html);
    return;
}


sub check_innodb_poolstatus($$)
{
    my $status = shift;
    my $variables = shift;
    
    my $poolstatus = 0;
    $poolstatus = 100-(100*($status->{innodb_buffer_pool_reads} / $status->{innodb_buffer_pool_read_requests}));
    
    $finalreport =$finalreport.doPrint("$SPACER InnoDB Pool Hit Ratio = $poolstatus",0,$finalreport,$genericStatus,$html);
    
}

sub check_innodb_bufferpoolusage($$)
{
    my $status = shift;
    my $variables = shift;
    

    
    my $bpUsage =(($status->{innodb_buffer_pool_pages_data})*16)/1024;
    my $bpTotal =(($status->{innodb_buffer_pool_pages_total})*16)/1024;
    
    my $bpPct = 100 *($bpUsage/$bpTotal);
    
    $finalreport =$finalreport.doPrint("$SPACER InnoDB BufferPool usage (%) = $bpPct",0,$finalreport,$genericStatus,$html);
    $finalreport =$finalreport.doPrint("$SPACER InnoDB BufferPool usage (MB) = $bpUsage OF tot = $bpTotal MB",0,$finalreport,$genericStatus,$html);
    
}

sub check_innodb_dirtypagesprc($$)
{
    my $status = shift;
    my $variables = shift;
    
    my $poolstatus = 0;
    $poolstatus = (100*($status->{innodb_buffer_pool_pages_dirty} / $status->{innodb_buffer_pool_pages_total}));
    
    $finalreport =$finalreport.doPrint("$SPACER InnoDB Dirty Pages % = $poolstatus",0,$finalreport,$genericStatus,$html);
    
}


sub check_innodb_dirtypagesnum($$)
{
    my $status = shift;
    my $variables = shift;
    
    my $poolstatus = 0;
    
    
    $finalreport =$finalreport.doPrint("$SPACER InnoDB Dirty Pages N = $status->{innodb_buffer_pool_pages_dirty} on of Total = $status->{innodb_buffer_pool_pages_total}",0,$finalreport,$genericStatus,$html);
    
}


sub check_innodb_rowusage($$)
{
    my $status = shift;
    my $variables = shift;
    

    
    #my $reads =($status->{innodb_rows_read});
    #my $writes =($status->{innodb_rows_inserted});
    #my $update =($status->{innodb_rows_updated});
    #my $delete =($status->{innodb_rows_deleted});
    #
      my $Variables = "innodb_rows_read,innodb_rows_inserted,innodb_rows_updated,innodb_rows_deleted";
    
     foreach my $key (sort split(',',$Variables)){
	    my $indicator;
	    my $value =0;
            $indicator = $MysqlIndicatorContainer->{$key};
            if (defined $indicator->{_relative} && $indicator->{_relative} ne ""){
                $value = $indicator->{_relative};
            }            
	$finalreport =$finalreport.doPrint("$SPACER $key = $value",0,$finalreport,$genericStatus,$html);
	
     }

    #$finalreport =$finalreport.doPrint("$SPACER InnoDB BufferPool READS   Cur = ".." avg = ".($reads/$status->{uptime})."",0,$finalreport,$genericStatus,$html);
    #$finalreport =$finalreport.doPrint("$SPACER InnoDB BufferPool WRITES  Cur = ".." avg = ".($writes/$status->{uptime})."",0,$finalreport,$genericStatus,$html);
    #$finalreport =$finalreport.doPrint("$SPACER InnoDB BufferPool UPDATE  Cur = ".." avg = ".($update/$status->{uptime})."",0,$finalreport,$genericStatus,$html);
    #$finalreport =$finalreport.doPrint("$SPACER InnoDB BufferPool DELETES Cur = ".." avg = ".($delete/$status->{uptime})."",0,$finalreport,$genericStatus,$html);
    
}

sub check_byteusage($$)
{
    my $status = shift;
    my $variables = shift;
    

    
    my $in =($status->{innodb_rows_read});
    my $out =($status->{innodb_rows_inserted});
    
    $finalreport =$finalreport.doPrint("$SPACER Bytes INcoming   avg = ".($in/$status->{uptime})."",0,$finalreport,$genericStatus,$html);
    $finalreport =$finalreport.doPrint("$SPACER Bytes OUTgoing  avg = ".($out/$status->{uptime})."",0,$finalreport,$genericStatus,$html);
    #doPrint("$SPACER InnoDB BufferPool UPDATE  avg = ".($update/$status->{uptime})."",0);
    
}

######################################################################
##
##  Put all status value in the box .
##

sub feed_MysqlIndicatorContainer($$$$$$){
    
    my $Param = shift;
    my $status = shift;
    my $localMysqlIndicatorContainer = shift;
    my $LocalIAB_Status= shift;
    my $state = shift;
    my $command = shift;
    my %IAB_Status= %{$LocalIAB_Status};
    my %MysqlIndicatorContainer = %{$localMysqlIndicatorContainer};
    my %KeyStatus = %{$status};
    my %localProcessState; # = defined $state?%{$state}:"";
    my %localProcessCommand; # = defined $command?%{$command}:"";
    if(defined $state && defined $command){
        %localProcessState = %{$state};
        %localProcessCommand = %{$command};    
    }
    
    foreach my $key (sort keys %KeyStatus)
    {
        if( defined $MysqlIndicatorContainer{$key}  ){
            
            my $value = $status->{$key};
            if ($value =~ m/[-+]?\b\d+\b/im){
                $MysqlIndicatorContainer{$key}->setValue($value);
            }
        }
        
    }

    if($Param->{processlist} eq 1){
        foreach my $key (sort keys %localProcessState)
        {
            if( defined $MysqlIndicatorContainer{"Proc_State_".$key}  ){
                
                my $value = $localProcessState{$key};
                if ($value =~ m/[-+]?\b\d+\b/im){
                    $MysqlIndicatorContainer{"Proc_State_".$key}->setValue($value);
                }
            }
            
        }
    
        foreach my $key (sort keys %localProcessCommand)
        {
            if( defined $MysqlIndicatorContainer{"Proc_Command_".$key}  ){
                
                my $value = $localProcessCommand{$key};
                if ($value =~ m/[-+]?\b\d+\b/im){
                    $MysqlIndicatorContainer{"Proc_Command_".$key}->setValue($value);
                }
            }
            
        }
    }



    foreach my $key (sort keys %IAB_Status)
    {
        if( defined $MysqlIndicatorContainer{$key}  ){
            
            my $value = $LocalIAB_Status->{$key};
            if ($value =~ m/[-+]?\b\d+\b/im){
                $MysqlIndicatorContainer{$key}->setValue($value);
            }
        }
        
    }


#    if ( defined $status->{'is_slave'}
#	&& $status->{'is_slave'}  eq "ON"
#	&& defined $slave_status->{'Seconds_Behind_Master'}){
#	    my $lag = $slave_status->{'Seconds_Behind_Master'};
#	    $MysqlIndicatorContainer{'Seconds_Behind_Master'}->setValue($lag);
#	
#    }
#    elsif(defined $status->{'is_slave'}
#	&& $status->{'is_slave'}  eq "ON"
#	&& !defined $slave_status->{'Seconds_Behind_Master'}){
#	    $MysqlIndicatorContainer{'Seconds_Behind_Master'}->setValue('-999');
#    }
#    elsif(defined $MysqlIndicatorContainer{'Seconds_Behind_Master'})
#    {
#	$MysqlIndicatorContainer{'Seconds_Behind_Master'}->setValue(0);
#    }
    
    return \%MysqlIndicatorContainer;
}

# ============================================================================
# Given INNODB STATUS text, returns a key-value array of the parsed text.  Each
# line shows a sample of the input for both standard InnoDB as you would find in
# MySQL 5.0, and XtraDB or enhanced InnoDB from Percona if applicable.  Note
# that extra leading spaces are ignored due to trim().
# ============================================================================
sub analise_innodb_Status_method2($) {
 my $text = shift;			      
 my %results  = (
      AIB_spin_waits  => [0,0,0],
      AIB_spin_rounds => [0,0,0],
      AIB_os_waits    => [0,0,0],
      AIB_pending_normal_aio_reads  => 0,
      AIB_pending_normal_aio_writes => 0,
      AIB_pending_ibuf_aio_reads    => 0,
      AIB_pending_aio_log_ios       => 0,
      AIB_pending_aio_sync_ios      => 0,
      AIB_pending_log_flushes       => 0,
      AIB_pending_buf_pool_flushes  => 0,
      AIB_file_reads                => 0,
      AIB_file_writes               => 0,
      AIB_file_fsyncs               => 0,
      AIB_ibuf_inserts              => 0,
      AIB_ibuf_merged               => 0,
      AIB_ibuf_merges               => 0,
      AIB_log_bytes_written         => 0,
      AIB_unflushed_log             => 0,
      AIB_log_bytes_flushed         => 0,
      AIB_pending_log_writes        => 0,
      AIB_pending_chkp_writes       => 0,
      AIB_log_writes                => 0,
      AIB_pool_size                 => 0,
      AIB_free_pages                => 0,
      AIB_database_pages            => 0,
      AIB_modified_pages            => 0,
      AIB_pages_read                => 0,
      AIB_pages_created             => 0,
      AIB_pages_written             => 0,
      AIB_queries_inside            => 0,
      AIB_queries_queued            => 0,
      AIB_read_views                => 0,
      AIB_rows_inserted             => 0,
      AIB_rows_updated              => 0,
      AIB_rows_deleted              => 0,
      AIB_rows_read                 => 0,
      AIB_innodb_transactions       => 0,
      AIB_unpurged_txns             => 0,
      AIB_history_list              => 0,
      AIB_current_transactions      => 0,
      AIB_active_transactions	    => 0,
      AIB_hash_index_cells_total    => 0,
      AIB_hash_index_cells_used     => 0,
      AIB_total_mem_alloc           => 0,
      AIB_additional_pool_alloc     => 0,
      AIB_last_checkpoint           => 0,
      AIB_uncheckpointed_bytes      => 0,
      AIB_ibuf_used_cells           => 0,
      AIB_ibuf_free_cells           => 0,
      AIB_ibuf_cell_count           => 0,
      AIB_adaptive_hash_memory      => 0,
      AIB_page_hash_memory          => 0,
      AIB_dictionary_cache_memory   => 0,
      AIB_file_system_memory        => 0,
      AIB_lock_system_memory        => 0,
      AIB_recovery_system_memory    => 0,
      AIB_thread_hash_memory        => 0,
      AIB_innodb_sem_waits          => 0,
      AIB_hash_searches             => 0,
      AIB_hash_searches_non          =>0,
      AIB_innodb_sem_wait_time_ms   => 0,
   );
   my $txn_seen = 0;
   my @lines = split(/\n/, $text) ;
    
   for my $line(@lines) {
      $line =~ s/^\s+|\s+$//g;
      $line =~ s/[,;:]//g;
      my @row = split(/ +/, $line);

#print $line."\n";
    no warnings 'all';
      # SEMAPHORES
      if (index($line, 'Mutex spin waits') >=0 ) {
         # Mutex spin waits 79626940, rounds 157459864, OS waits 698719
         # Mutex spin waits 0, rounds 247280272495, OS waits 316513438
         $results{AIB_spin_waits}[0] = int($row[3]);
         $results{AIB_spin_rounds}[0] = int($row[5]);
         $results{AIB_os_waits}[0]    = int($row[8]);
      }
      elsif (index($line, 'RW-shared spins') >=0 && $InnodbVersion ne "plugin" ) {
         # RW-shared spins 3859028, OS waits 2100750; RW-excl spins 4641946, OS waits 1530310
	    $results{AIB_spin_waits}[1] = int($row[2]);
	    $results{AIB_spin_waits}[2] = int($row[8]);
	    $results{AIB_os_waits}[1] = int($row[5]);
	    $results{AIB_os_waits}[2] = int($row[11]);
      }
      elsif (index($line, 'RW-shared spins') >=0 && $InnodbVersion eq "plugin" ) {
         # RW-shared spins 3859028, OS waits 2100750; RW-excl spins 4641946, OS waits 1530310
	    $results{sAIB_pin_waits}[1] = int($row[2]);
	    #$results{spin_waits}[2] = int($row[8]);
	    $results{AIB_os_waits}[1] = int($row[7]);
	    #$results{os_waits}[2] = int($row[11]);
      }
      elsif (index($line, 'RW-excl spins') >=0 && $InnodbVersion eq "plugin" ) {
         # RW-shared spins 3859028, OS waits 2100750; RW-excl spins 4641946, OS waits 1530310
	    #$results{spin_waits}[1] = int($row[2]);
	    $results{AIB_spin_waits}[2] = int($row[2]);
	    #$results{os_waits}[1] = int($row[5]);
	    $results{AIB_os_waits}[2] = int($row[7]);
      }

      
      elsif (index($line, 'seconds the semaphore:') > 0) {
         # --Thread 907205 has waited at handler/ha_innodb.cc line 7156 for 1.00 seconds the semaphore:
         increment(%results, 'AIB_innodb_sem_waits', 1);
         increment(%results, 'AIB_innodb_sem_wait_time_ms', int($row[9]) * 1000);
      }

      # TRANSACTIONS
      elsif ( index($line, 'Trx id counter') >=0 ) {
         # The beginning of the TRANSACTIONS section: start counting
         # transactions
         # Trx id counter 0 1170664159
         # Trx id counter 861B144C
         $results{AIB_innodb_transactions} = make_bigint($row[3], $row[4]);
         $txn_seen = 1;
      }
      elsif ( index($line, 'Purge done for trx') >=0 ) {
         # Purge done for trx's n:o < 0 1170663853 undo n:o < 0 0
         # Purge done for trx's n:o < 861B135D undo n:o < 0
         my $purged_to = make_bigint($row[6], $row[7] eq 'undo' ? 0 : $row[7]);
         $results{AIB_unpurged_txns} = big_sub($results{AIB_innodb_transactions}, $purged_to);
      }
      elsif (index($line, 'History list length') >=0 ) {
         # History list length 132
         $results{AIB_history_list} = int($row[3]);
      }
      elsif ( $txn_seen == 1 && index($line, '---TRANSACTION') >=0 ) {
         # ---TRANSACTION 0, not started, process no 13510, OS thread id 1170446656
         increment(%results, 'AIB_current_transactions', 1);
         if ( index($line, 'ACTIVE') > 0 ) {
            increment(%results, 'AIB_active_transactions', 1);
         }
      }
      elsif ( $txn_seen ==1 && index($line, '------- TRX HAS BEEN') >=0 ) {
         # ------- TRX HAS BEEN WAITING 32 SEC FOR THIS LOCK TO BE GRANTED:
         increment(%results, 'AIB_innodb_lock_wait_secs', int($row[5]));
      }
      elsif ( index($line, 'read views open inside InnoDB') > 0 ) {
         # 1 read views open inside InnoDB
         $results{AIB_read_views} = int($row[0]);
      }
      elsif ( index($line, 'mysql tables in use') >=0 ) {
         # mysql tables in use 2, locked 2
         increment(%results, 'AIB_innodb_tables_in_use', int($row[4]));
         increment(%results, 'AIB_innodb_locked_tables', int($row[6]));
      }
      elsif ( $txn_seen == 1 && index($line, 'lock struct(s)') > 0 ) {
         # 23 lock struct(s), heap size 3024, undo log entries 27
         # LOCK WAIT 12 lock struct(s), heap size 3024, undo log entries 5
         # LOCK WAIT 2 lock struct(s), heap size 368
         if ( index($line, 'LOCK WAIT') >=0 ) {
            increment(%results, 'AIB_innodb_lock_structs', int($row[2]));
            increment(%results, 'AIB_locked_transactions', 1);
         }
         else {
            increment(%results, 'AIB_innodb_lock_structs', int($row[0]));
         }
      }

      # FILE I/O
      elsif (index($line, ' OS file reads, ') > 0 ) {
         # 8782182 OS file reads, 15635445 OS file writes, 947800 OS fsyncs
         $results{AIB_file_reads}  = int($row[0]);
         $results{AIB_file_writes} = int($row[4]);
         $results{AIB_file_fsyncs} = int($row[8]);
      }
      elsif (index($line, 'Pending normal aio reads:') >=0 ) {
         # Pending normal aio reads: 0, aio writes: 0,
         $results{AIB_pending_normal_aio_reads}  = int($row[4]);
         $results{AIB_pending_normal_aio_writes} = int($row[7]);
      }
      elsif (index($line, 'ibuf aio reads') >=0 ) {
         #  ibuf aio reads: 0, log i/o's: 0, sync i/o's: 0
         $results{AIB_pending_ibuf_aio_reads} = int($row[3]);
         $results{AIB_pending_aio_log_ios}    = int($row[6]);
         $results{AIB_pending_aio_sync_ios}   = int($row[9]);
      }
      elsif ( index($line, 'Pending flushes (fsync)') >=0 ) {
         # Pending flushes (fsync) log: 0; buffer pool: 0
         $results{AIB_pending_log_flushes}      = int($row[4]);
         $results{AIB_pending_buf_pool_flushes} = int($row[7]);
      }

      # INSERT BUFFER AND ADAPTIVE HASH INDEX
      elsif (index($line, 'Ibuf for space 0: size ') >=0 ) {
         # Older InnoDB code seemed to be ready for an ibuf per tablespace.  It
         # had two lines in the output.  Newer has just one line, see below.
         # Ibuf for space 0: size 1, free list len 887, seg size 889, is not empty
         # Ibuf for space 0: size 1, free list len 887, seg size 889,
         $results{AIB_ibuf_used_cells}  = int($row[5]);
         $results{AIB_ibuf_free_cells}  = int($row[9]);
         $results{AIB_ibuf_cell_count}  = int($row[12]);
      }
      elsif (index($line, 'Ibuf: size ') >=0 ) {
         # Ibuf: size 1, free list len 4634, seg size 4636,
         $results{AIB_ibuf_used_cells}  = int($row[2]);
         $results{AIB_ibuf_free_cells}  = int($row[6]);
         $results{AIB_ibuf_cell_count}  = int($row[9]);
      }
      elsif (index($line, ' merged recs, ') > 0 ) {
         # 19817685 inserts, 19817684 merged recs, 3552620 merges
         $results{AIB_ibuf_inserts} = int($row[0]);
         $results{AIB_ibuf_merged}  = int($row[2]);
         $results{AIB_ibuf_merges}  = int($row[5]);
      }
      elsif (index($line, 'Hash table size ') >=0 ) {
         # In some versions of InnoDB, the used cells is omitted.
         # Hash table size 4425293, used cells 4229064, ....
         # Hash table size 57374437, node heap has 72964 buffer(s) <-- no used cells
         $results{AIB_hash_index_cells_total} = int($row[3]);
         $results{AIB_hash_index_cells_used} = index($line, 'used cells') > 0 ? int($row[6]) : '0';
      }

      elsif (index($line, 'hash searches/s') >=0 ) {
         #0.00 hash searches/s, 0.00 non-hash searches/s
         $results{AIB_hash_searches} = int($row[0]);
         $results{AIB_hash_searches_non} = int($row[3]);
      }




      # LOG
      elsif (index($line, " log i/o's done, ") > 0 ) {
         # 3430041 log i/o's done, 17.44 log i/o's/second
         # 520835887 log i/o's done, 17.28 log i/o's/second, 518724686 syncs, 2980893 checkpoints
         # TODO: graph syncs and checkpoints
         $results{AIB_log_writes} = int($row[0]);
      }
      elsif (index($line, " pending log writes, ") > 0 ) {
         # 0 pending log writes, 0 pending chkp writes
         $results{AIB_pending_log_writes}  = int($row[0]);
         $results{AIB_pending_chkp_writes} = int($row[4]);
      }
      elsif (index($line, "Log sequence number") >=0 ) {
         # This number is NOT printed in hex in InnoDB plugin.
         # Log sequence number 13093949495856 //plugin
         # Log sequence number 125 3934414864 //normal
         $results{AIB_log_bytes_written}
            = defined $row[4]
            ? make_bigint($row[3], $row[4])
            : int($row[3]);
      }
      elsif (index($line, "Log flushed up to") >=0 ) {
         # This number is NOT printed in hex in InnoDB plugin.
         # Log flushed up to   13093948219327
         # Log flushed up to   125 3934414864
         $results{AIB_log_bytes_flushed}
            = defined $row[5]
            ? make_bigint($row[4], $row[5])
            : int($row[4]);
      }
      elsif (index($line, "Last checkpoint at") >=0 ) {
         # Last checkpoint at  125 3934293461
         $results{AIB_last_checkpoint}
            = defined $row[4]
            ? make_bigint($row[3], $row[4])
            : int($row[3]);
      }

      # BUFFER POOL AND MEMORY
      elsif (index($line, "Total memory allocated") >=0 ) {
         # Total memory allocated 29642194944; in additional pool allocated 0
         if(looks_like_number($row[3])){
            $results{AIB_total_mem_alloc}= int($row[3]);
         }
         if(looks_like_number($row[8])){
             $results{AIB_additional_pool_alloc} = int($row[8]);
         }
      }
      elsif(index($line, 'Adaptive hash index ') >=0 ) {
         #   Adaptive hash index 1538240664 	(186998824 + 1351241840)
         $results{AIB_adaptive_hash_memory} = int($row[3]);
      } 
      elsif(index($line, 'Page hash           ') >=0 ) {
         #   Page hash           11688584
         $results{AIB_page_hash_memory} = int($row[2]);
      }
      elsif(index($line, 'Dictionary cache    ') >=0 ) {
         #   Dictionary cache    145525560 	(140250984 + 5274576)
         $results{AIB_dictionary_cache_memory} = int($row[2]);
      }
      elsif(index($line, 'File system         ') >=0 ) {
         #   File system         313848 	(82672 + 231176)
         $results{AIB_file_system_memory} = int($row[2]);
      }
      elsif(index($line, 'Lock system         ') >=0 ) {
         #   Lock system         29232616 	(29219368 + 13248)
         $results{AIB_lock_system_memory} = int($row[2]);
      }
      elsif(index($line, 'Recovery system     ') >=0 ) {
         #   Recovery system     0 	(0 + 0)
         $results{AIB_recovery_system_memory} = int($row[2]);
      }
      elsif(index($line, 'Threads             ') >=0 ) {
         #   Threads             409336 	(406936 + 2400)
         $results{AIB_thread_hash_memory} = int($row[1]);
      }
      elsif(index($line, 'innodb_io_pattern   ') >=0 ) {
         #   innodb_io_pattern   0 	(0 + 0)
         $results{AIB_innodb_io_pattern_memory} = int($row[1]);
      }
      elsif (index($line, "Buffer pool size ") >=0 ) {
         # The " " after size is necessary to avoid matching the wrong line:
         # Buffer pool size        1769471
         # Buffer pool size, bytes 28991012864
        if(looks_like_number($row[3])){
            $results{AIB_pool_size} = int($row[3]);
        }
      }
      elsif (index($line, "Free buffers") >=0 ) {
         # Free buffers            0
         $results{AIB_free_pages} = int($row[2]);
      }
      elsif (index($line, "Database pages") >=0 ) {
         # Database pages          1696503
         $results{AIB_database_pages} = int($row[2]);
      }
      elsif (index($line, "Modified db pages") >=0 ) {
         # Modified db pages       160602
         $results{AIB_modified_pages} = int($row[3]);
      }
      elsif (index($line, "Pages read ahead") >=0 ) {
         # Must do this BEFORE the next test, otherwise it'll get fooled by this
         # line from the new plugin (see samples/innodb-015.txt):
         # Pages read ahead 0.00/s, evicted without access 0.06/s
         # TODO: No-op for now, see issue 134.
      }
      elsif (index($line, "Pages read") >=0 ) {
         # Pages read 15240822, created 1770238, written 21705836
         $results{AIB_pages_read}    = int($row[2]);
         $results{AIB_pages_created} = int($row[4]);
         $results{AIB_pages_written} = int($row[6]);
      }

      # ROW OPERATIONS
      elsif (index($line, 'Number of rows inserted') >=0 ) {
         # Number of rows inserted 50678311, updated 66425915, deleted 20605903, read 454561562
         $results{AIB_rows_inserted} = int($row[4]);
         $results{AIB_rows_updated}  = int($row[6]);
         $results{AIB_rows_deleted}  = int($row[8]);
         $results{AIB_rows_read}     = int($row[10]);
      }
      elsif (index($line, " queries inside InnoDB, ") > 0 ) {
         # 0 queries inside InnoDB, 0 queries in queue
         $results{AIB_queries_inside} = int($row[0]);
         $results{AIB_queries_queued} = int($row[4]);
      }
   }

   for my $key ('AIB_spin_waits', 'AIB_spin_rounds', 'AIB_os_waits' ) {
      $results{$key} = int(array_sum($results{$key}));
   }
   $results{AIB_unflushed_log}
      = big_sub($results{AIB_log_bytes_written}, $results{AIB_log_bytes_flushed});
   $results{AIB_uncheckpointed_bytes}
      = big_sub($results{AIB_log_bytes_written}, $results{AIB_last_checkpoint});

   return \%results;
}


sub SysStats($$$$$)
{
    my ($CurrentDate,$CurrentTime);
    
    $CurrentDate = shift;
    $CurrentTime = shift; 
    $systatHeader=shift;
    $systatdata=shift;
    my $lxs = shift;
    my $mysqlpid;

    if($Param->{"OS"} eq "linux"){
        $mysqlpid = `pidof mysqld`;
        $mysqlpid =~ s/\n//g;
    }
    elsif($Param->{"OS"} eq "MSWin32"){
        my @procs = `tasklist`;
    }

#    my $lxs = Sys::Statistics::Linux->new(
#	sysinfo   => 0,
#        cpustats  => 1,
#        procstats => 1,
#        memstats  => 1,
#        pgswstats => 1,
#        netstats  => 1,
#        sockstats => 0,
#        diskstats => 1,
#        diskusage => 1,
#        loadavg   => 0,
#        filestats => 0,
#        processes => {init => 1,
#                      pids=> [$mysqlpid] }
#        );

    #sleep(1);
    my $stat = $lxs->get;
    #my %cpu  = $stat->cpustats;
    #my %disk = $stat->diskstats;
    
    $systatdata="";
    $systatHeader ="";
    
    
    $systatHeader = "execution_date,execution_time";
    $systatdata = $CurrentDate.",".$CurrentTime;
     
    
    #
    my @StatsToRead = ("netstats","diskstats","diskusage","cpustats","processes");
    
    foreach my $mainkey (sort @StatsToRead ){
        foreach my $key (sort keys %{$stat->{$mainkey}})
        {   #print "$mainkey $key \n";
	    foreach my $subkey (sort keys %{$stat->{$mainkey}->{$key}}){
		$systatHeader = $systatHeader.",${subkey}_${key}";
		$systatdata = $systatdata
		.",".$stat->{$mainkey}->{$key}->{$subkey};
	    }
	}
    }

    @StatsToRead = ("memstats","pgswstats");
    
    foreach my $mainkey (sort @StatsToRead ){
        foreach my $key (sort keys %{$stat->{$mainkey}})
        {   #print "$mainkey $key \n";
            $systatHeader = $systatHeader.",${key}";
            $systatdata = $systatdata
            .",".$stat->{$mainkey}->{$key};
        }
    }

    if ($Param->{sysstatsinit} eq "0" && $Param->{sysstats} eq "1"){
        print $FILEOUTSTATS $systatHeader."\n";
        $Param->{sysstatsinit} = 1;
    }
    print $FILEOUTSTATS $systatdata."\n";

#CPU Load
    #avg_1   -  The average processor workload of the last minute.
    #avg_5   -  The average processor workload of the last five minutes.
    #avg_15  -  The average processor workload of the last fifteen minutes.

        
#DIsk
    #major   -  The mayor number of the disk
    #minor   -  The minor number of the disk
    #rdreq   -  Number of read requests that were made to physical disk per second.
    #rdbyt   -  Number of bytes that were read from physical disk per second.
    #wrtreq  -  Number of write requests that were made to physical disk per second.
    #wrtbyt  -  Number of bytes that were written to physical disk per second.
    #ttreq   -  Total number of requests were made from/to physical disk per second.
    #ttbyt   -  Total number of bytes transmitted from/to physical disk per second.

#DISK2
    #total       -  The total size of the disk.
    #usage       -  The used disk space in kilobytes.
    #free        -  The free disk space in kilobytes.
    #usageper    -  The used disk space in percent.
    #mountpoint  -  The moint point of the disk.

#MEM
 #   memused         -  Total size of used memory in kilobytes.
 #   memfree         -  Total size of free memory in kilobytes.
 #   memusedper      -  Total size of used memory in percent.
 #   memtotal        -  Total size of memory in kilobytes.
 #   buffers         -  Total size of buffers used from memory in kilobytes.
 #   cached          -  Total size of cached memory in kilobytes.
 #   realfree        -  Total size of memory is real free (memfree + buffers + cached).
 #   realfreeper     -  Total size of memory is real free in percent of total memory.
 #   swapused        -  Total size of swap space is used is kilobytes.
 #   swapfree        -  Total size of swap space is free in kilobytes.
 #   swapusedper     -  Total size of swap space is used in percent.
 #   swaptotal       -  Total size of swap space in kilobytes.
 #   swapcached      -  Memory that once was swapped out, is swapped back in but still also is in the swapfile.
 #   active          -  Memory that has been used more recently and usually not reclaimed unless absolutely necessary.
 #   inactive        -  Memory which has been less recently used and is more eligible to be reclaimed for other purposes.
 #                      On earlier kernels (2.4) Inact_dirty + Inact_laundry + Inact_clean.
 #
 #   The following statistics are only available by kernels from 2.6.
 #
 #   slab            -  Total size of memory in kilobytes that used by kernel for data structure allocations.
 #   dirty           -  Total size of memory pages in kilobytes that waits to be written back to disk.
 #   mapped          -  Total size of memory in kilbytes that is mapped by devices or libraries with mmap.
 #   writeback       -  Total size of memory that was written back to disk.
 #   committed_as    -  The amount of memory presently allocated on the system.
 #
 #   The following statistic is only available by kernels from 2.6.9.
 #
 #   commitlimit     -  Total amount of memory currently available to be allocated on the system.

#Network
 #rxbyt    -  Number of bytes received per second.
 #   rxpcks   -  Number of packets received per second.
 #   rxerrs   -  Number of errors that happend while received packets per second.
 #   rxdrop   -  Number of packets that were dropped per second.
 #   rxfifo   -  Number of FIFO overruns that happend on received packets per second.
 #   rxframe  -  Number of carrier errors that happend on received packets per second.
 #   rxcompr  -  Number of compressed packets received per second.
 #   rxmulti  -  Number of multicast packets received per second.
 #   txbyt    -  Number of bytes transmitted per second.
 #   txpcks   -  Number of packets transmitted per second.
 #   txerrs   -  Number of errors that happend while transmitting packets per second.
 #   txdrop   -  Number of packets that were dropped per second.
 #   txfifo   -  Number of FIFO overruns that happend on transmitted packets per second.
 #   txcolls  -  Number of collisions that were detected per second.
 #   txcarr   -  Number of carrier errors that happend on transmitted packets per second.
 #   txcompr  -  Number of compressed packets transmitted per second.
 #   ttpcks   -  Number of total packets (received + transmitted) per second.
 #   ttbyt    -  Number of total bytes (received + transmitted) per second.

#Page
    #pgpgin      -  Number of pages the system has paged in from disk per second.
    #pgpgout     -  Number of pages the system has paged out to disk per second.
    #pswpin      -  Number of pages the system has swapped in from disk per second.
    #pswpout     -  Number of pages the system has swapped out to disk per second.
    #
    #The following statistics are only available by kernels from 2.6.
    #
    #pgfault     -  Number of page faults the system has made per second (minor + major).
    #pgmajfault  -  Number of major faults per second the system required loading a memory page from disk.

#Process
    #new       -  Number of new processes that were produced per second.
    #runqueue  -  The number of currently executing kernel scheduling entities (processes, threads).
    #count     -  The number of kernel scheduling entities that currently exist on the system (processes, threads).
    #blocked   -  Number of processes blocked waiting for I/O to complete (Linux 2.5.45 onwards).
    #running   -  Number of processes in runnable state (Linux 2.5.45 onwards).


#PROCESS LIST
  #ppid      -  The parent process ID of the process.
  #  nlwp      -  The number of light weight processes that runs by this process.
  #  owner     -  The owner name of the process.
  #  pgrp      -  The group ID of the process.
  #  state     -  The status of the process.
  #  session   -  The session ID of the process.
  #  ttynr     -  The tty the process use.
  #  minflt    -  The number of minor faults the process made.
  #  cminflt   -  The number of minor faults the child process made.
  #  mayflt    -  The number of mayor faults the process made.
  #  cmayflt   -  The number of mayor faults the child process made.
  #  stime     -  The number of jiffies the process have beed scheduled in kernel mode.
  #  utime     -  The number of jiffies the process have beed scheduled in user mode.
  #  ttime     -  The number of jiffies the process have beed scheduled (user + kernel).
  #  cstime    -  The number of jiffies the process waited for childrens have been scheduled in kernel mode.
  #  cutime    -  The number of jiffies the process waited for childrens have been scheduled in user mode.
  #  prior     -  The priority of the process (+15).
  #  nice      -  The nice level of the process.
  #  sttime    -  The time in jiffies the process started after system boot.
  #  actime    -  The time in D:H:M:S (days, hours, minutes, seconds) the process is active.
  #  vsize     -  The size of virtual memory of the process.
  #  nswap     -  The size of swap space of the process.
  #  cnswap    -  The size of swap space of the childrens of the process.
  #  cpu       -  The CPU number the process was last executed on.
  #  wchan     -  The "channel" in which the process is waiting.
  #  fd        -  This is a subhash containing each file which the process has open, named by its file descriptor.
  #               0 is standard input, 1 standard output, 2 standard error, etc. Because only the owner or root
  #               can read /proc/<pid>/fd this hash could be empty.
  #  cmd       -  Command of the process.
  #  cmdline   -  Command line of the process.



#Socket
    #used    -  Total number of used sockets.
    #tcp     -  Number of tcp sockets in use.
    #udp     -  Number of udp sockets in use.
    #raw     -  Number of raw sockets in use.
    #ipfrag  -  Number of ip fragments in use (only available by kernels > 2.2).

#SYSINFO
    #hostname   -  The host name.
    #domain     -  The host domain name.
    #kernel     -  The kernel name.
    #release    -  The kernel release.
    #version    -  The kernel version.
    #memtotal   -  The total size of memory.
    #swaptotal  -  The total size of swap space.
    #uptime     -  The uptime of the system.
    #idletime   -  The idle time of the system.
    #pcpucount  -  The total number of physical CPUs.
    #tcpucount  -  The total number of CPUs (cores, hyper threading).
    #interfaces -  The interfaces of the system.
    #arch       -  The machine hardware name (uname -m).
    #
    ## countcpus is the same like tcpucount
    #countcpus  -  The total (maybe logical) number of CPUs.

}

################################################
# Get STATE / command from the proceslist

sub check_users_state($$) {
  my $pl = shift;
  my $dbh = shift;
  my %localProcessState = %processState;
  my %localProcessCommand = %processCommand;
  my %ProcessValues;
  
  $ProcessValues{state}=%localProcessState;
  $ProcessValues{command}=%localProcessCommand;
  
  
  my $usercount = scalar(@$pl);
	for(my $ico=0;$ico < $usercount; $ico++){
	    
	    my %user=%{@{$pl}[$ico]};
	    #my $entry = $user{'User'};
	    
	    my $entry = lc $user{'State'};#."_".$n;
	    $entry =~ s/[% . \s]/_/g;
            
	    if (exists $localProcessState{$entry})
	    {
		$localProcessState{$entry}++;
	    }

	    my $entryC = lc $user{'Command'};#."_".$n;
	    $entryC =~ s/[% . \s]/_/g;
            
	    if (exists$localProcessCommand{$entryC})
	    {
		$localProcessCommand{$entryC}++;
	    }


		#$stringToPrint = $stringToPrint .  "ID = " . $line->{'Id'} . "\n";
		#$stringToPrint = $stringToPrint .  "User = " . $line->{'User'} .  "\n";
		#$stringToPrint = $stringToPrint .  "Host = " . $line->{'Host'} .  "\n";
		#$stringToPrint = $stringToPrint .  "db = " . $line->{'db'} .  "\n";
		#$stringToPrint = $stringToPrint .  "Command = " . $line->{'Command'} .  "\n";
		#$stringToPrint = $stringToPrint .  "Time = " . $line->{'Time'} .  "\n";
		#$stringToPrint = $stringToPrint .  "State = " . $line->{'State'} .  "\n";
		#$stringToPrint = $stringToPrint .  "Info = " . $line->{'Info'} . "\n";
		#$stringToPrint = $stringToPrint .  "#********************************************\n";
		#$state{$line->{'state'}}->{value}=$state{$line->{'state'}}->{value}++;

	}
	#$stringToPrint = $stringToPrint .  "#********************************************\n";
  $ProcessValues{state}=\%localProcessState;
  $ProcessValues{command}=\%localProcessCommand;
   
  return  \%ProcessValues;
  
}

######################################################################
##
##  Create Gnuplot graphs
##
sub GnuPlotGenerator($$$){
    my $Params = shift;
    my $HeadersMap = shift;
   # my $dir = getcwd;
   # my $gnuplotfile = $dir.'/gnuplot_graphs.ini';
    my $cfg = shift;
    #$cfg->read($gnuplotfile);
    my @returnvaluesLocal;
    my $awkcommands;
    my $gnuplotcommands;
    my @returnvalues;
    
    foreach my $key (sort keys %{$cfg})
    {

        if ($key eq "__default__"
            || $key eq "__append__"
            || $key eq "__eol__"
            || $key eq "__file__")
        {
            print "";
        }
        else
        { 
 #           print $key."\n";
            my $gnuparam = $cfg->{$key};
            $gnuparam->{title} = $key;
            
            if (substr($key,0,5) ne "Hwsys" ){
                @returnvaluesLocal = PrintGnufile($gnuparam,$HeadersMap);
                if(@returnvaluesLocal > 0)
        	    {
        		$awkcommands = $awkcommands . $returnvaluesLocal[0];
        		$gnuplotcommands = $gnuplotcommands . $returnvaluesLocal[1];
		
		
        	    }
            }
            else{
                print "";
            }
#            print "\n"."awk -F , '{print \$1,\$2,".$awkposition."}'".$Param->{outfile}." >> ".$key.".csv ;"
        }
    }

    if($gnuplotcommands ne "" && $awkcommands ne ""){
	$returnvalues[0] =$awkcommands;
	$returnvalues[1] =$gnuplotcommands;
    }
    
    return @returnvalues;
    
}

######################################################################
##
##  Print the file definition
##

sub PrintGnufile($$){
    my $gnuparam = shift;
    my $HeadersMap = shift;
    my $plotstring="";
    my $awkposition ="";
    my $gnuconf="";
    my @returnvalues;
    my $relativePosition =2;
    my $prePlotstring ="" ;
    
    foreach my $key2 (sort keys %{$gnuparam})
    {
       
       
       if ($key2 eq "yaxis"
           || $key2 eq "xaxis")
       {
           print "";
       }
       else
       {
          if($key2 eq "y2axis"){
            $plotstring = "set y2label \"$gnuparam->{$key2}\" \nset y2range [0:] \nset y2tics \n".$plotstring;
            next;
           }

        
            my $position = 0;
            if(defined $HeadersMap->{$key2} && $HeadersMap->{$key2} ne "")
            {
                $position = $HeadersMap->{$key2};
                if($position > 0)
                {
                    if($awkposition eq "")
                    {
                        $awkposition = "\$".$position;
                    }
                    else
                    {
                        $awkposition = $awkposition.",\$".$position;
                    }
                }
            }
            
            my @gnuparamValueArray;
            my $chartType = "";
            my $chartOptions ="";
            
            if(defined $gnuparam->{$key2}){
                 @gnuparamValueArray=split(',',$gnuparam->{$key2});
            }
            
            if($#gnuparamValueArray > 0){
                $chartType = $gnuparamValueArray[0];
                if($#gnuparamValueArray > 1){
                    $chartOptions = "title \"$gnuparamValueArray[1]\" "};
                if($#gnuparamValueArray == 2){
                    $chartOptions = $chartOptions." ".$gnuparamValueArray[2]};
            }
            else{
                $chartType =  $gnuparam->{$key2};
            }
            
            if($position > 0 &&  $chartType eq "lines")
            {        
                #plot "Connections.csv" u 1:($3)  w l ,
                if ($plotstring eq "")
                {
                    $plotstring="plot \"".$gnuparam->{title}.".csv\" u 1:(\$".$relativePosition++."/".$Param->{interval}.") $chartOptions w l ls ".($relativePosition-1);
                }
                else
                {
                    $plotstring=$plotstring.", \"".$gnuparam->{title}.".csv\" u 1:(\$".$relativePosition++."/".$Param->{interval}.") $chartOptions w l ls ".($relativePosition-1);
                }
            }
            elsif($position > 0 &&  $chartType eq "boxes")
            {
                #plot "Connections.csv" u 1:($3)  w l ,
                if ($plotstring eq "")
                {
                    $plotstring=$prePlotstring."set boxwidth 50.50 absolute \nset style fill solid 10.00 border \n plot \"".$gnuparam->{title}.".csv\" u 1:(\$".$relativePosition++."/".$Param->{interval}.") $chartOptions w boxes lc rgb \"gray\" ";
                }
                else
                {
                    $plotstring=$plotstring.", \"".$gnuparam->{title}.".csv\" u 1:(\$".$relativePosition++."/".$Param->{interval}.") $chartOptions  w boxes lc rgb \"gray\"";
                }
            }
            
            #print "\t".$key2."\n";
            #print "\t\t".$gnuparam->{$key2}."\n";
       }
    }
    
    if( $awkposition ne "")
    {
	if($Param->{debug} >0 ){
	    print "\n\n#----------------$gnuparam->{title}--------------------\n";
	    print "awk -F , '{printf(\"\\\"%s %s\\\" \",\$1,\$2) ;print ".$awkposition."}' ".$Param->{outfile}." >> ".$gnuparam->{title}.".csv \n";
	}
	$awkposition = "awk -F , '{printf(\"\\\"%s %s\\\" \",\$1,\$2) ;print ".$awkposition."}' ".$Param->{outfile}." >> ".$gnuparam->{title}.".csv \n";
    }
    if( $gnuparam ne "" &&  $awkposition ne "")
    {
	
	$gnuconf=$gnuconf."\n#------------$gnuparam->{title}------------------------\n";
	$gnuconf=$gnuconf."reset \n";
	$gnuconf=$gnuconf."set title \"".$gnuparam->{title}."\"\n";
	$gnuconf=$gnuconf."set xlabel \"".$gnuparam->{xaxis}."\"\n";
	$gnuconf=$gnuconf."set ylabel \"".$gnuparam->{yaxis}."\"\n";
	$gnuconf=$gnuconf."set datafile separator \" \"\n\n";
	$gnuconf=$gnuconf."set timefmt \"%Y-%m-%d %H:%M:%S\"\n";
	$gnuconf=$gnuconf."#set logscale # turn on double logarithmic plotting\n";
	$gnuconf=$gnuconf."#set logscale y # for y-axis only\n";
	$gnuconf=$gnuconf."#set logscale x\n";
	$gnuconf=$gnuconf."#set xdtics 24\n\n";
	$gnuconf=$gnuconf."set autoscale xfixmin\n";
	$gnuconf=$gnuconf."set autoscale xfixmax\n";
	$gnuconf=$gnuconf."set xrange [0:]\n";
	$gnuconf=$gnuconf."set yrange [1:]\n\n";
            
	$gnuconf=$gnuconf."set lmargin at screen 0.10\n";
	$gnuconf=$gnuconf."set rmargin at screen 0.90\n";
	$gnuconf=$gnuconf."set tmargin at screen 0.91\n";

        $gnuconf=$gnuconf."set grid\n";
	$gnuconf=$gnuconf."set border 1\n";
	$gnuconf=$gnuconf."set xdata time\n";
	$gnuconf=$gnuconf."set key autotitle columnhead\n\n";

        $gnuconf=$gnuconf."set term pngcairo size 1900,950 font \"arial:name 6:size\"\n";
        $gnuconf=$gnuconf."#set terminal x11 size 1149,861\n";
        $gnuconf=$gnuconf."set output \"".$gnuparam->{title}.".png\"\n\n";

	$gnuconf=$gnuconf."set auto x\n";
	$gnuconf=$gnuconf."set format x \"%m-%d %H:%M:%S\"\n";
	$gnuconf=$gnuconf."set xtics rotate by -45 autofreq \n";
        $gnuconf=$gnuconf."set mxtics 4\n";
	$gnuconf=$gnuconf."set ytics\n";
	$gnuconf=$gnuconf."set mytics 5\n";
	$gnuconf=$gnuconf."set termoption font \"arial:name 10:size\"\n\n";
        $gnuconf=$gnuconf."set style line 1 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#113F8C\"\n";
        $gnuconf=$gnuconf."set style line 2 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#61AE24\"\n";
        $gnuconf=$gnuconf."set style line 3 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#D70060\"\n";
        $gnuconf=$gnuconf."set style line 4 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#616161\"\n";
        $gnuconf=$gnuconf."set style line 5 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#01A4A4\"\n";
        $gnuconf=$gnuconf."set style line 6 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#D0D102\"\n";
        $gnuconf=$gnuconf."set style line 7 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#E54028\"\n";
        $gnuconf=$gnuconf."set style line 8 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#00A1CB\"\n";
        $gnuconf=$gnuconf."set style line 9 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#32742C\"\n";
        $gnuconf=$gnuconf."set style line 10 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#F18D05\"\n";
        $gnuconf=$gnuconf."set style line 11 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#709DEB\"\n";
        $gnuconf=$gnuconf."set style line 12 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#99F553\"\n"; 
        $gnuconf=$gnuconf."set style line 13 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#9F0649\"\n";
        $gnuconf=$gnuconf."set style line 14 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#C9BCC2\"\n";
        $gnuconf=$gnuconf."set style line 15 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#20DEDE\"\n";
        $gnuconf=$gnuconf."set style line 16 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#A8A809\"\n";
        $gnuconf=$gnuconf."set style line 17 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#861706\"\n";
        $gnuconf=$gnuconf."set style line 18 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#488797\"\n";
        $gnuconf=$gnuconf."set style line 19 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#25721C\"\n";
        $gnuconf=$gnuconf."set style line 20 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#BD8128\"\n";
        
	
	$gnuconf=$gnuconf.$plotstring."\n\n";
	if($Param->{debug} >0 ){
	    print $gnuconf;
	}

            


	$returnvalues[0]= $awkposition;
	$returnvalues[1]= $gnuconf;

    }
   
    
    #print $plotstring;
    return @returnvalues;
}

sub PrintSystatGnufile($$){
    my $cfg = shift;
    my $lxs = shift;
    my $awkposition ="";
    my $gnuconf=shift;
    my @returnvalues;
    my $relativePosition =2;

    my ($CurrentDate,$CurrentTime);
    my $mysqlpid ;
    
    if($Param->{"OS"} eq "linux"){
        $mysqlpid = `pidof mysqld`;
        $mysqlpid =~ s/\n//g;
    }
    elsif($Param->{"OS"} eq "MSWin32"){
        my @procs = `tasklist`;
    }
#
#    my $lxs = Sys::Statistics::Linux->new(
#	sysinfo   => 0,
#        cpustats  => 1,
#        procstats => 1,
#        memstats  => 1,
#        pgswstats => 1,
#        netstats  => 1,
#        sockstats => 0,
#        diskstats => 1,
#        diskusage => 1,
#        loadavg   => 0,
#        filestats => 0,
#        processes => {init => 1,
#                      pids=> [$mysqlpid] }
#        );
    #sleep(1);
    my $stat = $lxs->get;
    #my %cpu  = $stat->cpustats;
    #my %disk = $stat->diskstats;
    
    my $position = 3; 
    
    #
    my @StatsToRead = ("netstats","diskstats","cpustats","diskusage","processes");
    #,"diskstatsOperation","diskstatsBytes","cpustatsActivity","cpustatsIrq","processStats","memstatsSwap","memstatsPageFs" ,"memstatsUsage" );
    #"processes"
    #"diskstatsOperation","diskstatsBytes","cpustatsActivity","cpustatsIrq","processStats","memstatsSwap","memstatsPageFs" ,"memstatsUsage" 
    
    foreach my $mainkey (sort @StatsToRead ){
        $relativePosition =2;
        my $awkpositionLocal ="";
        my $plotstring="" ;
        my @filters = defined $cfg->{"Hwsys_".$mainkey}?split(',',$cfg->{"Hwsys_".$mainkey}->{filter}):"na";
        my $gnuplotConf;
        my $processStats = 0;
        my $processElementStats =0;
        my $filterString = "";
        my @itemAttribs;
        my $filterItemC="";
	
        foreach my $key (sort keys %{$stat->{$mainkey}})
        {   #print "$mainkey $key \n";
            foreach my $filterItem (sort @filters){
                if($key eq $filterItem || $filterItem eq '*'){
                    $processStats = 1;
                    $filterItemC = $filterItem;
                    $filterString = $filterString."_".$filterItem;
                    $gnuplotConf = $cfg->{"Hwsys_".$mainkey};
                    last;
                }
                else{
                    $filterItemC="";  
                }
            }


#   my @StatsToRead = ("netstats","diskstats","diskusage","cpustats","processes");
#    
#    foreach my $mainkey (sort @StatsToRead ){
#        foreach my $key (sort keys %{$stat->{$mainkey}})
#        {   #print "$mainkey $key \n";
#	    foreach my $subkey (sort keys %{$stat->{$mainkey}->{$key}}){
#		$systatHeader = $systatHeader.",${subkey}_${key}";
#		$systatdata = $systatdata
#		.",".$stat->{$mainkey}->{$key}->{$subkey};
#	    }
#	}
#    }
#
#    @StatsToRead = ("memstats","pgswstats");
#    
#    foreach my $mainkey (sort @StatsToRead ){
#        foreach my $key (sort keys %{$stat->{$mainkey}})
#        {   #print "$mainkey $key \n";
#            $systatHeader = $systatHeader.",${key}";
#            $systatdata = $systatdata
#            .",".$stat->{$mainkey}->{$key};
#        }
#    }

            
        
                foreach my $subkey (sort keys %{$stat->{$mainkey}->{$key}}){
                    foreach my $cfgKey (sort keys %{$gnuplotConf}){
                         if($filterItemC ne "" && $subkey eq $cfgKey){
                             $processElementStats = 1;
                             @itemAttribs = split(',',$gnuplotConf->{$cfgKey});
                             last;
                         }
                         else{
                             $processElementStats = 0;
                         }
                     }

                    if($position > 2 && $processElementStats == 1)
                    {
                        if($awkpositionLocal eq "")
                        {
                            $awkpositionLocal = "\$".$position;
                        }
                        else
                        {
                            $awkpositionLocal = $awkpositionLocal.",\$".$position;
                        }
                    }
                    if ($plotstring eq "" && $processElementStats == 1)
                    {
                        print $#itemAttribs."   ".$itemAttribs[0];
                        if($processElementStats == 1
                           && $#itemAttribs >= 0
                           && $itemAttribs[0] eq "line"){
                            $plotstring="plot \"".$mainkey.".csv\" u 1:(\$".$relativePosition++."/".$Param->{interval}.")  w l ls ".($relativePosition-1);
                        }
                        elsif($processElementStats == 1 && $#itemAttribs >= 1) {
                            $plotstring="plot \"".$mainkey.".csv\" u 1:(\$".$relativePosition++."/".$Param->{interval}.") title ". $itemAttribs[1]. " ". $#itemAttribs ==2?$itemAttribs[2]:""  ;
                        }
                        else{
                            $relativePosition++;
                        }
                    }
                    elsif($processElementStats == 1)
                    {
                        if($processElementStats == 1 && $#itemAttribs >= 0 && $itemAttribs[0] eq "line"){
                            $plotstring=$plotstring.", \"".$mainkey.".csv\" u 1:(\$".$relativePosition++."/".$Param->{interval}.")  w l ls ".($relativePosition-1);
                        }
                        elsif($processElementStats == 1 && $#itemAttribs >= 1){
                            $plotstring=$plotstring.", \"".$mainkey.".csv\" u 1:(\$".$relativePosition++."/".$Param->{interval}.") title ". $itemAttribs[1]. " ". $#itemAttribs ==2?$itemAttribs[2]:""  ;
                        }
                        else{
                            $relativePosition++;
                        }
                    }
                    $position++ ;
                }
        }
        if($Param->{debug} >0 ){
	    print "\n\n#----------------$mainkey--------------------\n";
	    print "awk -F , '{printf(\"\\\"%s %s\\\" \",\$1,\$2) ;print ".$awkposition."}' ".$Param->{stattfile}." >> ".$mainkey.".csv \n";
	}
	$awkposition = $awkposition."awk -F , '{printf(\"\\\"%s %s\\\" \",\$1,\$2) ;print ".$awkpositionLocal."}' ".$Param->{stattfile}." >> ".$mainkey.".csv \n";
        $gnuconf = $gnuconf.GnuPlotConfStats($mainkey,$plotstring,$filterString);
    }

    @StatsToRead = ("memstats","pgswstats");
    
    foreach my $mainkey (sort @StatsToRead ){
        $relativePosition =2;
        my $awkpositionLocal ="";
        my $plotstring="" ;

        foreach my $key (sort keys %{$stat->{$mainkey}})
        {   #print "$mainkey $key \n";
                   
                if($position > 2)
                {
                    if($awkpositionLocal eq "")
                    {
                        $awkpositionLocal = "\$".$position;
                    }
                    else
                    {
                        $awkpositionLocal = $awkpositionLocal.",\$".$position;
                    }
                }
                if ($plotstring eq "")
                {
                    $plotstring="plot \"".$mainkey.".csv\" u 1:(\$".$relativePosition++."/".$Param->{interval}.")  w l ls ".($relativePosition-1);
                }
                else
                {
                    $plotstring=$plotstring.", \"".$mainkey.".csv\" u 1:(\$".$relativePosition++."/".$Param->{interval}.")  w l ls ".($relativePosition-1);
                }
                ++$position ;
        }
        if($Param->{debug} >0 ){
	    print "\n\n#----------------$mainkey--------------------\n";
	    print "awk -F , '{printf(\"\\\"%s %s\\\" \",\$1,\$2) ;print ".$awkposition."}' ".$Param->{stattfile}." >> ".$mainkey.".csv \n";
	}
	$awkposition = $awkposition."awk -F , '{printf(\"\\\"%s %s\\\" \",\$1,\$2) ;print ".$awkpositionLocal."}' ".$Param->{stattfile}." >> ".$mainkey.".csv \n";
        $gnuconf = $gnuconf.GnuPlotConfStats($mainkey,$plotstring,"");

    }
    print "\n\n ----------------------------------- STATISTICS -----------------------------\n";
    
    print $awkposition;
    print $gnuconf;
}

sub GnuPlotConfStats($$$){
    my ($mainkey, $plotstring, $gnuconf);
    $mainkey = shift;
    $plotstring = shift;
    my $filterString = shift;
    
    if( $mainkey ne "" &&  $plotstring ne "")
    {
	
	$gnuconf=$gnuconf."\n#------------$mainkey------------------------\n";
        $gnuconf=$gnuconf."\n#--FILTERED $filterString------\n";
	$gnuconf=$gnuconf."reset \n";
	$gnuconf=$gnuconf."set title \"".$mainkey."\"\n";
	$gnuconf=$gnuconf."set xlabel \"time\"\n";
	$gnuconf=$gnuconf."set ylabel \"instances\"\n";
	$gnuconf=$gnuconf."set datafile separator \" \"\n\n";
	$gnuconf=$gnuconf."set timefmt \"%Y-%m-%d %H:%M:%S\"\n";
	$gnuconf=$gnuconf."#set logscale # turn on double logarithmic plotting\n";
	$gnuconf=$gnuconf."#set logscale y # for y-axis only\n";
	$gnuconf=$gnuconf."#set logscale x\n";
	$gnuconf=$gnuconf."#set xdtics 24\n\n";
	$gnuconf=$gnuconf."set autoscale xfixmin\n";
	$gnuconf=$gnuconf."set autoscale xfixmax\n";
	$gnuconf=$gnuconf."set xrange [0:]\n";
	$gnuconf=$gnuconf."set yrange [1:]\n\n";
            
	$gnuconf=$gnuconf."set lmargin at screen 0.10\n";
	$gnuconf=$gnuconf."set rmargin at screen 0.90\n";
	$gnuconf=$gnuconf."set tmargin at screen 0.91\n";

        $gnuconf=$gnuconf."set grid\n";
	$gnuconf=$gnuconf."set border 1\n";
	$gnuconf=$gnuconf."set xdata time\n";
	$gnuconf=$gnuconf."set key autotitle columnhead\n\n";

        $gnuconf=$gnuconf."set term pngcairo size 1900,950 font \"arial:name 6:size\"\n";
        $gnuconf=$gnuconf."#set terminal x11 size 1149,861\n";
        $gnuconf=$gnuconf."set output \"".$mainkey.".png\"\n\n";

	$gnuconf=$gnuconf."set auto x\n";
	$gnuconf=$gnuconf."set format x \"%m-%d %H:%M:%S\"\n";
        $gnuconf=$gnuconf."set format y \"%s\"\n";
	$gnuconf=$gnuconf."set xtics rotate by -45 autofreq \n";
        $gnuconf=$gnuconf."set mxtics 4\n";
	$gnuconf=$gnuconf."set ytics\n";
	$gnuconf=$gnuconf."set mytics 5\n";
	$gnuconf=$gnuconf."set termoption font \"arial:name 10:size\"\n\n";
        $gnuconf=$gnuconf."set style line 1 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#113F8C\"\n";
        $gnuconf=$gnuconf."set style line 2 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#61AE24\"\n";
        $gnuconf=$gnuconf."set style line 3 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#D70060\"\n";
        $gnuconf=$gnuconf."set style line 4 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#616161\"\n";
        $gnuconf=$gnuconf."set style line 5 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#01A4A4\"\n";
        $gnuconf=$gnuconf."set style line 6 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#D0D102\"\n";
        $gnuconf=$gnuconf."set style line 7 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#E54028\"\n";
        $gnuconf=$gnuconf."set style line 8 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#00A1CB\"\n";
        $gnuconf=$gnuconf."set style line 9 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#32742C\"\n";
        $gnuconf=$gnuconf."set style line 10 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#F18D05\"\n";
        $gnuconf=$gnuconf."set style line 11 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#709DEB\"\n";
        $gnuconf=$gnuconf."set style line 12 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#99F553\"\n"; 
        $gnuconf=$gnuconf."set style line 13 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#9F0649\"\n";
        $gnuconf=$gnuconf."set style line 14 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#C9BCC2\"\n";
        $gnuconf=$gnuconf."set style line 15 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#20DEDE\"\n";
        $gnuconf=$gnuconf."set style line 16 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#A8A809\"\n";
        $gnuconf=$gnuconf."set style line 17 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#861706\"\n";
        $gnuconf=$gnuconf."set style line 18 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#488797\"\n";
        $gnuconf=$gnuconf."set style line 19 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#25721C\"\n";
        $gnuconf=$gnuconf."set style line 20 lt 1 lw 2 pt 7 ps 0.4 lc rgbcolor \"#BD8128\"\n";
        
	
	$gnuconf=$gnuconf.$plotstring."\n\n";
	if($Param->{debug} >0 ){
	    print $gnuconf;
	}

            


	
    }
   
    
    #print $plotstring;
    return $gnuconf;
}


######################################################################
##
##  ok, now make it work.
##

my $dbh = get_connection($dsn, $user, $pass,$SPACER);
$innodb_version = get_innodb_version($dbh);
$InnodbVersion = $innodb_version;

my $databases = get_databases($dbh);
my $status = get_status($dbh,$debug);
my $variables = get_variables($dbh,$debug);
my $iLoop = $Param->{loop};
my $iInterval = $Param->{interval};

my %processListState;


$strMySQLVersion = substr($variables->{'version'},0,3 );
$Param->{mysqlversion} = substr($variables->{'version'},0,3 );

$MysqlIndicatorContainer = initIndicators($Param,$status);

if ($Param->{headers} > 0){
    print_report_column();
    exit(0);
}


my $innodb_status = get_innodb_status($dbh);

my $innodb_check_method1 = 0;
my $innodb_check_method2 ;

    SWITCH: {
	if ($innodbMethod == 1) { $innodb_check_method1=analise_innodb_Status_method1($innodb_status); last SWITCH; }
	if ($innodbMethod == 2) { $innodb_check_method2=analise_innodb_Status_method2($innodb_status); last SWITCH;  }
	if ($innodbMethod == 3) { $innodb_check_method1=analise_innodb_Status_method1($innodb_status);
				 $innodb_check_method2=analise_innodb_Status_method2($innodb_status);
				 last SWITCH;  }
    }


my $slave_status = get_slave_status($dbh);
my $is_slave = defined($slave_status);

$status->{'is_slave'} = $is_slave?"ON":"OFF";

#Prepare for printing file out
print_report_header();


#if ($Param->{doGraphs} > 0){
#    GnuPlotGenerator($Param);
#    exit(0);
#}

my $startDate;
my $startTime;

{
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =localtime(time);
    $startDate = $hour.":".$min.":".$sec;
    $startTime = (1900+$year)."-".($mon+1)."-".$mday;
    
    set_minexecTime($startDate,$startTime);
}
my $startseconds = time;
my $iCountLoop = 0;

#for (my $iCountLoop = 0 ; $iCountLoop <= $iLoop; $iCountLoop++){
 while (1==1){
    
    if($iLoop > 0 && $iCountLoop >= $iLoop ){
        exit(0);
    }
    else
    {
        $iCountLoop++ ;
    }
    
    {
        my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =localtime(time);
        $CurrentDate = (1900+$year)."-".($mon+1)."-".$mday;
        $CurrentTime = $hour.":".$min.":".$sec;
	
    }
    
    
    #set the execution time for each loop
    set_currentexecTime();
    if ($Param->{sysstats} eq "1"){
	#GET MAchine stats
	#$CurrentDate;
	#$CurrentTime;
	#$systatHeader="";
	#$systatdata="";
	SysStats($CurrentDate,$CurrentTime,$systatHeader,$systatdata,$Param->{hwsys_stats});
	
    }



    #get one and only one STATUS for all checks
    $status = get_status($dbh,$debug);
    $innodb_status = get_innodb_status($dbh);
    $status->{'is_slave'} = $is_slave?"ON":"OFF";
    
    #get slave status and log positions
    my $slave_status = get_slave_status($dbh);
    
    #get processlist
    # TODO need to improve adding report for each process status
    
    my $processlist = get_processlist($dbh);

    my $localProcessState;
    my $localProcessCommand;
    
    if($Param->{processlist} eq 1){
       my %processValue = %{check_users_state($processlist,$dbh)};
       $localProcessState = $processValue{state};
       $localProcessCommand = $processValue{command};
    }
    
    # get values for InnoDB (from InnoDB status)
    if (defined $innodb_advance && $innodb_advance > 0 ){
	SWITCH: {
	    if ($innodbMethod == 1) { $innodb_check_method1=analise_innodb_Status_method1($innodb_status); last SWITCH; }
	    if ($innodbMethod == 2) { $innodb_check_method2=analise_innodb_Status_method2($innodb_status); last SWITCH;  }
	    if ($innodbMethod == 3) { $innodb_check_method1=analise_innodb_Status_method1($innodb_status);
				     $innodb_check_method2=analise_innodb_Status_method2($innodb_status); last SWITCH;  }
	}
    }
    #load all the numbers we are interested from the status to $MysqlIndicatorContainer
    {
       $MysqlIndicatorContainer = feed_MysqlIndicatorContainer($Param,$status,$MysqlIndicatorContainer,$innodb_check_method2,$localProcessState,$localProcessCommand);
       
    }
    
    $finalreport ="";
    
    if($Param->{session} == 1){
        check_databases($databases);
        %processListState = check_users($processlist);
    }
    
    if($Param->{healtonscreen} == 1){
        $finalreport =$finalreport.doPrint("$SPACER Loop Number = $iCountLoop",0,$finalreport,$genericStatus,$html);
	
	#{
	#    getCPU();
	#}
	check_uptime($status);
        check_qps($status);
        check_trxps($status);

	check_query_cache_efficiency($status);
	check_query_cache_fragmentation($status);
	
	check_myisam_cache_efficiency($status);
	check_myisam_lock_contention($status);
	
	check_innodb_cache_efficiency($status);
	check_innodb_log_waits($status);
	check_innodb_pending_ops($status);
	
	check_table_cache($status, $variables,$Param );
	check_thread_cache($status);
	check_connection_limits($status, $variables);
	
	check_tmp_disk_tables($status);
	
       	$finalreport =$finalreport.doPrint("$SPACER ================= Handlers Section ================",0,$finalreport,$genericStatus,$html);
	check_handlers($status);

        
	$finalreport =$finalreport.doPrint("$SPACER ================= InnoDb Section ================",0,$finalreport,$genericStatus,$html);
	check_innodb_poolstatus($status, $variables);
	check_innodb_bufferpoolusage($status, $variables);
	check_innodb_dirtypagesprc($status, $variables);
	check_innodb_dirtypagesnum($status, $variables);
	check_innodb_rowusage($status, $variables);
	
	$finalreport =$finalreport.doPrint("$SPACER ==================================================",0,$finalreport,$genericStatus,$html);
	
	$finalreport =$finalreport.doPrint("$SPACER =================== Byte Trx =====================",0,$finalreport,$genericStatus,$html);
	check_byteusage($status, $variables);
	
	
	$finalreport =$finalreport.doPrint("$SPACER ==================================================",0,$finalreport,$genericStatus,$html);
	$finalreport =$finalreport.doPrint("$SPACER =================== Statments executed =====================",0,$finalreport,$genericStatus,$html);
	check_inserts($status);
	check_updates($status);
	check_replace($status);
	check_deletes($status);
	check_allmodifier($status);
	check_selects($status);
	check_read_or_write($status);
	$finalreport =$finalreport.doPrint("$SPACER ==================================================",0,$finalreport,$genericStatus,$html);
	
	
	if ($is_slave) {
	  check_slave_running($slave_status);
	  check_slave_lag($slave_status);
	  check_slave_errors($slave_status);
	} else {
	  $finalreport =$finalreport.doPrint("$SPACER&green This is not a slave.",0,$finalreport,$genericStatus,$html);
	}
	finalFlush();
    }
    print_report_line();
    
    
    sleep($iInterval);
}
my $endtime= time;

my $execTime = ($endtime - $startseconds);
my $endDate;
my $endTime;

{
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =localtime(time);
    $endDate = (1900+$year)."-".($mon+1)."-".$mday;
    $endTime = $hour.":".$min.":".$sec;
    set_maxexecTime($endDate,$endTime);
}
#print_report_header();
print_report_summary($Param,$MysqlIndicatorContainer);



$finalreport = insert_BBheader($Param,$genericStatus) . $finalreport;
$finalreport =$finalreport.insert_BBtail($Param);
#finalFlush();

if( defined $Param->{outfile}){
    close $FILEOUT;
}

exit(0);

sub ShowOptions {
    print <<EOF;
Usage: mysqllocalcheck_multiple.pl -u -p -h -P -l -o

mysqllocalcheck_multiple.pl -u=root -p=password -H=127.0.0.1 -P=3306 -l=0 -w=0 -i=60 -x=2000 --innodb=3 --healtonscreen=0 -o=/tmp/stats.csv
-u=marco  -p=mysql -H=127.0.0.1 -P=3310 -l=0 -w=0 -i=10 -x=2000 --innodb=3 --healtonscreen=1 -o=/tmp/stats.csv -C=1 --sysstats=0
-u=marco  -p=mysql -H=127.0.0.1 -P=3310 -l=0 -w=0 -i=10 -x=2000 --innodb=3 --healtonscreen=1 -o=/tmp/stats.csv -C=1 --sysstats=0 --headers=1 --creategnuplot=1


--help, -h
    Display this help message

--host=HOSTNAME, -H=HOSTNAME
    Connect to the MySQL server on the given host
--user=USERNAME, -u=USERNAME
    The MySQL username to use when connecting to the server
--password=PASSWORD, -p=PASSWORD
    The password to use when connecting to the server
--port=PORT, -P=PORT
    The socket file to use when connecting to the server
--session=0 (skip user session retrival) |1 (get user/session information) -s=0|1
--html=[0|1|2] -l=[0|1|2] where 0=text; 1=table; 2=pre

--outfile=FULLPATH, -o=FULLPATH
--wrmethod=0 (append)|1 (overwrite) -w=0|1
-- Debug set e=1

-- headers=1 Print all active headers and number position then exit default headers=0
-- creategnuplot WHEN headers enable it prints gnuplot definition and command line for generating the datasets from the given destination file
   default creategnuplot=0
   
--healtonscreen [0|1] default=0 (dasable) print on screen current data report and healt of the monitored instance    
--Interval in seconds (default 2 sec) : interval or -i
--Loops: number of repeats if 0 (default) will run forever: loop|x 
--

InnoDB checks, there are two methods on going right now, to choose which one:
--innodb=1 reg exp on innodb status sperimental (list of values prefix is innodb_IB) 
--innodb=2 cacti approach (not really optimal) but familiar for the most (parameters prefix AIB_)
--innodb=3 (default)


Process list information
Count process STATE and Command for the define interval
--processlist|C [0|1] Default 0 disable

System Statistics
if ENABLE [disable by default] will collect System statistics in a separate file with name as the one define for the outfile but with prefix sysstats_
sysstats = 0 [default] disable
sysstats = 1 Enable

Security
add user as:
grant select, show databases, process,replication client,replication slave on *.* to user\@'ip' identified by xxx


EOF
}

sub URLDecode {
    my $theURL = $_[0];
    $theURL =~ tr/+/ /;
    $theURL =~ s/%([a-fA-F0-9]{2,2})/chr(hex($1))/eg;
    $theURL =~ s/<!--(.|\n)*-->//g;
    return $theURL;
}
sub URLEncode {
    my $theURL = $_[0];
   $theURL =~ s/([\W])/"%" . uc(sprintf("%2.2x",ord($1)))/eg;
   return $theURL;
}
sub debugEnv{
    my $key = keys %ENV;
    foreach $key (sort(keys %ENV)) {

       print $key, '=', $ENV{$key}, "\n";

    }

}

sub load_statusparameters{
    
$baseSP = "execution_time";
$baseSP = $baseSP.",aborted_clients,aborted_connects,bytes_received,bytes_sent,compression,connections,max_used_connections|0,created_tmp_disk_tables,created_tmp_files";
$baseSP = $baseSP.",created_tmp_tables,delayed_errors,delayed_insert_threads,delayed_writes,not_flushed_delayed_rows";
##$baseSP = $baseSP.",Slow_launch_threads,Slow_queries,Sort_merge_passes,Sort_range,Sort_rows,Sort_scan,Table_locks_immediate,Table_locks_waited";
##$baseSP = $baseSP.",Tc_log_max_pages_used,Tc_log_page_size,Tc_log_page_waits";
##$baseSP = $baseSP.",Threads_cached,Threads_connected,Threads_created,Threads_running,Uptime,Uptime_since_flush_status";

$baseSP = $baseSP.",binlog_cache_disk_use,binlog_cache_use,binlog_stmt_cache_disk_use,binlog_stmt_cache_use";
$baseSP = $baseSP.",handler_commit,handler_delete,handler_discover,handler_prepare,handler_read_first,handler_read_key,handler_read_last,handler_read_next,handler_read_prev";
$baseSP = $baseSP.",handler_read_rnd,handler_read_rnd_next,handler_rollback,handler_savepoint,handler_savepoint_rollback,handler_update,handler_write";
$baseSP = $baseSP.",com_delete,com_delete_multi,com_insert,com_insert_select,com_replace,com_replace_select,com_rollback,com_rollback_to_savepoint,com_commit,com_select,com_update,com_update_multi";
$baseSP = $baseSP.",qcache_free_blocks|0,qcache_free_memory|0,qcache_hits,qcache_inserts,qcache_lowmem_prunes,qcache_not_cached,qcache_queries_in_cache|0,qcache_total_blocks|0,queries";
$baseSP = $baseSP.",questions,key_blocks_not_flushed|0,key_blocks_unused|0,key_blocks_used|0,key_read_requests,key_reads,key_write_requests,key_writes";


$baseSP = $baseSP.",open_files,open_tables,opened_files|1,opened_tables|1,opened_table_definitions|1";


$baseSP = $baseSP.",select_full_join,select_full_range_join,select_range,select_range_check,select_scan,slow_launch_threads,slow_queries,sort_merge_passes,sort_range,sort_rows";
$baseSP = $baseSP.",sort_scan,table_locks_immediate,table_locks_waited";
$baseSP = $baseSP.",threads_cached|0,threads_connected|0,threads_created,threads_running|0,uptime|0,uptime_since_flush_status|0";

##$baseSP = $baseSP.",tc_log_max_pages_used,tc_log_page_size,tc_log_page_waits";


#=======================================
# GALERA Monitor
#=======================================
$baseSP = $baseSP.",wsrep_last_committed,wsrep_replicated,wsrep_replicated_bytes,wsrep_received,wsrep_received_bytes,wsrep_local_commits,wsrep_local_cert_failures,wsrep_local_bf_aborts";
$baseSP = $baseSP.",wsrep_local_replays,wsrep_local_send_queue,wsrep_local_send_queue_avg,wsrep_local_recv_queue,wsrep_local_recv_queue_avg,wsrep_flow_control_paused";
$baseSP = $baseSP.",wsrep_flow_control_sent,wsrep_flow_control_recv,wsrep_cert_deps_distance|0,wsrep_apply_oooe,wsrep_apply_oool,wsrep_apply_window|0,wsrep_commit_oooe";
$baseSP = $baseSP.",wsrep_commit_oool,wsrep_commit_window|0,wsrep_local_state,wsrep_cert_index_size,wsrep_cluster_conf_id,wsrep_cluster_size,wsrep_evs_repl_latency|0";



my $slaveSP=",Seconds_Behind_Master|0,ProfId|0,ProfTime|0,ProfState|0";
$slaveSP=$slaveSP.",slave_heartbeat_period,slave_open_temp_tables,slave_received_heartbeats,slave_retried_transactions,slave_running,,rpl_status";
$baseSP = $baseSP.$slaveSP;

#$baseSP = $baseSP.",com_admin_commands,com_alter_db,com_alter_db_upgrade,com_alter_event,com_alter_function,com_alter_procedure,
#com_alter_server,com_alter_table,com_alter_tablespace,com_analyze,com_assign_to_keycache,com_begin,com_binlog,
#com_call_procedure,com_change_db,com_change_master,com_check,com_checksum,com_commit,com_create_db,com_create_event,
#com_create_function,com_create_index,com_create_procedure,com_create_server,com_create_table,com_create_trigger,
#com_create_udf,com_create_user,com_create_view,com_dealloc_sql,com_do,com_drop_db,
#com_drop_event,com_drop_function,com_drop_index,com_drop_procedure,com_drop_server,com_drop_table,com_drop_trigger,
#com_drop_user,com_drop_view,com_empty_query,com_execute_sql,com_flush,com_grant,com_ha_close,com_ha_open,com_ha_read,
#com_help,com_install_plugin,com_kill,com_load,com_lock_tables,com_optimize,com_preload_keys,
#com_prepare_sql,com_purge,com_purge_before_date,com_release_savepoint,com_rename_table,com_rename_user,com_repair,
#com_reset,com_resignal,com_revoke,com_revoke_all,com_rollback,com_rollback_to_savepoint,
#com_savepoint,com_set_option,com_show_authors,com_show_binlog_events,com_show_binlogs,com_show_charsets,
#com_show_collations,com_show_contributors,com_show_create_db,com_show_create_event,com_show_create_func,com_show_create_proc,
#com_show_create_table,com_show_create_trigger,com_show_databases,com_show_engine_logs,com_show_engine_mutex,com_show_engine_status,
#com_show_errors,com_show_events,com_show_fields,com_show_function_status,com_show_grants,com_show_keys,com_show_master_status,
#com_show_open_tables,com_show_plugins,com_show_privileges,com_show_procedure_status,com_show_processlist,com_show_profile,
#com_show_profiles,com_show_relaylog_events,com_show_slave_hosts,com_show_slave_status,com_show_status,com_show_storage_engines,
#com_show_table_status,com_show_tables,com_show_triggers,com_show_variables,com_show_warnings,com_signal,com_slave_start,
#com_slave_stop,com_stmt_close,com_stmt_execute,com_stmt_fetch,com_stmt_prepare,com_stmt_reprepare,com_stmt_reset,
#com_stmt_send_long_data,com_truncate,com_uninstall_plugin,com_unlock_tables,com_xa_commit,
#com_xa_end,com_xa_prepare,com_xa_recover,com_xa_rollback,com_xa_start,flush_commands";

#$baseSP = $baseSP.",tc_log_max_pages_used,tc_log_page_size,tc_log_page_waits";



#$baseSP = $baseSP.",ssl_accept_renegotiates,ssl_accepts,ssl_callback_cache_hits,ssl_cipher,ssl_cipher_list,ssl_client_connects,ssl_connect_renegotiates,ssl_ctx_verify_depth,ssl_ctx_verify_mode,ssl_default_timeout,ssl_finished_accepts,ssl_finished_connects,ssl_session_cache_hits,ssl_session_cache_misses,ssl_session_cache_mode,ssl_session_cache_overflows,ssl_session_cache_size,ssl_session_cache_timeouts,ssl_sessions_reused,ssl_used_session_cache_entries,ssl_verify_depth,      
#ssl_verify_mode,ssl_version";

my $IB_Special="";

$IB_Special = $IB_Special.",innodb_IBdiscarddelete|1,innodb_IBdiscarddeletemark|1,innodb_IBdiscardinsert|1,innodb_IBfreelistsize|0,innodb_IBmergedelete|1,innodb_IBmergedinsert|1";
$IB_Special = $IB_Special.",innodb_IBmergedmarkdelete|1,innodb_IBmerges|0,innodb_IBsegsize|0,innodb_IBsize|0,innodb_IBDatabasepages|0,innodb_IBDatabasepagesold|0,innodb_IBPagesread|1";
$IB_Special = $IB_Special.",innodb_IBPagesreadcreated|1,innodb_IBPagesreadwritten|1,innodb_IBPagesreadhaed|0,innodb_IBPagesreadhaedevicted";
$IB_Special = $IB_Special."|0,innodb_IBPendingwriteLRU|0,innodb_IBPendingwriteFlush|0,innodb_IBPendingwriteSinglepage|0";
$IB_Special = $IB_Special."|0,innodb_IBLogSequenceN|0,innodb_IBLogFlushN|0,innodb_IBLogLastCheckPN|0,innodb_IBLogPendingCheckpWN|0";
$baseSP = $baseSP.$IB_Special;

$AIB_Cacti= ",AIB_spin_waits|0,AIB_spin_rounds|0,AIB_os_waits|0,AIB_pending_normal_aio_reads|1,AIB_pending_normal_aio_writes|01,AIB_pending_ibuf_aio_reads|0,AIB_pending_aio_log_ios|0";
$AIB_Cacti= $AIB_Cacti.",AIB_pending_aio_sync_ios|0,AIB_pending_log_flushes|0,AIB_pending_buf_pool_flushes|0,AIB_file_reads|0,AIB_file_writes|0,AIB_file_fsyncs|0,AIB_ibuf_inserts|0,AIB_ibuf_merged|0";
$AIB_Cacti= $AIB_Cacti.",AIB_ibuf_merges|0,AIB_log_bytes_written|1,AIB_unflushed_log|0,AIB_log_bytes_flushed|1,AIB_pending_log_writes|0,AIB_pending_chkp_writes|0,AIB_log_writes|1,AIB_pool_size|0";
$AIB_Cacti= $AIB_Cacti.",AIB_free_pages|0,AIB_database_pages|0,AIB_modified_pages|0,AIB_pages_read|1,AIB_pages_created|1,AIB_pages_written|1,AIB_queries_inside|0,AIB_queries_queued|0,AIB_read_views|0";
$AIB_Cacti= $AIB_Cacti.",AIB_rows_inserted|1,AIB_rows_updated|1,AIB_rows_deleted|1,AIB_rows_read|1,AIB_innodb_transactions|0,AIB_unpurged_txns|0,AIB_history_list|0,AIB_current_transactions|0,AIB_active_transactions|0";
$AIB_Cacti= $AIB_Cacti.",AIB_hash_index_cells_total|0,AIB_hash_index_cells_used|0,AIB_total_mem_alloc|0,AIB_additional_pool_alloc|0,AIB_last_checkpoint|0,AIB_uncheckpointed_bytes|0,AIB_ibuf_used_cells|1";
$AIB_Cacti= $AIB_Cacti.",AIB_ibuf_free_cells|1,AIB_ibuf_cell_count|1,AIB_adaptive_hash_memory|0,AIB_page_hash_memory|0,AIB_dictionary_cache_memory|0,AIB_file_system_memory|0,AIB_lock_system_memory|0";
$AIB_Cacti= $AIB_Cacti.",AIB_recovery_system_memory|0,AIB_thread_hash_memory|0,AIB_innodb_sem_waits|0,AIB_innodb_sem_wait_time_ms|0";
$AIB_Cacti= $AIB_Cacti.",AIB_hash_searches|0,AIB_hash_searches_non|0";
$AIB_Cacti= $AIB_Cacti.",slave_seconds_behind_master|0,slave_pos_write_delay|0";

$baseSP = $baseSP.$AIB_Cacti;


#Innodb parameters from STATUS
my $Innodb_status="";
$Innodb_status=$Innodb_status.",innodb_buffer_pool_read_ahead_rnd|0,innodb_buffer_pool_pages_data|0,innodb_buffer_pool_pages_dirty|0,innodb_buffer_pool_pages_flushed|1,innodb_buffer_pool_pages_free";
$Innodb_status=$Innodb_status."|0,innodb_buffer_pool_pages_misc|0,innodb_buffer_pool_pages_total|0,innodb_buffer_pool_read_ahead|1,innodb_buffer_pool_read_ahead_evicted";
$Innodb_status=$Innodb_status."|1,innodb_buffer_pool_read_requests|1,innodb_buffer_pool_reads|1,innodb_buffer_pool_wait_free|0,innodb_buffer_pool_write_requests";
$Innodb_status=$Innodb_status."|1,innodb_data_fsyncs|0,innodb_data_pending_fsyncs|0,innodb_data_pending_reads|0,innodb_data_pending_writes|0,innodb_data_read|1,innodb_data_reads";
$Innodb_status=$Innodb_status."|1,innodb_data_writes|1,innodb_data_written|1,innodb_dblwr_pages_written|0,innodb_dblwr_writes|0,innodb_have_atomic_builtins|0,innodb_history";
$Innodb_status=$Innodb_status."|0,innodb_log_waits|0,innodb_log_write_requests|0,innodb_log_writes|0,innodb_mutexoswait|0,innodb_mutexrounds|0,innodb_mutexspin|0,innodb_os_log_fsyncs";
$Innodb_status=$Innodb_status."|0,innodb_os_log_pending_fsyncs|0,innodb_os_log_pending_writes|0,innodb_os_log_written|0,innodb_page_size|0,innodb_pages_created|0,innodb_pages_read";
$Innodb_status=$Innodb_status."|0,innodb_pages_written|0,innodb_row_lock_current_waits|0,innodb_row_lock_time|1,innodb_row_lock_time_avg|0,innodb_row_lock_time_max|0";
$Innodb_status=$Innodb_status."|0,innodb_row_lock_waits|1,innodb_rows_deleted|1,innodb_rows_inserted|1,innodb_rows_read|1,innodb_rows_updated|1,innodb_truncated_status_writes";     
$baseSP = $baseSP.$Innodb_status;   

if($Param->{processlist} eq "1"){
    %processState = ('after_create'=>0,
    ,'analyzing'=>0
    ,'checking_permissions'=>0
    ,'checking_table'=>0
    ,'cleaning_up'=>0
    ,'closing_tables'=>0
    ,'converting_heap_to_myisam'=>0
    ,'copy_to_tmp_table'=>0
    ,'copying_to_group_table'=>0
    ,'copying_to_tmp_table'=>0
    ,'copying_to_tmp_table_on_disk'=>0
    ,'creating_index'=>0
    ,'creating_sort_index'=>0
    ,'creating_table'=>0
    ,'creating_tmp_table'=>0
    ,'deleting_from_main_table'=>0
    ,'deleting_from_reference_tables'=>0
    ,'discard_or_import_tablespace'=>0
    ,'end'=>0
    ,'executing'=>0
    ,'execution_of_init_command'=>0
    ,'freeing_items'=>0
    ,'flushing_tables'=>0
    ,'fulltext_initialization'=>0
    ,'init'=>0
    ,'killed'=>0
    ,'locked'=>0
    ,'logging_slow_query'=>0
    ,'null'=>0
    ,'login'=>0
    ,'manage_keys'=>0
    ,'opening_tables'=>0
    ,'opening_table'=>0
    ,'optimizing'=>0
    ,'preparing'=>0
    ,'purging_old_relay_logs'=>0
    ,'query_end'=>0
    ,'reading_from_net'=>0
    ,'removing_duplicates'=>0
    ,'removing_tmp_table'=>0
    ,'rename'=>0
    ,'rename_result_table'=>0
    ,'reopen_tables'=>0
    ,'repair_by_sorting'=>0
    ,'repair_done'=>0
    ,'repair_with_keycache'=>0
    ,'rolling_back'=>0
    ,'saving_state'=>0
    ,'searching_rows_for_update'=>0
    ,'sending_data'=>0
    ,'setup'=>0
    ,'sorting_for_group'=>0
    ,'sorting_for_order'=>0
    ,'sorting_index'=>0
    ,'sorting_result'=>0
    ,'statistics'=>0
    ,'system_lock'=>0
    ,'table_lock'=>0
    ,'updating'=>0
    ,'updating_main_table'=>0
    ,'updating_reference_tables'=>0
    ,'user_lock'=>0
    ,'user_sleep'=>0
    ,'waiting_for_all_running_commits_to_finish'=>0
    ,'waiting_for_commit_lock'=>0
    ,'waiting_for_global_read_lock'=>0
    ,'waiting_for_tables'=>0
    ,'waiting_for_table'=>0
    ,'waiting_for_table_flush'=>0
    ,'waiting_for_global_metadata_lock'=>0
    ,'waiting_for_global_read_lock'=>0
    ,'waiting_for_schema_metadata_lock'=>0
    ,'waiting_for_stored_function_metadata_lock'=>0
    ,'waiting_for_stored_procedure_metadata_lock'=>0
    ,'waiting_for_table_level_lock'=>0
    ,'waiting_for_table_metadata_lock'=>0
    ,'waiting_for_trigger_metadata_lock'=>0
    ,'waiting_for_master_to_send_event'=>0
    ,'waiting_on_cond'=>0
    ,'waiting_to_get_readlock'=>0
    ,'writing_to_net'=>0);
    
    
    %processCommand = ('binlog_dump'=>0
    ,'change_user'=>0
    ,'close_stmt'=>0
    ,'connect'=>0
    ,'connect_out'=>0
    ,'create_db'=>0
    ,'daemon'=>0
    ,'debug'=>0
    ,'delayed_insert'=>0
    ,'drop_db'=>0
    ,'error'=>0
    ,'execute'=>0
    ,'fetch'=>0
    ,'field_list'=>0
    ,'init_db'=>0
    ,'kill'=>0
    ,'long_data'=>0
    ,'ping'=>0
    ,'prepare'=>0
    ,'processlist'=>0
    ,'query'=>0
    ,'quit'=>0
    ,'refresh'=>0
    ,'register_slave'=>0
    ,'reset_stmt'=>0
    ,'set_option'=>0
    ,'shutdown'=>0
    ,'sleep'=>0
    ,'statistics'=>0
    ,'table_dump'=>0
    ,'time'=>0);
  }
}

sub loadSettingsSimpleFromIni($)
{
    my $conf = shift;
    #my $Param = shift;

    my $newconfNumber = (keys(%{$conf}));
    
    my $key;
    my $pCounter = 1;
    my @auds;
    foreach $key (keys %{$conf})
    {
        
        if(substr($key,0,2) ne '__')
        {
            $auds[$pCounter] = $key;
        }
        
    }
   
    
    my $keyHash = $conf;

    return $keyHash;
    
}
