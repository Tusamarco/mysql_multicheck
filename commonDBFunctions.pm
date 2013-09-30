#!/usr/bin/perl
package commonDBFunctions;

use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION);
$VERSION = 1.00;              # Or higher
@ISA = qw(Exporter);
@EXPORT = qw(get_connection get_databases get_status get_variables get_slave_status get_processlist get_innodb_status get_innodb_version get_accounts);


##
## get_connection -- return a valid database connection handle (or die)
##
## $dsn  -- a perl DSN, e.g. "DBI:mysql:host=ltsdbwm1;port=3311"
## $user -- a valid username, e.g. "check"
## $pass -- a matching password, e.g. "g33k!"
##
sub get_connection($$$$) {
  my $dsn  = shift;
  my $user = shift;
  my $pass = shift;
  my $SPACER = shift;
  my $dbh = DBI->connect($dsn, $user, $pass);

  if (!defined($dbh)) {
    print "$SPACER&red Cannot connect to $dsn as $user\n";
    die();
  }
  
  return $dbh;
}

######################################################################
##
## collection functions -- fetch datbases from the instance
##
##
## get_databases -- return a hash ref to SHOW DATABASES output
##
## $dbh -- a non-null database handle, as returned from get_connection()
##
sub get_databases($) {
  my $dbh = shift;
  
  my @v;
  my $cmd = "show databases";

  my $sth = $dbh->prepare($cmd);
  $sth->execute();
  my $i = 0;
  while (my $ref = $sth->fetchrow_hashref()) {
    
    $v[$i] = $ref->{'Database'};
    $i++;
  }

    
  return \@v;
}




######################################################################
##
## collection functions -- fetch status data from db
##

##
## get_status -- return a hash ref to SHOW GLOBAL STATUS output
##
## $dbh -- a non-null database handle, as returned from get_connection()
##



##
## get_accounts -- return a hash ref to SHOW GLOBAL VARIABLES output
##
## $dbh -- a non-null database handle, as returned from get_connection()
##
sub get_accounts($) {
  my $dbh = shift;

  my %v;
  my $cmd = "select user,host from mysql.user where user !='' order by 1,2;";

  my $sth = $dbh->prepare($cmd);
  $sth->execute();
  while (my $ref = $sth->fetchrow_hashref()) {
    my $index = index($ref->{'host'},":");
    my $n;
    my $host="";
    
    $n = $ref->{'user'};
    if ($index > 0){
        $n = $ref->{'user'};#."_".substr($ref->{'host'},0,$index);
        $n=~ s/[% .]/_/g; 
    }
    else
    {
        $n = $ref->{'user'};#."_".$ref->{'host'};
        $n=~ s/[% .]/_/g; 
     
    }
    $v{$n} = 0;
  }
  return \%v;
}

sub get_status($$) {
  my $dbh = shift;
  my $debug = shift;
  my %v;
  my $cmd = "show /*!50000 global */ status";

  my $sth = $dbh->prepare($cmd);
  $sth->execute();
  while (my $ref = $sth->fetchrow_hashref()) {
    my $n = $ref->{'Variable_name'};
    $v{"\L$n\E"} = $ref->{'Value'};
    if ($debug>0){print "MySQL status = ".$n."\n";}
  }

  return \%v;
}

##
## get_variables -- return a hash ref to SHOW GLOBAL VARIABLES output
##
## $dbh -- a non-null database handle, as returned from get_connection()
##
sub get_variables($$) {
  my $dbh = shift;
  my $debug = shift;
  my %v;
  my $cmd = "show variables";

  my $sth = $dbh->prepare($cmd);
  $sth->execute();
  while (my $ref = $sth->fetchrow_hashref()) {
    my $n = $ref->{'Variable_name'};
    $v{"\L$n\E"} = $ref->{'Value'};
  }
  
 
  return \%v;
}


##
## get_slave_status -- return a hash ref to SHOW SLAVE STATUS output
##
## $dbh -- a non-null database handle, as returned from get_connection()
##
sub get_slave_status($) {
  my $dbh = shift;
  
  my $cmd = "show slave status";
  my $sth = $dbh->prepare($cmd);
  $sth->execute();
  my $ref = $sth->fetchrow_hashref();
  if (!defined($ref)) {
    # not a slave
    return undef;
  }
  my %v = %$ref;

  return \%v;
}

##
## get_processlist -- return a an array of hash refs
##                    containing SHOW FULL PROCESSLIST output
##
## $dbh -- a non-null database handle, as returned from get_connection()
##
sub get_processlist($) {
  my $dbh = shift;
  
  my @v;
  my $count = 0;
  my $cmd = "show full processlist";

  my $sth = $dbh->prepare($cmd);
  $sth->execute();
  while (my $ref = $sth->fetchrow_hashref()) {
    my %line = map { defined($_)?$_:"(null)" } %$ref;
    $v[$count++] = \%line;
  }

  return \@v;
}

########################################
## Return the value of the Innodb version
##

sub get_innodb_version($) {
  my $dbh = shift;
  my $innodb_version;
  
    my $cmd = "show global variables like 'innodb_version'";
    my $sth = $dbh->prepare($cmd);
    $sth->execute();
    my $ref = $sth->fetchrow_hashref();
    if (!defined($ref)) {
        # not a slave
        return "base";
      }
    $innodb_version = $ref->{Value};
    my @version = split(m/\./im,$innodb_version); 
      
    if ($version[0] >= 1 && $version[1] >= 1 && $version[2] >= 1){
        $innodb_version = "plugin";
    }
    return $innodb_version;
}


##
## get_innodb_status -- return a hash ref to SHOW Innodb STATUS output
##
## $dbh -- a non-null database handle, as returned from get_connection()
sub get_innodb_status($) {
  my $dbh = shift;
  
  my $cmd = "show /*!50501 engine */ innodb status";
  my $sth = $dbh->prepare($cmd);
  $sth->execute();
  my $ref = $sth->fetchrow_hashref();
  if (!defined($ref)) {
    # not a slave
    return undef;
  }
  my $status = $ref->{Status};
  return $status;  
}
