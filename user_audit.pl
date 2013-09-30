#! /usr/bin/perl
#######################################
#
# Mysql user/connection audit v 1 (2012)
#
# Author Marco Tusa 
# Copyright (C) 2001-2003, 2012
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
use visualization;
use commonFunctions;
use commonDBFunctions;
use commonPrintFormat;
use IO::Handle;
use strict;

use DBI;
use Getopt::Long;
$Getopt::Long::ignorecase = 0;



my @usersaudit = '';
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
my $reportHeader = 0;


$Param->{user}       = '';
$Param->{password}   = '';
$Param->{host}       = '';
$Param->{port}       = 3306;
$Param->{debug}      = 0;
$Param->{wrmethod}   = 0;
$Param->{session}    = 1;
$Param->{interval}    = 2; 
$Param->{loop}   = 0;
$Param->{healtonscreen}=0;
$Param->{historylistsize} = $historyListSize;
$Param->{headers}   =0;
$Param->{sysstats}   = 0;
$Param->{sysstatsinit}   = 0;
$Param->{users}       = '';
#$Param->{outfile};

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
        'users|U:s'      => \$Param->{users},
        'outfile|o:s'    => \$outfile,
        'debug|e:i'      => \$Param->{debug},
        'wrmethod|w:i'   => \$Param->{wrmethod},
        'getsession|s:i' => \$Param->{session},
	'healtonscreen:s'=> \$Param->{healtonscreen},
        'headers:i'    	 => \$Param->{headers},
        'sysstats:i'     => \$Param->{sysstats},
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

#my $user = "check";
#my $pass = "g33k!";

my $SPACER = "    ";


if( defined $Param->{outfile}){
    my $fullname = $Param->{outfile};
    my $filename = "sysstat_";
    my $volume;
    my $directories;
    my $file;
   # ($volume, $directories, $file) = File::Spec->splitpath($fullname);

    #my $basename = basename($fullname, my @suffixlist);
    #my $dirname  = dirname($fullname);    
    
    
    if( $Param->{wrmethod} == 0){

         open  $FILEOUT , '>>', $Param->{outfile};
         $FILEOUT->autoflush(1);

        #if (open $$FILEOUT, '>>', $Param->{outfile}){
        #}
    }
    else
    {
         open $FILEOUT , ">", $Param->{outfile};
         $FILEOUT->autoflush(1);
        #if (open $$FILEOUT, '>', $Param->{outfile}){
        #}
    }
}

# ============================================================================
# END Initialization
# ============================================================================




sub check_users($$) {
  my $pl = shift;
  my $dbh = shift;
  my %accounts = %{get_accounts($dbh)};
  
  
  my $usercount = scalar(@$pl);
	for(my $ico=0;$ico < $usercount; $ico++){
	    
	    my %user=%{@{$pl}[$ico]};
	    #my $entry = $user{'User'};
	    my $index = index($user{'Host'},":");
	    my $n;
	    if ($index > 0){
	        $n = substr($user{'Host'},0,$index);  
	    }
	    else
	    {
		$n = $user{'Host'};
	    }
	    
	    my $entry = $user{'User'};#."_".$n;
	    $entry =~ s/[% .]/_/g;
	    if (exists $accounts{$entry})
	    {
		$accounts{$entry}++;
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
  return \%accounts;
  
}

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
    $finalreport =$finalreport.doPrint("$SPACER&red More than $redlimit% of all possible connections used ($conn_used).",0,$finalreport,$genericStatus,0);
    return;
  }

  if ($conn_used > $yellowlimit) {
    $finalreport =$finalreport.doPrint("$SPACER&yellow More than $yellowlimit% of all possible connections used ($conn_used).",0,$finalreport,$genericStatus,0);
    return;
  }
  
  $finalreport =$finalreport.doPrint("$SPACER&green $conn_used% of all possible connections have been used.",0,$finalreport,$genericStatus,0);
  return;
}



######################################################################
##
##  ok, now make it work.
##

my $dbh = get_connection($dsn, $user, $pass,$SPACER);

my $databases = get_databases($dbh);
my $status = get_status($dbh,$debug);
my $variables = get_variables($dbh,$debug);
my $iLoop = $Param->{loop};
my $iInterval = $Param->{interval};

my %processListState;


my $slave_status = get_slave_status($dbh);
my $is_slave = defined($slave_status);

$status->{'is_slave'} = $is_slave?"ON":"OFF";


my $startDate;
my $startTime;

{
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =localtime(time);
    $startDate = $hour.":".$min.":".$sec;
    $startTime = (1900+$year)."-".($mon+1)."-".$mday;
}
my $startseconds = time;
my $iCountLoop = 0;

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

    #get one and only one STATUS for all checks
    $status = get_status($dbh,$debug);
    $status->{'is_slave'} = $is_slave?"ON":"OFF";
    
    #get processlist
    # TODO need to improve adding report for each process status
    my $processlist = get_processlist($dbh);

    
    if($Param->{session} == 1){
	my $line = "" ; 
	
        my %userlist = %{check_users($processlist,$dbh)};

	if($reportHeader == 0){
	    $line = "execution_date,execution_time";

	    for my $key (sort keys %userlist){
		my $user = $key;
		$line = $line.",".$user;
	    }
		$line = $line.",max_used_connections,%maxconnections";
    		print $FILEOUT $line."\n";
		$reportHeader = 1;
	}   

	$line = $CurrentDate.",".$CurrentTime;
	for my $key (sort keys %userlist){
	    my $count = $userlist{$key};
	    $line = $line.",".$count;    
	    
	}
	my $conn_used = $status->{'max_used_connections'} / $variables->{'max_connections'} * 100;
	$line = $line.",".$status->{'max_used_connections'}.",".$conn_used;
	
	print $FILEOUT $line."\n";
    }
    
    
    
    sleep($iInterval);
}
if( defined $Param->{outfile}){
    close $FILEOUT;
}

exit(0);

sub ShowOptions {
    print <<EOF;
Usage: user_audit.pl -u -p -h -P -o -U

user_audit.pl.pl -u=<> -p=<> -H=127.0.0.1 -P=3306  -w=1 -i=1 -x=0 -o=/tmp/user.csv
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

--outfile=FULLPATH, -o=FULLPATH
--wrmethod=0 (append)|1 (overwrite) -w=0|1
-- Debug set e=1
--Interval in seconds (default 2 sec) : interval or -i
--Loops: number of repeats if 0 (default) will run forever: loop|x 
--


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

