#!/usr/bin/perl

package commonPrintFormat;

use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION);
$VERSION = 1.00;              # Or higher
@ISA = qw(Exporter);
@EXPORT = qw(insert_BBheader insert_BBtail doPrint doPrintextended);

######################################################################
## InsertBBB (Big Brother) header
##

sub insert_BBheader($$){
    my $header = "";
    my $Param = shift;
    my $genericStatus = shift;
        
    if (defined $Param->{html} && $Param->{html} == 1){
        $header = "</PRE><H3>Generic Status for Instance at ".$Param->{host}." PORT:" . $Param->{port} .  " $genericStatus </H3>";
    }
    else
    {
    $header = "Generic Status for Instance at ".$Param->{host}." PORT:" . $Param->{port} .  " $genericStatus \n";
    }
    #$finalreport = $header . $finalreport;

    return $header;
}

sub insert_BBtail($){
    my $Param = shift;
    my $finalreport ="";
    
    if (defined $Param->{html} && $Param->{html} == 1){
        $finalreport =$finalreport ."<PRE>";
    }
    else{
        $finalreport =$finalreport ."\n";
    }
    return $finalreport;
}

sub doPrint ($$$$$)
{
    my $stringToprint = shift;
    my $direct = shift;

    my $finalreport = shift;
    my $genericStatus = shift;
    my $html=shift;


    $finalreport = doPrintextended($stringToprint, $direct, 1);
    return $finalreport;
}

sub doPrintextended ($$$$$$){
    
    my $stringToprint = shift;
    my $direct = shift;
    my $setgeneric_color = shift;

    my $finalreport = shift;
    my $genericStatus = shift;
    my $html=shift;

    my $prefx = "";
    my $postfx = "";
    my $head = "";
    my $tail = "\n";

    if ($html == 1) {
            $prefx = "<tr><td>";
            $postfx = "</td></tr>";
            $head = "<table>";
            $tail = "</table></br>\n";
    
    }
    elsif ($html == 2) {
            $prefx = "";
            $postfx = "";
            $head = "<pre>";
            $tail = "</pre>\n";
    
    }
    
    
        if($stringToprint =~ m/&red/ && $setgeneric_color > 0){
                          if($genericStatus eq "&green" || $genericStatus eq "&yellow"){
                                            $genericStatus = $html?"&red":"ERROR";
                          }
        }
        elsif($stringToprint =~ m/&yellow/ && $setgeneric_color > 0){
                          if($genericStatus eq "&green"){
                                         $genericStatus = $html?"&yellow":"WARNING";
                          }
        }


        if($html != 1 ){
               $stringToprint =~ s/&green/OK/ig;
               $stringToprint =~ s/&yellow/WARNING/ig;
               $stringToprint =~ s/&red/ERROR/ig;

        }

        if($direct){
#                print $stringToprint ;
                $finalreport = $finalreport . $stringToprint;

        }
        else{
#                print $head . $prefx . $stringToprint . $postfx . $tail;
                $finalreport = $finalreport . $head . $prefx . $stringToprint . $postfx . $tail;
        }
    return $finalreport;
}

