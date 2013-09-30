#!/usr/bin/perl

package mysqlindicator;
use strict;
use warnings;
use Exporter;
use sigtrap;
  
use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION);
$VERSION = 1.00;              # Or higher
@ISA = qw(Exporter);
@EXPORT = qw(new name category parent exectime requestid current previous average max min relative calculated setValue);

sub new {
    my $class = shift;
    
    # Variable section for  looping values
    #Generalize object for now I have conceptualize as:
    # Indicator (generic container)
    # Indicator->{category}     This is the category for the value (query cache; traffic; handlers; innodb_rows; etc)
    # Indicator->{parent}       If the parameter is bounded to another then is reported (you cannot have rowinsert without insert and so on)
    # Indicator->{exectime}     The time of the request (system value);
    # Indicator->{requestid}    The unique Id for the whole set of data collected (incremental number) 
    # Indicator->{current}=0;   The current value
    # Indicator->{previous}=0;  The previous value 
    # Indicator->{relative}=0;  the current relative value calculated Current - Previous
    # Indicator->{average}=0;   The average calculated on the base of the EPOCH
    # Indicator->{max}=0;       The max absolute value
    # Indicator->{min}=0;       The min absolute value must be != 0
    # Indicator->{calculated}=0; If it is absolute values or a calculated one like Delta      
    
    
    my $self = {
        _name      => undef,
        _category  => undef,
        _parent    => undef,
        _exectime  => undef,
        _requestid => undef,
        
        _current => undef,
        _previous => undef,
        _relative => undef,
        _average => undef,
        _max => undef,
        _min => undef,
        _calculated => 2,
    };
    bless $self, $class;
    return $self;
    
}

sub name {
    my ( $self, $name ) = @_;
    $self->{_name} = $name if defined($name);
    return $self->{_name};
}

sub category {
    my ( $self, $category ) = @_;
    $self->{_category} = $category if defined($category);
    return $self->{_category};
}

sub parent {
    my ( $self, $parent ) = @_;
    $self->{_parent} = $parent if defined($parent);
    return $self->{_parent};
}

sub exectime {
    my ( $self, $exectime ) = @_;
    $self->{_exectime} = $exectime if defined($exectime);
    return $self->{_exectime};
}

sub requestid {
    my ( $self, $requestid ) = @_;
    $self->{_requestid} = $requestid if defined($requestid);
    return $self->{_requestid};
}


sub current {
    my ( $self, $current ) = @_;
    $self->{_current} = $current if defined($current);
    return $self->{_current};
}

sub relative {
    my ( $self, $relative ) = @_;
    $self->{_current} = $relative if defined($relative);
    return $self->{_relative};
}

sub previous {
    my ( $self, $previous ) = @_;
    $self->{_previous} = $previous if defined($previous);
    return $self->{_previous};
}

sub average {
    my ( $self, $average ) = @_;
    $self->{_average} = $average if defined($average);
    return $self->{_average};
}

sub max {
    my ( $self, $max ) = @_;
    $self->{_max} = $max if defined($max);
    return $self->{_max};
}


sub min {
    my ( $self, $min ) = @_;
    $self->{_min} = $min if defined($min);
    return $self->{_min};
}

sub calculated {
    my ( $self, $calculated ) = @_;
    $self->{_calculated} = $calculated if defined($calculated);
    return $self->{_calculated};
}

sub setValue{
    my ( $self, $TempValue) = @_;
    if(!defined $self->{_previous} && !defined  $self->{_current}){
        $self->{_previous} = $TempValue;
        $self->{_current} = $TempValue;
        
    }
    else{
        $self->{_previous} = $self->{_current};
        $self->{_current} = $TempValue;       
    }
    
    if( defined  $self->{_max}){
       $self->{_max} = ($self->{_current} > $self->{_max})?$self->{_current}:$self->{_max};
    }
    else
    {
         $self->{_max} = $self->{_current};
    }
    
    if( defined  $self->{_min}){
       $self->{_min} = ($self->{_current} < $self->{_min})?$self->{_current}:$self->{_min};
    }
    else
    {
         $self->{_min} = $self->{_current};
    }
    
    if(defined $self->{_calculated} && $self->{_calculated} > 0 ){
        #DEBUG
        #if($self->{name} eq "innodb_IBmergedinsert"){
        #print $self->{name}."\n";
        #print $self->{_current}."\n";
        #print $self->{_previous}."\n";
        #my $aa =  ($self->{_current} - $self->{_previous});
        #print $aa."\n";
        #}
        $self->{_relative} = ( $self->{_current} - $self->{_previous});
        
    }
    else
    {
        $self->{_relative} = ( $self->{_current});
        
    }
    
    return;
}

